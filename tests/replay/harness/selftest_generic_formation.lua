local formation = require('uc_generic_formation')

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

local function assert_near(actual, expected, tolerance, message)
	if math.abs(actual - expected) > tolerance then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function radial_config()
	return {
		enabled = true,
		placement = {
			mode = 'radial_band',
			anchor = 'encounter_origin',
			preferred_radius = 2.0,
			minimum_radius = 1.0,
			maximum_radius = 3.0,
			radius_step = 1.0,
			angle_step_deg = 90.0,
		},
		hysteresis = {
			start_distance = 0.5,
			stop_distance = 0.1,
		},
		constraints = {
			avoid_encounter_hazards = false,
			hazard_margin = 0,
		},
	}
end

local function context(config, me)
	return {
		config = config,
		me = me or { id = 1, name = 'Me', x = 2, y = 0 },
		boss = { id = 900, name = 'Boss', x = 0, y = 0 },
		encounter_origin = { x = 0, y = 0 },
		party_members = {
			{ id = 1, name = 'Me', x = 2, y = 0 },
			{ id = 2, name = 'Reference', x = 4, y = 0 },
		},
		encounter_hazards = {},
		was_moving = false,
	}
end

local proposal = formation.evaluate(context(radial_config()))
assert_equal(proposal.action, 'hold', 'valid radial position must hold')
assert_equal(proposal.reason, 'FORMATION_POSITION_VALID', 'valid radial reason mismatch')

proposal = formation.evaluate(context(radial_config(), { id = 1, name = 'Me', x = 5, y = 0 }))
assert_equal(proposal.action, 'move', 'invalid radial position must move')
assert_near(proposal.goal.x, 3, 0.0001, 'nearest radial goal x mismatch')
assert_near(proposal.goal.y, 0, 0.0001, 'nearest radial goal y mismatch')

proposal = formation.evaluate(context(radial_config(), { id = 1, name = 'Me', x = 3.4, y = 0 }))
assert_equal(proposal.action, 'hold', 'stationary position inside start hysteresis must hold')
assert_equal(proposal.reason, 'FORMATION_POSITION_HYSTERESIS', 'start hysteresis reason mismatch')

local moving_ctx = context(radial_config(), { id = 1, name = 'Me', x = 3.4, y = 0 })
moving_ctx.was_moving = true
proposal = formation.evaluate(moving_ctx)
assert_equal(proposal.action, 'move', 'moving position outside stop hysteresis must keep correcting')

local polar = radial_config()
polar.placement = {
	mode = 'polar_band',
	anchor = 'boss',
	axis = {
		type = 'boss_to_member',
		member = 'Reference',
	},
	preferred_radius = 3.0,
	minimum_radius = 2.0,
	maximum_radius = 4.0,
	preferred_angle_deg = 180.0,
	allowed_angle_half_width_deg = 45.0,
	radius_step = 1.0,
	angle_step_deg = 45.0,
}
proposal = formation.evaluate(context(polar, { id = 1, name = 'Me', x = -3, y = 0 }))
assert_equal(proposal.action, 'hold', 'valid polar position must hold')

proposal = formation.evaluate(context(polar, { id = 1, name = 'Me', x = 0, y = 3 }))
assert_equal(proposal.action, 'move', 'position outside polar arc must move')
assert_true(proposal.detail.selected_angle_deg >= 135, 'polar candidate below allowed arc')
assert_true(proposal.detail.selected_angle_deg <= 225, 'polar candidate above allowed arc')
assert_true(proposal.detail.selected_radius >= 2, 'polar candidate below radius band')
assert_true(proposal.detail.selected_radius <= 4, 'polar candidate above radius band')

local boss_heading = radial_config()
boss_heading.placement = {
	mode = 'polar_band',
	anchor = 'boss',
	axis = {
		type = 'boss_heading',
	},
	preferred_radius = 12.0,
	minimum_radius = 10.0,
	maximum_radius = 14.0,
	preferred_angle_deg = 180.0,
	allowed_angle_half_width_deg = 130.0,
	radius_step = 1.0,
	angle_step_deg = 10.0,
}
local boss_heading_ctx = context(boss_heading, { id = 1, name = 'Me', x = -12, y = 0 })
boss_heading_ctx.boss.facing = 0
proposal = formation.evaluate(boss_heading_ctx)
assert_equal(proposal.action, 'hold', 'ranged position behind boss heading must hold')
assert_near(proposal.detail.resolved_axis.x, 1, 0.0001, 'boss heading axis x mismatch')
assert_near(proposal.detail.resolved_axis.y, 0, 0.0001, 'boss heading axis y mismatch')

