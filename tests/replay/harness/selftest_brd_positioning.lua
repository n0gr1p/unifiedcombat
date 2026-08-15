package.loaded['uc_brd_positioning'] = nil

local positioning = require('uc_brd_positioning')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message or 'assert_true failed')
	end
end

local function member(id, name, x, y, is_self)
	return {
		id = id,
		name = name,
		x = x,
		y = y,
		hpp = 100,
		spawn_type = 13,
		is_npc = false,
		is_self = is_self == true,
	}
end

local split_party = {
	member(1, 'Bard', 0, 0, true),
	member(2, 'CampTank', 0, 1),
	member(3, 'CampMage', 0, -1),
	member(4, 'ForwardTank', 15, 0),
	member(5, 'ForwardMelee', 15, 1),
	member(6, 'ForwardHealer', 15, -1),
}

local plan, reason = positioning.select_position({
	me = { x = 0, y = 0 },
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(type(plan) == 'table', 'split party must have a feasible midpoint plan')
assert_equal(reason, 'BRD_REPOSITION_FULL_PARTY', 'split-party plan reason mismatch')
assert_true(plan.full_coverage, 'midpoint plan must cover the full party')
assert_equal(plan.coverage_count, 5, 'midpoint plan must cover every recipient other than the caster')
assert_true(plan.x > 5 and plan.x < 10, 'midpoint plan must lie between the two groups')

local already_covered = positioning.select_position({
	me = { x = 7.5, y = 0 },
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(already_covered.move_distance < 0.001, 'a Bard already covering everyone must not reposition')

local separated_party = {
	member(1, 'Bard', 0, 0, true),
	member(2, 'CampTank', 0, 1),
	member(3, 'CampMage', 0, -1),
	member(4, 'RemoteTank', 30, 0),
	member(5, 'RemoteMelee', 30, 1),
}
local cluster = positioning.select_position({
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(type(cluster) == 'table', 'separated party must produce a largest-cluster plan')
assert_equal(cluster.full_coverage, false, 'separated party must not claim full coverage')
assert_equal(cluster.coverage_count, 2, 'largest cluster must cover the camp group')
assert_true(cluster.move_distance < 0.001, 'largest-cluster tie must prefer no Bard movement')

local normal_action = {
	action_type = 'spell',
	action_name = 'Honor March',
	reason_code = 'brd_song_expiring',
	urgency = 0.74,
	detail = {},
}
local ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 10,
	action = normal_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'ordinary maintenance must wait when full-party coverage is impossible')
assert_equal(prepare_reason, 'BRD_REPOSITION_WAIT_FULL_PARTY', 'ordinary split-party wait reason mismatch')

local urgent_action = {
	action_type = 'spell',
	action_name = 'Honor March',
	reason_code = 'brd_song_expiring',
	urgency = 0.98,
	detail = {},
}
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 11,
	action = urgent_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(ready, 'urgent maintenance may use the largest cluster when already positioned')
assert_equal(prepare_reason, 'BRD_REPOSITION_URGENT_CLUSTER_CURRENT', 'urgent cluster reason mismatch')

local capacity_action = {
	action_type = 'spell',
	action_name = 'Army\'s Paeon',
	reason_code = 'brd_build_capacity_dummy',
	urgency = 0.98,
	detail = { is_dummy = true },
}
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 12,
	action = capacity_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'capacity work must not begin for a partial cluster')
assert_equal(prepare_reason, 'BRD_REPOSITION_WAIT_FULL_PARTY_RESOURCE', 'capacity split-party wait reason mismatch')

local ability_action = {
	action_type = 'ja',
	action_name = 'Soul Voice',
	reason_code = 'brd_activate_soul_voice',
	urgency = 0.99,
	detail = {},
}
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 13,
	action = ability_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'Bard resource abilities must not begin for a partial cluster')
assert_equal(prepare_reason, 'BRD_REPOSITION_WAIT_FULL_PARTY_RESOURCE', 'ability split-party wait reason mismatch')

positioning.reset('formation_partial_song')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = true,
	now = 14,
	action = normal_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(ready, 'active generic formation must maintain songs for the largest reachable cluster')
assert_equal(prepare_reason, 'BRD_REPOSITION_FORMATION_CLUSTER_CURRENT', 'formation song cluster reason mismatch')

positioning.reset('formation_partial_capacity')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = true,
	now = 15,
	action = capacity_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(ready, 'active generic formation must allow capacity work for the largest reachable cluster')
assert_equal(prepare_reason, 'BRD_REPOSITION_FORMATION_CLUSTER_CURRENT', 'formation capacity cluster reason mismatch')

positioning.reset('formation_partial_ability')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = true,
	now = 16,
	action = ability_action,
	me = { x = 0, y = 0 },
	party_members = separated_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(ready, 'active generic formation must allow Bard setup abilities for the largest reachable cluster')
assert_equal(prepare_reason, 'BRD_REPOSITION_FORMATION_CLUSTER_CURRENT', 'formation ability cluster reason mismatch')

local formation_move_party = {
	member(1, 'Bard', 0, 0, true),
	member(2, 'CampTank', 0, 1),
	member(3, 'RemoteTank', 30, 0),
	member(4, 'RemoteMelee', 30, 1),
	member(5, 'RemoteHealer', 30, -1),
}
positioning.reset('formation_partial_movement')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = true,
	now = 17,
	action = normal_action,
	me = { x = 0, y = 0 },
	party_members = formation_move_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'active generic formation must reposition toward the largest reachable cluster')
assert_equal(prepare_reason, 'BRD_REPOSITION_FORMATION_CLUSTER', 'formation movement reason mismatch')
local formation_request = positioning.movement_request({ x = 0, y = 0 }, 17)
assert_equal(formation_request.kind, 'run', 'formation cluster plan must use Bard movement ownership')
assert_true(formation_request.run_x > 0, 'formation cluster movement must point toward the larger remote group')
assert_equal(formation_request.coverage_count, 3, 'formation cluster movement must maximize reachable recipients')
local formation_arrival = { x = formation_request.target_x, y = formation_request.target_y }
assert_equal(positioning.movement_request(formation_arrival, 17.2).kind, 'stop', 'formation cluster arrival must stop movement')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = true,
	now = 17.6,
	action = normal_action,
	me = formation_arrival,
	party_members = formation_move_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(ready, 'settled formation cluster must release the song proposal')
assert_equal(prepare_reason, 'BRD_REPOSITION_READY_FORMATION_CLUSTER', 'settled formation cluster reason mismatch')

local camp_blocked_plan, camp_blocked_reason = positioning.select_position({
	me = { x = 0, y = 0 },
	party_members = {
		member(1, 'Bard', 20, 0, true),
		member(2, 'RemoteTank', 21, 0),
	},
	ignore_names = {},
	radius = 5,
	camp_anchor = { x = 0, y = 0 },
	camp_leash_yalms = 5,
})
assert_equal(camp_blocked_plan, nil, 'camp-constrained planning must reject positions covering no recipients')
assert_equal(camp_blocked_reason, 'BRD_REPOSITION_NO_CAMP_VIABLE_POSITION', 'camp-constrained rejection reason mismatch')

positioning.reset('movement_test')
ready = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 20,
	action = normal_action,
	me = { x = 0, y = 0 },
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'split-party midpoint must require movement')
local request = positioning.movement_request({ x = 0, y = 0 }, 20)
assert_equal(request.kind, 'run', 'midpoint plan must emit a run vector')
assert_true(request.run_x > 0, 'midpoint run vector must point toward the forward group')
local original_target_x = request.target_x
local halfway_party = {
	member(1, 'Bard', original_target_x / 2, 0, true),
	member(2, 'CampTank', 0, 1),
	member(3, 'CampMage', 0, -1),
	member(4, 'ForwardTank', 15, 0),
	member(5, 'ForwardMelee', 15, 1),
	member(6, 'ForwardHealer', 15, -1),
}
ready = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 20.2,
	action = normal_action,
	me = { x = original_target_x / 2, y = 0 },
	party_members = halfway_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'in-flight positioning must retain the movement phase')
