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

local function sample(recast)
	return {
		main_job = 'SCH',
		main_job_level = 99,
		job_points_present = true,
		job_points_spent = 2100,
		recast_present = true,
		recast = recast,
		buffs = { 358 },
		candidate = 'Accession',
		blocker = 'charge_confidence_unknown',
		party_generation = 1,
		party = {
			{
				id = 1001,
				name = 'Scholar',
				hpp = 100,
				x = 1,
				y = 2,
				z = 3,
				coordinate_observed_at = 99.9,
				buffs = { 358 },
			},
			{
				id = 1002,
				name = 'Tank',
				hpp = 100,
				x = 2,
				y = 2,
				z = 3,
				coordinate_observed_at = 99.9,
				buffs = {},
			},
		},
	}
end

local function main()
	package.loaded.uc_sch_trace = nil
	local trace_module = require('uc_sch_trace')
	local trace = trace_module.new()

	local armed, message = trace.arm(100)
	assert_true(armed, 'trace failed to arm: ' .. tostring(message))
	assert_true(not trace.arm(100.1), 'duplicate trace arm must fail')
	trace.observe_sample(sample(17), 100.2)
	trace.observe_sample(sample(17), 100.3)
	local active = trace.snapshot().active
	assert_equal(#active.events, 2, 'identical trace samples must be deduplicated')
	assert_true(not trace.observe_action({
		actor_id = 1001,
		category = 1,
		param = 0,
		targets = {},
	}, 1001, 100.4), 'irrelevant action must not start a trace')
	assert_true(not trace.observe_action({
		actor_id = 2000,
		category = 6,
		param = 218,
		targets = {},
	}, 1001, 100.5), 'other actor must not start a trace')
	assert_true(trace.observe_action({
		actor_id = 1001,
		category = 6,
		param = 218,
		targets = {
			{ id = 1001, actions = { { message = 101, param = 218 } } },
		},
	}, 1001, 101), 'Accession action must start the trace')
	assert_true(trace.observe_action_message({
		actor_id = 1001,
		target_id = 1001,
		message_id = 101,
		param_1 = 218,
		param_2 = 7,
		param_3 = 8,
		_uc_source = 'raw_029',
	}, 1001, 101.1), 'local action message must be captured')
	trace.observe_sample(sample(16), 101.2)
	assert_true(trace.snapshot().armed, 'trace must remain armed during settlement')
	assert_true(trace.tick(103.1), 'settled trace must complete')
	local completed = trace.snapshot()
	assert_true(not completed.armed, 'completed trace must disarm')
	assert_equal(completed.last.focus_action_name, 'Accession', 'trace focus action mismatch')
	assert_equal(completed.last.events[2].job_points_spent, 2100, 'trace job-point context mismatch')
	assert_equal(completed.last.terminal_reason, 'settled', 'trace completion mismatch')
	assert_equal(completed.last.events[3].targets[1].actions[1].message, 101, 'raw target message mismatch')

	assert_true(trace.arm(200), 'second trace failed to arm')
	assert_true(trace.tick(230), 'unobserved trace must time out')
	local timed_out = trace.snapshot().last
	assert_equal(timed_out.terminal_reason, 'timeout_awaiting_relevant_action', 'trace timeout mismatch')

	assert_true(trace.arm(250), 'message-only trace failed to arm')
	assert_true(trace.observe_action_message({
		actor_id = 1001,
		target_id = 1001,
		message_id = 17,
		param_1 = 218,
	}, 1001, 250.2), 'message-only rejection must be captured')
	assert_equal(trace.snapshot().active.focus_action_name, 'action_message', 'message-only focus mismatch')
	assert_true(trace.tick(252.3), 'message-only trace must settle')
	assert_equal(trace.snapshot().last.terminal_reason, 'settled', 'message-only terminal mismatch')

	assert_true(trace.arm(300), 'spell trace failed to arm')
	trace.observe_sample(sample(0), 300.1)
	assert_true(trace.observe_action({
		actor_id = 1001,
		category = 8,
		param = 504,
		targets = { { id = 1001, actions = { { message = 327, param = 504 } } } },
	}, 1001, 300.2), 'Regen cast-start must start trace capture')
	assert_equal(trace.snapshot().active.phase, 'capturing', 'cast-start must await completion')
	assert_true(trace.observe_action({
		actor_id = 1001,
		category = 4,
		param = 504,
		targets = {
			{ id = 1001, actions = { { message = 230, param = 42 } } },
			{ id = 1002, actions = { { message = 230, param = 42 } } },
		},
	}, 1001, 301), 'Regen completion must be captured')
	trace.observe_sample(sample(0), 303.1)
	local regen_trace = trace.snapshot().last
	assert_equal(regen_trace.focus_action_name, 'Regen V', 'spell trace action mismatch')
	assert_equal(#regen_trace.events[4].targets, 2, 'multi-target spell evidence mismatch')

	local invalid = trace_module.new()
	invalid.arm(400)
	local ok = pcall(invalid.observe_sample, {
		main_job = 'SCH',
		main_job_level = 99,
		job_points_present = false,
		job_points_spent = 0,
		recast_present = true,
		recast = 0,
		buffs = { 'bad' },
		candidate = '',
		blocker = '',
		party_generation = 1,
		party = {},
	}, 400.1)
	assert_true(not ok, 'malformed trace sample must fail fast')

	local absent_recast = trace_module.new()
	assert_true(absent_recast.arm(450), 'absent-recast trace failed to arm')
	local absent_sample = sample(0)
	absent_sample.recast_present = false
	absent_sample.recast = nil
	absent_recast.observe_sample(absent_sample, 450.1)
	assert_true(absent_recast.snapshot().active.events[2].recast == nil,
		'absent trace recast must remain missing')
	local sentinel_sample = sample(0)
	sentinel_sample.recast_present = false
	assert_true(not pcall(absent_recast.observe_sample, sentinel_sample, 450.2),
		'absent trace recast must reject a numeric sentinel')

	local geometry = trace_module.new()
	assert_true(geometry.arm(500), 'geometry trace failed to arm')
	geometry.observe_sample(sample(17), 500.1)
	local moved = sample(17)
	moved.party[2].x = 4
	geometry.observe_sample(moved, 500.2)
	assert_equal(#geometry.snapshot().active.events, 3,
		'party coordinate change must produce a distinct trace sample')

	print('selftest_sch_trace: OK')
end

main()
