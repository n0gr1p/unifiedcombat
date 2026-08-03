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

local function expected()
	return {
		{ id = 1001, name = 'Scholar' },
		{ id = 1002, name = 'Tank' },
		{ id = 1003, name = 'Mage' },
	}
end

local function catalog()
	return {
		confidence = 'confirmed',
		model_key = 'spell|Regen V',
		source = 'fixture:classified_regen_v_results',
		rules = {
			{ message_id = 230, param = 'any', outcome = 'success' },
			{ message_id = 236, param = 'any', outcome = 'no_effect' },
			{ message_id = 284, param = 'any', outcome = 'resist' },
			{ message_id = 16, param = 'any', outcome = 'interrupted' },
		},
	}
end

local function classify(results, rules)
	local module = require('uc_sch_action_results')
	return module.classify({
		action_type = 'spell',
		action_name = 'Regen V',
		expected_recipients = expected(),
		raw_targets = results,
		catalog = rules,
	})
end

local function main()
	package.loaded.uc_sch_action_results = nil
	local module = require('uc_sch_action_results')
	local success = classify({
		{ id = 1001, actions = { { message = 230, param = 42 } } },
		{ id = 1002, actions = { { message = 230, param = 42 } } },
		{ id = 1003, actions = { { message = 230, param = 42 } } },
	}, catalog())
	assert_equal(success.state, 'classified', 'full success state mismatch')
	assert_equal(success.outcome, 'success', 'full success outcome mismatch')
	assert_equal(#success.successful_recipients, 3, 'full success recipient count mismatch')

	local partial = classify({
		{ id = 1001, actions = { { message = 230, param = 42 } } },
		{ id = 1002, actions = { { message = 236, param = 42 } } },
	}, catalog())
	assert_equal(partial.outcome, 'partial_success', 'partial success outcome mismatch')
	assert_equal(partial.successful_recipients[1].id, 1001, 'partial success recipient mismatch')
	assert_equal(partial.missing_expected_recipient_ids[1], 1003, 'missing expected recipient mismatch')

	local unexpected = classify({
		{ id = 1001, actions = { { message = 230, param = 42 } } },
		{ id = 1002, actions = { { message = 230, param = 42 } } },
		{ id = 1003, actions = { { message = 230, param = 42 } } },
		{ id = 1099, actions = { { message = 230, param = 42 } } },
	}, catalog())
	assert_equal(unexpected.outcome, 'success', 'unexpected success transaction mismatch')
	assert_equal(unexpected.unexpected_recipient_ids[1], 1099, 'unexpected recipient mismatch')
	assert_equal(unexpected.successful_recipients[4].name, '',
		'unexpected recipient must not gain an invented name')

	local unknown_catalog = module.production_catalog('spell', 'Regen V')
	local blocked = classify({
		{ id = 1001, actions = { { message = 230, param = 42 } } },
	}, unknown_catalog)
	assert_equal(blocked.state, 'unclassified', 'production catalog must remain unclassified')
	assert_equal(blocked.blocker, 'phase0_action_results_unvalidated',
		'production action-result blocker mismatch')
	assert_equal(#blocked.successful_recipients, 0,
		'unvalidated production messages must not create successful recipients')
	assert_equal(blocked.unknown_message_ids[1], 230, 'unknown message visibility mismatch')

	local unknown_message = classify({
		{ id = 1001, actions = { { message = 999, param = 42 } } },
	}, catalog())
	assert_equal(unknown_message.blocker, 'action_result_unclassified',
		'unknown confirmed-catalog message blocker mismatch')
	assert_equal(#unknown_message.successful_recipients, 0,
		'an unclassified transaction must not commit known target successes')

	local interrupted = classify({
		{ id = 1001, actions = { { message = 16, param = 42 } } },
	}, catalog())
	assert_equal(interrupted.outcome, 'failure', 'interrupted transaction outcome mismatch')
	assert_true(interrupted.interrupted, 'interrupted transaction flag mismatch')

	local duplicate_ok = pcall(classify, {
		{ id = 1001, actions = { { message = 230, param = 42 } } },
		{ id = 1001, actions = { { message = 230, param = 42 } } },
	}, catalog())
	assert_true(not duplicate_ok, 'duplicate raw target ids must fail fast')

	local coerced_ok = pcall(classify, {
		{ id = '1001', actions = { { message = 230, param = 42 } } },
	}, catalog())
	assert_true(not coerced_ok, 'coerced raw target ids must fail fast')
	print('selftest_sch_action_results: OK')
end

main()
