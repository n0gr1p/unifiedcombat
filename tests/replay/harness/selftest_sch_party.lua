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
	package.loaded.uc_sch_party = nil
	local party = require('uc_sch_party')
	local tracker = party.new_tracker()
	local first = party.observe(tracker, {
		{ id = 1001, name = 'Scholar', hpp = 100, x = 1, y = 2, z = 3, buffs = { 358 } },
		{ id = 1002, name = 'Tank', hpp = 100, buffs = {} },
	}, 100)
	assert_equal(first.generation, 1, 'first roster generation mismatch')
	assert_equal(first.members[1].coordinate_observed_at, 100,
		'complete coordinates must receive the observation timestamp')
	assert_true(first.members[2].coordinate_observed_at == nil,
		'missing coordinates must not receive a freshness timestamp')
	local reordered = party.observe(tracker, {
		{ id = 1002, name = 'Tank', hpp = 90, buffs = { 42 } },
		{ id = 1001, name = 'Scholar', hpp = 99, x = 4, y = 5, buffs = { 358 } },
	}, 101)
	assert_equal(reordered.generation, 1, 'slot and vital changes must not change roster generation')
	assert_equal(reordered.members[2].coordinate_observed_at, 101,
		'coordinate observations must be timestamped independently of roster generation')
	local replaced = party.observe(tracker, {
		{ id = 1001, name = 'Scholar', hpp = 99, buffs = { 358 } },
		{ id = 1003, name = 'Healer', hpp = 100, buffs = {} },
	}, 102)
	assert_equal(replaced.generation, 2, 'membership change must increment roster generation')
	assert_true(first.members[1].buffs ~= replaced.members[1].buffs, 'party snapshots must not share buff tables')

	local duplicate_ok = pcall(party.observe, tracker, {
		{ id = 1001, name = 'Scholar' },
		{ id = 1001, name = 'Duplicate' },
	}, 103)
	assert_true(not duplicate_ok, 'duplicate party ids must fail fast')
	local coerced_ok = pcall(party.observe, tracker, {
		{ id = '1001', name = 'Scholar' },
	}, 104)
	assert_true(not coerced_ok, 'string party ids must fail fast')
	local coordinate_ok = pcall(party.observe, tracker, {
		{ id = 1001, name = 'Scholar', x = '1', y = 2 },
	}, 105)
	assert_true(not coordinate_ok, 'string coordinates must fail fast')
	assert_equal(tracker.generation, 2,
		'invalid coordinates must not partially advance party generation')

	print('selftest_sch_party: OK')
end

main()
