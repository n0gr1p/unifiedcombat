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

local function enabled_config()
	local config = require('uc_sch_config').default_config()
	config.enabled = true
	config.support.regen.enabled = true
	return config
end

local function regen_plan(id, deadline)
	return {
		id = id,
		purpose = 'party_regen',
		domain = 'maintenance',
		required_art = 'light',
		required_addendum = nil,
		stratagems = { 'Accession', 'Perpetuance' },
		spell = 'Regen V',
		anchor_id = 1001,
		anchor_name = 'Anchor',
		expected_recipients = {
			{ id = 1001, name = 'Anchor' },
			{ id = 1002, name = 'Second' },
			{ id = 1003, name = 'Third' },
			{ id = 1004, name = 'Fourth' },
		},
		party_generation = 7,
		deadline = deadline,
	}
end

local function configure_ready(runtime, at, available)
	runtime.reset('test_setup', at)
	runtime.configure(enabled_config(), { main_job = 'SCH' }, 1, at)
	runtime.observe_environment({
		engine_enabled = true,
		maintenance_enabled = true,
		main_job = 'SCH',
		player_hpp = 100,
		party_generation = 7,
		party_members = {
			{ id = 1001, name = 'Anchor', hpp = 100 },
			{ id = 1002, name = 'Second', hpp = 100 },
			{ id = 1003, name = 'Third', hpp = 100 },
			{ id = 1004, name = 'Fourth', hpp = 100 },
		},
	}, at)
	runtime.observe_player_buffs({ 358 }, at)
	runtime.observe_charge({
		available = available or 2,
		maximum = 5,
		recast_present = true,
		observed_recast = 0,
		confidence = 'confirmed',
		tabula_rasa_active = false,
		model_key = 'SCH|99|true|2100|231',
		decoder_source = 'fixture:confirmed_charge_state',
		reason = '',
	}, at)
end

local function dispatch_and_confirm_ja(runtime, step, action_buffs, at)
	local dispatched, dispatch_reason = runtime.note_dispatched(step, at)
	assert_true(dispatched, 'Scholar JA dispatch failed: ' .. tostring(dispatch_reason))
	local observed, observation_reason = runtime.observe_local_action({
		action_type = 'job_ability',
		action_name = step.action_name,
		success = true,
	}, at + 0.1)
	assert_true(observed, 'Scholar JA action observation failed: ' .. tostring(observation_reason))
	runtime.observe_player_buffs(action_buffs, at + 0.2)
end

local function prepare_regen_spell(runtime, id, at)
	assert_true(runtime.start_sequence(regen_plan(id, at + 30), at),
		'fixture Regen sequence start failed')
	local accession = runtime.next_step(at + 0.1)
	dispatch_and_confirm_ja(runtime, accession, { 358, 366 }, at + 0.2)
	local perpetuance = runtime.next_step(at + 0.5)
	dispatch_and_confirm_ja(runtime, perpetuance, { 358, 366, 469 }, at + 0.6)
	local spell = runtime.next_step(at + 0.9)
	assert_true(runtime.note_dispatched(spell, at + 1.0),
		'fixture Regen spell dispatch failed')
	return spell
end

local function observe_environment(runtime, at, engine_enabled, maintenance_enabled, main_job, player_hpp)
	return runtime.observe_environment({
		engine_enabled = engine_enabled,
		maintenance_enabled = maintenance_enabled,
		main_job = main_job,
		player_hpp = player_hpp,
		party_generation = 7,
		party_members = {
			{ id = 1001, name = 'Anchor', hpp = 100 },
			{ id = 1002, name = 'Second', hpp = 100 },
			{ id = 1003, name = 'Third', hpp = 100 },
			{ id = 1004, name = 'Fourth', hpp = 100 },
		},
	}, at)
end

