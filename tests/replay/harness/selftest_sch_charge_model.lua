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

local function input(recast)
	return {
		main_job_level = 99,
		job_points_present = true,
		job_points_spent = 2100,
		recast_present = true,
		observed_recast = recast,
		tabula_rasa_active = false,
	}
end

local function catalog(tabula_policy)
	return {
		confidence = 'confirmed',
		model_key = 'SCH|99|true|2100|231',
		source = 'fixture:validated_time_until_full',
		encoding = 'time_until_full',
		maximum_charges = 5,
		recharge_interval_s = 30,
		recast_unit_scale = 1,
		boundary_tolerance_s = 0,
		tabula_rasa_policy = tabula_policy or 'use_recast',
	}
end

local function main()
	package.loaded.uc_sch_charge_model = nil
	local model = require('uc_sch_charge_model')
	local production = model.decode(input(17), model.production_catalog(99, true, 2100))
	assert_equal(production.confidence, 'confirmed', 'production charge confidence mismatch')
	assert_equal(production.available, 4, 'captured production charge count mismatch')
	assert_equal(production.decoder_source,
		'sch_capture:Nyoourke_solo_phase1_20260820T104827Z',
		'production charge evidence source mismatch')
	local uncaptured_input = input(17)
	uncaptured_input.job_points_spent = 2000
	local unknown = model.decode(
		uncaptured_input,
		model.production_catalog(99, true, 2000)
	)
	assert_equal(unknown.confidence, 'unknown', 'uncaptured progression must remain unknown')
	assert_equal(unknown.reason, 'charge_mapping_not_captured_for_exact_progression',
		'uncaptured progression blocker mismatch')

	local full = model.decode(input(0), catalog())
	assert_equal(full.available, 5, 'zero time-until-full charge count mismatch')
	local four = model.decode(input(30), catalog())
	assert_equal(four.available, 4, 'one-interval charge count mismatch')
	local three = model.decode(input(30.1), catalog())
	assert_equal(three.available, 3, 'boundary rounding charge count mismatch')
	local empty = model.decode(input(150), catalog())
	assert_equal(empty.available, 0, 'maximum debt charge count mismatch')

	local contradiction = model.decode(input(151), catalog())
	assert_equal(contradiction.confidence, 'unknown', 'out-of-model recast must invalidate confidence')
	assert_equal(contradiction.reason, 'recast_outside_confirmed_model',
		'out-of-model recast blocker mismatch')

	local absent_input = input(0)
	absent_input.recast_present = false
	absent_input.observed_recast = nil
	local absent = model.decode(absent_input, catalog())
	assert_equal(absent.reason, 'recast_unavailable', 'absent recast blocker mismatch')
	assert_true(absent.observed_recast == nil, 'absent recast must remain missing')

	local missing_jp_input = input(0)
	missing_jp_input.job_points_present = false
	missing_jp_input.job_points_spent = 0
	local missing_jp = model.decode(
		missing_jp_input,
		model.production_catalog(99, false, 0)
	)
	assert_equal(missing_jp.reason, 'job_points_unobserved', 'missing job-point blocker mismatch')

	local tabula_input = input(120)
	tabula_input.tabula_rasa_active = true
	local tabula = model.decode(tabula_input, catalog('force_maximum'))
	assert_equal(tabula.available, 5, 'confirmed Tabula policy mismatch')
	local tabula_unknown = model.decode(tabula_input, catalog('unknown'))
	assert_equal(tabula_unknown.reason, 'tabula_rasa_charge_semantics_unvalidated',
		'unknown Tabula policy blocker mismatch')

	local malformed_absent = input(0)
	malformed_absent.recast_present = false
	assert_true(not pcall(model.decode, malformed_absent, catalog()),
		'absent recast with a numeric sentinel must fail fast')
	print('selftest_sch_charge_model: OK')
end

main()
