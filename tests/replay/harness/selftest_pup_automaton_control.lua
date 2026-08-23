package.path = './?.lua;' .. package.path

local commands = require('uc_pet_commands')
local coordinator = require('uc_pet_command_coordinator')
local runtime = require('uc_pup_runtime')
local adapter_module = require('uc_pup_pet_combat_adapter')

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

local function assert_false(value, message)
	if value ~= false then
		error(message)
	end
end

local function config()
	return runtime.config_from_settings({
		puppetmaster = {
			enabled = true,
			activate_if_missing = true,
			deploy_on_combat_start = true,
			maneuvers = {
				enabled = true,
				pattern = { 'Fire Maneuver', 'Fire Maneuver', 'Light Maneuver' },
				post_activate_quiet_seconds = 120,
				safe_burden_ceiling = 30,
			},
		},
	})
end

local function ctx(now, pet_present, buffs)
	local player_buffs = buffs or {}
	return {
		now = now,
		settings = {
			puppetmaster = config(),
		},
		player_present = true,
		player_id = 100,
		player_name = 'Tester',
		player = {
			id = 100,
			name = 'Tester',
			main_job = 'PUP',
			buffs = player_buffs,
		},
		player_buffs = player_buffs,
		pet_present = pet_present == true,
		pet_id = pet_present == true and 200 or 0,
		pet_name = pet_present == true and 'Automaton' or '',
		pet_status = 0,
		pet_inferred_target_id = 0,
		ability_recasts_present = true,
		ability_recasts = {
			[runtime.RECAST_ACTIVATE] = 0,
			[runtime.RECAST_DEPLOY] = 0,
			[runtime.RECAST_MANEUVER] = 0,
		},
		target_valid = true,
		target_id = 300,
		target_hpp = 100,
		combat_generation = 4,
	}
end

local function activate_command()
	return {
		kind = 'activate',
		action_name = 'Activate',
		recast_id = runtime.RECAST_ACTIVATE,
		recast_before = 0,
		retry_key = 'pup:activate',
	}
end

local function maneuver_command()
	return {
		kind = 'maneuver',
		action_name = 'Fire Maneuver',
		action_id = 141,
		recast_id = 210,
		recast_before = 0,
		pet_id = 200,
		retry_key = 'pup:maneuver:Fire Maneuver',
	}
end

local function test_command_contract()
	assert_equal(
		commands.serialize(activate_command()),
		'input /ja "Activate" <me>',
		'Activate serialization'
	)
	local deploy = {
		kind = 'deploy',
		action_name = 'Deploy',
		pet_id = 200,
		target_id = 300,
		combat_generation = 4,
		retry_key = 'pup:deploy:4:200',
	}
	assert_equal(commands.serialize(deploy), 'input /pet "Deploy" 300', 'Deploy serialization')
	assert_equal(
		commands.serialize(maneuver_command()),
		'input /pet "Fire Maneuver" <me>',
		'Maneuver serialization'
	)
end

local function test_coordinator_completion()
	local state = coordinator.new({
		timeout = 2.5,
		ward_effect_timeout = 8.0,
		backoff_base = 1.0,
		backoff_max = 8.0,
	})

	coordinator.begin(state, activate_command(), 0)
	local activate_pending_ctx = ctx(0.1, false, {})
	activate_pending_ctx.ability_recasts[runtime.RECAST_ACTIVATE] = 1200
	assert_equal(
		coordinator.observe(state, activate_pending_ctx),
		nil,
		'Activate recast consumption alone must not complete automaton creation'
	)
	local activate_live_ctx = ctx(0.2, true, {})
	activate_live_ctx.ability_recasts[runtime.RECAST_ACTIVATE] = 1200
	local event = coordinator.observe(state, activate_live_ctx)
	assert_equal(event.outcome, 'complete', 'Activate completion outcome')
	assert_equal(event.reason, 'automaton_appeared', 'Activate completion evidence')

	local deploy = {
		kind = 'deploy',
		action_name = 'Deploy',
		pet_id = 200,
		target_id = 300,
		combat_generation = 4,
		retry_key = 'pup:deploy:4:200',
	}
	coordinator.begin(state, deploy, 1)
	local deploy_ctx = ctx(1.1, true, {})
	deploy_ctx.pet_status = 1
	event = coordinator.observe(state, deploy_ctx)
	assert_equal(event.outcome, 'complete', 'Deploy completion outcome')
	assert_equal(event.reason, 'pet_engaged_observed', 'Deploy completion evidence')

	local maneuver = maneuver_command()
	coordinator.begin(state, maneuver, 2)
	local maneuver_ctx = ctx(2.1, true, {})
	maneuver_ctx.ability_recasts[210] = 10
	event = coordinator.observe(state, maneuver_ctx)
	assert_equal(event.outcome, 'complete', 'Maneuver completion outcome')
	assert_equal(event.reason, 'maneuver_recast_consumed', 'Maneuver recast completion evidence')

	coordinator.begin(state, maneuver, 3)
	local overload_ctx = ctx(3.1, true, { runtime.BUFF_OVERLOAD })
	event = coordinator.observe(state, overload_ctx)
	assert_equal(event.outcome, 'failed', 'Overload must fail in-flight maneuver command')
	assert_equal(event.reason, 'overload_observed', 'Overload failure reason')
