local context = require('uc_scheduler_context')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local calls = {
	player = 0,
	target = 0,
	party = 0,
	mobs = 0,
	now = 0,
}
local player = { id = 101, name = 'Player', status = 1 }
local me = { id = 101, name = 'Player' }
local target = { id = 202, name = 'Target' }
local mob_array = {
	[1] = target,
	[2] = { id = 303, name = 'Other' },
}
local phase1 = { tick = 7 }
local settings = { autotarget = true }

local snapshot = context.build(settings, phase1, {
	get_player = function()
		calls.player = calls.player + 1
		return player
	end,
	get_mob_by_target = function(token)
		calls.target = calls.target + 1
		if token == 'me' then
			return me
		end
		if token == 't' then
			return target
		end
		error('unexpected target token: ' .. tostring(token))
	end,
	get_party = function()
		calls.party = calls.party + 1
		return { p0 = { id = 101 } }
	end,
	get_mob_array = function()
		calls.mobs = calls.mobs + 1
		return mob_array
	end,
	now = function()
		calls.now = calls.now + 1
		return 123.5
	end,
})

assert_equal(snapshot.now, 123.5, 'snapshot time')
assert_equal(snapshot.tick, 8, 'snapshot tick')
assert_equal(phase1.tick, 8, 'phase tick incremented once')
assert_equal(snapshot.settings, settings, 'settings identity')
assert_equal(snapshot.player, player, 'player identity')
assert_equal(snapshot.target, target, 'target identity')
assert_equal(snapshot.player_status, 1, 'derived player status')
assert_equal(snapshot.mobs_by_id[202], target, 'target indexed by id')
assert_equal(snapshot.mobs_by_id[303].name, 'Other', 'mob array indexed by id')
assert_equal(calls.player, 1, 'player sampled once')
assert_equal(calls.target, 2, 'me and target sampled once each')
assert_equal(calls.party, 1, 'party sampled once')
assert_equal(calls.mobs, 1, 'mob array sampled once')
assert_equal(calls.now, 1, 'time sampled once')

player.status = 0
target.name = 'Changed'
assert_equal(snapshot.player_status, 1, 'derived status remains tick-stable')
assert_equal(snapshot.target_name, nil, 'no unsanctioned derived target name')

local empty = context.build({}, {}, {
	get_player = function()
		return nil
	end,
	get_mob_by_target = function()
		return nil
	end,
	get_party = function()
		return nil
	end,
	get_mob_array = function()
		return nil
	end,
	now = function()
		return 0
	end,
})
assert_equal(empty.player_present, false, 'missing player recorded')
assert_equal(empty.target_present, false, 'missing target recorded')
assert_equal(empty.player_status, -1, 'missing player status')

io.stdout:write('selftest_scheduler_context: OK\n')
