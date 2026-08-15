local generic_formation = require('uc_generic_formation')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function positive_number(value, name)
	local number = tonumber(value)
	if number == nil or number <= 0 then
		error(name .. ' must be a positive number')
	end
	return number
end

local function point(value, name)
	if type(value) ~= 'table' or tonumber(value.x) == nil or tonumber(value.y) == nil then
		error(name .. ' must contain numeric x and y')
	end
	return { x = tonumber(value.x), y = tonumber(value.y) }
end

local function distance(left, right)
	local dx = left.x - right.x
	local dy = left.y - right.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local function hold(reason, detail)
	return {
		action = 'hold',
		reason = reason,
		detail = detail,
	}
end

local function failure(reason)
	return {
		action = 'error',
		reason = reason,
	}
end

local function generic_context(ctx, config)
	return {
		config = config,
		me = ctx.me,
		boss = ctx.boss,
		encounter_origin = ctx.center,
		party_members = ctx.party_members,
		encounter_hazards = {},
		was_moving = ctx.was_moving == true,
	}
end

local function no_constraints()
	return {
		avoid_encounter_hazards = false,
		hazard_margin = 0,
	}
end

local function evaluate_tank(ctx, config)
	local center = point(ctx.center, 'ctx.center')
	local me = point(ctx.me, 'ctx.me')
	local accept_radius = positive_number(config.tank.accept_radius, 'tank.accept_radius')
	local return_radius = positive_number(config.tank.return_radius, 'tank.return_radius')
	if return_radius <= accept_radius then
		return failure('TANK_RADIUS_ORDER_INVALID')
	end
	local result = generic_formation.evaluate(generic_context(ctx, {
		enabled = true,
		placement = {
			mode = 'radial_band',
			anchor = 'encounter_origin',
			preferred_radius = 0,
			minimum_radius = 0,
			maximum_radius = 0,
			radius_step = 1,
			angle_step_deg = 360,
		},
		hysteresis = {
			start_distance = return_radius,
			stop_distance = accept_radius,
		},
		constraints = no_constraints(),
	}))
	if result.action == 'error' then
		return result
	end
	local center_distance = distance(me, center)
	if result.action == 'hold' then
		if center_distance <= accept_radius then
			return hold('FORMATION_TANK_CENTERED', { distance = center_distance })
		end
		return hold('FORMATION_TANK_HYSTERESIS', { distance = center_distance })
	end
	return {
		action = 'move',
		goal = center,
		reason = 'FORMATION_TANK_RETURN',
		detail = { distance = center_distance },
	}
end

local function starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function evaluate_dps(ctx, config)
	local radius = positive_number(config.dps.melee_radius, 'dps.melee_radius')
	local tolerance = positive_number(config.dps.position_tolerance, 'dps.position_tolerance')
	local flank_angle = tonumber(config.dps.flank_angle_deg)
	if flank_angle == nil then
		error('dps.flank_angle_deg must be numeric')
	end
	local result = generic_formation.evaluate(generic_context(ctx, {
		enabled = true,
		placement = {
			mode = 'polar_band',
			anchor = 'encounter_origin',
			axis = {
				type = 'boss_to_member',
				member = tostring(config.tank_name or ''),
			},
			preferred_radius = radius,
			minimum_radius = radius,
			maximum_radius = radius,
			preferred_angle_deg = -flank_angle,
			allowed_angle_half_width_deg = 0,
			radius_step = 1,
			angle_step_deg = 1,
		},
		hysteresis = {
			start_distance = tolerance,
			stop_distance = tolerance,
		},
		constraints = no_constraints(),
	}))
	if result.action == 'error' then
		local reason = tostring(result.reason or '')
		if starts_with(reason, 'FORMATION_MEMBER_UNRESOLVED:')
			or starts_with(reason, 'FORMATION_MEMBER_AMBIGUOUS:')
			or starts_with(reason, 'FORMATION_MEMBER_POSITION_UNAVAILABLE:') then
			return failure('TANK_MEMBER_UNRESOLVED')
		end
		if starts_with(reason, 'FORMATION_AXIS_ZERO_VECTOR:') then
			return failure('DPS_TANK_VECTOR_UNRESOLVED')
		end
		return result
	end
	local detail = result.detail or {}
	local anchor = point(detail.resolved_anchor, 'generic result resolved_anchor')
	local axis = point(detail.resolved_axis, 'generic result resolved_axis')
	local radians = math.rad(-flank_angle)
	local cosine = math.cos(radians)
	local sine = math.sin(radians)
	local rotated = {
		x = (axis.x * cosine) - (axis.y * sine),
		y = (axis.x * sine) + (axis.y * cosine),
	}
	local goal = {
		x = anchor.x + (rotated.x * radius),
		y = anchor.y + (rotated.y * radius),
	}
	local goal_distance = distance(point(ctx.me, 'ctx.me'), goal)
	if result.action == 'hold' then
		return hold('FORMATION_DPS_FLANK_OK', {
			distance = goal_distance,
			goal = goal,
		})
	end
	return {
		action = 'move',
		goal = goal,
		reason = 'FORMATION_DPS_FLANK',
		detail = { distance = goal_distance },
	}
end

function M.evaluate(ctx, deps)
	ctx = require_table(ctx, 'uc_lilith_formation_adapter ctx')
	deps = require_table(deps, 'uc_lilith_formation_adapter deps')
	if type(deps.evaluate_healer) ~= 'function' then
		error('uc_lilith_formation_adapter deps.evaluate_healer must be a function')
	end
	local config = require_table(ctx.config, 'ctx.config')
	if type(ctx.party_members) ~= 'table' then
		error('ctx.party_members must be a table')
	end
	if config.enabled ~= true then
		return hold('FORMATION_DISABLED')
	end
	if config.encounter ~= 'lilith_easy' then
		return failure('UNSUPPORTED_ENCOUNTER')
	end
	local role = tostring(config.role)
	if role == 'disabled' then
		return hold('FORMATION_ROLE_DISABLED')
	end
	if role == 'tank' then
		return evaluate_tank(ctx, config)
	end
	if role == 'dps' then
		return evaluate_dps(ctx, config)
	end
	if role == 'healer' then
		return deps.evaluate_healer(ctx, config, ctx.party_members)
	end
	return failure('FORMATION_ROLE_INVALID')
end

return M
