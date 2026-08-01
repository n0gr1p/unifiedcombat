local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	if not value then
		error(message or 'assert_true failed')
	end
end

local function set_active_profile(active_config, config)
	local ok, err = active_config.set_active_profile({
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			source = 'selftest',
		},
		config = config or {},
	})
	if ok ~= true then
		error('failed to set active profile: ' .. tostring(err))
	end
end

local function main()
	local previous_windower = rawget(_G, 'windower')
	local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	local previous_settings = rawget(_G, 'UC_SETTINGS')

	package.loaded['uc_active_config'] = nil
	package.loaded['uc_config_normalizer'] = nil
	package.loaded['uc_scheduler_config'] = nil

	rawset(_G, 'windower', {
		addon_path = './',
		ffxi = {
			get_player = function()
				return {
					name = 'Tester',
					main_job = 'PLD',
					sub_job = 'WAR',
				}
			end,
		},
	})

	local active_config = require('uc_active_config')
	local scheduler_config = require('uc_scheduler_config')
	local flat = {
		debug = false,
		log_combat_sched = false,
		log_ja_sched = false,
		log_ja_debug = false,
		log_def_sched = false,
		log_tank_sched = false,
		autotarget = false,
		prime = false,
		tank = false,
		tank_enmity_actions = { 'spell:Flash' },
		def_remove_enemy_buffs = false,
	}

	set_active_profile(active_config, {
		debug = {
			enabled = true,
			combat_sched = true,
			ja_sched = true,
			ja_debug = true,
			def_sched = true,
			tank_sched = true,
		},
		combat = {
			autotarget = true,
			prime = true,
		},
		ownership = {},
		tank = {
			enabled = true,
			enmity = {
				actions = { 'ja:Provoke', 'spell:Flash' },
			},
		},
		defensive = {
			enemy_buffs = {
				remove = true,
			},
		},
	})

	assert_equal(scheduler_config.debug_enabled(flat), true, 'debug enabled should prefer active config')
	assert_equal(scheduler_config.debug_log_combat_sched(flat), true, 'combat scheduler log gate should prefer active config')
	assert_equal(scheduler_config.debug_log_ja_sched(flat), true, 'ja scheduler log gate should prefer active config')
	assert_equal(scheduler_config.debug_log_ja_debug(flat), true, 'ja debug log gate should prefer active config')
	assert_equal(scheduler_config.debug_log_def_sched(flat), true, 'defensive scheduler log gate should prefer active config')
	assert_equal(scheduler_config.debug_log_tank_sched(flat), true, 'tank scheduler log gate should prefer active config')
	assert_equal(scheduler_config.combat_autotarget(flat), true, 'autotarget should prefer active config')
	assert_equal(scheduler_config.combat_prime(flat), true, 'prime should prefer active config')
	assert_equal(scheduler_config.tank_enabled(flat), true, 'tank enabled should prefer active config')
	assert_equal(scheduler_config.defensive_enemy_buffs_remove(flat), true, 'enemy-buff removal should prefer active config')
	assert_equal(scheduler_config.tank_enmity_actions(flat)[1], 'ja:Provoke', 'tank enmity actions should prefer active config')

	set_active_profile(active_config, {
		debug = {},
		combat = {},
		ownership = {},
		tank = {},
		defensive = {
			enemy_buffs = {},
		},
	})

	local fallback = {
		debug = true,
		log_combat_sched = true,
		log_ja_sched = true,
		log_ja_debug = true,
		log_def_sched = true,
		log_tank_sched = true,
		autotarget = true,
		prime = true,
		tank = true,
		tank_enmity_actions = { 'spell:Foil' },
		def_remove_enemy_buffs = true,
	}

	assert_equal(scheduler_config.debug_enabled(fallback), true, 'debug enabled should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.debug_log_combat_sched(fallback), true, 'combat scheduler log gate should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.debug_log_ja_sched(fallback), true, 'ja scheduler log gate should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.debug_log_ja_debug(fallback), true, 'ja debug log gate should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.debug_log_def_sched(fallback), true, 'defensive scheduler log gate should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.debug_log_tank_sched(fallback), true, 'tank scheduler log gate should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.combat_autotarget(fallback), true, 'autotarget should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.combat_prime(fallback), true, 'prime should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.tank_enabled(fallback), true, 'tank enabled should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.defensive_enemy_buffs_remove(fallback), true, 'enemy-buff removal should preserve flat fallback when active path is missing')
	assert_equal(scheduler_config.tank_enmity_actions(fallback)[1], 'spell:Foil', 'tank enmity actions should preserve flat fallback when active path is missing')

	rawset(_G, 'UC_SETTINGS', fallback)
	assert_true(scheduler_config.debug_enabled(), 'global settings fallback should remain available')
	assert_equal(scheduler_config.tank_enmity_actions()[1], 'spell:Foil', 'global settings table should back facade fallback reads')

	rawset(_G, 'windower', previous_windower)
	rawset(_G, 'UC_ACTIVE_PROFILE', previous_active_profile)
	rawset(_G, 'UC_SETTINGS', previous_settings)
	package.loaded['uc_scheduler_config'] = nil
	package.loaded['uc_active_config'] = nil
	package.loaded['uc_config_normalizer'] = nil

	io.stdout:write('selftest_scheduler_config_readers: OK\n')
end

main()
