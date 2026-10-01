local encounter = require('uc_encounter_state')

local SORTIE_ZONE_ID = 133

local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_false(condition, message)
	if condition ~= false then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function boss(id, name, status, hpp, x, y, facing)
	return {
		id = id,
		name = name,
		status = status,
		hpp = hpp,
		x = x,
		y = y,
		z = 0,
		facing = facing,
	}
end

local function observe(now, actors, members, zone_id)
	return encounter.observe_snapshot({
		now = now,
		zone_id = zone_id or SORTIE_ZONE_ID,
		actors = actors,
		members = members or {},
	})
end

local configured, reason = encounter.configure({ enabled = true, id = 'sortie_ghatjot' }, 'test_start')
assert_true(configured, 'Ghatjot should be a supported encounter')
assert_equal(reason, 'CONFIGURED', 'initial configuration reason mismatch')

local ok
ok, reason = encounter.observe_snapshot({
	now = 0.5,
	zone_name = 'Untrusted Diagnostic Zone',
	actors = { boss(1001, 'Ghatjot', 0, 100, 10, 20) },
	members = {},
})
assert_true(ok, 'configured Ghatjot must bind without a zone id')
assert_equal(reason, 'ORIGIN_CAPTURE_STABILIZING', 'zone-independent bind reason mismatch')
encounter.reset('zone_independent_missing_zone_complete')

ok, reason = observe(1.0, { boss(1001, 'Ghatjot', 0, 100, 10, 20) }, {}, 999)
assert_true(ok, 'configured Ghatjot must bind regardless of reported zone id')
assert_equal(reason, 'ORIGIN_CAPTURE_STABILIZING', 'arbitrary-zone bind reason mismatch')
encounter.reset('zone_independent_arbitrary_zone_complete')

ok, reason = observe(2.0, { boss(1001, 'Dhartok', 0, 100, 10, 20) })
assert_false(ok, 'wrong configured actor must not bind')
assert_equal(reason, 'EXPECTED_BOSS_NOT_FOUND', 'wrong actor reason mismatch')

ok, reason = observe(3.0, {
	boss(1001, 'Ghatjot', 0, 100, 10, 20),
	boss(1002, 'Ghatjot', 0, 100, 11, 20),
})
assert_false(ok, 'multiple matching actors must not bind')
assert_equal(reason, 'MULTIPLE_BOSS_ACTORS', 'multiple actor reason mismatch')

ok, reason = observe(4.0, { boss(1001, 'Ghatjot', 0, 100, 10, 20) }, {
	{ id = 2001, name = 'MemberA', source = 'party_packet_0x076', buff_names = { 'Poison' } },
	{ id = 2002, name = 'MemberB', source = 'local_player', buff_names = { 'Taint' } },
})
assert_true(ok, 'single configured actor should bind by encounter identity and exact name')
assert_equal(reason, 'ORIGIN_CAPTURE_STABILIZING', 'first origin sample reason mismatch')

ok, reason = observe(4.6, { boss(1001, 'Ghatjot', 0, 100, 10, 20, 0.75) }, {
	{ id = 2001, name = 'MemberA', source = 'party_packet_0x076', buff_names = { 'Poison' } },
	{ id = 2002, name = 'MemberB', source = 'local_player', buff_names = { 'Taint' } },
})
assert_true(ok, 'stable boss origin should remain bound')
assert_equal(reason, 'ORIGIN_CAPTURED', 'origin capture reason mismatch')
local snapshot = encounter.snapshot()
assert_equal(snapshot.resolved_id, 'sortie_ghatjot', 'resolved encounter mismatch')
assert_equal(snapshot.policy_modes.water_damage, 'enforce', 'Ghatjot Water policy default mismatch')
assert_equal(snapshot.policy_modes.repeat_action_wall, 'off', 'Ghatjot repeat policy default mismatch')
assert_equal(snapshot.origin.x, 10, 'origin x mismatch')
assert_equal(snapshot.boss.facing, 0.75, 'live encounter boss heading must be preserved')
assert_true(snapshot.status_context[1].poison, 'Poison observation missing')
assert_true(snapshot.status_context[2].taint, 'Taint observation missing')

