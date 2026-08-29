local skillchain = require('uc_skillchain_state')
local fixtures = require('tests.replay.fixtures.skillchain.skillchain_state_fixtures')
local field_log_audit = require('tests.replay.harness.skillchain_field_log_audit')

local function assert_true(value, message)
	if value ~= true then
		error(message or 'assert_true failed')
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message or 'assert_false failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function clone(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = clone(item)
	end
	return out
end

local function new_runtime(start_at)
	local clock = { now = start_at or 0 }
	local events = {}
	local runtime = skillchain.new({
		now = function()
			return clock.now
		end,
		telemetry = function(code, fields)
			events[#events + 1] = { code = code, fields = fields }
		end,
	})
	return runtime, clock, events
end

local function opener(runtime, target_id, observed_at, properties)
	local event = clone(fixtures.opener)
	event.target_id = target_id or event.target_id
	event.observed_at = observed_at or event.observed_at
	event.effective_properties = properties or event.effective_properties
	return runtime:observe_action_result(event)
end

local function candidate(properties)
	return {
		ws_id = 10,
		ws_name = 'Test WS',
		effective_properties = properties,
	}
end

local function actor_context(actor_id, aftermath_level, diamond_aspis, weapon_signature, aeonic_weapon_name)
	return {
		actor_id = actor_id or 2001,
		aftermath_level = aftermath_level or 0,
		diamond_aspis = diamond_aspis == true,
		weapon_signature = weapon_signature or 'main:sub:range',
		aeonic_weapon_name = aeonic_weapon_name or '',
	}
end

local function valid_commit(plan, context, now)
	return {
		now = now,
		engine_enabled = true,
		current_target_id = plan.target_id,
		target_valid = true,
		ws_available = true,
		tp = 2000,
		actor_blocked = false,
		range_valid = true,
		reaction_hold = false,
		intent_valid = true,
		actor_context = context,
		effective_properties = clone(plan.effective_properties),
	}
end

local function test_clock_contract()
	local ok = pcall(function()
		skillchain.new({})
	end)
	assert_false(ok, 'runtime must reject missing monotonic clock')
	local previous = os.clock()
	for _ = 1, 1000 do
		local current = os.clock()
		assert_true(current >= previous, 'Windower runtime clock contract must be monotonic')
		previous = current
	end
end

local function test_action_family_classification()
	assert_true(skillchain.action_succeeded({ message_success = true }), 'successful propertyless WS message must be accepted')
	assert_false(skillchain.action_succeeded({}), 'failed action message must remain unsuccessful')
	assert_true(skillchain.should_observe_action({ source_resource = 'weapon_skills' }), 'propertyless WS must be observed')
	assert_true(skillchain.should_observe_action({ source_resource = 'job_abilities', has_properties = true }), 'pet Rage action must be observed')
	assert_true(skillchain.should_observe_action({ source_resource = 'monster_abilities', has_properties = true }), 'monster or pet move must be observed')
	assert_false(skillchain.should_observe_action({ source_resource = 'spells', has_properties = true }), 'unqualified spell must not participate')
	assert_true(skillchain.should_observe_action({
		source_resource = 'spells',
		has_properties = true,
		chain_affinity_success = true,
	}), 'qualified spell must participate')
	assert_true(skillchain.should_observe_action({ source_resource = 'job_abilities', chainbound_level = 1 }), 'Chainbound must be observed')
	assert_false(skillchain.should_observe_action({ source_resource = 'job_abilities' }), 'propertyless ordinary JA must not participate')
	assert_equal(skillchain.chainbound_expires_at(209, 100), 103, 'Wild Flourish source expiry')
	assert_equal(skillchain.chainbound_expires_at(320, 100), 160, 'Konzen-ittai source expiry')
	assert_equal(skillchain.chainbound_expires_at(77, 100), nil, 'Weapon Bash expiry remains telemetry-calibrated')
	local runtime, _, events = new_runtime(100)
	local unsupported = clone(fixtures.chainbound)
	unsupported.action_id = 77
	unsupported.expires_at_override = nil
	local state, reason = runtime:observe_action_result(unsupported)
	assert_equal(state, nil, 'unknown Chainbound source lifetime must not install fallback state')
	assert_equal(reason, 'SC_CHAINBOUND_SOURCE_UNSUPPORTED', 'unknown Chainbound source must fail closed explicitly')
	assert_equal(events[#events].fields.chainbound_source_expiry_known, false, 'unsupported Chainbound telemetry must identify missing lifetime')
end

local function test_basic_directional_success()
	local runtime = new_runtime(100)
	opener(runtime)
	local state, reason = runtime:observe_action_result(clone(fixtures.closer))
	assert_equal(reason, 'SC_RESULT_CONFIRMED', 'basic close reason')
	assert_equal(#state.active_properties, 1, 'result must be sole active property')
	assert_equal(state.active_properties[1], 'Transfixion', 'basic result property')
	assert_equal(state.action_count, 2, 'action count')
	assert_equal(state.skillchain_stage, 1, 'skillchain stage')
	assert_equal(state.magic_burst_expires_at, 113.5, 'MB timing')
end

local function test_action_specific_delay_and_server_authority()
	local runtime, _, events = new_runtime(100)
	local spell_opener = clone(fixtures.opener)
	spell_opener.source_resource = 'spells'
	spell_opener.delay = 5
	runtime:observe_action_result(spell_opener)
	assert_equal(runtime:get_state(1001).earliest_close_at, 105, 'action-specific delay must set earliest close')

	runtime, _, events = new_runtime(100)
	opener(runtime)
	local disagreement = clone(fixtures.closer)
	disagreement.effective_properties = { 'Scission' }
	disagreement.server_result = 'Transfixion'
	local state = runtime:observe_action_result(disagreement)
	assert_equal(state.active_properties[1], 'Transfixion', 'server result must override prediction')
	assert_equal(events[#events].code, 'SC_PREDICTION_DISAGREEMENT', 'prediction disagreement must be explicit')
end

local function test_early_and_late_overwrite()
	local runtime = new_runtime(100)
	opener(runtime)
	local early = clone(fixtures.closer)
	early.observed_at = 102
	early.server_result = ''
	local early_state = runtime:observe_action_result(early)
	assert_equal(early_state.active_properties[1], 'Transfixion', 'early action becomes opener')
	assert_equal(early_state.action_count, 1, 'early overwrite resets count')
	assert_equal(early_state.skillchain_stage, 0, 'early overwrite resets stage')

	runtime = new_runtime(100)
	opener(runtime)
	local late = clone(fixtures.closer)
	late.observed_at = 110.1
	late.server_result = ''
	local late_state = runtime:observe_action_result(late)
	assert_equal(late_state.active_properties[1], 'Transfixion', 'late action becomes opener')
	assert_equal(late_state.action_count, 1, 'late overwrite resets count')
end

local function test_failed_and_propertyless_preservation()
	local runtime = new_runtime(100)
	local original = opener(runtime)
	local state = runtime:observe_action_result(clone(fixtures.miss))
	assert_equal(state.generation, original.generation, 'miss preserves generation')
	state = runtime:observe_action_result(clone(fixtures.interruption))
	assert_equal(state.generation, original.generation, 'interruption preserves generation')
	state = runtime:observe_action_result(clone(fixtures.propertyless))
	assert_equal(state.generation, original.generation, 'propertyless action preserves generation')

	local close = clone(fixtures.closer)
	local result = runtime:observe_action_result(close)
	local mb_expiry = result.magic_burst_expires_at
	local propertyless = clone(fixtures.propertyless)
	propertyless.observed_at = 104
	state = runtime:observe_action_result(propertyless)
	assert_equal(state.magic_burst_expires_at, mb_expiry, 'propertyless action preserves MB state')
end

local function test_target_isolation_and_aoe_selected_target()
	local runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Compression' })
	opener(runtime, 1002, 101, { 'Fusion' })
	assert_equal(runtime:get_state(1001).active_properties[1], 'Compression', 'target A state')
	assert_equal(runtime:get_state(1002).active_properties[1], 'Fusion', 'target B state')
	assert_equal(runtime:get_state(1003), nil, 'unobserved AoE secondary target must not receive state')
end

local function test_priority_and_level_two_transitions()
	local first = skillchain.resolve_properties({ 'Induration' }, { 'Compression', 'Reverberation' }, 0)
	assert_equal(first.property, 'Compression', 'first valid property pair must win')
	local cases = {
		{ 'Gravitation', 'Distortion', 'Darkness', 3 },
		{ 'Gravitation', 'Fragmentation', 'Fragmentation', 2 },
		{ 'Distortion', 'Gravitation', 'Darkness', 3 },
		{ 'Distortion', 'Fusion', 'Fusion', 2 },
		{ 'Fusion', 'Fragmentation', 'Light', 3 },
		{ 'Fusion', 'Gravitation', 'Gravitation', 2 },
		{ 'Fragmentation', 'Fusion', 'Light', 3 },
		{ 'Fragmentation', 'Distortion', 'Distortion', 2 },
	}
	for i = 1, #cases do
		local row = cases[i]
		local result = skillchain.resolve_properties({ row[1] }, { row[2] }, 0)
		assert_equal(result.property, row[3], 'level two transition property ' .. tostring(i))
		assert_equal(result.level, row[4], 'level two transition level ' .. tostring(i))
	end
end

local function test_terminal_and_aeonic()
	local runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Light' })
	local terminal_event = clone(fixtures.closer)
	terminal_event.effective_properties = { 'Light' }
	terminal_event.server_result = 'Light'
	terminal_event.server_result_level = 3
	local terminal = runtime:observe_action_result(terminal_event)
	assert_true(terminal.terminal, 'normal Double Light must be terminal')
	assert_equal(terminal.result_level, 4, 'normal Double Light level')
	local no_plan, reason = runtime:plan_continuation(1001, { candidate({ 'Light' }) }, actor_context(), 104)
	assert_equal(no_plan, nil, 'terminal state cannot plan')
	assert_equal(reason, 'SC_TERMINAL', 'terminal plan reason')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Darkness' })
	local double_darkness = clone(fixtures.closer)
	double_darkness.effective_properties = { 'Darkness' }
	double_darkness.server_result = 'Darkness'
	double_darkness.server_result_level = 3
	terminal = runtime:observe_action_result(double_darkness)
	assert_true(terminal.terminal, 'normal Double Darkness must be terminal')
	assert_equal(terminal.result_level, 4, 'normal Double Darkness level')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Light' })
	local non_aeonic_context = actor_context(2001, 3, false)
	local plan = runtime:plan_continuation(1001, { candidate({ 'Light' }) }, non_aeonic_context, 103.5)
	assert_equal(plan.predicted_result, 'Light', 'non-Aeonic AM3 must not predict Radiance')
	local context = actor_context(2001, 3, false, nil, 'Dojikiri Yasutsuna')
	plan = runtime:plan_continuation(1001, { candidate({ 'Light' }) }, context, 103.5)
	assert_equal(plan.predicted_result, 'Radiance', 'AM3 predicts Radiance')
	assert_equal(plan.predicted_level, 4, 'Radiance predicted level')
	local lost_aftermath = valid_commit(plan, actor_context(2001, 0, false, nil, 'Dojikiri Yasutsuna'), 103.6)
	local commit_ok, commit_reason = runtime:revalidate_plan(plan, lost_aftermath)
	assert_false(commit_ok, 'aftermath loss cancels Ultimate plan')
	assert_equal(commit_reason, 'SC_PROPERTIES_CHANGED', 'aftermath loss reason')
	local aeonic_event = clone(fixtures.closer)
	aeonic_event.effective_properties = { 'Light' }
	aeonic_event.server_result = 'Radiance'
	aeonic_event.server_result_level = 4
	aeonic_event.actor_context = context
	local radiance = runtime:observe_action_result(aeonic_event)
	assert_true(radiance.terminal, 'Radiance must be terminal')
	assert_equal(radiance.active_properties[1], 'Radiance', 'server Radiance is authoritative')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Darkness' })
	plan = runtime:plan_continuation(1001, { candidate({ 'Darkness' }) }, context, 103.5)
	assert_equal(plan.predicted_result, 'Umbra', 'AM3 predicts Umbra')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Light' })
	plan = runtime:plan_continuation(1001, { candidate({ 'Light' }) }, actor_context(2001, 1, false, nil, 'Dojikiri Yasutsuna'), 103.5)
	assert_equal(plan.predicted_result, 'Light', 'AM1 cannot produce Ultimate at action two')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Liquefaction' })
	local fusion_result = clone(fixtures.closer)
	fusion_result.effective_properties = { 'Impaction' }
	fusion_result.server_result = 'Fusion'
	fusion_result.server_result_level = 2
	runtime:observe_action_result(fusion_result)
	local three_action_light = clone(fixtures.closer)
	three_action_light.observed_at = 107
	three_action_light.effective_properties = { 'Fragmentation' }
	three_action_light.server_result = 'Light'
	three_action_light.server_result_level = 3
	runtime:observe_action_result(three_action_light)
	plan = runtime:plan_continuation(1001, { candidate({ 'Light' }) }, actor_context(2001, 1, false, nil, 'Dojikiri Yasutsuna'), 110.5)
	assert_equal(plan.predicted_result, 'Radiance', 'AM1 produces Ultimate after three prior actions')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Fusion' })
	local light_result = clone(fixtures.closer)
	light_result.effective_properties = { 'Fragmentation' }
	light_result.server_result = 'Light'
	light_result.server_result_level = 3
	runtime:observe_action_result(light_result)
	plan = runtime:plan_continuation(1001, { candidate({ 'Light' }) }, actor_context(2001, 2, false, nil, 'Dojikiri Yasutsuna'), 107)
	assert_equal(plan.predicted_result, 'Radiance', 'AM2 produces Ultimate after two prior actions')
end

local function test_chainbound_rules()
	local runtime = new_runtime(100)
	local bound = runtime:observe_action_result(clone(fixtures.chainbound))
	assert_equal(bound.earliest_close_at, 102, 'Chainbound earliest timing')
	assert_equal(bound.expires_at, 160, 'Chainbound source expiry')
	local result = skillchain.resolve_properties(bound.active_properties, { 'Transfixion', 'Detonation' }, 1)
	assert_equal(result.property, 'Transfixion', 'Chainbound L1 ignores secondary L1 closer property')
	local plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion', 'Detonation' }) }, actor_context(), 101.9)
	assert_equal(plan.ws_name, 'Test WS', 'Chainbound plan exists before ready boundary')
	assert_equal(reason, 'SC_NOT_READY', 'Chainbound waits until two seconds')
	plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion', 'Detonation' }) }, actor_context(), 102.1)
	assert_equal(reason, 'SC_NOT_READY', 'Chainbound honors the preferred positive buffer')
	plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion', 'Detonation' }) }, actor_context(), 102.3)
	assert_equal(reason, 'SC_READY', 'Chainbound ready at buffered preferred timing')
	local level_two = skillchain.resolve_properties(
		{ 'Gravitation', 'Fragmentation', 'Distortion' },
		{ 'Transfixion', 'Distortion' },
		2
	)
	assert_equal(level_two.property, 'Darkness', 'Chainbound L2 preserves opener property priority')
end

local function test_diamond_aspis_actor_expiry()
	local runtime = new_runtime(100)
	opener(runtime)
	local close = clone(fixtures.closer)
	close.actor_id = 2001
	close.actor_has_diamond_aspis = true
	local result = runtime:observe_action_result(close)
	assert_equal(result.expires_at, 112.5, 'normal step-two expiry')
	assert_equal(result.actor_expiry_overrides[2001], 113.5, 'Diamond Aspis wearer expiry')
	local wearer = actor_context(2001, 0, true)
	local plan, reason = runtime:plan_continuation(1001, { candidate({ 'Compression' }) }, wearer, 112.7)
	assert_equal(reason, 'SC_READY', 'wearer remains eligible')
	assert_true(plan ~= nil, 'wearer plan exists')
	local nonwearer = actor_context(2002, 0, false)
	plan, reason = runtime:plan_continuation(1001, { candidate({ 'Compression' }) }, nonwearer, 112.7)
	assert_equal(plan, nil, 'nonwearer plan expired')
	assert_equal(reason, 'SC_WINDOW_EXPIRED', 'nonwearer expiry reason')
end

local function test_long_nonterminal_chain()
	local runtime = new_runtime(100)
	opener(runtime)
	local now = 103.5
	for step = 2, 7 do
		local event = clone(fixtures.closer)
		event.observed_at = now
		event.effective_properties = { 'Transfixion' }
		event.server_result = 'Transfixion'
		event.server_result_level = 1
		local state = runtime:observe_action_result(event)
		assert_false(state.terminal, 'nonterminal chain must not close at action ' .. tostring(step))
		now = now + 3.1
	end
	assert_equal(runtime:get_state(1001).action_count, 7, 'long chain action count')
end

local function test_plan_and_commit_revalidation()
	local runtime = new_runtime(100)
	opener(runtime)
	local context = actor_context(2001, 0, false, 'weapon-a')
	local plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 103.5)
	assert_equal(reason, 'SC_READY', 'ready plan reason')
	local commit = valid_commit(plan, context, 103.6)
	local ok, commit_reason = runtime:revalidate_plan(plan, commit)
	assert_true(ok, 'valid plan must commit')
	assert_equal(commit_reason, 'SC_DISPATCHED', 'valid commit reason')

	local cases = {
		{ 'engine_enabled', false, 'SC_ENGINE_DISABLED' },
		{ 'current_target_id', 1002, 'SC_TARGET_CHANGED' },
		{ 'target_valid', false, 'SC_TARGET_INVALID' },
		{ 'ws_available', false, 'SC_WS_UNAVAILABLE' },
		{ 'tp', 999, 'SC_TP_LOST' },
		{ 'actor_blocked', true, 'SC_ACTOR_BLOCKED' },
		{ 'range_valid', false, 'SC_OUT_OF_RANGE' },
		{ 'reaction_hold', true, 'SC_REACTION_HOLD' },
		{ 'intent_valid', false, 'SC_INTENT_LOST' },
	}
	for i = 1, #cases do
		local row = cases[i]
		local changed = valid_commit(plan, context, 103.6)
		changed[row[1]] = row[2]
		ok, commit_reason = runtime:revalidate_plan(plan, changed)
		assert_false(ok, 'commit invalidation case ' .. tostring(i))
		assert_equal(commit_reason, row[3], 'commit invalidation reason ' .. tostring(i))
	end

	local equipment_changed = valid_commit(plan, actor_context(2001, 0, false, 'weapon-b'), 103.6)
	ok, commit_reason = runtime:revalidate_plan(plan, equipment_changed)
	assert_false(ok, 'equipment change cancels plan')
	assert_equal(commit_reason, 'SC_PROPERTIES_CHANGED', 'equipment reason')

	local properties_changed = valid_commit(plan, context, 103.6)
	properties_changed.effective_properties = { 'Scission' }
	ok, commit_reason = runtime:revalidate_plan(plan, properties_changed)
	assert_false(ok, 'property change cancels plan')
	assert_equal(commit_reason, 'SC_PROPERTIES_CHANGED', 'property reason')

	local intervening = clone(fixtures.closer)
	intervening.observed_at = 103.7
	intervening.effective_properties = { 'Detonation' }
	intervening.server_result = ''
	runtime:observe_action_result(intervening)
	local stale = valid_commit(plan, context, 103.8)
	ok, commit_reason = runtime:revalidate_plan(plan, stale)
	assert_false(ok, 'intervening action cancels stale plan')
	assert_equal(commit_reason, 'SC_RESONANCE_CHANGED', 'stale generation reason')
end

local function test_dispatched_generation_waits_for_result()
	local runtime = new_runtime(100)
	opener(runtime)
	local context = actor_context()
	local plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 103.5)
	assert_equal(reason, 'SC_READY', 'dispatch reservation setup plan')
	local marked, mark_reason = runtime:mark_plan_dispatched(plan, 103.6)
	assert_true(marked, 'dispatched plan generation must be reserved')
	assert_equal(mark_reason, 'SC_DISPATCH_PENDING_RESULT', 'dispatch reservation reason')
	local duplicate, duplicate_reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 103.7)
	assert_true(duplicate ~= nil, 'pending result must retain a non-dispatchable scheduler lane reservation')
	assert_equal(duplicate_reason, 'SC_DISPATCH_PENDING_RESULT', 'duplicate generation rejection reason')
	local duplicate_commit = valid_commit(duplicate, context, 103.7)
	local duplicate_ok, duplicate_commit_reason = runtime:revalidate_plan(duplicate, duplicate_commit)
	assert_false(duplicate_ok, 'pending result reservation must not dispatch the same generation')
	assert_equal(duplicate_commit_reason, 'SC_DISPATCH_PENDING_RESULT', 'pending result commit rejection reason')

	local intervening = clone(fixtures.closer)
	intervening.observed_at = 103.8
	intervening.effective_properties = { 'Detonation' }
	intervening.server_result = ''
	runtime:observe_action_result(intervening)
	local replacement, replacement_reason = runtime:plan_continuation(1001, { candidate({ 'Compression' }) }, context, 107.2)
	assert_true(replacement ~= nil, 'new resonance generation must clear the dispatch reservation')
	assert_equal(replacement_reason, 'SC_READY', 'replacement generation plan reason')
end

local function test_timing_boundaries_and_cleanup()
	local runtime = new_runtime(100)
	opener(runtime)
	local context = actor_context()
	local plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 102.9)
	assert_equal(reason, 'SC_NOT_READY', 'ordinary close must wait three seconds')
	assert_equal(plan.preferred_execute_at, 103.3, 'preferred dispatch timing')
	plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 103.1)
	assert_equal(reason, 'SC_NOT_READY', 'ordinary close must target the buffered preferred time')
	local early_commit = valid_commit(plan, context, 103.1)
	local early_commit_ok, early_commit_reason = runtime:revalidate_plan(plan, early_commit)
	assert_equal(early_commit_ok, false, 'commit must preserve the preferred dispatch buffer')
	assert_equal(early_commit_reason, 'SC_NOT_READY', 'commit before preferred timing reason')
	plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 103.3)
	assert_equal(reason, 'SC_READY', 'ordinary close becomes ready at preferred timing')
	plan, reason = runtime:plan_continuation(1001, { candidate({ 'Transfixion' }) }, context, 109.5)
	assert_equal(reason, 'SC_LATEST_SAFE_PASSED', 'guarded late window')
	assert_equal(plan, nil, 'late-safe plan rejected')
	assert_true(runtime:clear_target(1001, 'death'), 'death clears target')
	assert_equal(runtime:get_state(1001), nil, 'target state cleared')
	opener(runtime, 1001, 120)
	opener(runtime, 1002, 121)
	runtime:reset('zone_change')
	assert_equal(runtime:get_state(1001), nil, 'zone reset clears A')
	assert_equal(runtime:get_state(1002), nil, 'zone reset clears B')