boss_heading_ctx.me = { id = 1, name = 'Me', x = 12, y = 0 }
proposal = formation.evaluate(boss_heading_ctx)
assert_equal(proposal.action, 'move', 'ranged position inside boss front cone must move')
assert_true(
	math.abs(math.atan2(proposal.goal.y, proposal.goal.x)) >= math.rad(50) - 0.0001,
	'boss heading formation must select a point outside the configured front cone'
)

boss_heading_ctx.boss.facing = math.pi / 2
boss_heading_ctx.me = { id = 1, name = 'Me', x = 0, y = 12 }
proposal = formation.evaluate(boss_heading_ctx)
assert_equal(proposal.action, 'hold', 'boss heading axis must rotate with live boss facing')
assert_near(proposal.detail.resolved_axis.x, 0, 0.0001, 'quarter-turn boss heading axis x mismatch')
assert_near(proposal.detail.resolved_axis.y, -1, 0.0001, 'quarter-turn boss heading axis y mismatch')

boss_heading_ctx.me = { id = 1, name = 'Me', x = 0, y = -12 }
proposal = formation.evaluate(boss_heading_ctx)
assert_equal(proposal.action, 'move', 'Windower-facing front position must move after a quarter turn')

boss_heading_ctx.boss.facing = nil
proposal = formation.evaluate(boss_heading_ctx)
assert_equal(proposal.action, 'error', 'missing boss heading must fail closed')
assert_equal(proposal.reason, 'FORMATION_BOSS_HEADING_UNAVAILABLE', 'missing boss heading reason mismatch')

local missing_axis = context(polar)
missing_axis.party_members = {
	{ id = 1, name = 'Me', x = 2, y = 0 },
}
proposal = formation.evaluate(missing_axis)
assert_equal(proposal.action, 'error', 'missing axis member must error')
assert_equal(proposal.reason, 'FORMATION_MEMBER_UNRESOLVED:Reference', 'missing axis reason mismatch')

local member_anchor = radial_config()
member_anchor.placement.anchor = 'member'
member_anchor.placement.anchor_member = 'Missing'
proposal = formation.evaluate(context(member_anchor))
assert_equal(proposal.action, 'error', 'missing anchor member must error')
assert_equal(proposal.reason, 'FORMATION_MEMBER_UNRESOLVED:Missing', 'missing anchor reason mismatch')

local resolved_member_anchor = radial_config()
resolved_member_anchor.placement.anchor = 'member'
resolved_member_anchor.placement.anchor_member = 'Reference'
proposal = formation.evaluate(context(
	resolved_member_anchor,
	{ id = 1, name = 'Me', x = 2, y = 0 }
))
assert_equal(proposal.action, 'hold', 'resolved member anchor should evaluate normally')

local zero_axis = context(polar)
zero_axis.party_members[2].x = zero_axis.boss.x
zero_axis.party_members[2].y = zero_axis.boss.y
proposal = formation.evaluate(zero_axis)
assert_equal(proposal.action, 'error', 'zero-length axis must error')
assert_equal(proposal.reason, 'FORMATION_AXIS_ZERO_VECTOR:Reference', 'zero axis reason mismatch')

local safe_origin = radial_config()
safe_origin.placement.anchor = 'boss'
safe_origin.constraints.safe_origin_radius = 5
local missing_origin = context(safe_origin)
missing_origin.encounter_origin = nil
proposal = formation.evaluate(missing_origin)
assert_equal(proposal.action, 'error', 'missing constrained origin must error')
assert_equal(proposal.reason, 'FORMATION_ENCOUNTER_ORIGIN_UNRESOLVED', 'missing origin reason mismatch')

local party_range = radial_config()
party_range.constraints.maximum_party_range = 6
party_range.constraints.required_party_names = { 'Missing' }
proposal = formation.evaluate(context(party_range))
assert_equal(proposal.action, 'error', 'missing required party member must error')
assert_equal(proposal.reason, 'FORMATION_MEMBER_UNRESOLVED:Missing', 'required member reason mismatch')

