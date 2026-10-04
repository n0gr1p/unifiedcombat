package.path = './?.lua;' .. package.path

local normalizer = require('uc_config_normalizer')
local profile_v2 = require('uc_profile_v2')
local active_config = require('uc_active_config')
local contract = require('uc_profile_contract')
local runtime = require('uc_pup_runtime')

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, message)
    if value ~= true then error(message) end
end

local function assert_false(value, message)
    if value ~= false then error(message) end
end

local function flat_settings()
    return {
        puppetmaster_enabled = true,
        puppetmaster_activate_if_missing = true,
        puppetmaster_deploy_on_combat_start = true,
        puppetmaster_maneuvers_enabled = true,
        puppetmaster_maneuver_pattern = 'Fire Maneuver|Fire Maneuver|Light Maneuver',
        puppetmaster_post_activate_quiet_seconds = 120,
        puppetmaster_safe_burden_ceiling = 30,
    }
end

local meta = {
    character = 'Tester',
    main_job = 'PUP',
    sub_job = 'WAR',
}

local normalized = normalizer.normalize(flat_settings(), meta)
assert_true(type(normalized.puppetmaster) == 'table', 'normalizer must own puppetmaster domain')
assert_true(normalized.puppetmaster.enabled, 'normalized Puppetmaster automation enabled')
assert_equal(normalized.puppetmaster.maneuvers.pattern[1], 'Fire Maneuver', 'pattern slot 1')
assert_equal(normalized.puppetmaster.maneuvers.pattern[2], 'Fire Maneuver', 'pattern slot 2')
assert_equal(normalized.puppetmaster.maneuvers.pattern[3], 'Light Maneuver', 'pattern slot 3')

local structured = profile_v2.build_structured_profile(flat_settings(), meta)
assert_true(type(structured.config.puppetmaster) == 'table', 'PUP profile export must retain puppetmaster domain')
assert_equal(structured.config.puppetmaster.maneuvers.safe_burden_ceiling, 30, 'PUP profile export burden ceiling')

local active_from_v2, active_error = active_config.build_active_profile_from_v2_payload(structured, meta)
assert_true(active_from_v2 ~= nil, 'active PUP profile build failed: ' .. tostring(active_error))
assert_true(type(active_from_v2.config.puppetmaster) == 'table', 'active PUP profile must retain puppetmaster domain')
assert_true(active_from_v2.config.puppetmaster.enabled, 'active PUP profile must retain enabled=true')

local projected, project_error = active_config.project_flat_settings(active_from_v2, {})
assert_true(projected ~= nil, 'active config projection failed: ' .. tostring(project_error))
assert_true(type(projected.puppetmaster) == 'table', 'active config must project nested puppetmaster settings')
assert_true(projected.puppetmaster_enabled, 'active config must project flat PUP UI mirror')
assert_equal(projected.puppetmaster_maneuver_pattern, 'Fire Maneuver|Fire Maneuver|Light Maneuver', 'active config pattern mirror')

local conversion = profile_v2.build_settings_candidate_from_structured_profile({}, structured, meta)
assert_true(conversion.ok, 'enabled PUP profile-v2 conversion must round-trip: ' .. tostring(conversion.error or conversion.detail))
assert_true(conversion.candidate.puppetmaster_enabled, 'autoload candidate must retain PUP enabled=true')
assert_true(type(conversion.candidate_config.puppetmaster) == 'table', 'autoload candidate durable config must retain puppetmaster domain')
assert_true(conversion.candidate_config.puppetmaster.enabled, 'autoload candidate durable config must retain enabled=true')

local no_profile_config = runtime.config_from_config({ profile = { main_job = 'PUP' } })
assert_false(no_profile_config.enabled, 'missing canonical PUP config must disable automation')

local compatibility_no_profile = runtime.config_from_settings({ profile = { main_job = 'PUP' } })
assert_false(compatibility_no_profile.enabled, 'legacy/direct PUP compatibility parser must preserve disabled default')

local ok_non_pup = pcall(function()
    normalizer.normalize(flat_settings(), { character = 'Tester', main_job = 'WAR', sub_job = 'NIN' })
end)
assert_false(ok_non_pup, 'enabled Puppetmaster config must be rejected outside main job PUP')

assert_equal(
    contract.classify_profile_field('puppetmaster_maneuver_pattern'),
    'profile_owned_by_ui',
    'PUP flat fields must be profile owned'
)

local contract_result = contract.validate_structured_profile_config(structured)
assert_true(contract_result.configuration_valid, 'structured PUP profile must pass contract validation')
assert_true(contract_result.puppetmaster.valid, 'PUP contract validation must be explicit')

io.stdout:write('selftest_pup_profile_v2: OK\n')
