package.path = './?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_false(value, message)
    if value ~= false then error(message or ('expected false, got ' .. tostring(value))) end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
    end
end

local function assert_nil(value, message)
    if value ~= nil then error(message or ('expected nil, got ' .. tostring(value))) end
end

local function assert_deep_equal(actual, expected, message)
    if type(actual) ~= type(expected) then
        error(message or 'deep equality type mismatch')
    end
    if type(actual) ~= 'table' then
        if actual ~= expected then
            error((message or 'deep equality mismatch') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
        end
        return
    end
    for key, value in pairs(actual) do
        assert_deep_equal(value, expected[key], message)
    end
    for key in pairs(expected) do
        if actual[key] == nil then
            error((message or 'deep equality missing key') .. ': ' .. tostring(key))
        end
    end
end

local function deep_clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, inner in pairs(value) do
        out[deep_clone(key)] = deep_clone(inner)
    end
    return out
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

local active_config = require('uc_active_config')

local job_defaults = {
    WAR = {
        ws1 = 'Savage Blade',
        ability1 = '',
        ability2 = '',
        ability3 = '',
        ability4 = '',
        ability5 = '',
        ability6 = '',
    },
    SAM = {
        ws1 = 'Tachi: Kasha',
        ability1 = 'Hasso',
        ability2 = 'Third Eye',
        ability3 = 'Berserk',
        ability4 = 'Aggressor',
        ability5 = 'Meditate',
        ability6 = '',
    },
    DRG = {
        ws1 = 'Stardiver',
        ability1 = 'Hasso',
        ability2 = '',
        ability3 = 'Berserk',
        ability4 = 'Aggressor',
        ability5 = 'Meditate',
        ability6 = '',
    },
}

local stale_flat = {
    weaponskill = 'Stale WS',
    weaponskill_active = true,
    abilities = { 'Stale Ability' },
    ability_active = true,
    defensive_enabled = true,
    domain_combat_enabled = false,
    domain_defensive_enabled = false,
    food_enabled = true,
    food_item = 'Stale Food',
    path_file_name = 'runtime-route.lua',
    path_points = {
        { x = 1, y = 2, z = 3 },
    },
}
local stale_snapshot = deep_clone(stale_flat)
local previous_settings = rawget(_G, 'UC_SETTINGS')
local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')
rawset(_G, 'UC_SETTINGS', stale_flat)
rawset(_G, 'UC_ACTIVE_PROFILE', nil)

local sam, sam_err = active_config.build_default_active_profile({
    character = 'Etamame',
    main_job = 'SAM',
    sub_job = 'WAR',
    profile_key = 'Etamame|SAM|WAR',
    source = 'UC_DEFAULTS',
    engine_enabled = true,
    job_for_defaults = 'SAM',
}, job_defaults)
assert_true(type(sam) == 'table', 'SAM canonical default profile must build: ' .. tostring(sam_err))
assert_equal(sam.version, 2, 'safe bootstrap version mismatch')
assert_equal(sam.profile.schema_version, 2, 'safe bootstrap schema mismatch')
assert_equal(sam.profile.character, 'Etamame', 'safe bootstrap character mismatch')
assert_equal(sam.profile.main_job, 'SAM', 'safe bootstrap main job mismatch')
assert_equal(sam.profile.sub_job, 'WAR', 'safe bootstrap sub job mismatch')
assert_equal(sam.profile.profile_key, 'Etamame|SAM|WAR', 'safe bootstrap profile key mismatch')
assert_equal(sam.profile.source, 'UC_DEFAULTS', 'safe bootstrap source mismatch')
assert_true(sam.config.command.engine_enabled_default, 'safe bootstrap must preserve current engine state as compatibility default')
assert_equal(sam.config.combat.weaponskill.primary, 'Tachi: Kasha', 'SAM WS default mismatch')
assert_false(sam.config.combat.weaponskill.enabled, 'SAM WS default must remain configured but disabled')
assert_false(sam.config.abilities.enabled, 'SAM ability defaults must remain configured but disabled')
assert_deep_equal(
    sam.config.abilities.configured,
    { 'Hasso', 'Third Eye', 'Berserk', 'Aggressor', 'Meditate' },
    'SAM configured ability defaults mismatch'
)
assert_deep_equal(
    sam.config.abilities.legacy_slots,
    { 'Hasso', 'Third Eye', 'Berserk', 'Aggressor', 'Meditate' },
    'SAM compacted legacy ability mirror mismatch'
)

local drg = assert(active_config.build_default_active_profile({
    character = 'Ponpon',
    main_job = 'DRG',
    sub_job = 'SAM',
    profile_key = 'Ponpon|DRG|SAM',
    source = 'UC_DEFAULTS',
    engine_enabled = false,
    job_for_defaults = 'DRG',
}, job_defaults))
assert_equal(drg.config.combat.weaponskill.primary, 'Stardiver', 'DRG WS default mismatch')
assert_deep_equal(
    drg.config.abilities.configured,
    { 'Hasso', 'Berserk', 'Aggressor', 'Meditate' },
    'DRG sparse legacy slots must compact exactly like the old bootstrap'
)
assert_false(drg.config.command.engine_enabled_default, 'disabled engine compatibility default mismatch')

local whm = assert(active_config.build_default_active_profile({
    character = 'Niightsiide',
    main_job = 'WHM',
    sub_job = 'SCH',
    profile_key = 'Niightsiide|WHM|SCH',
    source = 'UC_DEFAULTS',
    engine_enabled = false,
    job_for_defaults = 'WHM',
}, job_defaults))
assert_equal(whm.config.combat.weaponskill.primary, '', 'jobs without legacy job defaults must keep canonical empty WS')
assert_equal(#whm.config.abilities.configured, 0, 'jobs without legacy job defaults must keep canonical empty ability list')

local ok_set, set_err = active_config.set_active_profile(sam)
assert_true(ok_set == true, 'safe canonical profile publish failed: ' .. tostring(set_err))
assert_deep_equal(stale_flat, stale_snapshot, 'canonical safe bootstrap must not rewrite stale flat/transient settings')
assert_equal(active_config.get_config().combat.weaponskill.primary, 'Tachi: Kasha',
    'published safe profile must expose canonical job defaults')

rawset(_G, 'UC_SETTINGS', previous_settings)
rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)

local addon = read_all('UnifiedCombat.lua')
local safe_block = extract(
    addon,
    'local function uc_initialize_safe_profile_v2_identity(player, job_for_defaults)',
    '\n\nlocal function uc_establish_profile_v2_identity'
)
assert_contains(safe_block, 'uc_active_config.build_default_active_profile({',
    'safe identity bootstrap must build canonical defaults directly')
assert_contains(safe_block, 'uc_active_config.set_active_profile(active_profile)',
    'safe identity bootstrap must publish canonical active profile')
assert_contains(safe_block, 'job_for_defaults = uc_job_default_key(job_for_defaults or player.main_job)',
    'safe identity bootstrap must preserve job-default identity handling')
assert_not_contains(safe_block, '_G.UC_SETTINGS',
    'safe identity bootstrap must not read or write flat settings')
assert_not_contains(safe_block, 'uc_new_settings_defaults(',
    'safe identity bootstrap must not rebuild the flat default table')
assert_not_contains(safe_block, 'sync_flat_settings_in_place(',
    'safe identity bootstrap must not publish defaults into flat settings')
assert_not_contains(safe_block, 'uc_normalize_settings_table(',
    'safe identity bootstrap must not normalize a flat shadow')
assert_not_contains(safe_block, 'build_active_profile_from_settings(',
    'safe identity bootstrap must not derive canonical config from flat settings')
assert_not_contains(addon, 'uc_apply_job_defaults(',
    'retired global flat job-default mutator must stay removed')
assert_not_contains(addon, 'sync_flat_settings_in_place(',
    'UnifiedCombat addon must have no remaining full-table flat publication call')

print('selftest_phase6_safe_identity_bootstrap: OK (safe identity defaults are canonical and flat state is untouched)')
