local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_false(value, message)
	if value then
		error(message or 'expected false')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function read(path)
	local file = assert(io.open(path, 'rb'))
	local content = file:read('*a')
	file:close()
	return content
end

local original_active_config = package.loaded.uc_active_config
local original_recovery_hold = package.loaded.uc_recovery_hold
local original_dispatcher = package.loaded.uc_scheduler_dispatcher
local original_movement_dispatcher = package.loaded.uc_movement_dispatcher
local original_windower = rawget(_G, 'windower')
local original_settings = rawget(_G, 'UC_SETTINGS')
local original_active = rawget(_G, 'UC_RECOVERY_HOLD_ACTIVE')
local original_status = rawget(_G, 'UC_RECOVERY_HOLD_STATUS')

local configured = nil
local player = { id = 100, buffs = {} }
package.loaded.uc_active_config = {
	get_path = function(path)
		assert_equal(path, 'config.ownership.pause_automation_while_weakened', 'recovery hold config path')
		return configured
	end,
}
package.loaded.uc_recovery_hold = nil
package.loaded.uc_scheduler_dispatcher = nil
package.loaded.uc_movement_dispatcher = nil
rawset(_G, 'windower', {
	ffxi = {
		get_player = function()
			return player
		end,
	},
})
rawset(_G, 'UC_SETTINGS', {})

local recovery_hold = require('uc_recovery_hold')
local dispatcher = require('uc_scheduler_dispatcher')
local movement_dispatcher = require('uc_movement_dispatcher')

assert_equal(recovery_hold.WEAKNESS_BUFF_ID, 1, 'authoritative Weakness buff id')
assert_true(recovery_hold.validate_resources({ [1] = { en = 'weakness' } }), 'Weakness resource validation')
assert_true(recovery_hold.player_is_weakened({ buffs = { 1 } }), 'Weakness detection')
assert_true(recovery_hold.player_is_weakened({ buffs = { 1, 1 } }), 'repeated-death weakness uses the same buff id')
assert_false(recovery_hold.player_is_weakened({ buffs = { 2, 3 } }), 'unrelated buffs must not trigger recovery hold')

configured = nil
player.buffs = { 1 }
assert_false(recovery_hold.current(), 'missing setting must default off')

local command_calls = 0
local function send_command()
	command_calls = command_calls + 1
end

configured = false
local result = dispatcher.dispatch_intent({ kind = 'send_command', command = 'input /ws "Test" <t>' }, {
	execute = true,
	send_command = send_command,
})
assert_true(result.executed, 'setting OFF plus Weakness must preserve automation')
assert_equal(command_calls, 1, 'setting OFF dispatch count')

configured = true
player.buffs = {}
result = dispatcher.dispatch_intent({ kind = 'send_command', command = 'input /ja "Test" <me>' }, {
	execute = true,
	send_command = send_command,
})
assert_true(result.executed, 'setting ON without Weakness must preserve automation')
assert_equal(command_calls, 2, 'non-weakened dispatch count')

player.buffs = { 1 }
assert_true(recovery_hold.current(), 'setting ON plus Weakness must activate recovery hold')

local blocked_commands = {
	'input /ws "Test WS" <t>',
	'input /ja "Test JA" <me>',
	'input /ma "Test Spell" <me>',
	'input /ra <t>',
	'input /pet "Test Pet" <t>',
}
for i = 1, #blocked_commands do
	result = dispatcher.dispatch_intent({ kind = 'send_command', command = blocked_commands[i] }, {
		execute = true,
		send_command = send_command,
	})
	assert_false(result.executed, 'weakened action must not execute: ' .. blocked_commands[i])
	assert_equal(result.reason, recovery_hold.BLOCK_REASON, 'weakened action rejection reason')
end
assert_equal(command_calls, 2, 'WS/JA/spell/ranged/pet actions must remain suppressed')

result = dispatcher.dispatch_intent({ kind = 'send_command', source = 'test:release', command = 'input /ja "Bypass" <me>' }, {
	execute = true,
	send_command = send_command,
}, {
	allow_during_recovery_hold = true,
})
assert_false(result.executed, 'only the one-time run-stop release may bypass recovery hold')

local target_calls = 0
local engage_calls = 0
for _, case in ipairs({
	{ kind = 'select_target', dep = 'set_target', target_id = 501 },
	{ kind = 'switch_target', dep = 'switch_target', target_id = 502 },
	{ kind = 'engage', dep = 'engage_target', target_id = 503 },
}) do
	local deps = { execute = true }
	deps[case.dep] = function()
		if case.kind == 'engage' then
			engage_calls = engage_calls + 1
		else
			target_calls = target_calls + 1
		end
		return true
	end
	result = dispatcher.dispatch_intent({ kind = case.kind, target_id = case.target_id }, deps)
	assert_false(result.executed, case.kind .. ' must be suppressed')
end
assert_equal(target_calls, 0, 'target-control side effects')
assert_equal(engage_calls, 0, 'engage side effects')

local run_calls = 0
local turn_calls = 0
local mover_calls = 0
local function build_movement(source)
	return movement_dispatcher.build({
		dispatcher = dispatcher,
		run = function()
			run_calls = run_calls + 1
		end,
		turn = function()
			turn_calls = turn_calls + 1
		end,
		source_prefix = source,
	})
end

