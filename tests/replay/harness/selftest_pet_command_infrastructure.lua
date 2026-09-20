package.path = './?.lua;' .. package.path

local commands = require('uc_pet_commands')
local coordinator = require('uc_pet_command_coordinator')
local context_builder = require('uc_scheduler_context')
local locks = require('uc_scheduler_locks')

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

local function assert_error(fn, expected_fragment)
	local ok, message = pcall(fn)
	if ok then
		error('expected error containing: ' .. expected_fragment)
	end
	if not tostring(message):find(expected_fragment, 1, true) then
		error(('expected error containing %q, got %q'):format(expected_fragment, tostring(message)))
	end
end

local function new_state()
	return coordinator.new({
		timeout = 2.5,
		ward_effect_timeout = 8.0,
		backoff_base = 1.0,
		backoff_max = 8.0,
	})
end

local function base_command(kind)
	local command = {
		kind = kind,
		action_name = kind == 'release' and 'Release' or 'Assault',
		pet_id = 200,
		retry_key = 'smn:' .. kind,
	}
	if kind == 'assault' or kind == 'rage' then
		command.target_id = 300
		command.combat_generation = 4
	end
	if kind == 'ward' or kind == 'rage' then
		command.action_name = kind == 'ward' and 'Crimson Howl' or 'Flaming Crush'
		command.action_id = kind == 'ward' and 323 or 164
		command.recast_id = kind == 'ward' and 174 or 173
		command.recast_before = 0
	end
	if kind == 'ward' then
		command.expected_effect_ids = { 68, 69 }
	end
	return command
end

local function context(now)
	return {
		now = now,
		pet_present = true,
		pet_id = 200,
		pet_status = 0,
		pet_target_id = 0,
		pet_inferred_target_id = 0,
		player_buffs = {},
		ability_recasts_present = true,
		ability_recasts = {
			[173] = 0,
			[174] = 0,
		},
		combat_generation = 4,
		target_id = 300,
		target_valid = true,
		target_hpp = 100,
	}
end

local function test_command_contract()
	local assault = base_command('assault')
	local action_type, kind = commands.classify(assault)
	assert_equal(action_type, 'pet', 'pet action classification')
	assert_equal(kind, 'assault', 'pet command kind')
	assert_equal(commands.serialize(assault), 'input /pet "Assault" 300', 'Assault command serialization')
	assert_equal(
		commands.serialize(base_command('ward')),
		'input /pet "Crimson Howl" <me>',
		'Ward command serialization'
	)
	assert_error(function()
		commands.serialize({
			kind = 'rage',
			action_name = 'Flaming Crush',
			pet_id = 200,
			target_id = 300,
			action_id = 164,
			recast_id = 173,
		})
	end, 'combat_generation')
end

local function test_context_capture()
	local mobs = {
		{ id = 100, index = 10, name = 'Tester' },
		{ id = 200, index = 20, name = 'Ifrit', target_index = 30 },
		{ id = 300, index = 30, name = 'Enemy', hpp = 100, valid_target = true },
	}
	local by_target = {
		me = mobs[1],
		t = mobs[3],
		pet = mobs[2],
	}
	local built = context_builder.build({}, { tick = 0 }, {
		get_player = function()
			return { id = 100, name = 'Tester', status = 1 }
		end,
		get_mob_by_target = function(target)
			return by_target[target]
		end,
		get_mob_by_index = function(index)
			for _, mob in ipairs(mobs) do
				if mob.index == index then
					return mob
				end
			end
			return nil
		end,
		get_party = function()
			return {}
		end,
		get_mob_array = function()
			return mobs
		end,
		now = function()
			return 12.5
		end,
	})
	assert_true(built.pet_present, 'context must capture the live pet')
	assert_equal(built.pet_id, 200, 'context pet server id')
	assert_equal(built.pet_name, 'Ifrit', 'context pet name')
	assert_equal(built.pet_target_id, 300, 'context pet target server id')
	assert_equal(built.pet_target_matches_current, true, 'context pet/current target index match')
end

