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
	package.loaded.uc_sch_duration = nil
	local duration = require('uc_sch_duration')
	local unknown = duration.estimate({
		family = 'regen',
		spell = 'Regen V',
		cast_at = 100,
		applied_modifiers = { 'Accession', 'Perpetuance' },
		evidence = {
			confidence = 'unknown',
			reason = 'phase0_duration_unvalidated',
		},
	})
	assert_equal(unknown.duration_confidence, 'unknown', 'unknown duration confidence mismatch')
	assert_equal(unknown.estimated_expires_at, 0, 'unknown duration must not claim an end time')
	assert_equal(unknown.duration_model_key, 'regen|Regen V|Accession,Perpetuance',
		'duration model key mismatch')
	local unknown_storm = duration.estimate({
		family = 'storm',
		spell = 'Thunderstorm II',
		cast_at = 100,
		applied_modifiers = {},
		evidence = {
			confidence = 'unknown',
			reason = 'phase0_duration_unvalidated',
		},
	})
	assert_equal(unknown_storm.duration_confidence, 'unknown',
		'unvalidated storm duration must remain unknown')
	assert_equal(unknown_storm.duration_model_key, 'storm|Thunderstorm II|',
		'storm duration model key mismatch')

	local confirmed = duration.estimate({
		family = 'regen',
		spell = 'Regen V',
		cast_at = 100,
		applied_modifiers = { 'Accession', 'Perpetuance' },
		evidence = {
			confidence = 'confirmed',
			model_key = 'regen|Regen V|Accession,Perpetuance',
			duration_s = 180,
			source = 'fixture:validated_regen_v_accession_perpetuance',
		},
	})
	assert_equal(confirmed.duration_confidence, 'confirmed', 'confirmed duration confidence mismatch')
	assert_equal(confirmed.estimated_expires_at, 280, 'confirmed duration end time mismatch')
	assert_equal(confirmed.duration_source, 'fixture:validated_regen_v_accession_perpetuance',
		'confirmed duration source mismatch')

	local mismatched = pcall(duration.estimate, {
		family = 'regen',
		spell = 'Regen V',
		cast_at = 100,
		applied_modifiers = { 'Accession', 'Perpetuance' },
		evidence = {
			confidence = 'confirmed',
			model_key = 'regen|Regen V|Perpetuance',
			duration_s = 180,
			source = 'fixture:mismatch',
		},
	})
	assert_true(not mismatched, 'mismatched duration evidence must fail fast')

	local invented_unknown = pcall(duration.estimate, {
		family = 'regen',
		spell = 'Regen V',
		cast_at = 100,
		applied_modifiers = { 'Accession', 'Perpetuance' },
		evidence = {
			confidence = 'unknown',
			reason = 'unvalidated',
			duration_s = 180,
		},
	})
	assert_true(not invented_unknown, 'unknown evidence must not carry an invented duration')

	local duplicate = pcall(duration.model_key,
		'regen', 'Regen V', { 'Perpetuance', 'Perpetuance' })
	assert_true(not duplicate, 'duplicate duration modifiers must fail fast')
	print('selftest_sch_duration: OK')
end

main()
