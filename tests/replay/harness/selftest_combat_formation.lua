local formation = require('uc_combat_formation')

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

local function config(role)
	return {
		enabled = true,
		encounter = 'lilith_easy',
		role = role,
		tank_name = 'Tank',
		required_party_names = {},
		safe_radius = 16,
		tank = {
			accept_radius = 1.5,
			return_radius = 3.0,
		},
		dps = {
			flank_angle_deg = 90,
			melee_radius = 3,
			position_tolerance = 1.5,
		},
		healer = {
			preferred_radius = 12,
			minimum_boss_distance = 8,
			maximum_party_range = 18,
			cone_half_angle_deg = 50,
			cone_safety_margin_deg = 15,
			sample_step_deg = 10,
		},
	}
end

local center = { x = 0, y = 0 }
local boss = { id = 900, x = 0, y = 0 }
local members = {
	{ id = 1, name = 'Tank', x = 3, y = 0 },
	{ id = 2, name = 'Dps', x = 0, y = -3 },
	{ id = 3, name = 'Healer', x = -12, y = 0 },
}

local proposal = formation.evaluate({
	config = config('tank'),
	center = center,
	boss = boss,
	me = { id = 1, x = 1, y = 0 },
	party_members = members,
	was_moving = false,
})
assert_equal(proposal.action, 'hold', 'tank inside accept radius should hold')
assert_equal(proposal.reason, 'FORMATION_TANK_CENTERED', 'tank centered reason mismatch')

proposal = formation.evaluate({
	config = config('tank'),
	center = center,
	boss = boss,
	me = { id = 1, x = 4, y = 0 },
	party_members = members,
	was_moving = false,
})
assert_equal(proposal.action, 'move', 'tank outside return radius should move')
assert_equal(proposal.goal.x, 0, 'tank goal x mismatch')
assert_equal(proposal.goal.y, 0, 'tank goal y mismatch')

proposal = formation.evaluate({
	config = config('dps'),
	center = center,
	boss = boss,
	me = { id = 2, x = 4, y = 0 },
	party_members = members,
	was_moving = false,
})
assert_equal(proposal.action, 'move', 'mispositioned DPS should move')
assert_true(math.abs(proposal.goal.x) < 0.0001, 'DPS flank goal x mismatch')
assert_true(math.abs(proposal.goal.y + 3) < 0.0001, 'DPS flank goal y mismatch')

proposal = formation.evaluate({
	config = config('dps'),
	center = center,
	boss = { id = 900, x = 5, y = 0 },
	me = { id = 2, x = 5, y = -3 },
	party_members = {
		{ id = 1, name = 'Tank', x = 6, y = 0 },
		{ id = 2, name = 'Dps', x = 5, y = -3 },
	},
	was_moving = false,
})
assert_equal(proposal.action, 'move', 'DPS on a displaced boss-relative flank must return toward arena center')
assert_equal(proposal.reason, 'FORMATION_DPS_FLANK', 'knockback recovery reason mismatch')
assert_true(math.abs(proposal.goal.x) < 0.0001, 'knockback recovery goal must remain arena-center anchored')
assert_true(math.abs(proposal.goal.y + 3) < 0.0001, 'knockback recovery goal must preserve the configured flank offset')

proposal = formation.evaluate({
	config = config('healer'),
	center = center,
	boss = boss,
	boss_target = members[1],
	me = { id = 3, x = -12, y = 0 },
	party_members = members,
	was_moving = false,
})
assert_equal(proposal.action, 'hold', 'safe healer position should hold')

proposal = formation.evaluate({
	config = config('healer'),
	center = center,
	boss = boss,
	boss_target = members[1],
	me = { id = 3, x = 12, y = 0 },
	party_members = members,
	was_moving = false,
})
assert_equal(proposal.action, 'move', 'healer inside tank cone should reposition')
assert_equal(proposal.reason, 'FORMATION_HEALER_REPOSITION', 'healer reposition reason mismatch')
local healer_goal_angle = math.abs(math.atan2(proposal.goal.y, proposal.goal.x))
assert_true(healer_goal_angle > math.rad(65), 'healer goal must clear the tank cone and safety margin')

local missing_tank_config = config('healer')
missing_tank_config.tank_name = 'MissingTank'
proposal = formation.evaluate({
	config = missing_tank_config,
	center = center,
	boss = boss,
	me = { id = 3, x = -12, y = 0 },
	party_members = members,
	was_moving = false,
})
assert_equal(proposal.action, 'error', 'missing tank must be an explicit error')
assert_equal(proposal.reason, 'TANK_MEMBER_UNRESOLVED', 'missing tank reason mismatch')

io.stdout:write('selftest_combat_formation: OK\n')