local function test_serialization_and_completion()
	local state = new_state()
	coordinator.begin(state, base_command('release'), 1)
	assert_true(coordinator.is_pending(state), 'Release must reserve the shared pet channel')
	assert_error(function()
		coordinator.begin(state, base_command('assault'), 1.1)
	end, 'another pet command')
	local release_ctx = context(1.2)
	release_ctx.pet_present = false
	release_ctx.pet_id = 0
	local release_event = coordinator.observe(state, release_ctx)
	assert_equal(release_event.outcome, 'complete', 'Release completion outcome')
	assert_equal(release_event.reason, 'pet_disappeared', 'Release completion evidence')

	coordinator.begin(state, base_command('assault'), 2)
	local assault_ctx = context(2.1)
	assault_ctx.pet_target_id = 0
	assault_ctx.pet_status = 1
	local assault_event = coordinator.observe(state, assault_ctx)
	assert_equal(assault_event.reason, 'pet_engaged_observed', 'Assault engaged-state observation')

	coordinator.begin(state, base_command('assault'), 2.2)
	local inferred_other_ctx = context(2.3)
	inferred_other_ctx.pet_status = 1
	inferred_other_ctx.pet_inferred_target_id = 301
	assert_equal(coordinator.observe(state, inferred_other_ctx), nil, 'different inferred pet target must not satisfy Assault')
	local inferred_target_event = coordinator.observe_action(state, {
		category = 1,
		actor_id = 200,
		targets = { { id = 300 } },
	}, 2.4)
	assert_equal(inferred_target_event.reason, 'pet_action_on_target', 'pet action target completes Assault')

	coordinator.begin(state, base_command('ward'), 3)
	local ward_ctx = context(3.1)
	ward_ctx.ability_recasts[174] = 45
	assert_equal(
		coordinator.observe(state, ward_ctx),
		nil,
		'Ward recast consumption must not complete the pact before its action resolves'
	)
	assert_true(coordinator.is_pending(state), 'Ward must remain pending during its action animation')
	local release_allowed, release_reason = coordinator.can_attempt(state, 'smn:release:200', 3.2)
	assert_equal(release_allowed, false, 'Release must remain blocked until the Ward action resolves')
	assert_equal(release_reason, 'pet_command_pending', 'Release must remain on the shared pet-command lock')
	local partial_effect_ctx = context(3.3)
	partial_effect_ctx.player_buffs = { 68 }
	assert_equal(
		coordinator.observe(state, partial_effect_ctx),
		nil,
		'Ward must remain pending until every maintained effect is present'
	)
	local ward_event = coordinator.observe_action(state, {
		category = 7,
		actor_id = 200,
		param = 323,
		targets = { { id = 100 } },
	}, 3.4)
	assert_equal(ward_event, nil, 'Ward readying packet must only acknowledge the action')
	assert_true(coordinator.is_pending(state), 'Ward readying packet must keep Release blocked')
	ward_event = coordinator.observe_action(state, {
		category = 13,
		actor_id = 200,
		param = 323,
		targets = { { id = 100 } },
	}, 5.9)
	assert_equal(ward_event, nil, 'Ward finish packet must wait for maintained effects')
	assert_true(coordinator.is_pending(state), 'Ward finish packet must keep Release blocked until effects appear')
	local extended_wait_ctx = context(6.0)
	assert_equal(
		coordinator.observe(state, extended_wait_ctx),
		nil,
		'Ward-specific effect timeout must outlive the generic pet-command timeout'
	)
	release_allowed, release_reason = coordinator.can_attempt(state, 'smn:release:200', 6.1)
	assert_equal(release_allowed, false, 'Release must remain blocked after the Ward finish packet')
	assert_equal(release_reason, 'pet_command_pending', 'Ward effect wait must retain the shared pet-command lock')
	local complete_effect_ctx = context(6.2)
	complete_effect_ctx.player_buffs = { 68, 69 }
	ward_event = coordinator.observe(state, complete_effect_ctx)
	assert_equal(ward_event.reason, 'ward_effect_observed', 'all Ward effects complete the command')

	coordinator.begin(state, base_command('rage'), 7)
	local rage_ctx = context(7.1)
	rage_ctx.ability_recasts[173] = 45
	local rage_event = coordinator.observe(state, rage_ctx)
	assert_equal(rage_event.reason, 'rage_recast_consumed', 'Rage recast observation')
end