local function main()
	package.loaded.uc_sch_runtime = nil
	local runtime = require('uc_sch_runtime')

	configure_ready(runtime, 100, 2)
	assert_equal(runtime.snapshot().eligibility, 'eligible', 'Scholar eligibility mismatch')
	assert_equal(runtime.snapshot().arts.observed, 'light', 'Light Arts observation mismatch')
	assert_equal(runtime.snapshot().environment.party_generation, 7, 'party generation observation mismatch')
	assert_true(not runtime.requires_fast_tick(), 'idle Scholar runtime must not require fast tick')

	local started, generation = runtime.start_sequence(regen_plan('regen-success', 130), 100)
	assert_true(started, 'valid Regen sequence failed to start: ' .. tostring(generation))
	assert_equal(generation, 1, 'first sequence generation mismatch')
	assert_true(runtime.requires_fast_tick(), 'active Scholar sequence must require fast tick')
	assert_equal(runtime.lane_status().class, 'planning', 'initial Scholar lane mismatch')

	local accession, accession_reason = runtime.next_step(100.1)
	assert_true(type(accession) == 'table', 'Accession step missing: ' .. tostring(accession_reason))
	assert_equal(accession.action_name, 'Accession', 'first stratagem mismatch')
	assert_equal(accession.phase, 'use_accession', 'Accession phase mismatch')
	dispatch_and_confirm_ja(runtime, accession, { 358, 366 }, 100.2)
	assert_equal(runtime.snapshot().active_sequence.phase, 'use_perpetuance', 'Perpetuance phase mismatch')
	assert_equal(runtime.lane_status().class, 'prepared_support', 'prepared Accession must reserve support lane')

	local perpetuance = runtime.next_step(100.5)
	assert_equal(perpetuance.action_name, 'Perpetuance', 'second stratagem mismatch')
	dispatch_and_confirm_ja(runtime, perpetuance, { 358, 366, 469 }, 100.6)
	assert_equal(runtime.snapshot().active_sequence.phase, 'cast_spell', 'spell phase mismatch')
	assert_equal(runtime.snapshot().active_sequence.reserved_charges_remaining, 0, 'charge reservation mismatch')

	local spell = runtime.next_step(100.9)
	assert_equal(spell.action_type, 'spell', 'Regen step action type mismatch')
	assert_equal(spell.action_name, 'Regen V', 'Regen step spell mismatch')
	assert_equal(spell.target_id, 1001, 'Regen anchor mismatch')
	assert_true(runtime.note_dispatched(spell, 101.0), 'Regen dispatch failed')
	local completed, complete_reason = runtime.observe_local_action({
		action_type = 'spell',
		action_name = 'Regen V',
		success = true,
		successful_recipients = {
			{ id = 1001, name = 'Anchor' },
			{ id = 1002, name = 'Second' },
			{ id = 1099, name = 'Unexpected' },
		},
	}, 103.0)
	assert_true(completed, 'Regen sequence did not complete: ' .. tostring(complete_reason))
	local completed_snapshot = runtime.snapshot()
	assert_true(completed_snapshot.active_sequence == nil, 'completed sequence must clear active state')
	assert_equal(completed_snapshot.last_sequence.result, 'complete', 'completed sequence result mismatch')
	assert_equal(completed_snapshot.owned_buffs[1001].regen.exact_spell, 'Regen V', 'owned Regen identity mismatch')
	assert_equal(completed_snapshot.owned_buffs[1001].regen.duration_confidence, 'unknown',
		'unvalidated duration must remain unknown')
	assert_equal(completed_snapshot.owned_buffs[1001].regen.duration_reason,
		'phase0_duration_unvalidated', 'unknown duration reason mismatch')
	assert_equal(completed_snapshot.owned_buffs[1001].regen.duration_model_key,
		'regen|Regen V|Accession,Perpetuance', 'owned duration model key mismatch')
	assert_true(completed_snapshot.owned_buffs[1003] == nil, 'unsuccessful planned recipient must not gain ownership')
	assert_equal(completed_snapshot.owned_buffs[1099].regen.presence, 'present', 'successful unexpected recipient must be recorded')
	assert_equal(completed_snapshot.unexpected_recipients[1], 1099, 'unexpected recipient diagnostic mismatch')
	assert_true(not runtime.requires_fast_tick(), 'completed runtime must return to idle cadence')

	runtime.observe_party_buffs({
		{ id = 1001, buffs = {} },
		{ id = 1002, buffs = nil },
		{ id = 1099, buffs = { 42 } },
	}, 104.0)
	local reconciled = runtime.snapshot()
	assert_equal(reconciled.owned_buffs[1001].regen.presence, 'absent', 'observed Regen loss mismatch')
	assert_equal(reconciled.owned_buffs[1002].regen.presence, 'unknown', 'missing party buffs must remain unknown')
	assert_equal(reconciled.owned_buffs[1099].regen.presence, 'present', 'confirmed Regen presence mismatch')
	assert_equal(reconciled.owned_buffs[1099].regen.estimated_expires_at, 0, 'unproven duration must remain unknown')

	configure_ready(runtime, 150, 2)
	prepare_regen_spell(runtime, 'invalid-recipient', 150)
	local invalid_recipient_ok, invalid_recipient_reason = runtime.observe_local_action({
		action_type = 'spell',
		action_name = 'Regen V',
		success = true,
		successful_recipients = {
			{ id = 1001, name = 'Anchor' },
			{ id = '1002', name = 'Invalid' },
		},
	}, 153)
	assert_true(not invalid_recipient_ok, 'invalid successful recipient must abort the sequence')
	assert_equal(invalid_recipient_reason, 'spell_recipient_invalid',
		'invalid successful recipient reason mismatch')
	assert_true(runtime.snapshot().owned_buffs[1001] == nil,
		'invalid recipient sets must not leave partial ownership')

	configure_ready(runtime, 175, 2)
	prepare_regen_spell(runtime, 'duplicate-recipient', 175)
	local duplicate_recipient_ok, duplicate_recipient_reason = runtime.observe_local_action({
		action_type = 'spell',
		action_name = 'Regen V',
		success = true,
		successful_recipients = {
			{ id = 1001, name = 'Anchor' },
			{ id = 1001, name = 'Anchor' },
		},
	}, 178)
	assert_true(not duplicate_recipient_ok, 'duplicate successful recipients must abort the sequence')
	assert_equal(duplicate_recipient_reason, 'spell_recipient_duplicate',
		'duplicate successful recipient reason mismatch')
	assert_true(runtime.snapshot().owned_buffs[1001] == nil,
		'duplicate recipient sets must not leave partial ownership')

	configure_ready(runtime, 190, 2)
	prepare_regen_spell(runtime, 'unclassified-result', 190)
	local unclassified_ok, unclassified_reason = runtime.observe_local_action({
		action_type = 'spell',
		action_name = 'Regen V',
		result_unclassified = true,
	}, 193)
	assert_true(not unclassified_ok, 'unclassified action result must abort the sequence')
	assert_equal(unclassified_reason, 'action_result_unclassified',
		'unclassified action-result abort reason mismatch')
	assert_equal(runtime.lane_status().class, 'none',
		'unclassified action result must release the Scholar lane')
	assert_true(runtime.snapshot().owned_buffs[1001] == nil,
		'unclassified action result must not create ownership')

	configure_ready(runtime, 200, 2)
	runtime.observe_charge({
		available = 0,
		maximum = 0,
		recast_present = true,
		observed_recast = 12,
		confidence = 'unknown',
		tabula_rasa_active = false,
		model_key = 'SCH|99|true|2100|231',
		decoder_source = '',
		reason = 'phase0_charge_mapping_unvalidated',
	}, 200)
	local unknown_started, unknown_reason = runtime.start_sequence(regen_plan('unknown-charge', 230), 200)
	assert_true(not unknown_started, 'unknown charge state must not start a sequence')
	assert_equal(unknown_reason, 'charge_confidence_unknown', 'unknown charge blocker mismatch')

	configure_ready(runtime, 300, 1)
	local short_started, short_reason = runtime.start_sequence(regen_plan('one-charge', 330), 300)
	assert_true(not short_started, 'one charge must not start two-stratagem Regen')
	assert_equal(short_reason, 'insufficient_confirmed_charges', 'insufficient charge blocker mismatch')

	configure_ready(runtime, 400, 2)
	local addendum_plan = regen_plan('addendum-budget', 430)
	addendum_plan.required_addendum = 'white'
	local addendum_started, addendum_reason = runtime.start_sequence(addendum_plan, 400)
	assert_true(not addendum_started, 'unconfirmed Addendum must reserve a third shared charge')
	assert_equal(addendum_reason, 'insufficient_confirmed_charges', 'Addendum charge blocker mismatch')
	runtime.observe_player_buffs({ 401 }, 400.1)
	local addendum_confirmed_started = runtime.start_sequence(addendum_plan, 400.1)
	assert_true(addendum_confirmed_started, 'confirmed Addendum should remove its extra reservation')
	runtime.cancel('test_cleanup', 400.2, 0)

	configure_ready(runtime, 500, 2)
	assert_true(runtime.start_sequence(regen_plan('contamination', 530), 500), 'contamination sequence start failed')
	local contamination_accession = runtime.next_step(500.1)
	dispatch_and_confirm_ja(runtime, contamination_accession, { 358, 366 }, 500.2)
	local contaminated, contamination_reason = runtime.observe_local_action({
		action_type = 'spell',
		action_name = 'Cure IV',
		success = true,
	}, 500.5)
	assert_true(not contaminated, 'manual spell must abort prepared Scholar sequence')
	assert_equal(contamination_reason, 'manual_action_contamination', 'contamination reason mismatch')
	assert_equal(runtime.snapshot().stratagem.confidence, 'unknown', 'contamination must invalidate charge confidence')
	assert_equal(runtime.lane_status().class, 'none', 'contamination must release Scholar lane')

	configure_ready(runtime, 550, 2)
	assert_true(runtime.start_sequence(regen_plan('unknown-contamination', 580), 550),
		'unknown-contamination sequence start failed')
	local unknown_accession = runtime.next_step(550.1)
	dispatch_and_confirm_ja(runtime, unknown_accession, { 358, 366 }, 550.2)
	local unknown_observed, unknown_observation_reason = runtime.observe_local_action({
		action_type = 'spell',
		action_name = '',
		recognized = false,
	}, 550.5)
	assert_true(not unknown_observed, 'unrecognized local spell must abort prepared Scholar state')
	assert_equal(unknown_observation_reason, 'unrecognized_local_spell', 'unrecognized spell reason mismatch')
	assert_equal(runtime.snapshot().stratagem.confidence, 'unknown',
		'unrecognized spell must invalidate charge confidence')

	configure_ready(runtime, 600, 2)
	assert_true(runtime.start_sequence(regen_plan('timeout', 630), 600), 'timeout sequence start failed')
	local timeout_accession = runtime.next_step(600.1)
	assert_true(runtime.note_dispatched(timeout_accession, 600.2), 'timeout action dispatch failed')
	local ticked, timeout_reason = runtime.tick(602.3)
	assert_true(not ticked, 'timeout tick result must report abort')
	assert_equal(timeout_reason, 'confirmation_timeout', 'confirmation timeout mismatch')
	assert_equal(runtime.snapshot().last_sequence.result, 'aborted', 'timeout result mismatch')

	configure_ready(runtime, 700, 2)
	assert_true(runtime.start_sequence(regen_plan('profile-change', 730), 700), 'profile-change sequence start failed')
	runtime.configure(enabled_config(), { main_job = 'SCH' }, 2, 700.1)
	assert_true(runtime.snapshot().active_sequence == nil, 'profile generation change must clear active sequence')
	assert_equal(runtime.snapshot().last_sequence.reason, 'configuration_changed', 'profile-change reason mismatch')

	configure_ready(runtime, 750, 2)
	assert_true(runtime.start_sequence(regen_plan('party-change', 780), 750), 'party-change sequence start failed')
	local environment_ok, environment_reason = runtime.observe_environment({
		engine_enabled = true,
		maintenance_enabled = true,
		main_job = 'SCH',
		player_hpp = 100,
		party_generation = 8,
		party_members = {
			{ id = 1001, name = 'Anchor', hpp = 100 },
			{ id = 1002, name = 'Second', hpp = 100 },
		},
	}, 750.1)
	assert_true(not environment_ok, 'party generation change must abort active sequence')
	assert_equal(environment_reason, 'party_generation_changed', 'party generation abort mismatch')
	assert_equal(runtime.snapshot().last_sequence.reason, 'party_generation_changed', 'party generation history mismatch')

	configure_ready(runtime, 760, 2)
	assert_true(runtime.start_sequence(regen_plan('anchor-dead', 790), 760), 'anchor-dead sequence start failed')
	local anchor_ok, anchor_reason = runtime.observe_environment({
		engine_enabled = true,
		maintenance_enabled = true,
		main_job = 'SCH',
		player_hpp = 100,
		party_generation = 7,
		party_members = {
			{ id = 1001, name = 'Anchor', hpp = 0 },
			{ id = 1002, name = 'Second', hpp = 100 },
		},
	}, 760.1)
	assert_true(not anchor_ok, 'dead anchor must abort active sequence')
	assert_equal(anchor_reason, 'target_unavailable', 'dead anchor abort mismatch')

	configure_ready(runtime, 770, 2)
	assert_true(runtime.start_sequence(regen_plan('engine-stop', 800), 770), 'engine-stop sequence start failed')
	local engine_ok, engine_reason = runtime.observe_environment({
		engine_enabled = false,
		maintenance_enabled = true,
		main_job = 'SCH',
		player_hpp = 100,
		party_generation = 7,
		party_members = {
			{ id = 1001, name = 'Anchor', hpp = 100 },
		},
	}, 770.1)
	assert_true(not engine_ok, 'engine stop must abort active sequence')
	assert_equal(engine_reason, 'engine_stopped', 'engine-stop abort mismatch')

	configure_ready(runtime, 772, 2)
	assert_true(runtime.start_sequence(regen_plan('domain-disable', 802), 772), 'domain-disable sequence start failed')
	local domain_ok, domain_reason = observe_environment(runtime, 772.1, true, false, 'SCH', 100)
	assert_true(not domain_ok, 'maintenance domain disable must abort active sequence')
	assert_equal(domain_reason, 'maintenance_domain_disabled', 'maintenance-domain abort mismatch')

	configure_ready(runtime, 774, 2)
	assert_true(runtime.start_sequence(regen_plan('job-change', 804), 774), 'job-change sequence start failed')
	local job_ok, job_reason = observe_environment(runtime, 774.1, true, true, 'WHM', 100)
	assert_true(not job_ok, 'main-job change must abort active sequence')
	assert_equal(job_reason, 'job_changed', 'job-change abort mismatch')

	configure_ready(runtime, 776, 2)
	assert_true(runtime.start_sequence(regen_plan('incapacitated', 806), 776), 'incapacitation sequence start failed')
	local alive_ok, alive_reason = observe_environment(runtime, 776.1, true, true, 'SCH', 0)
	assert_true(not alive_ok, 'player incapacitation must abort active sequence')
	assert_equal(alive_reason, 'player_incapacitated', 'incapacitation abort mismatch')

	configure_ready(runtime, 778, 2)
	assert_true(runtime.start_sequence(regen_plan('preempt', 808), 778), 'preemption sequence start failed')
	local preempted, preempt_reason = runtime.preempt('critical_cure_preemption', 778.1)
	assert_true(not preempted, 'preemption reports an aborted sequence')
	assert_equal(preempt_reason, 'critical_cure_preemption', 'preemption reason mismatch')
	assert_equal(runtime.snapshot().stratagem.confidence, 'unknown', 'preemption must invalidate charge confidence')
	assert_equal(runtime.lane_status().class, 'none', 'preemption must release Scholar lane')

	configure_ready(runtime, 800, 2)
	assert_true(runtime.start_sequence(regen_plan('lifecycle-reset', 830), 800), 'reset sequence start failed')
	runtime.reset('zone_change', 800.1)
	local reset_snapshot = runtime.snapshot()
	assert_true(reset_snapshot.active_sequence == nil, 'lifecycle reset must clear active sequence')
	assert_true(reset_snapshot.pending == nil, 'lifecycle reset must clear pending action')
	assert_equal(reset_snapshot.lane.class, 'none', 'lifecycle reset must release lane')
	assert_equal(reset_snapshot.last_reset_reason, 'zone_change', 'reset reason mismatch')
	assert_equal(reset_snapshot.stratagem.confidence, 'unknown', 'lifecycle reset must invalidate charge state')
	assert_equal(reset_snapshot.arts.observed, 'unknown', 'lifecycle reset must invalidate Arts state')
	assert_true(not reset_snapshot.environment.observed, 'lifecycle reset must invalidate environment state')
	assert_true(runtime.check_invariants(), 'reset runtime invariants must hold')
	local internal = runtime._test_state()
	internal.pending = { sequence_id = 'invalid' }
	local invariants_valid, invariant_reason = runtime.enforce_invariants(800.2)
	assert_true(not invariants_valid, 'invalid pending state must fail runtime invariants')
	assert_equal(invariant_reason, 'pending_without_active_sequence', 'invariant reason mismatch')
	assert_true(runtime.snapshot().pending == nil, 'invariant enforcement must clear orphaned pending state')
	assert_equal(
		runtime.snapshot().last_blocker,
		'invariant_violation:pending_without_active_sequence',
		'invariant blocker mismatch'
	)

	print('selftest_sch_runtime: OK')
end

main()
