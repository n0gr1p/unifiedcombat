local function read(path)
	local file = assert(io.open(path, 'r'))
	local text = file:read('*a')
	file:close()
	return text
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected)
			.. ', actual=' .. tostring(actual))
	end
end

local function assert_contains(text, needle, message)
	if not text:find(needle, 1, true) then
		error(message or ('missing expected text: ' .. needle))
	end
end

local function assert_not_contains(text, needle, message)
	if text:find(needle, 1, true) then
		error(message or ('unexpected text present: ' .. needle))
	end
end

local function ownership_config(domain_values)
	return {
		version = 2,
		profile = {},
		config = {
			ownership = {
				domain_combat_enabled = domain_values.combat,
				domain_defensive_enabled = domain_values.defensive,
				domain_movement_enabled = domain_values.movement,
				domain_maintenance_enabled = domain_values.maintenance,
			},
		},
	}
end

local function main()
	local old_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	local active_config = require('uc_active_config')
	local domain_values = { combat = true, defensive = false, movement = true, maintenance = false }
	local ok_set = active_config.set_active_profile(ownership_config(domain_values))
	assert_equal(ok_set, true, 'test active profile must be accepted')
	package.loaded.uc_domain_ownership = nil
	local ownership = require('uc_domain_ownership')
	assert_equal(ownership.is_enabled('combat'), true, 'combat must follow domain enablement')
	assert_equal(ownership.is_enabled('defensive'), false, 'defensive must follow domain enablement')
	assert_equal(ownership.is_enabled('movement'), true, 'movement must follow domain enablement')
	assert_equal(ownership.is_enabled('maintenance'), false, 'maintenance must follow domain enablement')

	_G.UC_ACTIVE_PROFILE.config.ownership.domain_combat_enabled = nil
	local ok, err = pcall(function()
		ownership.is_enabled('combat')
	end)
	assert_equal(ok, false, 'missing domain ownership must fail fast')
	assert_contains(tostring(err), 'requires boolean active config', 'missing-domain error')
	_G.UC_ACTIVE_PROFILE = old_active_profile
	package.loaded.uc_domain_ownership = nil

	local engine = read('unified_engine.lua')
	local scheduler = read('unified_scheduler.lua')
	local core = read('unified_combat_core.lua')
	local addon = read('UnifiedCombat.lua')
	local normalizer = read('uc_config_normalizer.lua')
	local contract = read('uc_profile_contract.lua')
	local pathing = read('uc_pathing.lua')
	local runtime_domain_consumers = {
		scheduler,
		pathing,
		read('uc_provider_combat.lua'),
		read('uc_provider_defensive.lua'),
		read('uc_provider_enemy_buff_removal.lua'),
		read('uc_provider_maintenance.lua'),
		read('uc_provider_tank_enmity.lua'),
		read('uc_provider_target_control.lua'),
	}

	assert_not_contains(engine, 'UC_CoreCombatTickOnce', 'engine must not call the legacy core tick')
	assert_not_contains(engine, 'core_tick_allowed_for_domain', 'engine core fallback gate must be removed')
	assert_not_contains(engine, 'scheduler_dark_launch_', 'engine must not branch on legacy ownership markers')
	for _, source in ipairs(runtime_domain_consumers) do
		assert_not_contains(source, 'config.ownership.scheduler_dark_launch_',
			'active runtime domain consumers must not consult legacy ownership markers')
	end

	for _, path in ipairs({
		'tests/replay/harness/selftest_engage_dispatch_priority.lua',
		'tests/replay/harness/selftest_scheduler_sleep_toggle.lua',
		'tests/replay/harness/selftest_sleep_target_state_suppression.lua',
		'tests/replay/harness/selftest_tank_engage_priority.lua',
		'tests/replay/harness/selftest_target_acquire_nonblocking.lua',
	}) do
		local behavior_test = read(path)
		assert_contains(behavior_test, 'domain_combat_enabled',
			path .. ' must model the authoritative combat domain')
		assert_not_contains(behavior_test, 'scheduler_dark_launch_combat',
			path .. ' must not model combat behavior with the compatibility marker')
	end
	assert_contains(scheduler, "domain_ownership.is_enabled('combat')", 'scheduler combat domain gate')
	assert_contains(scheduler, "domain_ownership.is_enabled('defensive')", 'scheduler defensive domain gate')
	assert_contains(scheduler, "domain_ownership.is_enabled('movement')", 'scheduler movement domain gate')
	assert_contains(scheduler, "domain_ownership.is_enabled('maintenance')", 'scheduler maintenance domain gate')
	assert_not_contains(scheduler, 'local scheduler_owns_defensive =', 'legacy defensive fallback selector must be removed')
	assert_contains(core, 'function core.dispatch_pull_for_scheduler(settings, target_id, executor, config)', 'pull bridge must require an executor')
	assert_contains(core, 'require_pull_executor(executor)', 'pull bridge must validate its executor')
	assert_contains(scheduler, 'p1_build_pull_executor()', 'scheduler pull path must inject its dispatcher-backed executor')
	assert_contains(core, 'local s = scheduler_settings_view(settings, config)', 'scheduler pull dispatch must use canonical path settings')
	assert_contains(scheduler, "require('uc_active_config').get_config()", 'pull dispatch must pass active Profile V2 policy')
	assert_contains(pathing, "local domain_ownership = require('uc_domain_ownership')", 'pathing must use domain ownership policy')
	assert_contains(pathing, "if not domain_ownership.is_enabled('movement') then", 'pathing must honor movement domain disablement')

	for _, source in ipairs({ addon, normalizer, contract }) do
		assert_not_contains(source, 'scheduler_dark_launch_', 'obsolete ownership markers must be retired')
	end

	io.stdout:write('selftest_phase5_domain_cutover: OK\n')
end

main()
