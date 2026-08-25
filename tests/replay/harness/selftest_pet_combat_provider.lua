package.path = './?.lua;' .. package.path

local adapter_module = require('uc_smn_pet_combat_adapter')
local provider_module = require('uc_pet_combat_provider')
local state_module = require('uc_pet_combat_state')

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

local function settings()
	return {
		summoner_enabled = true,
		summoner_avatar = 'Ifrit',
		summoner_avatar_favor = false,
		summoner_ward_enabled = false,
		summoner_ward_action = nil,
		summoner_engage_on_combat_start = true,
		summoner_rage_enabled = true,
		summoner_rage_action = 'Flaming Crush',
		summoner_rage_usage = 'on_cooldown',
	}
end

local function context()
	return {
		now = 10,
		settings = settings(),
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
		target_present = true,
		target = {
			id = 300,
			name = 'Enemy',
			hpp = 100,
			valid_target = true,
			x = 5,
			y = 0,
		},
		pet_present = true,
		pet_id = 200,
		pet_name = 'Ifrit',
		pet_status = 0,
		pet_target_id = 0,
		pet_target_matches_current = false,
		pet = {
			id = 200,
			name = 'Ifrit',
			x = 4,
			y = 0,
		},
		combat_domain_enabled = true,
		combat_committed = true,
		ability_recasts_present = true,
		ability_recasts = {
			[170] = 0,
			[173] = 0,
		},
	}
end

local blocked_keys = {}
local adapter = adapter_module.new({
	get_ja_resource = function(name)
		if name == 'Flaming Crush' then
			return {
				mp_cost = 164,
				range = 2,
			}
		end
		return nil
	end,
	action_effective_range = function(raw)
		assert_equal(raw, 2, 'Rage resource range')
		return 3.9
	end,
})
local function commitment_evaluate(ctx)
	local committed = ctx.combat_committed == true
	return { committed = committed, reason = committed and 'test_committed' or 'selection_only' }
end

local state = state_module.new()
local provider = provider_module.new({
	adapter = adapter,
	state = state,
	target_is_actionable = function(target)
		return target.valid_target == true and target.hpp > 0
	end,
	combat_commitment_evaluate = commitment_evaluate,
	coordinator_can_attempt = function(key)
		return blocked_keys[key] ~= true, blocked_keys[key] and 'retry_backoff' or '', 0
	end,
})

local function collect(ctx)
	provider.observe_target(ctx)
	local out = {}
	provider.collect(ctx, out)
	return out
end

local function find(actions, kind)
	for _, action in ipairs(actions) do
		if action.detail.pet_command.kind == kind then
			return action
		end
	end
	return nil
end

local function test_selection_only_does_not_start_pet_combat()
	_G.Start_Engine = true
	local local_provider = provider_module.new({
		adapter = adapter,
		state = state_module.new(),
		target_is_actionable = function(target)
			return target.valid_target == true and target.hpp > 0
		end,
		combat_commitment_evaluate = commitment_evaluate,
		coordinator_can_attempt = function()
			return true, '', 0
		end,
	})
	local ctx = context()
	ctx.combat_committed = false
	local_provider.observe_target(ctx)
	local actions = {}
	local_provider.collect(ctx, actions)
	assert_equal(ctx.target_valid, false, 'selected-only target must not be a pet combat target')
	assert_equal(ctx.combat_generation, 0, 'selected-only target must not start combat generation')
	assert_equal(find(actions, 'assault'), nil, 'selected-only target must not trigger Assault')
	assert_equal(find(actions, 'rage'), nil, 'selected-only target must not trigger Rage')

	ctx.combat_committed = true
	ctx.now = 11
	local_provider.observe_target(ctx)
	actions = {}
	local_provider.collect(ctx, actions)
	assert_equal(ctx.combat_generation, 1, 'combat commitment starts combat generation')
	assert_true(find(actions, 'assault') ~= nil, 'committed combat target triggers Assault')
	assert_true(find(actions, 'rage') ~= nil, 'committed combat target permits Rage')
end

