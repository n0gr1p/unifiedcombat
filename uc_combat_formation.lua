local geometry = require('uc_scheduler_geometry')

local M = {}

local function point(value, name)
	if type(value) ~= 'table' or tonumber(value.x) == nil or tonumber(value.y) == nil then
		error(name .. ' must contain numeric x and y')
	end
	return { x = tonumber(value.x), y = tonumber(value.y) }
end

local function positive_number(value, name)
	local number = tonumber(value)
	if number == nil or number <= 0 then
		error(name .. ' must be a positive number')
	end
	return number
end

local function distance(left, right)
	local dx = left.x - right.x
	local dy = left.y - right.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local function direction(origin, target)
	local dx = target.x - origin.x
	local dy = target.y - origin.y
	local length = math.sqrt((dx * dx) + (dy * dy))
	if length <= 0.0001 then
		return nil
	end
	return { x = dx / length, y = dy / length }
end

local function rotate(vector, radians)
	local cosine = math.cos(radians)
	local sine = math.sin(radians)
	return {
		x = (vector.x * cosine) - (vector.y * sine),
		y = (vector.x * sine) + (vector.y * cosine),
	}
end

local function projected(origin, vector, radius)
	return {
		x = origin.x + (vector.x * radius),
		y = origin.y + (vector.y * radius),
	}
end

local function move(goal, reason, detail)
	return {
		action = 'move',
		goal = goal,
		reason = reason,
		detail = detail,
	}
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

local function find_member_by_name(members, wanted)
	local wanted_key = tostring(wanted):lower()
	for i = 1, #members do
		local member = members[i]
		if tostring(member.name):lower() == wanted_key then
			return member
		end
	end
	return nil
end

local function evaluate_tank(ctx, config)
	local center = point(ctx.center, 'ctx.center')
	local me = point(ctx.me, 'ctx.me')
	local accept_radius = positive_number(config.tank.accept_radius, 'tank.accept_radius')
	local return_radius = positive_number(config.tank.return_radius, 'tank.return_radius')
	if return_radius <= accept_radius then
		return failure('TANK_RADIUS_ORDER_INVALID')
	end
	local center_distance = distance(me, center)
	if center_distance <= accept_radius then
		return hold('FORMATION_TANK_CENTERED', { distance = center_distance })
	end
	if ctx.was_moving == true or center_distance >= return_radius then
		return move(center, 'FORMATION_TANK_RETURN', { distance = center_distance })
	end
	return hold('FORMATION_TANK_HYSTERESIS', { distance = center_distance })
end

local function dps_goal(ctx, config, center, boss, tank)
	local boss_to_tank = direction(boss, tank)
	if boss_to_tank == nil then
		return nil, 'DPS_TANK_VECTOR_UNRESOLVED'
	end
	local angle = math.rad(tonumber(config.dps.flank_angle_deg))
	local radius = positive_number(config.dps.melee_radius, 'dps.melee_radius')
	return projected(center, rotate(boss_to_tank, -angle), radius), nil
end

local function evaluate_dps(ctx, config, members)
	local me = point(ctx.me, 'ctx.me')
	local center = point(ctx.center, 'ctx.center')
	local boss = point(ctx.boss, 'ctx.boss')
	local tank = find_member_by_name(members, config.tank_name)
	if tank == nil then
		return failure('TANK_MEMBER_UNRESOLVED')
	end
	tank = point(tank, 'tank member')
	local goal, goal_error = dps_goal(ctx, config, center, boss, tank)
	if goal == nil then
		return failure(goal_error)
	end
	local tolerance = positive_number(config.dps.position_tolerance, 'dps.position_tolerance')
	local goal_distance = distance(me, goal)
	if goal_distance <= tolerance then
		return hold('FORMATION_DPS_FLANK_OK', { distance = goal_distance, goal = goal })
	end
	return move(goal, 'FORMATION_DPS_FLANK', { distance = goal_distance })
end

local function candidate_in_cone(candidate, boss, axis_point, half_angle)
	local boss_to_candidate = direction(boss, candidate)
	local boss_to_axis = direction(boss, axis_point)
	if boss_to_candidate == nil or boss_to_axis == nil then
		return true
	end
	local candidate_angle = math.atan2(boss_to_candidate.y, boss_to_candidate.x)
	local axis_angle = math.atan2(boss_to_axis.y, boss_to_axis.x)
	local delta = math.abs(geometry.normalize_angle_rad(candidate_angle - axis_angle))
	return delta <= half_angle
end

