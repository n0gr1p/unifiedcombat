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

local function members()
	return {
		{ id = 1001, name = 'First', hpp = 100, x = 0, y = 0, z = 0, coordinate_observed_at = 99.8 },
		{ id = 1002, name = 'Second', hpp = 100, x = 2, y = 0, z = 0, coordinate_observed_at = 99.8 },
		{ id = 1003, name = 'Third', hpp = 100, x = 4, y = 0, z = 0, coordinate_observed_at = 99.8 },
		{ id = 1004, name = 'Fourth', hpp = 100, x = 20, y = 0, z = 0, coordinate_observed_at = 99.8 },
	}
end

local function input()
	return {
		now = 100,
		members = members(),
		eligible_recipient_ids = { 1001, 1002, 1003, 1004 },
		unsafe_recipient_ids = {},
		minimum_coverage = 3,
		mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:confirmed_accession_geometry',
			radius_yalms = 3,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
	}
end

local function main()
	package.loaded.uc_sch_area_planner = nil
	local planner = require('uc_sch_area_planner')
	local planned = planner.select(input())
	assert_equal(planned.state, 'ready', 'confirmed geometry plan state mismatch')
	assert_equal(planned.selected.anchor_id, 1002, 'maximum coverage anchor mismatch')
	assert_equal(planned.selected.coverage_count, 3, 'maximum coverage count mismatch')
	assert_equal(planned.selected.expected_recipient_ids[1], 1001, 'recipient order mismatch')
	assert_equal(planned.selected.expected_recipient_ids[3], 1003, 'recipient order mismatch')
	assert_equal(#planned.candidates, 4, 'planner must consider every eligible anchor')

	local tied = input()
	tied.mechanics.radius_yalms = 5
	local tied_plan = planner.select(tied)
	assert_equal(tied_plan.selected.anchor_id, 1001,
		'equal maximum coverage must use stable party order before target id')

	local unsafe = input()
	unsafe.eligible_recipient_ids = { 1001, 1002, 1004 }
	unsafe.unsafe_recipient_ids = { 1003 }
	unsafe.minimum_coverage = 2
	local unsafe_plan = planner.select(unsafe)
	assert_equal(unsafe_plan.selected.anchor_id, 1001,
		'anchor covering an unsafe recipient must be rejected')
	assert_true(not unsafe_plan.candidates[2].safe, 'unsafe coverage must be diagnosed per anchor')

	local stale = input()
	stale.members[2].coordinate_observed_at = 90
	local stale_plan = planner.select(stale)
	assert_equal(stale_plan.blocker, 'coverage_unknown', 'stale coordinate blocker mismatch')
	assert_equal(stale_plan.stale_coordinate_ids[1], 1002, 'stale coordinate id mismatch')

	local missing = input()
	missing.members[3].x = nil
	local missing_plan = planner.select(missing)
	assert_equal(missing_plan.blocker, 'coverage_unknown', 'missing coordinate blocker mismatch')
	assert_equal(missing_plan.missing_coordinate_ids[1], 1003, 'missing coordinate id mismatch')

	local below = input()
	below.minimum_coverage = 4
	assert_equal(planner.select(below).blocker, 'coverage_below_minimum',
		'minimum coverage blocker mismatch')

	local unknown = input()
	unknown.mechanics = planner.production_mechanics()
	assert_equal(planner.select(unknown).state, 'ready',
		'captured production mechanics must authorize planning')
	assert_equal(planner.select(unknown).mechanics_source,
		'sch_capture:Nyoourke_party_ranges_20260820T113121Z',
		'production geometry source mismatch')

	local invalid = input()
	invalid.eligible_recipient_ids = { 1001, 1001 }
	assert_true(not pcall(planner.select, invalid), 'duplicate eligible ids must fail fast')

	local future = input()
	future.members[1].coordinate_observed_at = 100.1
	assert_true(not pcall(planner.select, future),
		'future coordinate observation times must fail fast')
	print('selftest_sch_area_planner: OK')
end

main()