local function test_generation_and_initial_actions()
	_G.Start_Engine = true
	local ctx = context()
	local actions = collect(ctx)
	assert_equal(ctx.combat_generation, 1, 'initial combat generation')
	assert_true(find(actions, 'assault') ~= nil, 'initial Assault candidate')
	assert_true(find(actions, 'rage') ~= nil, 'initial Rage candidate')
	assert_equal(find(actions, 'assault').priority_band, 147, 'Assault instant-action priority')
	assert_equal(find(actions, 'rage').priority_band, 146, 'Rage instant-action priority')
	assert_equal(find(actions, 'assault').movement_policy, 'none', 'Assault movement policy')
	assert_equal(find(actions, 'rage').movement_policy, 'none', 'Rage movement policy')

	ctx.now = 11
	actions = collect(ctx)
	assert_equal(ctx.combat_generation, 1, 'stable target generation')

	ctx.target_present = false
	ctx.target.valid_target = false
	actions = collect(ctx)
	assert_equal(#actions, 0, 'no target actions')
	ctx.target_present = true
	ctx.target.valid_target = true
	ctx.now = 12
	actions = collect(ctx)
	assert_equal(ctx.combat_generation, 2, 're-engagement generation')

	ctx.target.id = 301
	ctx.target.name = 'Enemy Two'
	ctx.now = 13
	actions = collect(ctx)
	assert_equal(ctx.combat_generation, 3, 'target switch generation')
end

local function test_engagement_identity()
	state = state_module.new()
	provider = provider_module.new({
		adapter = adapter,
		state = state,
		target_is_actionable = function(target)
			return target.valid_target == true and target.hpp > 0
		end,
		combat_commitment_evaluate = commitment_evaluate,
		coordinator_can_attempt = function()
			return true, '', 0
		end,
	})
	local ctx = context()
	local actions = collect(ctx)
	local assault = find(actions, 'assault')
	assert_true(assault ~= nil, 'Assault candidate before satisfaction')
	provider.observe_coordinator_event({
		outcome = 'complete',
		kind = 'assault',
		combat_generation = 1,
		pet_id = 200,
	})
	actions = collect(ctx)
	assert_equal(find(actions, 'assault'), nil, 'satisfied engagement must not be resent')

	ctx.pet_id = 201
	ctx.pet.id = 201
	actions = collect(ctx)
	assert_true(find(actions, 'assault') ~= nil, 'new pet instance must receive Assault')

	ctx.pet_status = 1
	actions = collect(ctx)
	assert_equal(find(actions, 'assault'), nil, 'engaged pet status satisfies engagement')
	ctx.pet_status = 0
	actions = collect(ctx)
	assert_equal(find(actions, 'assault'), nil, 'v1 must not continuously maintain engagement')
end

local function test_hard_prerequisites_and_rage_guards()
	local ctx = context()
	ctx.pet_name = 'Garuda'
	assert_equal(#collect(ctx), 0, 'wrong avatar must block Assault and Rage')

	ctx = context()
	ctx.settings.summoner_engage_on_combat_start = false
	local actions = collect(ctx)
	assert_equal(find(actions, 'assault'), nil, 'disabled engagement')
	assert_true(find(actions, 'rage') ~= nil, 'Rage must not require Assault to be enabled')

	ctx.ability_recasts[173] = 30
	actions = collect(ctx)
	assert_equal(find(actions, 'rage'), nil, 'Rage recast guard')

	ctx.ability_recasts[173] = 0
	ctx.player.vitals.mp = 163
	actions = collect(ctx)
	assert_equal(find(actions, 'rage'), nil, 'Rage MP guard')

	ctx.player.vitals.mp = 1000
	ctx.target.x = 20
	actions = collect(ctx)
	assert_equal(find(actions, 'rage'), nil, 'Rage pet-to-target range guard')
end

local function test_non_summoner_ignores_summoner_settings()
	local ctx = context()
	ctx.player.main_job = 'PLD'
	ctx.settings = {}
	assert_equal(#collect(ctx), 0, 'non-Summoner must not evaluate Summoner configuration')
	assert_equal(_G.UC_SMN_PET_COMBAT_STATUS.state, 'disabled', 'non-Summoner status')
end

local function test_pet_action_target_inference()
	state = state_module.new()
	provider = provider_module.new({
		adapter = adapter,
		state = state,
		target_is_actionable = function(target)
			return target.valid_target == true and target.hpp > 0
		end,
		combat_commitment_evaluate = commitment_evaluate,
		coordinator_can_attempt = function()
			return true, '', 0
		end,
	})
	local ctx = context()
	local actions = collect(ctx)
	local assault = find(actions, 'assault')
	assert_true(assault ~= nil, 'Assault candidate before pet action inference')
	assert_equal(provider.observe_pet_action({
		category = 1,
		actor_id = 999,
		targets = { { id = 300 } },
	}, 10.1), false, 'non-pet melee action must be ignored')
	assert_true(provider.observe_pet_action({
		category = 1,
		actor_id = 200,
		targets = { { id = 301 } },
	}, 10.2), 'pet melee target observation')
	ctx.pet_status = 1
	actions = collect(ctx)
	assert_true(find(actions, 'assault') ~= nil, 'different inferred pet target permits Assault')
	assert_true(provider.revalidate(assault, ctx), 'different inferred pet target permits commit')

	assert_true(provider.observe_pet_action({
		category = 1,
		actor_id = 200,
		targets = { { id = 300 } },
	}, 10.3), 'current-target pet melee observation')
	actions = collect(ctx)
	assert_equal(find(actions, 'assault'), nil, 'current-target pet action satisfies engagement')
end

local function test_stale_commit_validation()
	local ctx = context()
	local actions = collect(ctx)
	local rage = find(actions, 'rage')
	assert_true(rage ~= nil, 'Rage candidate for stale validation')
	local valid = provider.revalidate(rage, ctx)
	assert_true(valid, 'unchanged Rage capture')

	ctx.pet_id = 201
	ctx.pet.id = 201
	valid = provider.revalidate(rage, ctx)
	assert_equal(valid, false, 'stale Rage pet identity')

	ctx = context()
	actions = collect(ctx)
	rage = find(actions, 'rage')
	ctx.target.id = 301
	provider.observe_target(ctx)
	valid = provider.revalidate(rage, ctx)
	assert_equal(valid, false, 'stale Rage target identity')
end

test_selection_only_does_not_start_pet_combat()
test_generation_and_initial_actions()
test_engagement_identity()
test_hard_prerequisites_and_rage_guards()
test_non_summoner_ignores_summoner_settings()
test_pet_action_target_inference()
test_stale_commit_validation()

print('selftest_pet_combat_provider: OK')
