package.path = './?.lua;' .. package.path

package.loaded.uc_reaction_runtime = {
	smn_rage_should_hold = function()
		return false, '', nil
	end,
}

local coordinator = require('uc_pet_command_coordinator')
local maintenance_module = require('uc_smn_maintenance')
local adapter_module = require('uc_smn_pet_combat_adapter')
local pet_provider_module = require('uc_pet_combat_provider')
local pet_state_module = require('uc_pet_combat_state')
local runtime = require('uc_smn_runtime')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local function context()
	local ctx = {
		now = 10,
		settings = {
			summoner_enabled = true,
			summoner_avatar = 'Ifrit',
			summoner_avatar_favor = true,
			summoner_ward_enabled = true,
			summoner_ward_action = 'Crimson Howl',
			summoner_engage_on_combat_start = true,
			summoner_rage_enabled = true,
			summoner_rage_action = 'Flaming Crush',
			summoner_rage_usage = 'on_cooldown',
			summoner_rage_target_hpp_above_enabled = false,
			summoner_rage_target_hpp_above = 50,
			summoner_rage_pet_tp_above_enabled = false,
			summoner_rage_pet_tp_above = 2000,
		},
		player_present = true,
		player = {
			id = 100,
			name = 'Tester',
			main_job = 'SMN',
			vitals = {
				mp = 1000,
			},
			buffs = {},
		},
		player_id = 100,
		player_name = 'Tester',
		pet_present = true,
		pet_id = 200,
		pet_name = 'Ifrit',
		pet_status = 0,
		pet_target_id = 0,
		pet_target_matches_current = false,
		pet_tp = 3000,
		pet = {
			id = 200,
			name = 'Ifrit',
			x = 4,
			y = 0,
		},
		target_present = true,
		target = {
			id = 300,
			name = 'Enemy',
			hpp = 100,
			valid_target = true,
			x = 5,
			y = 0,
		},
		combat_domain_enabled = true,
		combat_committed = true,
		ability_recasts_present = true,
		ability_recasts = {
			[170] = 0,
			[172] = 0,
			[173] = 0,
			[174] = 0,
		},
	}
	ctx.config = { summoner = select(1, runtime.config_from_settings(ctx.settings)) }
	return ctx
end

local command_state = coordinator.new({
	timeout = 2.5,
	ward_effect_timeout = 8.0,
	backoff_base = 1,
	backoff_max = 8,
})
local function can_attempt(key, now)
	return coordinator.can_attempt(command_state, key, now)
end

local maintenance = maintenance_module.new({
	action_ready = function(name)
		if name == 'Avatar\'s Favor' then
			return true, '', 'ja'
		end
		return false, 'not_used', 'none'
	end,
	coordinator_can_attempt = can_attempt,
	player_is_moving = function()
		return false
	end,
	get_ja_resource = function(name)
		if name == 'Crimson Howl' then
			return { mp_cost = 84 }
		end
		return nil
	end,
	log = function()
	end,
})
local adapter = adapter_module.new({
	get_ja_resource = function(name)
		if name == 'Flaming Crush' then
			return { mp_cost = 164, range = 2 }
		end
		return nil
	end,
	action_effective_range = function()
		return 3.9
	end,
})
local pet_provider = pet_provider_module.new({
	adapter = adapter,
	state = pet_state_module.new(),
	target_is_actionable = function(target)
		return target.valid_target == true and target.hpp > 0
	end,
	combat_commitment_evaluate = function(ctx)
		return { committed = ctx.combat_committed == true, reason = ctx.combat_committed == true and 'test_committed' or 'selection_only' }
	end,
	coordinator_can_attempt = can_attempt,
})

local function collect_all(ctx)
	pet_provider.observe_target(ctx)
	local out = {}
	maintenance.collect(ctx, out)
	pet_provider.collect(ctx, out)
	return out
end

local function contains_kind(actions, kind)
	for _, action in ipairs(actions) do
		if type(action.detail) == 'table'
			and type(action.detail.pet_command) == 'table'
			and action.detail.pet_command.kind == kind then
			return true
		end
	end
	return false
end

local function find_kind(actions, kind)
	for _, action in ipairs(actions) do
		if type(action.detail) == 'table'
			and type(action.detail.pet_command) == 'table'
			and action.detail.pet_command.kind == kind then
			return action
		end
	end
	return nil
end

local function contains_action(actions, name)
	for _, action in ipairs(actions) do
		if action.action_name == name then
			return true
		end
	end
	return false
end

local function score(action)
	return action.priority_band + action.urgency * 9.9
end

