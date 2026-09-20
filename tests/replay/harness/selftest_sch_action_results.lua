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

	local production_catalog = module.production_catalog('spell', 'Regen V')
	local production = classify({
		{ id = 1001, actions = { { message = 230, param = 42 } } },
	}, production_catalog)
	assert_equal(production.state, 'classified', 'captured production result must classify')
	assert_equal(production.outcome, 'partial_success',
		'captured single-recipient production outcome mismatch')
	assert_equal(production.catalog_source,
		'windower_resources:action_messages',
		'production action-result source mismatch')
	local phalanx = module.classify({
		action_type = 'spell',
		action_name = 'Phalanx',
		expected_recipients = { { id = 1001, name = 'Scholar' } },
		raw_targets = { { id = 1001, actions = { { message = 230, param = 116 } } } },
		catalog = module.production_catalog('spell', 'Phalanx'),
	})
	assert_equal(phalanx.outcome, 'success',
		'cataloged Accession maintenance spell result mismatch')
	local light_arts = module.classify({
		action_type = 'job_ability',
		action_name = 'Light Arts',
		expected_recipients = { { id = 1001, name = 'Scholar' } },
		raw_targets = { { id = 1001, actions = { { message = 100, param = 0 } } } },
		catalog = module.production_catalog('job_ability', 'Light Arts'),
	})
	assert_equal(light_arts.outcome, 'success', 'captured Light Arts result mismatch')
	local sublimation_release = module.classify({
		action_type = 'job_ability',
		action_name = 'Sublimation',
		expected_recipients = { { id = 1001, name = 'Scholar' } },
		raw_targets = { { id = 1001, actions = { { message = 451, param = 332 } } } },
		catalog = module.production_catalog('job_ability', 'Sublimation'),
	})
	assert_equal(sublimation_release.outcome, 'success',
		'captured Sublimation release result mismatch')
	local thunderstorm = module.classify({
		action_type = 'spell',
		action_name = 'Thunderstorm II',
		expected_recipients = { { id = 1002, name = 'Tank' } },
		raw_targets = { { id = 1002, actions = { { message = 230, param = 593 } } } },
		catalog = module.production_catalog('spell', 'Thunderstorm II'),
	})
	assert_equal(thunderstorm.outcome, 'success',
		'captured Thunderstorm II result mismatch')
	local unknown_catalog = module.production_catalog('spell', 'Haste')
	assert_equal(unknown_catalog.confidence, 'unknown',
		'uncaptured exact action must remain unknown')

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
