local function assert_true(condition, message)
	if not condition then
		error(message or 'assertion failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values are not equal') .. ': expected=' .. tostring(expected)
			.. ', actual=' .. tostring(actual))
	end
end

local function main()
	package.loaded.uc_sch_sublimation = nil
	local sublimation = require('uc_sch_sublimation')
	local safe = sublimation.validate_safety({
		confidence = 'confirmed',
		model_key = 'scheduler_support_safety|v1',
		source = 'fixture:existing_scheduler_signals',
		critical_defensive_present = false,
		dangerous_local_pressure_present = false,
	})
	assert_equal(safe.confidence, 'confirmed', 'confirmed safety confidence mismatch')
	assert_equal(safe.source, 'fixture:existing_scheduler_signals', 'confirmed safety source mismatch')
	local dangerous = sublimation.validate_safety({
		confidence = 'confirmed',
		model_key = 'scheduler_support_safety|v1',
		source = 'fixture:existing_scheduler_signals',
		critical_defensive_present = true,
		dangerous_local_pressure_present = true,
	})
	assert_true(dangerous.critical_defensive_present, 'critical safety signal mismatch')
	assert_true(dangerous.dangerous_local_pressure_present, 'local pressure signal mismatch')
	local scheduler_safe = sublimation.scheduler_safety({
		proposals = {
			{ provider = 'defensive_internal', critical = true },
			{ provider = 'charm_sleeper', critical = false },
		},
		player_doom_present = false,
		defensive_evidence_current = true,
		is_critical_defensive = function(proposal)
			return proposal.critical
		end,
		source = 'fixture:scheduler_signal_scan',
	})
	assert_true(scheduler_safe.critical_defensive_present,
		'scheduler critical defensive scan mismatch')
	assert_true(scheduler_safe.dangerous_local_pressure_present,
		'scheduler charm pressure scan mismatch')
	local doom_safety = sublimation.scheduler_safety({
		proposals = {},
		player_doom_present = true,
		defensive_evidence_current = true,
		is_critical_defensive = function()
			return false
		end,
		source = 'fixture:scheduler_signal_scan',
	})
	assert_true(doom_safety.dangerous_local_pressure_present,
		'scheduler Doom pressure scan mismatch')
	local stale_safety = sublimation.scheduler_safety({
		proposals = {},
		player_doom_present = false,
		defensive_evidence_current = false,
		is_critical_defensive = function()
			return false
		end,
		source = 'fixture:scheduler_signal_scan',
	})
	assert_equal(stale_safety.confidence, 'unknown',
		'stale defensive proposal evidence must remain unknown')
	assert_equal(stale_safety.reason, 'scheduler_defensive_evidence_not_current',
		'stale defensive proposal blocker mismatch')

	local production = sublimation.evaluate_release_capacity({
		mp = 500,
		max_mp = 1000,
	}, sublimation.production_release_mechanics())
	assert_equal(production.state, 'blocked', 'unknown production release mechanics must block')
	assert_equal(production.blocker, 'phase0_sublimation_release_capacity_unvalidated',
		'unknown production release blocker mismatch')
	assert_equal(production.missing_mp, 500, 'unknown release missing MP mismatch')

	local ready = sublimation.evaluate_release_capacity({
		mp = 500,
		max_mp = 1000,
	}, {
		confidence = 'confirmed',
		model_key = 'Sublimation|release_capacity',
		source = 'fixture:validated_release_capacity',
		minimum_missing_mp = 300,
	})
	assert_equal(ready.state, 'ready', 'confirmed release capacity mismatch')
	assert_equal(ready.minimum_missing_mp, 300, 'release minimum capacity mismatch')
	local insufficient = sublimation.evaluate_release_capacity({
		mp = 850,
		max_mp = 1000,
	}, {
		confidence = 'confirmed',
		model_key = 'Sublimation|release_capacity',
		source = 'fixture:validated_release_capacity',
		minimum_missing_mp = 300,
	})
	assert_equal(insufficient.blocker, 'sublimation_release_capacity_below_minimum',
		'insufficient release capacity blocker mismatch')

	local invented_unknown = pcall(sublimation.evaluate_release_capacity, {
		mp = 500,
		max_mp = 1000,
	}, {
		confidence = 'unknown',
		reason = 'unvalidated',
		minimum_missing_mp = 1,
	})
	assert_true(not invented_unknown, 'unknown release mechanics must reject invented capacity')
	local invalid_safety = pcall(sublimation.validate_safety, {
		confidence = 'confirmed',
		model_key = 'wrong',
		source = 'fixture:wrong',
		critical_defensive_present = false,
		dangerous_local_pressure_present = false,
	})
	assert_true(not invalid_safety, 'mismatched safety evidence must fail fast')
	print('selftest_sch_sublimation: OK')
end

main()
