local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local original_start_engine = rawget(_G, 'Start_Engine')

local function generic_deps(ability_name, ja_targets)
	return {
		bool_setting = function(value, default_value)
			if value == nil then return default_value end
			return value == true
		end,
		clamp_urgency = function(value) return value end,
		build_partner_target_set = function() return {} end,
		select_ws_plan = function() return nil end,
        weaponskill_enabled = function() return false end,
		weaponskill_enabled = function() return false end,
		action_timeline_log = function() end,
		combat_domain_enabled = function() return true end,
		sleep_enabled = function() return false end,
		sleep_spell_list = function() return {} end,
		is_live_actionable_target = function() return true end,
		build_friendly_claims = function() return {}, {} end,
		mob_targets_friendly_member = function() return false end,
		sleep_max_target_distance = function() return 20 end,
		target_sleep_suppressed = function() return false end,
		select_sleep_spell = function() return nil end,
		combat_autotarget = function() return false end,
		tank_enabled = function() return false end,
		debug_enabled = function() return false end,
		combat_prime = function() return false end,
		fight_leader_enabled = function() return false end,
		fight_leader_id = function() return 0 end,
		fight_leader_target_id = function() return 0 end,
		add_control_enabled = function() return false end,
		select_pull = function() return nil end,
		build_party_id_set = function() return {} end,
		prime_unclaimed_party_aggressive_ok = function() return false end,
		pending_engage_state = function() return nil end,
		pending_engage_live = function() return false end,
		collect_ordered_abilities = function() return { ability_name } end,
		get_ja_resource = function(name)
			if name ~= ability_name then return nil end
			return { name = name, targets = ja_targets, range = 0 }
		end,
		action_ready = function(name)
			if name == ability_name then return true, 'OK', 'ja' end
			return false, 'NOT_READY', 'ja'
		end,
		action_effective_range = function() return 0 end,
		log_ja_sched = function() end,
		phase1 = {},
		action_state = {},
		skillchain_priority = 131,
		aftermath_priority = 130,
		sleep_priority = 142,
		tank_engage_priority = 120,
		default_engage_priority = 110,
		tank_engage_urgency = 1,
		default_engage_urgency = 0.5,
	}
end

local function enemy_target(id)
	return {
		id = id or 900,
		name = 'Test Enemy',
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		distance = 0,
	}
end

local ok, err = xpcall(function()
	_G.Start_Engine = true

	local combat_provider = require('uc_provider_combat')

	-- Existing default stays strict: unengaged players do not use configured JAs.
	local provider = combat_provider.new(generic_deps('Provoke', '{Enemy}'))
	local ctx = {
		now = 10,
		settings = { ability_active = true, ability_allow_unengaged = false },
		player_present = true,
		player = { id = 1, name = 'PLD', status = 0, vitals = { tp = 0 } },
		target_present = true,
		target = enemy_target(900),
		mobs_by_id = {}, mob_array = {}, party = {},
	}
	local out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 0, 'toggle-off unengaged JA must remain gated')

	-- Toggle on still requires a live enemy target; it is not an idle prebuff switch.
	ctx.settings.ability_allow_unengaged = true
	ctx.target_present = false
	ctx.target = nil
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 0, 'unengaged JA override must require a combat target')

	ctx.target_present = true
	ctx.target = enemy_target(900)
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 1, 'unengaged enemy JA must be proposed with valid target')
	assert_equal(out[1].action_name, 'Provoke', 'enemy JA action mismatch')
	assert_equal(out[1].target_id, 900, 'enemy JA target mismatch')
	assert_true(out[1].detail.unengaged_override, 'proposal must report unengaged override')

	-- Self-target hate tools such as Sentinel are allowed while unengaged only
	-- because the same valid enemy target proves that combat context exists.
	provider = combat_provider.new(generic_deps('Sentinel', '{Self}'))
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 1, 'self JA must be usable unengaged when combat target exists')
	assert_equal(out[1].target_kind, 'self', 'self JA target kind mismatch')
	assert_equal(out[1].target_id, 1, 'self JA target id mismatch')

	-- Engaged behavior is unchanged even when the new toggle is off.
	ctx.player.status = 1
	ctx.settings.ability_allow_unengaged = false
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 1, 'engaged JA behavior must remain unchanged')

	-- Dedicated tank-enmity provider has the same gate so PLD's tank action list
	-- does not remain partially engagement-locked.
	local tank_provider = require('uc_provider_tank_enmity').new({
		bool_setting = function(value, default_value)
			if value == nil then return default_value end
			return value == true
		end,
		select_tank_enmity = function()
			return {
				kind = 'ja', name = 'Provoke', target_id = 900, target_name = 'Test Enemy',
				action_range = 20, victim_hpp = 100,
			}
		end,
		action_ready = function() return true, 'OK', 'ja' end,
		log_tank_sched = function() end,
		clamp_urgency = function(value) return value end,
	})
	ctx.player.status = 0
	ctx.settings.ability_allow_unengaged = false
	ctx.mobs_by_id = { [900] = enemy_target(900) }
	out = {}
	tank_provider.collect(ctx, out)
	assert_equal(#out, 0, 'tank enmity must remain gated while override is off')

	ctx.settings.ability_allow_unengaged = true
	out = {}
	tank_provider.collect(ctx, out)
	assert_equal(#out, 1, 'tank enmity must be usable unengaged with valid target')
	assert_equal(out[1].target_id, 900, 'tank enmity target mismatch')

	ctx.mobs_by_id[900].hpp = 0
	out = {}
	tank_provider.collect(ctx, out)
	assert_equal(#out, 0, 'tank enmity must reject dead/stale unengaged target')
end, debug.traceback)

_G.Start_Engine = original_start_engine
if not ok then
	error(err)
end

io.stdout:write('selftest_unengaged_abilities: OK\n')