local function required_members(config, members, exclude_id)
	if type(config.required_party_names) ~= 'table' then
		return nil, 'REQUIRED_PARTY_NAMES_INVALID'
	end
	if #config.required_party_names == 0 then
		local required = {}
		for i = 1, #members do
			if tonumber(members[i].id) ~= exclude_id then
				required[#required + 1] = members[i]
			end
		end
		return required, nil
	end
	local required = {}
	for i = 1, #config.required_party_names do
		local name = config.required_party_names[i]
		local member = find_member_by_name(members, name)
		if member == nil then
			return nil, 'REQUIRED_PARTY_MEMBER_MISSING:' .. tostring(name)
		end
		if tonumber(member.id) ~= exclude_id then
			required[#required + 1] = member
		end
	end
	return required, nil
end

local function healer_axes(ctx, config, boss, tank, dps_point)
	local axes = { tank, dps_point }
	if type(ctx.boss_target) == 'table' and tonumber(ctx.boss_target.x) ~= nil and tonumber(ctx.boss_target.y) ~= nil then
		local target = point(ctx.boss_target, 'ctx.boss_target')
		if distance(boss, target) > 0.1 then
			axes[#axes + 1] = target
		end
	end
	return axes
end

local function healer_candidate_valid(candidate, center, boss, axes, required, config)
	local safe_radius = positive_number(config.safe_radius, 'safe_radius')
	if distance(candidate, center) > safe_radius then
		return false, 'OUTSIDE_SAFE_RADIUS'
	end
	local minimum_boss_distance = positive_number(config.healer.minimum_boss_distance, 'healer.minimum_boss_distance')
	if distance(candidate, boss) < minimum_boss_distance then
		return false, 'TOO_CLOSE_TO_BOSS'
	end
	local cone_degrees = positive_number(config.healer.cone_half_angle_deg, 'healer.cone_half_angle_deg')
	local margin_degrees = positive_number(config.healer.cone_safety_margin_deg, 'healer.cone_safety_margin_deg')
	local half_angle = math.rad(cone_degrees + margin_degrees)
	for i = 1, #axes do
		if candidate_in_cone(candidate, boss, axes[i], half_angle) then
			return false, 'INSIDE_THREAT_CONE'
		end
	end
	local maximum_party_range = positive_number(config.healer.maximum_party_range, 'healer.maximum_party_range')
	for i = 1, #required do
		if distance(candidate, required[i]) > maximum_party_range then
			return false, 'PARTY_RANGE_EXCEEDED'
		end
	end
	return true, 'VALID'
end

local function evaluate_healer(ctx, config, members)
	local me = point(ctx.me, 'ctx.me')
	local center = point(ctx.center, 'ctx.center')
	local boss = point(ctx.boss, 'ctx.boss')
	local tank_member = find_member_by_name(members, config.tank_name)
	if tank_member == nil then
		return failure('TANK_MEMBER_UNRESOLVED')
	end
	local tank = point(tank_member, 'tank member')
	local dps_point, dps_error = dps_goal(ctx, config, center, boss, tank)
	if dps_point == nil then
		return failure(dps_error)
	end
	local required, required_error = required_members(config, members, tonumber(ctx.me.id))
	if required == nil then
		return failure(required_error)
	end
	for i = 1, #required do
		required[i] = point(required[i], 'required party member')
	end
	local axes = healer_axes(ctx, config, boss, tank, dps_point)
	local current_valid, current_reason = healer_candidate_valid(me, center, boss, axes, required, config)
	if current_valid then
		return hold('FORMATION_HEALER_POSITION_OK', { constraint = current_reason })
	end
	local preferred_radius = positive_number(config.healer.preferred_radius, 'healer.preferred_radius')
	local safe_radius = positive_number(config.safe_radius, 'safe_radius')
	if preferred_radius >= safe_radius then
		return failure('HEALER_RADIUS_OUTSIDE_SAFE_ARENA')
	end
	local step_degrees = positive_number(config.healer.sample_step_deg, 'healer.sample_step_deg')
	if step_degrees > 90 then
		return failure('HEALER_SAMPLE_STEP_TOO_LARGE')
	end
	local best = nil
	local best_distance = nil
	local angle = 0
	while angle < 360 do
		local radians = math.rad(angle)
		local candidate = {
			x = center.x + (math.cos(radians) * preferred_radius),
			y = center.y + (math.sin(radians) * preferred_radius),
		}
		local valid = healer_candidate_valid(candidate, center, boss, axes, required, config)
		if valid then
			local travel = distance(me, candidate)
			if best == nil or travel < best_distance then
				best = candidate
				best_distance = travel
			end
		end
		angle = angle + step_degrees
	end
	if best == nil then
		return failure('HEALER_POSITION_UNSATISFIABLE:' .. current_reason)
	end
	return move(best, 'FORMATION_HEALER_REPOSITION', {
		constraint = current_reason,
		distance = best_distance,
	})
end

function M.evaluate(ctx)
	if type(ctx) ~= 'table' then
		error('uc_combat_formation.evaluate requires ctx')
	end
	if type(ctx.config) ~= 'table' then
		error('ctx.config must be a table')
	end
	if type(ctx.party_members) ~= 'table' then
		error('ctx.party_members must be a table')
	end
	local config = ctx.config
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
		return evaluate_dps(ctx, config, ctx.party_members)
	end
	if role == 'healer' then
		return evaluate_healer(ctx, config, ctx.party_members)
	end
	return failure('FORMATION_ROLE_INVALID')
end

return M