local origin_bound = radial_config()
origin_bound.placement.anchor = 'boss'
origin_bound.placement.preferred_radius = 2
origin_bound.placement.minimum_radius = 2
origin_bound.placement.maximum_radius = 2
origin_bound.constraints.safe_origin_radius = 1
proposal = formation.evaluate(context(origin_bound))
assert_equal(proposal.action, 'error', 'origin radius must reject all out-of-bound candidates')
assert_equal(proposal.reason, 'FORMATION_UNSATISFIED', 'origin radius unsatisfied reason mismatch')
assert_true(
	proposal.detail.rejection_counts.SAFE_ORIGIN_RADIUS ~= nil,
	'origin radius rejection diagnostic missing'
)

local boss_bound = radial_config()
boss_bound.placement.anchor = 'boss'
boss_bound.placement.preferred_radius = 2
boss_bound.placement.minimum_radius = 2
boss_bound.placement.maximum_radius = 2
boss_bound.constraints.minimum_boss_distance = 3
boss_bound.constraints.maximum_boss_distance = 4
proposal = formation.evaluate(context(boss_bound))
assert_equal(proposal.action, 'error', 'boss distance band must reject invalid candidates')
assert_true(
	proposal.detail.rejection_counts.MINIMUM_BOSS_DISTANCE ~= nil,
	'boss distance rejection diagnostic missing'
)

local required_range = radial_config()
required_range.placement.preferred_radius = 2
required_range.placement.minimum_radius = 2
required_range.placement.maximum_radius = 2
required_range.constraints.maximum_party_range = 2
required_range.constraints.required_party_names = { 'Reference' }
proposal = formation.evaluate(context(
	required_range,
	{ id = 1, name = 'Me', x = 0, y = 2 }
))
assert_equal(proposal.action, 'move', 'required-party range should select the legal side of the ring')
assert_near(proposal.goal.x, 2, 0.0001, 'required-party range selected x mismatch')
assert_near(proposal.goal.y, 0, 0.0001, 'required-party range selected y mismatch')

local hazard_config = radial_config()
hazard_config.placement.preferred_radius = 2
hazard_config.placement.minimum_radius = 2
hazard_config.placement.maximum_radius = 2
hazard_config.constraints.avoid_encounter_hazards = true
hazard_config.constraints.hazard_margin = 0.25
local hazard_ctx = context(hazard_config)
hazard_ctx.encounter_hazards = {
	{ center = { x = 2, y = 0 }, avoid_radius = 0.5 },
}
proposal = formation.evaluate(hazard_ctx)
assert_equal(proposal.action, 'move', 'hazard-intersecting current position must move')
assert_near(proposal.goal.x, 0, 0.0001, 'deterministic hazard goal x mismatch')
assert_near(proposal.goal.y, 2, 0.0001, 'deterministic hazard goal y mismatch')
local repeated = formation.evaluate(hazard_ctx)
assert_near(repeated.goal.x, proposal.goal.x, 0.000001, 'candidate x must be deterministic')
assert_near(repeated.goal.y, proposal.goal.y, 0.000001, 'candidate y must be deterministic')

local hazard_off = radial_config()
hazard_off.placement.preferred_radius = 2
hazard_off.placement.minimum_radius = 2
hazard_off.placement.maximum_radius = 2
local hazard_off_ctx = context(hazard_off)
hazard_off_ctx.encounter_hazards = hazard_ctx.encounter_hazards
proposal = formation.evaluate(hazard_off_ctx)
assert_equal(proposal.action, 'hold', 'explicitly disabled hazard avoidance must not reject position')

local unsatisfied = radial_config()
unsatisfied.constraints.avoid_encounter_hazards = true
unsatisfied.constraints.hazard_margin = 0
local unsatisfied_ctx = context(unsatisfied)
unsatisfied_ctx.encounter_hazards = {
	{ center = { x = 0, y = 0 }, avoid_radius = 10 },
}
proposal = formation.evaluate(unsatisfied_ctx)
assert_equal(proposal.action, 'error', 'unsatisfied geometry must error')
assert_equal(proposal.reason, 'FORMATION_UNSATISFIED', 'unsatisfied reason mismatch')
assert_equal(proposal.goal, nil, 'unsatisfied geometry must not guess a goal')

io.stdout:write('selftest_generic_formation: OK\n')
