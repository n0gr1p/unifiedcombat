package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_false(value, message)
	assert_equal(value, false, message)
end

local function bool_setting(value, default)
	if value == nil then
		return default
	end
	return value == true
end

local scheduler_config = require('uc_scheduler_config')
local extension_config = require('uc_combat_extension_config')

local function make_target_provider()
	return require('uc_provider_target_control').new({
		bool_setting = bool_setting,
		combat_autotarget = scheduler_config.combat_autotarget_from_config,
		combat_domain_enabled = function() return true end,
		tank_enabled = function() return false end,
		select_target = function(_settings, config)
			assert_true(type(config) == 'table', 'target selector must receive canonical config')
			return { target_id = 900, target_name = 'Colibri', hpp = 100 }
		end,
		add_control_enabled = function() return false end,
		select_pull = function() return nil end,
		action_timeline_log = function() end,
		clamp_urgency = function(value) return value end,
		tank_target_priority = 132,
		tank_target_urgency = 0.95,
		death_switch_priority = 148,
		death_switch_urgency = 1.0,
	})
end

local function run_target(canonical_autotarget, flat_autotarget)
	local previous_engine = rawget(_G, 'Start_Engine')
	rawset(_G, 'Start_Engine', true)
	local provider = make_target_provider()
	local out = {}
	provider.collect_target({
		now = 10,
		config = { combat = { autotarget = canonical_autotarget } },
		settings = { autotarget = flat_autotarget },
		player_present = true,
		player = { status = 0 },
		target_present = false,
	}, out)
	rawset(_G, 'Start_Engine', previous_engine)
	return out
end

local function make_combat_provider()
	return require('uc_provider_combat').new({
		bool_setting = bool_setting,
		clamp_urgency = function(value) return value end,
		build_partner_target_set = function() return {} end,
		select_ws_plan = function() return nil end,
		action_timeline_log = function() end,
		combat_domain_enabled = function() return true end,
		sleep_enabled = function() return false end,
		sleep_spell_list = function() return {} end,
		is_live_actionable_target = function() return true end,
		build_friendly_claims = function() return {}, { [1001] = true } end,
		mob_targets_friendly_member = function() return false end,
		sleep_max_target_distance = function() return 20 end,
		target_sleep_suppressed = function() return false end,
		select_sleep_spell = function() return nil end,
		combat_autotarget = scheduler_config.combat_autotarget_from_config,
		tank_enabled = function() return false end,
		debug_enabled = function() return false end,
		combat_prime = function() return false end,
		fight_leader_enabled = function() return false end,
		fight_leader_id = function() return 0 end,
		fight_leader_target_id = function() return 0 end,
		add_control_enabled = function() return false end,
		select_pull = function() return nil end,
		build_party_id_set = function() return { [1] = true } end,
		prime_unclaimed_party_aggressive_ok = function() return false end,
		pending_engage_state = function() return nil end,
		pending_engage_live = function() return false end,
		collect_ordered_abilities = function() return {} end,
		get_ja_resource = function() return nil end,
		action_ready = function() return false, 'NOT_READY', '' end,
		action_effective_range = function() return 20 end,
		log_ja_sched = function() end,
		phase1 = {},
		action_state = {},
		skillchain_priority = 160,
		aftermath_priority = 155,
		sleep_priority = 145,
		tank_engage_priority = 130,
		default_engage_priority = 80,
		tank_engage_urgency = 0.90,
		default_engage_urgency = 0.55,
	})
end

local function run_engage(canonical_autotarget, canonical_auto_engage, flat_autotarget, flat_auto_engage)
	local previous_engine = rawget(_G, 'Start_Engine')
	local previous_settings = rawget(_G, 'UC_SETTINGS')
	rawset(_G, 'Start_Engine', true)
	rawset(_G, 'UC_SETTINGS', {
		autotarget = flat_autotarget,
		auto_engage = flat_auto_engage,
	})
	local provider = make_combat_provider()
	local out = {}
	provider.collect_engage({
		now = 20,
		config = {
			combat = {
				autotarget = canonical_autotarget,
				auto_engage = canonical_auto_engage,
			},
		},
		settings = {
			autotarget = flat_autotarget,
			auto_engage = flat_auto_engage,
		},
		player_present = true,
		player = { id = 1, status = 0 },
		target_present = true,
		target = {
			id = 900,
			name = 'Colibri',
			valid_target = true,
			spawn_type = 16,
			hpp = 100,
			claim_id = 1001,
		},
		mobs_by_id = {},
	}, out)
	rawset(_G, 'Start_Engine', previous_engine)
	rawset(_G, 'UC_SETTINGS', previous_settings)
	return out
end

local function assert_static_wiring()
	local function read_all(path)
		local fh = assert(io.open(path, 'r'))
		local content = fh:read('*a')
		fh:close()
		return content
	end
	local scheduler = read_all('unified_scheduler.lua')
	local core = read_all('unified_combat_core.lua')
	assert_true(scheduler:find('combat_autotarget = uc_scheduler_config.combat_autotarget_from_config', 1, true) ~= nil,
		'scheduler providers must be wired to canonical autotarget accessor')
	assert_true(scheduler:find('scheduler.try_partner_tiebreak(s, get_tick_ctx().config)', 1, true) ~= nil,
		'partner arbitration must receive canonical tick config')
	assert_true(core:find('scheduler_config.combat_autotarget_from_config(config)', 1, true) ~= nil,
		'core scheduler view must derive autotarget from canonical config')
	assert_true(core:find('extension_config.auto_engage_enabled_from_config(config)', 1, true) ~= nil,
		'combat-close movement must derive auto-engage from canonical config')
end

local function main()
	local previous_settings = rawget(_G, 'UC_SETTINGS')
	rawset(_G, 'UC_SETTINGS', { autotarget = false, auto_engage = false })
	assert_true(scheduler_config.combat_autotarget_from_config({ combat = { autotarget = true } }),
		'canonical autotarget true must beat flat false')
	assert_true(extension_config.auto_engage_enabled_from_config({ combat = { auto_engage = true } }),
		'canonical auto-engage true must beat flat false')
	rawset(_G, 'UC_SETTINGS', { autotarget = true, auto_engage = true })
	assert_false(scheduler_config.combat_autotarget_from_config({ combat = { autotarget = false } }),
		'canonical autotarget false must beat flat true')
	assert_false(extension_config.auto_engage_enabled_from_config({ combat = { auto_engage = false } }),
		'canonical auto-engage false must beat flat true')
	rawset(_G, 'UC_SETTINGS', previous_settings)

	assert_equal(#run_target(true, false), 1, 'canonical autotarget ON + flat OFF must acquire')
	assert_equal(#run_target(false, true), 0, 'canonical autotarget OFF + flat ON must not acquire')
	assert_equal(#run_engage(true, true, false, false), 1,
		'canonical autotarget/auto-engage ON + flat OFF must engage')
	assert_equal(#run_engage(false, true, true, true), 0,
		'canonical autotarget OFF + flat ON must not engage')
	assert_equal(#run_engage(true, false, true, true), 0,
		'canonical auto-engage OFF + flat ON must not engage')

	assert_static_wiring()
	io.stdout:write('selftest_phase3_combat_enablement_authority: OK (9 canonical-authority checks)\n')
end

main()