end

local function test_burden_guard()
	local state = runtime.new_state()
	local cfg = config()
	local live = ctx(0, true, {})
	runtime.observe(state, live, 0, cfg)

	local safe, reason = runtime.maneuver_safe(state, cfg, live, 'Fire Maneuver', 1)
	assert_false(safe, 'post-Activate quiet period must block maneuvers')
	assert_equal(reason, 'post_activate_or_zone_quiet', 'post-Activate guard reason')

	live.now = 121
	runtime.observe(state, live, 121, cfg)
	safe, reason = runtime.maneuver_safe(state, cfg, live, 'Fire Maneuver', 121)
	assert_true(safe, 'maneuver must become safe after conservative burden drain')
	assert_equal(reason, '', 'safe maneuver reason')

	assert_true(runtime.record_maneuver(state, 'Fire Maneuver', 121), 'first Fire maneuver should record burden')
	safe, reason, _, wait_seconds = runtime.maneuver_safe(state, cfg, live, 'Fire Maneuver', 121.1)
	assert_false(safe, 'immediate second worst-case Fire maneuver must be blocked')
	assert_equal(reason, 'burden_guard', 'burden ceiling guard reason')
	assert_true(wait_seconds > 29 and wait_seconds < 31, 'burden guard should wait about thirty seconds')

	live.now = 151
	safe = runtime.maneuver_safe(state, cfg, live, 'Fire Maneuver', 151)
	assert_true(safe, 'second Fire maneuver should become safe after enough decay')
end

local function test_pattern_convergence()
	local cfg = config()
	local fire = runtime.maneuver('Fire Maneuver')
	local light = runtime.maneuver('Light Maneuver')
	local player = { buffs = {} }
	assert_equal(runtime.next_missing_maneuver(cfg, player), 'Fire Maneuver', 'empty pattern first need')
	player.buffs = { fire.buff_id }
	assert_equal(runtime.next_missing_maneuver(cfg, player), 'Fire Maneuver', 'one Fire still needs second Fire')
	player.buffs = { fire.buff_id, fire.buff_id }
	assert_equal(runtime.next_missing_maneuver(cfg, player), 'Light Maneuver', 'two Fires need Light')
	player.buffs = { fire.buff_id, fire.buff_id, light.buff_id }
	assert_equal(runtime.next_missing_maneuver(cfg, player), nil, 'configured three-slot multiset satisfied')
end

local function test_adapter_activate_deploy_and_maneuver()
	local resources = {
		Activate = { range = 0 },
		Deploy = { range = 12 },
	}
	local adapter = adapter_module.new({
		get_ja_resource = function(name)
			return resources[name]
		end,
		action_effective_range = function(range)
			return tonumber(range) or 0
		end,
	})

	local no_pet = ctx(0, false, {})
	local snapshot = adapter.snapshot(no_pet)
	local maintenance = adapter.maintenance(snapshot, no_pet)
	assert_equal(maintenance.action_name, 'Activate', 'missing automaton must propose Activate')
	assert_equal(maintenance.action_type, 'pet', 'Activate must use serialized pet-related lane')
	assert_equal(maintenance.command.kind, 'activate', 'Activate coordinator command kind')

	-- First automaton observation deliberately starts the conservative burden
	-- quiet window. Maneuver maintenance must wait until it drains.
	local pet = ctx(121, true, {})
	snapshot = adapter.snapshot(pet)
	assert_equal(adapter.maintenance(snapshot, pet), nil, 'new automaton must honor post-Activate burden quiet')

	pet.now = 242
	snapshot = adapter.snapshot(pet)
	maintenance = adapter.maintenance(snapshot, pet)
	assert_equal(maintenance.action_name, 'Fire Maneuver', 'first missing maneuver proposal')
	assert_equal(maintenance.action_type, 'pet', 'Maneuver uses pet command lane')
	assert_equal(maintenance.command.kind, 'maneuver', 'Maneuver command kind')

	local deploy = adapter.engagement(snapshot, pet)
	assert_equal(deploy.action_name, 'Deploy', 'combat engagement must propose Deploy')
	assert_equal(deploy.command.kind, 'deploy', 'Deploy command kind')
	assert_equal(deploy.command.target_id, 300, 'Deploy target identity')
end

test_command_contract()
test_coordinator_completion()
test_burden_guard()
test_pattern_convergence()
test_adapter_activate_deploy_and_maneuver()

print('selftest_pup_automaton_control: OK')