ok, reason = observe(5.0, { boss(1003, 'Ghatjot', 0, 100, 30, 40) })
assert_true(ok, 'replacement actor should bind after transient reset')
snapshot = encounter.snapshot()
assert_equal(snapshot.boss.id, 1003, 'replacement actor id mismatch')
assert_equal(snapshot.last_reset_reason, 'boss_actor_replaced', 'replacement reset reason mismatch')
assert_equal(snapshot.origin, nil, 'replacement actor must clear old origin')

ok, reason = observe(5.1, {})
assert_false(ok, 'missing configured actor must deactivate the encounter binding')
assert_equal(reason, 'EXPECTED_BOSS_NOT_FOUND', 'missing actor reason mismatch')
snapshot = encounter.snapshot()
assert_equal(snapshot.resolved_id, '', 'missing actor must clear resolved encounter identity')
assert_equal(snapshot.boss, nil, 'missing actor must clear boss binding')
assert_equal(snapshot.last_reset_reason, 'expected_boss_not_found', 'missing actor reset reason mismatch')

configured, reason = encounter.configure({ enabled = true, id = 'sortie_dhartok' }, 'switch_to_dhartok')
assert_true(configured, 'Dhartok should be a supported encounter')
assert_equal(reason, 'CONFIGURED', 'Dhartok configuration reason mismatch')
snapshot = encounter.snapshot()
assert_equal(snapshot.policy_modes.repeat_action_wall, 'warn', 'Dhartok repeat policy default mismatch')
assert_equal(snapshot.tuning.repeat_action_guard_s, 10.0, 'Dhartok repeat guard default mismatch')
ok, reason = observe(10.0, { boss(3001, 'Dhartok', 1, 100, -5, 8) })
assert_true(ok, 'active Dhartok should bind for telemetry')
assert_equal(reason, 'ORIGIN_CAPTURE_MISSED', 'engaged origin must remain unresolved')

ok, reason = encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Cesspool',
	phase = 'completed',
	target_id = 4001,
	observed_at = 11.0,
})
assert_true(ok, 'Cesspool completion should start telemetry')
assert_equal(reason, 'CESSPOOL_TELEMETRY_STARTED', 'Cesspool telemetry reason mismatch')

ok, reason = encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Auto Attack 1',
	phase = 'completed',
	target_id = 4001,
	target_position = { x = 100, y = 100, z = 8 },
	observed_at = 11.5,
})
assert_true(ok, 'Dhartok auto attack should remain observable')
assert_equal(reason, 'ABILITY_OBSERVED', 'auto attack must not advance Cesspool pairing')
assert_equal(encounter.snapshot().cesspool.pair_index, 0, 'auto attack advanced Cesspool pair index')

ok, reason = encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Fetid Eddies',
	phase = 'completed',
	target_id = 4001,
	observed_at = 12.0,
})
assert_true(ok, 'first post-Cesspool TP move should be observed')
assert_equal(reason, 'CESSPOOL_FIRST_TP_OBSERVED', 'first TP reason mismatch')

ok, reason = encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Noyade',
	phase = 'completed',
	target_id = 4001,
	target_position = { x = 6, y = 7, z = 8 },
	observed_at = 13.0,
})
assert_true(ok, 'second post-Cesspool TP move should be observed')
assert_equal(reason, 'HAZARD_ACTIVATED', 'validated hazard activation reason mismatch')
assert_false(encounter.snapshot().cesspool.active, 'completed Cesspool pair must close')

encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Cesspool',
	phase = 'completed',
	target_id = 4001,
	observed_at = 14.0,
})
encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Clobbering Wave',
	phase = 'completed',
	target_id = 4001,
	observed_at = 15.0,
})
ok, reason = encounter.observe_ability({
	actor_id = 3001,
	ability_name = 'Nullifying Rain',
	phase = 'completed',
	target_id = 4001,
	observed_at = 16.0,
})
assert_true(ok, 'unresolved second TP target should still be recorded as telemetry')
assert_equal(reason, 'HAZARD_LOCATION_UNRESOLVED', 'unresolved hazard reason mismatch')

ok, reason = encounter.observe_successful_action({
	action_class = 'ws',
	action_key = '42',
	action_name = 'Test WS',
	actor_id = 5001,
	target_id = 3001,
	observed_at = 17.0,
	success = true,
})
assert_true(ok, 'successful WS against Dhartok should be observed')
assert_equal(reason, 'ACTION_SUCCESS_OBSERVED', 'successful WS reason mismatch')

ok, reason = encounter.observe_successful_action({
	action_class = 'bp',
	action_key = '99',
	action_name = 'Test BP',
	actor_id = 5002,
	target_id = 3001,
	observed_at = 18.0,
	success = false,
})
assert_false(ok, 'failed BP must not create repeat telemetry')
assert_equal(reason, 'ACTION_NOT_SUCCESSFUL', 'failed BP reason mismatch')

snapshot = encounter.snapshot()
assert_equal(#snapshot.hazard_candidates, 1, 'hazard candidate count mismatch')
assert_equal(snapshot.hazard_candidates[1].x, 6, 'hazard candidate x mismatch')
assert_equal(#snapshot.active_hazards, 1, 'active hazard count mismatch')
assert_equal(snapshot.active_hazards[1].center.x, 6, 'active hazard center x mismatch')
assert_equal(snapshot.active_hazards[1].avoid_radius, 3.0, 'active hazard radius mismatch')
assert_equal(snapshot.active_hazards[1].source, 'dhartok_second_tp_target', 'active hazard source mismatch')
assert_equal(snapshot.unresolved_hazard_observations, 1, 'unresolved hazard count mismatch')
assert_true(snapshot.recent_repeat_actions['ws:42'] ~= nil, 'WS repeat observation missing')
assert_equal(snapshot.recent_repeat_actions['bp:99'], nil, 'failed BP must not be stored')

ok, reason = observe(200.0, { boss(3001, 'Dhartok', 1, 100, -5, 8) })
assert_true(ok, 'active Dhartok should remain bound after the Cesspool telemetry window')
assert_equal(#encounter.snapshot().active_hazards, 1, 'Dhartok hazard must remain active for the fight')

ok, reason = observe(201.0, { boss(3001, 'Dhartok', 1, 0, -5, 8) })
assert_false(ok, 'defeated boss should reset transient state')
assert_equal(reason, 'BOSS_DEFEATED', 'boss defeat reason mismatch')
snapshot = encounter.snapshot()
assert_equal(snapshot.boss, nil, 'boss defeat must clear binding')
assert_equal(#snapshot.hazard_candidates, 0, 'boss defeat must clear hazard candidates')
assert_equal(#snapshot.active_hazards, 0, 'boss defeat must clear active hazards')
assert_equal(snapshot.last_reset_reason, 'boss_defeated', 'boss defeat reset reason mismatch')

encounter.configure({ enabled = true, id = 'sortie_dhartok' }, 'death_message_test')
observe(202.0, { boss(3002, 'Dhartok', 1, 100, -5, 8) })
ok, reason = encounter.observe_boss_defeat(3002)
assert_true(ok, 'boss death action message should reset matching encounter')
assert_equal(reason, 'BOSS_DEFEATED', 'boss death action-message reason mismatch')
assert_equal(encounter.snapshot().last_reset_reason, 'boss_defeated_action_message', 'action-message reset reason mismatch')

encounter.configure({ enabled = false }, 'test_complete')
assert_equal(encounter.snapshot().phase, 'idle', 'disabled encounter should be idle')

io.stdout:write('selftest_encounter_state: OK\n')
