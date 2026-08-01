local encounter = require('uc_lilith_easy_encounter')

local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function boss(status, x, y)
	return {
		id = 1001,
		name = 'Lady Lilith',
		hpp = 100,
		status = status,
		x = x,
		y = y,
		z = 0,
	}
end

local function observe(now, actor)
	return encounter.observe({
		enabled = true,
		encounter = 'lilith_easy',
		capture_stable_s = 0.5,
		capture_tolerance = 0.1,
		now = now,
		boss = actor,
	})
end

encounter.reset('test_start')
local ready, reason = observe(10.0, boss(0, 12.5, -8.0))
assert_equal(ready, false, 'first stationary observation should not capture')
assert_equal(reason, 'CAPTURE_STABILIZING', 'first observation reason mismatch')

ready, reason = observe(10.6, boss(0, 12.5, -8.0))
assert_true(ready, 'stable idle actor should capture center')
assert_equal(reason, 'CENTER_CAPTURED', 'capture reason mismatch')
local center = encounter.center()
assert_equal(center.x, 12.5, 'captured center x mismatch')
assert_equal(center.y, -8.0, 'captured center y mismatch')

ready, reason = observe(11.0, boss(1, 10.0, -8.0))
assert_true(ready, 'captured center should remain ready after engagement')
assert_equal(reason, 'CENTER_READY', 'active center reason mismatch')
center = encounter.center()
assert_equal(center.x, 12.5, 'center must remain immutable after boss movement')

encounter.reset('missed_capture_test')
ready, reason = observe(20.0, boss(1, 9.0, 9.0))
assert_equal(ready, false, 'engaged actor must not be captured')
assert_equal(reason, 'CENTER_CAPTURE_MISSED', 'missed capture reason mismatch')
assert_equal(encounter.center(), nil, 'missed capture must not create a center')

encounter.reset('continuous_capture_test')
ready, reason = observe(30.0, boss(0, 4.0, 5.0))
assert_equal(reason, 'CAPTURE_STABILIZING', 'continuous capture first sample mismatch')
ready, reason = observe(30.6, nil)
assert_equal(reason, 'AWAITING_BOSS', 'missing boss should interrupt capture')
ready, reason = observe(30.7, boss(0, 4.0, 5.0))
assert_equal(ready, false, 'capture must restart after a missing observation')
assert_equal(reason, 'CAPTURE_STABILIZING', 'capture restart reason mismatch')

encounter.observe({ enabled = false })
assert_equal(encounter.status().phase, 'idle', 'disable should reset encounter state')

io.stdout:write('selftest_lilith_easy_encounter: OK\n')