local function test_action_events_and_stale_identity()
	local state = new_state()
	coordinator.begin(state, base_command('rage'), 1)
	local event = coordinator.observe_action(state, {
		actor_id = 200,
		param = 164,
		targets = { { id = 300 } },
	}, 1.2)
	assert_equal(event.reason, 'pet_action_completed', 'pet action packet completion')

	coordinator.begin(state, base_command('rage'), 2)
	local stale_pet = context(2.1)
	stale_pet.pet_id = 201
	local stale_pet_event = coordinator.observe(state, stale_pet)
	assert_equal(stale_pet_event.reason, 'stale_pet', 'stale pet cancellation')

	local allowed, reason = coordinator.can_attempt(state, 'smn:rage', 2.2)
	assert_equal(allowed, false, 'failed action must enter backoff')
	assert_equal(reason, 'retry_backoff', 'failed action backoff reason')
end

local function test_failure_timeout_and_backoff()
	local state = new_state()
	coordinator.begin(state, base_command('assault'), 1)
	local interrupted = coordinator.observe_action_message(state, {
		actor_id = 100,
		target_id = 300,
		message_id = 16,
	}, 100, 1.1)
	assert_equal(interrupted.reason, 'interrupted', 'interruption recognition')
	assert_equal(interrupted.retry_delay, 1, 'first failure backoff')

	local allowed = coordinator.can_attempt(state, 'smn:assault', 2.1)
	assert_equal(allowed, true, 'first backoff expiry')
	coordinator.begin(state, base_command('assault'), 2.1)
	local timed_out = coordinator.observe(state, context(4.6))
	assert_equal(timed_out.reason, 'timeout', 'watchdog timeout')
	assert_equal(timed_out.retry_delay, 2, 'exponential retry backoff')

	allowed = coordinator.can_attempt(state, 'smn:assault', 6.59)
	assert_equal(allowed, false, 'second backoff must remain active')
	allowed = coordinator.can_attempt(state, 'smn:assault', 6.6)
	assert_equal(allowed, true, 'second backoff expiry')
end

local function test_conduit_rage_lifecycle()
	local state = new_state()
	local command = base_command('rage')
	command.astral_conduit = true

	coordinator.begin(state, command, 1.0)
	local readying = coordinator.observe_action(state, {
		category = 7,
		actor_id = 200,
		param = 164,
		targets = { { id = 300 } },
	}, 1.2)
	assert_equal(readying, nil, 'Conduit Rage readying packet must not release the pet lane')
	assert_true(coordinator.is_pending(state), 'Conduit Rage must remain pending through readying')

	local still_pending = coordinator.observe(state, context(3.8))
	assert_equal(still_pending, nil, 'Conduit Rage readying must extend beyond the generic 2.5 second timeout')
	assert_true(coordinator.is_pending(state), 'Conduit Rage must remain pending until the result packet')

	local completed = coordinator.observe_action(state, {
		category = 13,
		actor_id = 200,
		param = 164,
		targets = { { id = 300 } },
	}, 4.0)
	assert_equal(completed.outcome, 'complete', 'Conduit Rage result outcome')
	assert_equal(completed.reason, 'pet_action_completed', 'Conduit Rage result completion')

	coordinator.begin(state, command, 5.0)
	local timed_out = coordinator.observe(state, context(6.3))
	assert_equal(timed_out.reason, 'conduit_rage_start_timeout', 'Conduit Rage launch watchdog')
	assert_equal(timed_out.retry_delay, 0.20, 'Conduit Rage must use fast non-exponential retry')

	local allowed = coordinator.can_attempt(state, 'smn:rage', 6.49)
	assert_equal(allowed, false, 'Conduit Rage fast retry must still serialize the retry window')
	allowed = coordinator.can_attempt(state, 'smn:rage', 6.50)
	assert_equal(allowed, true, 'Conduit Rage fast retry expiry')
end

local function test_pet_pending_does_not_lock_movement()
	local scheduler = {
		phase1 = {
			pending = {
				state = 'sent',
				action_type = 'pet',
			},
			recent_duplicate_until = {},
		},
	}
	local state = locks.p1_get_locks(scheduler, { now = 1 }, function(value, default)
		local number = tonumber(value)
		if number == nil then
			return default
		end
		return number
	end, {})
	assert_true(state.cast_lock.hard, 'pet pending must serialize the action channel')
	assert_equal(state.movement_lock.hard, false, 'pet pending must not lock movement')
end

test_command_contract()
test_context_capture()
test_serialization_and_completion()
test_action_events_and_stale_identity()
test_failure_timeout_and_backoff()
test_conduit_rage_lifecycle()
test_pet_pending_does_not_lock_movement()

print('selftest_pet_command_infrastructure: OK')