-- These represent combat, follow, formation, reaction, and path movement owners.
build_movement('combat').run_vector(1, 0)
build_movement('party_follow').run_vector(1, 0)
build_movement('formation').run_heading(1.5)
build_movement('reaction').move_towards({
	move_towards = function()
		mover_calls = mover_calls + 1
	end,
}, 504)
build_movement('pathing').run_forward()
build_movement('facing').turn(2.0)
assert_equal(run_calls, 0, 'automated movement must be suppressed')
assert_equal(turn_calls, 0, 'automatic facing must be suppressed')
assert_equal(mover_calls, 0, 'reaction move-to-range must be suppressed')

-- A movement executor prepared before Weakness must revalidate at execution.
player.buffs = {}
local stale_movement = build_movement('stale')
player.buffs = { 1 }
result = stale_movement.run_vector(0.5, 0.5)
assert_false(result.executed, 'stale movement must be rejected at execution')
assert_equal(run_calls, 0, 'stale movement side effects')

-- Transition callbacks model the lifecycle hook that releases movement once.
recovery_hold.reset_runtime()
local release_calls = 0
local release_executor = movement_dispatcher.build({
	dispatcher = dispatcher,
	run = function(value)
		assert_equal(value, false, 'recovery entry must release the run vector')
		release_calls = release_calls + 1
	end,
	source_prefix = 'recovery_test',
})
local hooks = {
	on_enter = function()
		release_executor.release({ reason = 'RECOVERY_HOLD_ENTER' })
	end,
}
configured = false
player.buffs = { 1 }
local transition = recovery_hold.update({}, player, hooks)
assert_false(transition.active, 'disabled hold must remain inactive while weak')
configured = true
transition = recovery_hold.update({}, player, hooks)
assert_true(transition.entered, 'enabling while already weak must enter immediately')
assert_equal(release_calls, 1, 'movement release on entry')
transition = recovery_hold.update({}, player, hooks)
assert_false(transition.entered, 'steady recovery hold must not re-enter')
assert_equal(release_calls, 1, 'steady recovery hold must not repeatedly stop movement')

-- A selected action that becomes stale before dispatch is rejected by the final gate.
player.buffs = {}
assert_false(recovery_hold.current(), 'cleared Weakness must remove execution hold immediately')
local stale_action = { kind = 'send_command', command = 'input /ma "Stale" <me>' }
player.buffs = { 1 }
result = dispatcher.dispatch_intent(stale_action, { execute = true, send_command = send_command })
assert_false(result.executed, 'stale selected action must be rejected at commit')

transition = recovery_hold.update({}, player, hooks)
assert_false(transition.entered, 'already-active runtime must remain steady')
player.buffs = {}
transition = recovery_hold.update({}, player, hooks)
assert_true(transition.cleared, 'Weakness removal must clear recovery hold')
result = dispatcher.dispatch_intent({ kind = 'send_command', command = 'input /ja "Fresh" <me>' }, {
	execute = true,
	send_command = send_command,
})
assert_true(result.executed, 'fresh post-Weakness automation must resume normally')
assert_equal(command_calls, 3, 'fresh resume dispatch count')

local party = { p0 = { id = player.id, name = 'RecoveringPlayer' }, p1 = { id = 200, name = 'Supporter' } }
assert_equal(party.p0.id, 100, 'recovery hold must not remove the local player from party state')
assert_equal(#player.buffs, 0, 'recovery hold detection must not mutate live buff state')

local scheduler_source = read('unified_scheduler.lua')
local broadcast_at = assert(scheduler_source:find('maybe_broadcast_party_state_ipc()', 1, true))
local hold_at = assert(scheduler_source:find('if recovery_hold.current() then', broadcast_at, true))
assert_true(broadcast_at < hold_at, 'party IPC observation must continue before scheduler recovery hold')
assert_true(scheduler_source:find('phase.last_selected = nil', hold_at, true) ~= nil, 'recovery entry must discard stale selected work')
assert_true(read('uc_party_follow.lua'):find('if uc_recovery_hold.current() then', 1, true) ~= nil, 'party follow must stop proposing movement while held')
assert_true(read('uc_pathing.lua'):find('if uc_recovery_hold.current() then', 1, true) ~= nil, 'pathing must stop proposing movement while held')
local addon_source = read('UnifiedCombat.lua')
local update_at = assert(addon_source:find('uc_update_recovery_hold()', 1, true))
local path_at = assert(addon_source:find('uc_pathing.tick()', update_at, true))
local follow_at = assert(addon_source:find('uc_party_follow.prerender()', update_at, true))
assert_true(update_at < path_at and update_at < follow_at, 'recovery transition must run before independent movement owners')

recovery_hold.reset_runtime()
package.loaded.uc_active_config = original_active_config
package.loaded.uc_recovery_hold = original_recovery_hold
package.loaded.uc_scheduler_dispatcher = original_dispatcher
package.loaded.uc_movement_dispatcher = original_movement_dispatcher
rawset(_G, 'windower', original_windower)
rawset(_G, 'UC_SETTINGS', original_settings)
rawset(_G, 'UC_RECOVERY_HOLD_ACTIVE', original_active)
rawset(_G, 'UC_RECOVERY_HOLD_STATUS', original_status)

io.stdout:write('selftest_deathsickness_recovery_hold: OK\n')
