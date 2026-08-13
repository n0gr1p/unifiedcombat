local mock_state_factory = require('uc_formation_mock_state')

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

local actors = {
	{ id = 700, name = 'Apex Crab', x = 10, y = 20, z = 0, facing = 0.5, hpp = 100, status = 0 },
}
local target = actors[1]
local runtime = mock_state_factory.build({
	get_mob_array = function()
		return actors
	end,
	get_target = function()
		return target
	end,
})
local config = {
	enabled = true,
	encounter = 'sortie_ghatjot',
	mob_name = 'Apex Crab',
}

local snapshot, reason = runtime.observe(1.0, config)
assert_equal(reason, 'FORMATION_MOCK_ORIGIN_CAPTURE_STABILIZING', 'idle mock must begin origin capture')
assert_equal(snapshot.phase, 'binding', 'idle mock binding phase mismatch')
assert_equal(snapshot.origin, nil, 'origin must not publish before stability interval')

snapshot, reason = runtime.observe(1.6, config)
assert_equal(reason, 'FORMATION_MOCK_ORIGIN_CAPTURED', 'stable idle mock must capture origin')
assert_equal(snapshot.origin.x, 10, 'captured mock origin x mismatch')
assert_equal(snapshot.origin.y, 20, 'captured mock origin y mismatch')
assert_equal(snapshot.boss.facing, 0.5, 'mock boss heading must be preserved')

actors[1].status = 1
actors[1].x = 14
actors[1].y = 22
actors[1].facing = 1.25
target = nil
snapshot, reason = runtime.observe(2.0, config)
assert_equal(snapshot.phase, 'active', 'engaged mock phase mismatch')
assert_equal(snapshot.boss.x, 14, 'mock boss must track live movement')
assert_equal(snapshot.boss.y, 22, 'mock boss live y mismatch')
assert_equal(snapshot.boss.facing, 1.25, 'mock boss heading must track live facing')
assert_equal(snapshot.origin.x, 10, 'mock origin must remain at pre-engage capture')
assert_equal(snapshot.resolved_id, 'sortie_ghatjot', 'mock must retain selected geometry identity')
assert_true(snapshot.mock, 'mock snapshot must identify its source')

actors[2] = { id = 701, name = 'Apex Crab', x = 30, y = 30, z = 0, hpp = 100, status = 1 }
snapshot, reason = runtime.observe(2.5, config)
assert_equal(snapshot.boss.id, 700, 'mock binding must track the originally targeted actor ID')
assert_equal(snapshot.boss.x, 14, 'same-name actors must not replace the bound mock boss')

actors = { actors[2] }
snapshot, reason = runtime.observe(3.0, config)
assert_equal(reason, 'FORMATION_MOCK_BOUND_MOB_NOT_FOUND', 'missing bound mock target reason mismatch')
assert_equal(snapshot.boss, nil, 'missing mock target must not retain a boss')

target = actors[1]
snapshot, reason = runtime.observe(3.5, config)
assert_equal(snapshot.boss.id, 701, 'retargeting must explicitly bind the replacement actor')

runtime.reset('target_required_test')
target = nil
snapshot, reason = runtime.observe(3.6, config)
assert_equal(reason, 'FORMATION_MOCK_TARGET_REQUIRED', 'initial mock binding must require the named target')

local ok, err = pcall(function()
	runtime.observe(4.0, {
		enabled = true,
		encounter = 'sortie_ghatjot',
		mob_name = '',
	})
end)
assert_equal(ok, false, 'enabled mock without a mob name must fail fast')
assert_true(tostring(err):find('mock.mob_name', 1, true) ~= nil, 'missing mock mob error mismatch')

snapshot, reason = runtime.observe(5.0, { enabled = false })
assert_equal(reason, 'FORMATION_MOCK_DISABLED', 'disabled mock reason mismatch')
assert_equal(snapshot.enabled, false, 'disabled mock must clear enabled state')

io.stdout:write('selftest_formation_mock_state: OK\n')