end

local function test_field_log_audit()
	local lines = {
		'0.000 | Nyoourke | SESSION_START | reload=1',
		'0.100 | Nyoourke | SC_CONTINUATION_PLANNED | target_id=1 preferred_execute_at=10 latest_safe_at=15 predicted_result=Radiance resonance_generation=1 ws_id=152 ws_name=Tachi: Kasha',
		'0.200 | Nyoourke | SC_COMMIT_RESULT | target_id=1 commit_result=SC_DISPATCHED commit_stage=dispatch_commit observed_at=11 predicted_result=Radiance resonance_generation=1 ws_id=152 ws_name=Tachi: Kasha',
		'0.000 | Nyoourke | SESSION_START | reload=1',
	}
	for generation = 1, 5 do
		local preferred = 100 + generation
		local latest = preferred + 5
		lines[#lines + 1] = ('%d.100 | Nyoourke | SC_CONTINUATION_PLANNED | target_id=1001 preferred_execute_at=%d latest_safe_at=%d predicted_result=Light resonance_generation=%d ws_id=152 ws_name=Tachi: Kasha'):format(
			generation, preferred, latest, generation
		)
		lines[#lines + 1] = ('%d.200 | Nyoourke | SC_COMMIT_RESULT | target_id=1001 commit_result=SC_DISPATCHED commit_stage=dispatch_commit observed_at=%.1f predicted_result=Light resonance_generation=%d ws_id=152 ws_name=Tachi: Kasha'):format(
			generation, preferred + 0.2, generation
		)
		lines[#lines + 1] = ('%d.201 | Nyoourke | SC_DISPATCH_PENDING_RESULT | target_id=1001 predicted_result=Light resonance_generation=%d ws_id=152 ws_name=Tachi: Kasha'):format(
			generation, generation
		)
	end
	local result = field_log_audit.audit_lines(lines, {
		minimum_dispatches = 5,
		expect_non_aeonic = true,
	})
	assert_true(result.ok, 'newest valid field session must pass the deterministic audit')
	assert_equal(result.dispatch_count, 5, 'field audit dispatch count')
	assert_equal(result.ultimate_predictions, 0, 'field audit non-Aeonic prediction count')

	local invalid = {
		'0.000 | Nyoourke | SESSION_START | reload=1',
		'0.100 | Nyoourke | SC_CONTINUATION_PLANNED | target_id=1 preferred_execute_at=10 latest_safe_at=15 predicted_result=Radiance resonance_generation=1 ws_id=152 ws_name=Tachi: Kasha',
		'0.200 | Nyoourke | SC_COMMIT_RESULT | target_id=1 commit_result=SC_DISPATCHED commit_stage=dispatch_commit observed_at=9 predicted_result=Radiance resonance_generation=1 ws_id=152 ws_name=Tachi: Kasha',
		'0.300 | Nyoourke | SC_COMMIT_RESULT | target_id=1 commit_result=SC_DISPATCHED commit_stage=dispatch_commit observed_at=11 predicted_result=Radiance resonance_generation=1 ws_id=152 ws_name=Tachi: Kasha',
	}
	result = field_log_audit.audit_lines(invalid, {
		minimum_dispatches = 1,
		expect_non_aeonic = true,
	})
	assert_false(result.ok, 'field audit must reject early, duplicate, unreserved, and non-Aeonic Ultimate dispatches')
	assert_true(#result.failures >= 4, 'field audit must report every acceptance failure')
end


local function named_candidate(id, name, properties)
	return {
		ws_id = id,
		ws_name = name,
		effective_properties = properties,
	}
end

local function test_configured_skillchain_target_planning()
	local runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Fragmentation' })
	local context = actor_context()
	local plan, reason = runtime:plan_continuation(1001, {
		named_candidate(11, 'Indirect Light Route', { 'Distortion' }),
		named_candidate(12, 'Direct Light', { 'Fusion' }),
	}, context, 103.5, 'light')
	assert_true(plan ~= nil, 'Light target must produce a plan')
	assert_equal(reason, 'SC_READY', 'Light target ready reason')
	assert_equal(plan.ws_name, 'Direct Light', 'direct target must outrank an intermediate route')
	assert_equal(plan.predicted_result, 'Light', 'direct target predicted result')
	assert_equal(plan.skillchain_target, 'light', 'plan records selected target')
	assert_equal(plan.target_distance, 0, 'direct target distance')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Distortion' })
	plan, reason = runtime:plan_continuation(1001, {
		named_candidate(21, 'Wrong Branch', { 'Gravitation' }),
		named_candidate(22, 'Toward Light', { 'Fusion' }),
	}, context, 103.5, 'light')
	assert_true(plan ~= nil, 'intermediate Light route must remain eligible')
	assert_equal(plan.ws_name, 'Toward Light', 'off-target branch must be filtered')
	assert_equal(plan.predicted_result, 'Fusion', 'intermediate route result')
	assert_true((tonumber(plan.target_distance) or 0) > 0, 'intermediate route must have positive distance')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Light' })
	plan, reason = runtime:plan_continuation(1001, {
		named_candidate(31, 'Double Light', { 'Light' }),
	}, context, 103.5, 'darkness')
	assert_equal(plan, nil, 'unreachable target must not plan a closer')
	assert_equal(reason, 'SC_NO_PATH_TO_TARGET', 'unreachable target reason')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Light' })
	plan, reason = runtime:plan_continuation(1001, {
		named_candidate(41, 'Double Light', { 'Light' }),
	}, context, 103.5, 'radiance')
	assert_equal(plan, nil, 'non-Aeonic actor must not claim a Radiance path')
	assert_equal(reason, 'SC_NO_PATH_TO_TARGET', 'non-Aeonic Radiance reason')

	local insufficient_aeonic_context = actor_context(2001, 1, false, nil, 'Dojikiri Yasutsuna')
	plan, reason = runtime:plan_continuation(1001, {
		named_candidate(42, 'Terminal Double Light', { 'Light' }),
	}, insufficient_aeonic_context, 103.5, 'radiance')
	assert_equal(plan, nil, 'insufficient Aeonic eligibility must not route through terminal Double Light')
	assert_equal(reason, 'SC_NO_PATH_TO_TARGET', 'terminal Double Light Radiance reason')

	local aeonic_context = actor_context(2001, 3, false, nil, 'Dojikiri Yasutsuna')
	plan, reason = runtime:plan_continuation(1001, {
		named_candidate(42, 'Radiance Closer', { 'Light' }),
	}, aeonic_context, 103.5, 'radiance')
	assert_true(plan ~= nil, 'Aeonic actor with valid aftermath must reach Radiance')
	assert_equal(plan.predicted_result, 'Radiance', 'Aeonic target result')
	assert_equal(plan.target_distance, 0, 'Aeonic direct target distance')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Induration' })
	plan = runtime:plan_continuation(1001, {
		named_candidate(51, 'First Equal Level', { 'Compression' }),
		named_candidate(52, 'Second Equal Level', { 'Impaction' }),
	}, context, 103.5, 'auto')
	assert_equal(plan.ws_name, 'Second Equal Level', 'Auto must preserve legacy later-candidate tie behavior')

	runtime = new_runtime(100)
	opener(runtime, 1001, 100, { 'Fragmentation' })
	plan = runtime:plan_continuation(1001, {
		named_candidate(61, 'Direct Light', { 'Fusion' }),
	}, context, 103.5, 'light')
	local commit = valid_commit(plan, context, 103.6)
	commit.skillchain_target = 'darkness'
	local ok, commit_reason = runtime:revalidate_plan(plan, commit)
	assert_false(ok, 'changing target policy after planning must cancel the closer')
	assert_equal(commit_reason, 'SC_TARGET_POLICY_CHANGED', 'changed target policy reason')
end

local function main()
	test_clock_contract()
	test_action_family_classification()
	test_basic_directional_success()
	test_action_specific_delay_and_server_authority()
	test_early_and_late_overwrite()
	test_failed_and_propertyless_preservation()
	test_target_isolation_and_aoe_selected_target()
	test_priority_and_level_two_transitions()
	test_configured_skillchain_target_planning()
	test_terminal_and_aeonic()
	test_chainbound_rules()
	test_diamond_aspis_actor_expiry()
	test_long_nonterminal_chain()
	test_plan_and_commit_revalidation()
	test_dispatched_generation_waits_for_result()
	test_timing_boundaries_and_cleanup()
	test_field_log_audit()
	io.stdout:write('selftest_skillchain_state: OK\n')
end

main()
