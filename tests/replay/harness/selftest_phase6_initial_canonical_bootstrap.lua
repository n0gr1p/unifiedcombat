package.path = './?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
    end
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then error(message or ('missing text: ' .. needle)) end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then error(message or ('unexpected text: ' .. needle)) end
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

local addon = read_all('UnifiedCombat.lua')
local defaults_source = extract(
    addon,
    'local function uc_new_settings_defaults()',
    '\n_G.UC_SETTINGS = uc_new_settings_defaults()'
)
local defaults_chunk, defaults_err = loadstring(
    defaults_source .. '\nreturn uc_new_settings_defaults',
    '@phase6_startup_flat_defaults'
)
assert_true(type(defaults_chunk) == 'function', 'failed to compile legacy flat defaults: ' .. tostring(defaults_err))
local flat_defaults = defaults_chunk()()

local previous_windower = rawget(_G, 'windower')
local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')
rawset(_G, 'windower', {
    ffxi = {
        get_player = function()
            return {
                name = 'Etamame',
                main_job = 'SAM',
                sub_job = 'WAR',
            }
        end,
    },
})

package.loaded.uc_active_config = nil
local active_config = require('uc_active_config')
local profile_v2 = require('uc_profile_v2')

-- Historical flat settings are normalized only inside this regression fixture.
-- No production flat-to-active-profile conversion API is retained.
local legacy_normalized = require('uc_config_normalizer').normalize(flat_defaults, {
    source = 'UC_SETTINGS',
})
local legacy_startup = {
    version = 2,
    profile = legacy_normalized.profile,
    config = (function()
        local config = {}
        for _, domain in ipairs({
            'ui', 'command', 'combat', 'abilities', 'defensive', 'encounter',
            'movement', 'follow', 'targeting', 'reactions', 'tank', 'sleep',
            'spells', 'maintenance', 'summoner', 'puppetmaster', 'sch',
            'debug', 'ownership', 'legacy',
        }) do
            if type(legacy_normalized[domain]) == 'table' then
                config[domain] = legacy_normalized[domain]
            end
        end
        if config.targeting then config.targeting.ignore = nil end
        if config.reactions and config.reactions.enabled ~= true
            and type(config.reactions.rules) == 'table' and #config.reactions.rules == 0 then
            config.reactions = nil
        end
        if config.encounter and config.encounter.enabled ~= true then config.encounter = nil end
        if config.ownership then
            config.ownership.profile_v2_autoload = nil
            config.ownership.profile_v2_auto_reload_on_change = nil
        end
        if legacy_normalized.profile.main_job ~= 'PUP' then config.puppetmaster = nil end
        return config
    end)(),
}
local canonical_startup, canonical_err = active_config.build_default_active_profile({
    source = 'UC_DEFAULTS',
    engine_enabled = false,
})
assert_true(type(canonical_startup) == 'table',
    'canonical startup profile must build: ' .. tostring(canonical_err))

local diff = profile_v2.diff_durable_config(legacy_startup.config, canonical_startup.config)
local first = diff.first_difference or {}
assert_equal(diff.count, 1,
    'startup authority cut may differ only by the retired legacy profile-tree leak')
assert_equal(first.path, 'config.legacy.profiles.UC',
    'the only old startup difference must be the transient v1 profile tree')
assert_true(type(first.left) == 'table' and first.right == nil,
    'old startup must be the side carrying the transient profiles.UC table')

legacy_startup.config.legacy.profiles = {}
local durable_diff = profile_v2.diff_durable_config(legacy_startup.config, canonical_startup.config)
assert_equal(durable_diff.count, 0,
    'all durable startup defaults must match once the transient v1 profile tree is excluded')
assert_equal(next(canonical_startup.config.legacy.profiles), nil,
    'canonical startup must not import transient v1 profile storage into active policy')
assert_equal(canonical_startup.profile.character, 'Etamame',
    'startup canonical profile may observe current player identity')
assert_equal(canonical_startup.profile.main_job, 'SAM',
    'startup canonical profile may observe current main job')
assert_equal(canonical_startup.profile.sub_job, 'WAR',
    'startup canonical profile may observe current sub job')
assert_equal(canonical_startup.profile.source, 'UC_DEFAULTS',
    'startup canonical source must identify canonical defaults')
assert_equal(canonical_startup.config.combat.weaponskill.primary, '',
    'pre-identity startup must not apply SAM job-default weaponskill')
assert_equal(#canonical_startup.config.abilities.configured, 0,
    'pre-identity startup must not apply SAM job-default abilities')

local ok_set, set_err = active_config.set_active_profile(canonical_startup)
assert_true(ok_set == true, 'canonical startup profile publish failed: ' .. tostring(set_err))
assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == active_config.get_active_profile(),
    'canonical startup publish must own the active profile')

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
rawset(_G, 'windower', previous_windower)

local startup = extract(
    addon,
    '_G.UC_SETTINGS = uc_new_settings_defaults()',
    '\nlocal function uc_truthy'
)
assert_contains(startup, '_G.UC_SETTINGS = uc_new_settings_defaults()',
    'flat settings table must remain available for transient/legacy runtime state')
assert_contains(startup, 'uc_active_config.build_default_active_profile({',
    'addon startup must build canonical defaults directly')
assert_contains(startup, "source = 'UC_DEFAULTS'",
    'addon startup canonical profile source mismatch')
assert_contains(startup, 'uc_active_config.set_active_profile(uc_startup_active_profile)',
    'addon startup must publish the canonical profile directly')
assert_not_contains(startup, 'initialize_active_profile(',
    'addon startup must not use the retired flat->canonical wrapper')
assert_not_contains(startup, 'build_active_profile_from_settings(',
    'addon startup must not derive canonical state from flat settings')
assert_not_contains(startup, 'UC_JOB_DEFAULTS',
    'pre-identity startup must not apply job defaults')
assert_not_contains(addon, 'uc_sync_active_profile_from_settings',
    'dead generic flat->canonical addon sync helper must remain removed')

local active_source = read_all('uc_active_config.lua')
assert_not_contains(active_source, 'function M.initialize_active_profile(',
    'startup-only flat->canonical wrapper must remain retired')
assert_not_contains(active_source, 'function M.build_active_profile_from_settings(',
    'orphaned legacy conversion API must remain retired')

print('selftest_phase6_initial_canonical_bootstrap: OK (startup active profile no longer derives from flat settings)')
