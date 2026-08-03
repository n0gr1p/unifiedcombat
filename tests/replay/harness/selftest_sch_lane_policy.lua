local function assert_true(condition, message)
	if not condition then
		error(message or 'assertion failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values are not equal') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function main()
	package.loaded.uc_sch_lane_policy = nil
	local policy = require('uc_sch_lane_policy')
	local routine = { provider = 'combat', action_type = 'spell', action_name = 'Fire V' }
	local planning = policy.decide({ class = 'planning', reserved = false }, routine, false, false)
	assert_true(planning.allowed and not planning.preempt, 'planning must not reserve the lane')

	local prepared = { class = 'prepared_support', reserved = true }
	local owned = policy.decide(prepared, { provider = 'maintenance_sch' }, false, false)
	assert_true(owned.allowed and not owned.preempt, 'Scholar owner proposal must remain eligible')
	local blocked = policy.decide(prepared, routine, false, false)
	assert_true(not blocked.allowed and not blocked.preempt, 'routine work must be held by prepared Scholar state')
	assert_equal(blocked.reason, 'sch_lane_prepared_support', 'routine hold reason mismatch')
	local cure = policy.decide(prepared, { provider = 'defensive_internal' }, true, false)
	assert_true(cure.allowed and cure.preempt, 'critical cure must preempt prepared Scholar state')
	assert_equal(cure.reason, 'critical_cure_preemption', 'critical cure reason mismatch')
	local charm = policy.decide(prepared, { provider = 'charm_sleeper' }, false, true)
	assert_true(charm.allowed and charm.preempt, 'hard emergency must preempt prepared Scholar state')
	assert_true(policy.holds_movement_and_targeting(prepared), 'prepared lane must hold movement and targeting')
	assert_true(not policy.holds_movement_and_targeting({ class = 'planning', reserved = false }),
		'planning lane must not hold movement and targeting')
	local dispatched = { class = 'dispatched', reserved = true }
	local dispatched_decision = policy.decide(dispatched, routine, false, false)
	assert_true(dispatched_decision.allowed and not dispatched_decision.preempt,
		'dispatched state must defer to existing action locks')
	assert_true(not policy.holds_movement_and_targeting(dispatched),
		'dispatched state must defer movement to existing cast locks')

	local invalid_ok = pcall(policy.decide, { class = 'unexpected', reserved = true }, routine, false, false)
	assert_true(not invalid_ok, 'invalid lane class must fail fast')
	print('selftest_sch_lane_policy: OK')
end

main()
