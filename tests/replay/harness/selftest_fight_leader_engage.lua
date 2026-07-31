package.path = './?.lua;' .. package.path

local combat_provider = require('uc_provider_combat')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function bool_setting(value)
	return value == true
end

local function make_provider(leader_target_id)
	return combat_provider.new({
		bool_setting = bool_setting,
		clamp_urgency = function(value)
			return value
		end,
		build_partner_target_set = function()
			return {}
		end,
		select_ws_plan = function()
			return nil
		end,
		action_timeline_log = function()
		end,
		combat_domain_enabled = function()
			return true
		end,
		sleep_enabled = function()
			return false
		end,
		sleep_spell_list = function()
			return {}
		end,
		is_live_actionable_target = function()
			return true
		end,
		build_friendly_claims = function()
			return {}, {}
		end,
		mob_targets_friendly_member = function()
			return false
		end,
		sleep_max_target_distance = function()
			return 0
		end,
		target_sleep_suppressed = function()
			return false
		end,
		select_sleep_spell = function()
			return nil
		end,
		combat_autotarget = function()
			return true
		end,
		tank_enabled = function()
			return false
		end,
		debug_enabled = function()
			return false
		end,
		combat_prime = function()
			return false
		end,
		fight_leader_enabled = function()
			return true
		end,
		fight_leader_id = function()
			return 500
		end,
		fight_leader_target_id = function(leader_id)
			assert_equal(leader_id, 500, 'fight leader id')
			return leader_target_id
		end,
		select_pull = function()
			return nil
		end,
		build_party_id_set = function()
			return {}
		end,
		prime_unclaimed_party_aggressive_ok = function()
			return false
		end,
		pending_engage_state = function()
			return nil
		end,
		pending_engage_live = function()
			return false
		end,
		collect_ordered_abilities = function()
			return {}
		end,
		get_ja_resource = function()
			return nil
		end,
		action_ready = function()
			return false
		end,
		action_effective_range = function()
			return 0
		end,
		log_ja_sched = function()
		end,
		phase1 = {},
		action_state = {},
		skillchain_priority = 114,
		aftermath_priority = 112,
		sleep_priority = 113,
		tank_engage_priority = 107,
		default_engage_priority = 72,
		tank_engage_urgency = 0.85,
		default_engage_urgency = 0.70,
	})
end

local function make_target(id, name)
	return {
		id = id,
		name = name,
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		claim_id = 0,
	}
end

local function make_context(current_target, leader_target)
	return {
		now = 10,
		settings = {},
		player_present = true,
		player = {
			status = 1,
		},
		target_present = true,
		target = current_target,
		mobs_by_id = {
			[leader_target.id] = leader_target,
		},
	}
end

local function main()
	_G.Start_Engine = true

	local leader_target = make_target(300, 'Leader Target')
	local provider = make_provider(leader_target.id)

	local out = {}
	provider.collect_engage(make_context(leader_target, leader_target), out)
	assert_equal(#out, 0, 'already engaged leader target must not emit another engage proposal')

	local current_target = make_target(301, 'Old Target')
	out = {}
	provider.collect_engage(make_context(current_target, leader_target), out)
	assert_equal(#out, 1, 'different leader target must preserve the retarget engage proposal')
	assert_equal(out[1].action_type, 'engage', 'retarget proposal action type')
	assert_equal(out[1].target_id, leader_target.id, 'retarget proposal target id')

	io.stdout:write('selftest_fight_leader_engage: OK\n')
end

main()
