package.path = './?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_false(value, message)
    if value ~= false then error(message or ('expected false, got ' .. tostring(value))) end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_nil(value, message)
    if value ~= nil then error(message or ('expected nil, got ' .. tostring(value))) end
end

local function read_all(path)
    local fh, err = io.open(path, 'rb')
    if not fh then error('failed to open ' .. tostring(path) .. ': ' .. tostring(err)) end
    local source = fh:read('*a')
    fh:close()
    return source
end

local function extract(source, start_marker, end_marker)
    local start_pos = source:find(start_marker, 1, true)
    if not start_pos then error('missing source block start: ' .. start_marker) end
    local end_pos = source:find(end_marker, start_pos + #start_marker, true)
    if not end_pos then error('missing source block end: ' .. end_marker) end
    return source:sub(start_pos, end_pos - 1)
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then error(message or ('missing text: ' .. needle)) end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then error(message or ('unexpected text: ' .. needle)) end
end

local profile_v2 = require('uc_profile_v2')
local active_config = require('uc_active_config')
local scheduler_config = require('uc_scheduler_config')

local meta = {
    character = 'Tester',
    main_job = 'WAR',
    sub_job = 'DNC',
    profile_key = 'Tester|WAR|DNC',
    exported_at = '2026-10-09T10:00:00Z',
}

local stale_flat = {
    domain_combat_enabled = true,
    domain_defensive_enabled = true,
    domain_movement_enabled = true,
    domain_maintenance_enabled = true,
    domain_follow_enabled = true,
    prime = false,
    food_enabled = false,
    food_item = 'Stale Food',
}
local stale_prime = stale_flat.prime
local stale_food_enabled = stale_flat.food_enabled
local stale_food_item = stale_flat.food_item

local payload = profile_v2.build_structured_profile(stale_flat, meta)
payload.config.combat.prime = true
payload.config.maintenance.food = {
    enabled = true,
    item = 'Grape Daifuku',
}

local converted = profile_v2.build_active_profile_from_structured_profile(payload, meta)
assert_true(type(converted) == 'table' and converted.ok == true,
    'canonical structured-profile conversion must succeed')
assert_true(type(converted.active_profile) == 'table',
    'canonical conversion must return active Profile V2')
assert_true(type(converted.candidate_config) == 'table',
    'canonical conversion must return candidate canonical config')
assert_nil(converted.candidate,
    'canonical conversion must not build a flat settings candidate')
assert_nil(converted.projected_settings,
    'canonical conversion must not expose projected flat settings')
assert_true(converted.candidate_config.combat.prime,
    'canonical conversion must preserve Profile V2 combat policy')
assert_true(converted.candidate_config.maintenance.food.enabled,
    'canonical conversion must preserve Profile V2 maintenance policy')
assert_equal(converted.candidate_config.maintenance.food.item, 'Grape Daifuku',
    'canonical conversion must preserve Profile V2 food item')

assert_equal(stale_flat.prime, stale_prime,
    'canonical conversion must not mutate stale flat combat policy')
assert_equal(stale_flat.food_enabled, stale_food_enabled,
    'canonical conversion must not mutate stale flat maintenance enable')
assert_equal(stale_flat.food_item, stale_food_item,
    'canonical conversion must not mutate stale flat maintenance item')

local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')
local previous_settings = rawget(_G, 'UC_SETTINGS')
rawset(_G, 'UC_ACTIVE_PROFILE', converted.active_profile)
rawset(_G, 'UC_SETTINGS', stale_flat)
assert_true(scheduler_config.combat_prime(stale_flat),
    'runtime canonical reader must observe applied Profile V2 over contradictory flat state')

local exported = profile_v2.build_structured_profile_from_active_profile(
    converted.active_profile,
    {
        character = meta.character,
        main_job = meta.main_job,
        sub_job = meta.sub_job,
        profile_key = meta.profile_key,
        exported_at = meta.exported_at,
        source = 'exported_from_active_profile',
    }
)
assert_true(exported.config.combat.prime,
    'save/export projection must source canonical combat policy from active Profile V2')
assert_true(exported.config.maintenance.food.enabled,
    'save/export projection must source canonical maintenance policy from active Profile V2')
assert_equal(exported.config.maintenance.food.item, 'Grape Daifuku',
    'save/export projection must preserve canonical food item')

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
rawset(_G, 'UC_SETTINGS', previous_settings)

local profile_source = read_all('uc_profile_v2.lua')
local apply_conversion = extract(
    profile_source,
    'local function apply_result_to_active_profile(payload, meta, deps)',
    'function M.build_active_profile_from_structured_profile'
)
assert_not_contains(apply_conversion, 'project_flat_settings(',
    'Profile V2 conversion must not round-trip canonical config through flat settings')
assert_not_contains(apply_conversion, 'projected_settings',
    'Profile V2 conversion must not expose projected flat settings')
assert_contains(apply_conversion, 'candidate_config = clone_value(active_profile.config)',
    'Profile V2 conversion must validate the canonical active config directly')

local addon = read_all('UnifiedCombat.lua')
local addon_apply = extract(
    addon,
    'local function uc_apply_profile_v2_file(meta, settings)',
    'local function uc_initialize_safe_profile_v2_identity'
)
assert_contains(addon_apply, 'apply_structured_profile_file_to_active_config',
    'addon apply path must use canonical apply API')
assert_contains(addon_apply, 'uc_active_config.set_active_profile(result.active_profile)',
    'addon apply path must publish canonical active Profile V2')
assert_not_contains(addon_apply, 'sync_flat_settings_in_place(',
    'addon apply path must not republish Profile V2 into flat settings')
assert_not_contains(addon_apply, 'uc_normalize_settings_table(settings)',
    'addon apply path must not normalize a flat mirror after canonical apply')

assert_contains(addon, 'inspect_structured_profile_status_against_config',
    'Profile V2 status must compare the file against canonical active config')
assert_contains(addon, 'diff_structured_profile_file_against_config',
    'Profile V2 diff must compare the file against canonical active config')
assert_contains(addon, 'build_structured_profile_from_active_profile',
    'Profile V2 save/export must serialize the canonical active profile')

print('selftest_phase6_profile_apply_publication_retirement: OK (canonical apply no longer republishes flat settings)')