request = positioning.movement_request({ x = original_target_x / 2, y = 0 }, 20.2)
assert_equal(request.target_x, original_target_x, 'caster movement must not cause the active target to drift')
local arrival = { x = request.target_x, y = request.target_y }
request = positioning.movement_request(arrival, 21)
assert_equal(request.kind, 'stop', 'arrival must emit a physical stop')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 21.2,
	action = normal_action,
	me = arrival,
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(ready, false, 'arrival must honor movement settle time')
ready, prepare_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 21.4,
	action = normal_action,
	me = arrival,
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(ready, 'settled midpoint must release the song proposal')
assert_equal(prepare_reason, 'BRD_REPOSITION_READY_FULL_PARTY', 'settled midpoint reason mismatch')

positioning.reset('stall_test')
positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 30,
	action = normal_action,
	me = { x = 0, y = 0 },
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_equal(positioning.movement_request({ x = 0, y = 0 }, 30).kind, 'run', 'stall test must begin movement')
local stalled = positioning.movement_request({ x = 0, y = 0 }, 32.1)
assert_equal(stalled.kind, 'stop', 'stalled movement must stop instead of perpetuating a vector')
assert_equal(stalled.reason, 'BRD_REPOSITION_STALLED', 'stalled movement reason mismatch')

local targeted_ready, targeted_reason = positioning.prepare({
	enabled = true,
	allow_formation_partial = false,
	now = 40,
	action = {
		action_name = 'Pianissimo',
		reason_code = 'brd_targeted_pianissimo',
		urgency = 0.74,
		detail = { targeted_recipient_id = 4 },
	},
	me = { x = 0, y = 0 },
	party_members = split_party,
	ignore_names = {},
	radius = 9.9,
})
assert_true(targeted_ready, 'targeted Bard work must not trigger group repositioning')
assert_equal(targeted_reason, 'targeted_action', 'targeted positioning bypass reason mismatch')

io.stdout:write('selftest_brd_positioning: OK\n')
