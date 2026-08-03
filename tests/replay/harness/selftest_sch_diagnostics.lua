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

local function contains(lines, needle)
	for i = 1, #lines do
		if lines[i]:find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function base_runtime()
	return {
		eligibility = 'eligible',
		profile_generation = 3,
		environment = {
			main_job = 'SCH',
			engine_enabled = true,
			maintenance_enabled = true,
			player_hpp = 100,
			observed_at = 99,
		},
		arts = { observed = 'light', desired = 'light', observed_at = 99, commit_until = 110 },
		stratagem = {
			estimated_available = 2,
			maximum = 5,
			confidence = 'confirmed',
			recast_present = true,
			observed_recast = 0,
			observed_at = 99,
			model_key = 'SCH|99|true|2100|231',
			decoder_source = 'fixture:diagnostic_charge_state',
			reason = '',
			tabula_rasa_active = false,
			last_used_at = 0,
		},
		sublimation = { observed = 'none', observed_at = 99 },
		active_sequence = nil,
		pending = nil,
		lane = { class = 'none', reserved = false, reason = '' },
		next_retry_at = 0,
		last_sequence = nil,
		owned_buffs = {},
		unexpected_recipients = {},
	}
end

local function status(runtime)
	return {
		mode = 'observe_only',
		enabled = true,
		eligibility = 'eligible',
		first_blocker = 'charge_confidence_unknown',
		candidate = { action_name = 'Thunderstorm II' },
		proposals_emitted = 0,
		party_generation = 7,
		main_job_level = 99,
		job_points_present = true,
		job_points_spent = 2100,
		regen = {
			state = 'blocked',
			blocker = 'charge_confidence_unknown',
			missing_recipient_ids = { 1001, 1002 },
			unknown_recipient_ids = {},
			unowned_existing_recipient_ids = { 1003 },
			geometry = {
				blocker = 'accession_geometry_unvalidated',
				selected = nil,
			},
		},
		storms = {
			state = 'actionable',
			blocker = '',
			plan = {
				spell = 'Thunderstorm II',
				target_id = 2002,
				duration_confidence = 'unknown',
				duration_model_key = 'storm|Thunderstorm II|',
				expected_recipients = {
					{ id = 2002, name = 'Tank' },
				},
			},
			assignments = {
				{
					spell = 'Thunderstorm II',
					target_name = 'Tank',
					state = 'actionable',
					blocker = '',
				},
			},
		},
		sublimation = { enabled = true, state = 'none', blocker = '' },
		trace_armed = false,
		trace_phase = 'idle',
		last_trace = nil,
		runtime = runtime,
	}
end