local function test_priority_order()
	_G.Start_Engine = true
	local actions = collect_all(context())
	table.sort(actions, function(left, right)
		return left.priority_band > right.priority_band
	end)
	assert_equal(actions[1].action_name, 'Avatar\'s Favor', 'Summoner priority 1')
	assert_equal(actions[2].action_name, 'Crimson Howl', 'Summoner priority 2')
	assert_equal(actions[3].action_name, 'Assault', 'Summoner priority 3')
	assert_equal(actions[4].action_name, 'Flaming Crush', 'Summoner priority 4')
	local critical_cure_score = 250 + 0.70 * 9.9
	local maximum_sleep_score = 142 + 1.00 * 9.9
	local release_score = 149 + 1.00 * 9.9
	assert_true(critical_cure_score > release_score, 'Release must remain below critical Cure')
	assert_true(release_score > maximum_sleep_score, 'Release must outrank maximum-urgency Sleep')
	for _, action in ipairs(actions) do
		assert_true(
			critical_cure_score > score(action),
			action.action_name .. ' must remain below critical Cure'
		)
		assert_true(
			score(action) > maximum_sleep_score,
			action.action_name .. ' must outrank maximum-urgency Sleep'
		)
	end
end

local function test_shared_serialization()
	local ctx = context()
	coordinator.begin(command_state, {
		kind = 'ward',
		action_name = 'Crimson Howl',
		action_id = 548,
		recast_id = 174,
		recast_before = 0,
		expected_effect_ids = { 68 },
		pet_id = 200,
		retry_key = 'smn:ward:Crimson Howl',
	}, ctx.now)
	local actions = collect_all(ctx)
	assert_equal(contains_kind(actions, 'ward'), false, 'pending Ward suppresses duplicate Ward')
	assert_equal(contains_kind(actions, 'assault'), false, 'pending Ward serializes Assault')
	assert_equal(contains_kind(actions, 'rage'), false, 'pending Ward serializes Rage')

	local failure = coordinator.fail(command_state, ctx.now + 0.1, 'test_failure')
	assert_equal(failure.retry_delay, 1, 'Ward failure backoff')
	ctx.now = 10.2
	actions = collect_all(ctx)
	assert_equal(contains_kind(actions, 'ward'), false, 'Ward remains in its own backoff')
	assert_true(contains_kind(actions, 'assault'), 'Ward backoff must not starve Assault')
	assert_true(contains_kind(actions, 'rage'), 'Ward backoff must not starve Rage')
end

local function test_astral_conduit_focus()
	local ctx = context()
	ctx.player.buffs = { 504 }
	local actions = collect_all(ctx)

	assert_equal(
		contains_action(actions, 'Avatar\'s Favor'),
		false,
		'Avatar Favor maintenance must not steal Astral Conduit action time'
	)
	assert_equal(
		contains_action(actions, 'Crimson Howl'),
		false,
		'Ward maintenance must not steal Astral Conduit action time'
	)
	local rage = find_kind(actions, 'rage')
	assert_true(rage ~= nil, 'Rage must remain available during Astral Conduit')
	assert_equal(
		rage.detail.pet_command.astral_conduit,
		true,
		'Rage command must carry Astral Conduit lifecycle metadata'
	)
end

local function test_optional_rage_gates()
	local ctx = context()
	ctx.pet_tp = nil
	assert_true(contains_kind(collect_all(ctx), 'rage'), 'disabled gates must not require pet TP')

	ctx.pet_tp = 3000
	ctx.config.summoner.pet_combat.offensive_action.target_hpp_above_enabled = true
	ctx.target.hpp = 50
	assert_equal(contains_kind(collect_all(ctx), 'rage'), false, 'target HPP equal to threshold must suppress Rage')
	ctx.target.hpp = 51
	assert_true(contains_kind(collect_all(ctx), 'rage'), 'target HPP above threshold must allow Rage')

	ctx.config.summoner.pet_combat.offensive_action.target_hpp_above_enabled = false
	ctx.config.summoner.pet_combat.offensive_action.pet_tp_above_enabled = true
	ctx.config.summoner.pet_combat.offensive_action.pet_tp_above = 2000
	ctx.pet_tp = 2000
	assert_equal(contains_kind(collect_all(ctx), 'rage'), false, 'pet TP equal to threshold must suppress Rage')
	ctx.pet_tp = 2001
	assert_true(contains_kind(collect_all(ctx), 'rage'), 'pet TP above threshold must allow Rage')

	ctx.config.summoner.pet_combat.offensive_action.target_hpp_above_enabled = true
	ctx.config.summoner.pet_combat.offensive_action.target_hpp_above = 50
	ctx.config.summoner.pet_combat.offensive_action.pet_tp_above = 2999
	ctx.target.hpp = 51
	ctx.pet_tp = 3000
	assert_true(contains_kind(collect_all(ctx), 'rage'), 'both enabled gates must allow Rage when both pass')
	ctx.target.hpp = 50
	assert_equal(contains_kind(collect_all(ctx), 'rage'), false, 'both enabled gates must reject failed target HPP')
	ctx.target.hpp = 51
	ctx.pet_tp = 2999
	assert_equal(contains_kind(collect_all(ctx), 'rage'), false, 'both enabled gates must reject failed pet TP')

	ctx.pet_tp = nil
	assert_equal(
		contains_kind(collect_all(ctx), 'rage'),
		false,
		'enabled pet TP gate must suppress only Rage when live pet TP is unavailable'
	)
end

test_priority_order()
test_shared_serialization()
test_astral_conduit_focus()
test_optional_rage_gates()

print('selftest_smn_cross_provider_integration: OK')