local function main()
	package.loaded.uc_sch_diagnostics = nil
	local diagnostics = require('uc_sch_diagnostics')
	local runtime = base_runtime()
	local lines = diagnostics.status_lines(status(runtime), 100)
	assert_equal(#lines, 9, 'Scholar status line count mismatch')
	assert_true(contains(lines, 'profile_generation=3'), 'profile generation missing from status')
	assert_true(contains(lines, 'jp_spent=2100'), 'job-point context missing from status')
	assert_true(contains(lines, 'available=2 maximum=5 confidence=confirmed'), 'charge state missing from status')
	assert_true(contains(lines, 'model=SCH|99|true|2100|231 source=fixture:diagnostic_charge_state'),
		'charge model evidence missing from status')
	assert_true(contains(lines, 'missing=1001,1002 unknown=none'), 'Regen recipients missing from status')
	assert_true(contains(lines, 'unowned=1003 geometry=accession_geometry_unvalidated'),
		'Regen ownership/geometry diagnostic missing from status')
	assert_true(contains(lines, 'Thunderstorm II->Tank:actionable/none'), 'storm diagnostic missing')
	assert_true(contains(lines, 'plan=Thunderstorm II/2002 expected=2002'),
		'storm exact plan diagnostic missing')
	assert_true(contains(lines, 'duration=unknown/storm|Thunderstorm II|'),
		'storm duration diagnostic missing')
	local result_status = status(runtime)
	result_status.last_action_result = {
		action_name = 'Regen V',
		outcome = 'unknown',
		blocker = 'phase0_action_results_unvalidated',
		unknown_message_ids = { 230, 999 },
	}
	local result_lines = diagnostics.status_lines(result_status, 100)
	assert_true(contains(result_lines,
		'action_result=Regen V/unknown/phase0_action_results_unvalidated unknown_messages=230,999'),
		'action-result blocker and unknown messages missing from status')

	local initial = diagnostics.runtime_events(nil, runtime, 100)
	assert_equal(#initial, 1, 'initial runtime event count mismatch')
	assert_equal(initial[1].code, 'SCH_CHARGE_OBSERVATION', 'initial charge event mismatch')
	assert_true(diagnostics.event_line(initial[1]):find('confidence=confirmed', 1, true) ~= nil,
		'charge event line missing confidence')

	local started = base_runtime()
	started.active_sequence = {
		id = 'regen-1',
		generation = 4,
		purpose = 'party_regen',
		phase = 'use_accession',
	}
	started.lane = { class = 'prepared_support', reserved = true, reason = 'use_accession' }
	local start_events = diagnostics.runtime_events(runtime, started, 101)
	assert_equal(start_events[1].code, 'SCH_SEQUENCE_START', 'sequence start event mismatch')
	assert_equal(start_events[2].code, 'SCH_LANE_ACQUIRE', 'lane acquire event mismatch')

	local transitioned = base_runtime()
	transitioned.active_sequence = {
		id = 'regen-1',
		generation = 4,
		purpose = 'party_regen',
		phase = 'use_perpetuance',
	}
	transitioned.lane = { class = 'prepared_support', reserved = true, reason = 'use_perpetuance' }
	local transition_events = diagnostics.runtime_events(started, transitioned, 102)
	assert_equal(#transition_events, 1, 'sequence transition event count mismatch')
	assert_equal(transition_events[1].code, 'SCH_SEQUENCE_TRANSITION', 'sequence transition event mismatch')

	local timed_out = base_runtime()
	timed_out.last_sequence = {
		id = 'regen-1',
		generation = 4,
		result = 'aborted',
		reason = 'confirmation_timeout',
		finished_at = 103,
	}
	local timeout_events = diagnostics.runtime_events(transitioned, timed_out, 103)
	assert_equal(timeout_events[1].code, 'SCH_SEQUENCE_ABORT', 'sequence abort event mismatch')
	assert_equal(timeout_events[2].code, 'SCH_ACTION_TIMEOUT', 'action timeout event mismatch')
	assert_equal(timeout_events[3].code, 'SCH_LANE_RELEASE', 'lane release event mismatch')

	local reconciled = base_runtime()
	reconciled.owned_buffs = {
		[1001] = {
			regen = {
				target_id = 1001,
				target_name = 'Scholar',
				exact_spell = 'Regen V',
				status_id = 42,
				presence = 'present',
				duration_confidence = 'unknown',
				estimated_expires_at = 0,
				duration_reason = 'phase0_duration_unvalidated',
				duration_source = '',
				duration_model_key = 'regen|Regen V|Accession,Perpetuance',
				last_observed_at = 104,
			},
		},
	}
	local reconcile_events = diagnostics.runtime_events(runtime, reconciled, 104)
	assert_equal(#reconcile_events, 1, 'recipient reconcile event count mismatch')
	assert_equal(reconcile_events[1].code, 'SCH_RECIPIENT_RECONCILE', 'recipient reconcile event mismatch')
	local owned_lines = diagnostics.status_lines(status(reconciled), 104)
	assert_equal(#owned_lines, 10, 'owned effect must add one deterministic status line')
	assert_true(contains(owned_lines,
		'owned target=1001/Scholar family=regen spell=Regen V presence=present duration=unknown/0'),
		'owned effect status must expose exact identity and duration confidence')
	assert_true(contains(owned_lines,
		'reason=phase0_duration_unvalidated model=regen|Regen V|Accession,Perpetuance'),
		'owned effect status must expose the duration evidence blocker and model key')

	local invalid_ok = pcall(diagnostics.status_lines, {}, '100')
	assert_true(not invalid_ok, 'string diagnostic time must fail fast')

	local trace_lines = diagnostics.trace_lines({
		id = 9,
		phase = 'complete',
		focus_action_name = 'Regen V',
		terminal_reason = 'settled',
		events = {
			{ kind = 'armed', at = 200 },
			{
				kind = 'sample',
				at = 200.1,
				main_job_level = 99,
				job_points_present = true,
				job_points_spent = 2100,
				recast_present = true,
				recast = 17,
				buffs = { 358 },
				candidate = 'Regen V',
				blocker = 'charge_confidence_unknown',
				party_generation = 3,
				party = {
					{
						id = 1001,
						name = 'Scholar',
						hpp = 100,
						x = 1,
						y = 2,
						z = 3,
						coordinate_observed_at = 200.1,
						source = 'self_local',
						buff_source = 'self_local',
						buffs = { 358 },
					},
				},
			},
			{
				kind = 'action',
				at = 201,
				category = 4,
				action_id = 504,
				action_name = 'Regen V',
				targets = {
					{
						target_id = 1001,
						actions = {
							{
								message = 230,
								param = 42,
								add_effect_message = 12,
								add_effect_param = 34,
							},
						},
					},
				},
			},
			{ kind = 'terminal', at = 203, reason = 'settled' },
		},
	})
	assert_true(contains(trace_lines,
		'party[1] id=1001 name=Scholar hpp=100 xyz=1,2,3 coordinate_observed_at=200.1'),
		'trace output must expose party coordinates and their observation time')
	assert_true(contains(trace_lines, 'message=230 param=42 add=12/34 spike=unobserved/unobserved'),
		'trace output must expose complete raw target result fields')
	print('selftest_sch_diagnostics: OK')
end

main()
