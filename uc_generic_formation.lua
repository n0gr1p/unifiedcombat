local M = {}

local EPSILON = 0.000001
local MAX_CANDIDATES = 20000

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_array(value, name)
	require_table(value, name)
	local count = 0
	local maximum = 0
	for key in pairs(value) do
		if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then
			error(name .. ' must be a contiguous array')
		end
		count = count + 1
		if key > maximum then
			maximum = key
		end
	end
	if maximum ~= count then
		error(name .. ' must be a contiguous array')
	end
	return value
end

local function finite_number(value, name)
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		error(name .. ' must be a finite number')
	end
	return number
end

local function nonnegative_number(value, name)
	local number = finite_number(value, name)
	if number < 0 then
		error(name .. ' must be non-negative')
	end
	return number
end

local function positive_number(value, name)
	local number = finite_number(value, name)
	if number <= 0 then
		error(name .. ' must be a positive number')
	end
	return number
end

local function nonempty_string(value, name)
	if type(value) ~= 'string' or value == '' then
		error(name .. ' must be a non-empty string')
	end
	return value
end

local function point(value, name)
	require_table(value, name)
	return {
		x = finite_number(value.x, name .. '.x'),
		y = finite_number(value.y, name .. '.y'),
	}
end

local function copy_point(value)
	return { x = value.x, y = value.y }
end

local function distance_squared(left, right)
	local dx = left.x - right.x
	local dy = left.y - right.y
	return (dx * dx) + (dy * dy)
end

local function distance(left, right)
	return math.sqrt(distance_squared(left, right))
end

local function normalize_angle(radians)
	local two_pi = math.pi * 2
	while radians > math.pi do
		radians = radians - two_pi
	end
	while radians <= -math.pi do
		radians = radians + two_pi
	end
	return radians
end

local function direction(origin, target)
	local dx = target.x - origin.x
	local dy = target.y - origin.y
	local length = math.sqrt((dx * dx) + (dy * dy))
	if length <= EPSILON then
		return nil
	end
	return { x = dx / length, y = dy / length }
end

local function error_result(reason, detail)
	return {
		action = 'error',
		reason = reason,
		detail = detail,
	}
end

local function hold_result(reason, detail)
	return {
		action = 'hold',
		reason = reason,
		detail = detail,
	}
end

local function move_result(goal, detail)
	return {
		action = 'move',
		reason = 'FORMATION_REPOSITION',
		goal = copy_point(goal),
		detail = detail,
	}
end

local function find_member(members, wanted)
	local wanted_name = nonempty_string(wanted, 'formation member name')
	local wanted_key = wanted_name:lower()
	local match = nil
	for i = 1, #members do
		local member = require_table(members[i], ('ctx.party_members[%d]'):format(i))
		local member_name = tostring(member.name or '')
		if member_name:lower() == wanted_key then
			if match ~= nil then
				return nil, 'FORMATION_MEMBER_AMBIGUOUS:' .. wanted_name
			end
			match = member
		end
	end
	if match == nil then
		return nil, 'FORMATION_MEMBER_UNRESOLVED:' .. wanted_name
	end
	if tonumber(match.x) == nil or tonumber(match.y) == nil then
		return nil, 'FORMATION_MEMBER_POSITION_UNAVAILABLE:' .. wanted_name
	end
	return point(match, 'formation member ' .. wanted_name), nil
end

local function validate_placement(config)
	local placement = require_table(config.placement, 'config.placement')
	local mode = nonempty_string(placement.mode, 'config.placement.mode')
	if mode ~= 'radial_band' and mode ~= 'polar_band' then
		error('config.placement.mode must be radial_band or polar_band')
	end
	local anchor = nonempty_string(placement.anchor, 'config.placement.anchor')
	if anchor ~= 'boss' and anchor ~= 'encounter_origin' and anchor ~= 'member' then
		error('config.placement.anchor must be boss, encounter_origin, or member')
	end
	if anchor == 'member' then
		nonempty_string(placement.anchor_member, 'config.placement.anchor_member')
	end
	local minimum_radius = nonnegative_number(placement.minimum_radius, 'config.placement.minimum_radius')
	local maximum_radius = nonnegative_number(placement.maximum_radius, 'config.placement.maximum_radius')
	local preferred_radius = nonnegative_number(placement.preferred_radius, 'config.placement.preferred_radius')
	if maximum_radius < minimum_radius then
		error('config.placement.maximum_radius must be >= minimum_radius')
	end
	if preferred_radius < minimum_radius or preferred_radius > maximum_radius then
		error('config.placement.preferred_radius must be inside the radius band')
	end
	local radius_step = positive_number(placement.radius_step, 'config.placement.radius_step')
	local angle_step_deg = positive_number(placement.angle_step_deg, 'config.placement.angle_step_deg')
	if angle_step_deg > 360 then
		error('config.placement.angle_step_deg must be <= 360')
	end
	local validated = {
		mode = mode,
		anchor = anchor,
		anchor_member = placement.anchor_member,
		minimum_radius = minimum_radius,
		maximum_radius = maximum_radius,
		preferred_radius = preferred_radius,
		radius_step = radius_step,
		angle_step_deg = angle_step_deg,
	}
	if mode == 'polar_band' then
		local axis = require_table(placement.axis, 'config.placement.axis')
		if axis.type ~= 'boss_to_member' and axis.type ~= 'boss_heading' then
			error('config.placement.axis.type must be boss_to_member or boss_heading')
		end
		validated.axis = {
			type = axis.type,
		}
		if axis.type == 'boss_to_member' then
			validated.axis.member = nonempty_string(axis.member, 'config.placement.axis.member')
		end
		validated.preferred_angle_deg = finite_number(
			placement.preferred_angle_deg,
			'config.placement.preferred_angle_deg'
		)
		validated.allowed_angle_half_width_deg = nonnegative_number(
			placement.allowed_angle_half_width_deg,
			'config.placement.allowed_angle_half_width_deg'
		)
		if validated.allowed_angle_half_width_deg > 180 then
			error('config.placement.allowed_angle_half_width_deg must be <= 180')
		end
	end
	return validated
end

local function validate_hysteresis(config)
	local hysteresis = require_table(config.hysteresis, 'config.hysteresis')
	local start_distance = nonnegative_number(
		hysteresis.start_distance,
		'config.hysteresis.start_distance'
	)
	local stop_distance = nonnegative_number(
		hysteresis.stop_distance,
		'config.hysteresis.stop_distance'
	)
	if start_distance < stop_distance then
		error('config.hysteresis.start_distance must be >= stop_distance')
	end
	return {
		start_distance = start_distance,
		stop_distance = stop_distance,
	}
end

local function validate_constraints(config)
	local constraints = require_table(config.constraints, 'config.constraints')
	if type(constraints.avoid_encounter_hazards) ~= 'boolean' then
		error('config.constraints.avoid_encounter_hazards must be boolean')
	end
	local validated = {
		avoid_encounter_hazards = constraints.avoid_encounter_hazards,
		hazard_margin = nonnegative_number(
			constraints.hazard_margin,
			'config.constraints.hazard_margin'
		),
	}
	if constraints.safe_origin_radius ~= nil then
		validated.safe_origin_radius = positive_number(
			constraints.safe_origin_radius,
			'config.constraints.safe_origin_radius'
		)
	end
	if constraints.minimum_boss_distance ~= nil then
		validated.minimum_boss_distance = nonnegative_number(
			constraints.minimum_boss_distance,
			'config.constraints.minimum_boss_distance'
		)
	end
	if constraints.maximum_boss_distance ~= nil then
		validated.maximum_boss_distance = positive_number(
			constraints.maximum_boss_distance,
			'config.constraints.maximum_boss_distance'
		)
	end
	if validated.minimum_boss_distance ~= nil and validated.maximum_boss_distance ~= nil
		and validated.maximum_boss_distance < validated.minimum_boss_distance then
		error('config.constraints.maximum_boss_distance must be >= minimum_boss_distance')
	end
	if constraints.maximum_party_range ~= nil then
		validated.maximum_party_range = positive_number(
			constraints.maximum_party_range,
			'config.constraints.maximum_party_range'
		)
		validated.required_party_names = require_array(
			constraints.required_party_names,
			'config.constraints.required_party_names'
		)
		if #validated.required_party_names == 0 then
			error('config.constraints.required_party_names must not be empty when maximum_party_range is set')
		end
		for i = 1, #validated.required_party_names do
			nonempty_string(
				validated.required_party_names[i],
				('config.constraints.required_party_names[%d]'):format(i)
			)
		end
	elseif constraints.required_party_names ~= nil then
		error('config.constraints.maximum_party_range is required with required_party_names')
	end
	return validated
end

local function resolve_anchor(ctx, placement, members, boss, origin)
	if placement.anchor == 'boss' then
		return copy_point(boss), nil
	end
	if placement.anchor == 'encounter_origin' then
		if origin == nil then
			return nil, 'FORMATION_ENCOUNTER_ORIGIN_UNRESOLVED'
		end
		return copy_point(origin), nil
	end
	local member, reason = find_member(members, placement.anchor_member)
	if member == nil then
		return nil, reason
	end
	return member, nil
end

local function resolve_axis(placement, members, boss, boss_heading)
	if placement.mode ~= 'polar_band' then
		return nil, nil
	end
	if placement.axis.type == 'boss_heading' then
		local heading = tonumber(boss_heading)
		if heading == nil or heading ~= heading or heading == math.huge or heading == -math.huge then
			return nil, 'FORMATION_BOSS_HEADING_UNAVAILABLE'
		end
		return {
			x = math.cos(heading),
			y = -math.sin(heading),
		}, nil
	end
	local member, reason = find_member(members, placement.axis.member)
	if member == nil then
		return nil, reason
	end
	local vector = direction(boss, member)
	if vector == nil then
		return nil, 'FORMATION_AXIS_ZERO_VECTOR:' .. placement.axis.member
	end
	return vector, nil
end

local function resolve_required_members(constraints, members)
	local resolved = {}
	if constraints.maximum_party_range == nil then
		return resolved, nil
	end
	for i = 1, #constraints.required_party_names do
		local member, reason = find_member(members, constraints.required_party_names[i])
		if member == nil then
			return nil, reason
		end
		resolved[#resolved + 1] = {
			name = constraints.required_party_names[i],
			point = member,
		}
	end
	return resolved, nil
end

local function resolve_hazards(constraints, hazards)
	local resolved = {}
	if constraints.avoid_encounter_hazards ~= true then
		return resolved
	end
	for i = 1, #hazards do
		local hazard = require_table(hazards[i], ('ctx.encounter_hazards[%d]'):format(i))
		resolved[#resolved + 1] = {
			center = point(hazard.center, ('ctx.encounter_hazards[%d].center'):format(i)),
			avoid_radius = positive_number(
				hazard.avoid_radius,
				('ctx.encounter_hazards[%d].avoid_radius'):format(i)
			),
		}
	end
	return resolved
end

local function add_unique_number(values, value)
	for i = 1, #values do
		if math.abs(values[i] - value) <= EPSILON then
			return
		end
	end
	values[#values + 1] = value
end

local function sample_radii(placement)
	local radii = {}
	add_unique_number(radii, placement.preferred_radius)
	local radius = placement.minimum_radius
	while radius <= placement.maximum_radius + EPSILON do
		add_unique_number(radii, math.min(radius, placement.maximum_radius))
		if #radii > MAX_CANDIDATES then
			error('formation radius sampling exceeds candidate limit')
		end
		radius = radius + placement.radius_step
	end
	add_unique_number(radii, placement.maximum_radius)
	return radii
end

local function sample_angles(placement)
	local angles = {}
	if placement.mode == 'radial_band' then
		local angle = 0
		while angle < 360 - EPSILON do
			add_unique_number(angles, angle)
			if #angles > MAX_CANDIDATES then
				error('formation angle sampling exceeds candidate limit')
			end
			angle = angle + placement.angle_step_deg
		end
		return angles
	end
	local preferred = placement.preferred_angle_deg
	local half_width = placement.allowed_angle_half_width_deg
	add_unique_number(angles, preferred)
	local offset = placement.angle_step_deg
	while offset < half_width - EPSILON do
		add_unique_number(angles, preferred - offset)
		add_unique_number(angles, preferred + offset)
		if #angles > MAX_CANDIDATES then
			error('formation angle sampling exceeds candidate limit')
		end
		offset = offset + placement.angle_step_deg
	end
	if half_width > EPSILON then
		add_unique_number(angles, preferred - half_width)
		add_unique_number(angles, preferred + half_width)
	end
	return angles
end

local function enumerate_candidates(anchor, axis, placement)
	local radii = sample_radii(placement)
	local angles = sample_angles(placement)
	local axis_angle = axis and math.atan2(axis.y, axis.x) or 0
	local candidates = {}
	for radius_index = 1, #radii do
		local radius = radii[radius_index]
		if radius <= EPSILON then
			candidates[#candidates + 1] = {
				x = anchor.x,
				y = anchor.y,
				radius = 0,
				angle_deg = angles[1],
				index = #candidates + 1,
			}
		else
			for angle_index = 1, #angles do
				if #candidates >= MAX_CANDIDATES then
					error('formation candidate sampling exceeds limit')
				end
				local angle_deg = angles[angle_index]
				local radians = axis_angle + math.rad(angle_deg)
				candidates[#candidates + 1] = {
					x = anchor.x + (math.cos(radians) * radius),
					y = anchor.y + (math.sin(radians) * radius),
					radius = radius,
					angle_deg = angle_deg,
					index = #candidates + 1,
				}
			end
		end
	end
	if #candidates == 0 then
		error('formation configuration produced no candidates')
	end
	return candidates
end

local function placement_valid(candidate, anchor, axis, placement)
	local radius = distance(candidate, anchor)
	if radius < placement.minimum_radius - EPSILON or radius > placement.maximum_radius + EPSILON then
		return false, 'PLACEMENT_RADIUS'
	end
	if placement.mode ~= 'polar_band' or radius <= EPSILON then
		return true, 'VALID'
	end
	local candidate_direction = direction(anchor, candidate)
	local axis_angle = math.atan2(axis.y, axis.x)
	local candidate_angle = math.atan2(candidate_direction.y, candidate_direction.x)
	local relative = normalize_angle(candidate_angle - axis_angle)
	local preferred = math.rad(placement.preferred_angle_deg)
	local delta = math.abs(normalize_angle(relative - preferred))
	if delta > math.rad(placement.allowed_angle_half_width_deg) + EPSILON then
		return false, 'PLACEMENT_ANGLE'
	end
	return true, 'VALID'
end

local function constraints_valid(candidate, resolved)
	local constraints = resolved.constraints
	if constraints.safe_origin_radius ~= nil then
		if resolved.origin == nil then
			return false, 'SAFE_ORIGIN_UNRESOLVED'
		end
		if distance(candidate, resolved.origin) > constraints.safe_origin_radius + EPSILON then
			return false, 'SAFE_ORIGIN_RADIUS'
		end
	end
	local boss_distance = distance(candidate, resolved.boss)
	if constraints.minimum_boss_distance ~= nil
		and boss_distance < constraints.minimum_boss_distance - EPSILON then
		return false, 'MINIMUM_BOSS_DISTANCE'
	end
	if constraints.maximum_boss_distance ~= nil
		and boss_distance > constraints.maximum_boss_distance + EPSILON then
		return false, 'MAXIMUM_BOSS_DISTANCE'
	end
	for i = 1, #resolved.required_members do
		if distance(candidate, resolved.required_members[i].point) > constraints.maximum_party_range + EPSILON then
			return false, 'REQUIRED_PARTY_RANGE:' .. resolved.required_members[i].name
		end
	end
	for i = 1, #resolved.hazards do
		local hazard = resolved.hazards[i]
		if distance(candidate, hazard.center)
			< hazard.avoid_radius + constraints.hazard_margin then
			return false, 'ENCOUNTER_HAZARD:' .. tostring(i)
		end
	end
	return true, 'VALID'
end

local function candidate_score(candidate, me, placement)
	local angle_preference = 0
	if placement.mode == 'polar_band' then
		angle_preference = math.abs(normalize_angle(
			math.rad(candidate.angle_deg - placement.preferred_angle_deg)
		))
	end
	return {
		travel = distance_squared(candidate, me),
		radius_preference = math.abs(candidate.radius - placement.preferred_radius),
		angle_preference = angle_preference,
		index = candidate.index,
	}
end

local function score_less(left, right)
	if right == nil then
		return true
	end
	if math.abs(left.travel - right.travel) > EPSILON then
		return left.travel < right.travel
	end
	if math.abs(left.radius_preference - right.radius_preference) > EPSILON then
		return left.radius_preference < right.radius_preference
	end
	if math.abs(left.angle_preference - right.angle_preference) > EPSILON then
		return left.angle_preference < right.angle_preference
	end
	return left.index < right.index
end

local function diagnostic_base(placement, anchor, axis)
	return {
		mode = placement.mode,
		anchor_source = placement.anchor,
		resolved_anchor = copy_point(anchor),
		resolved_axis = axis and copy_point(axis) or nil,
	}
end

function M.evaluate(ctx)
	require_table(ctx, 'uc_generic_formation.evaluate ctx')
	local config = require_table(ctx.config, 'ctx.config')
	if type(config.enabled) ~= 'boolean' then
		error('ctx.config.enabled must be boolean')
	end
	if config.enabled ~= true then
		return hold_result('FORMATION_DISABLED', { enabled = false })
	end
	local me = point(ctx.me, 'ctx.me')
	local boss = point(ctx.boss, 'ctx.boss')
	local boss_heading = ctx.boss.facing
	local members = require_array(ctx.party_members, 'ctx.party_members')
	local hazards = require_array(ctx.encounter_hazards, 'ctx.encounter_hazards')
	if type(ctx.was_moving) ~= 'boolean' then
		error('ctx.was_moving must be boolean')
	end
	local origin = nil
	if ctx.encounter_origin ~= nil then
		origin = point(ctx.encounter_origin, 'ctx.encounter_origin')
	end
	local placement = validate_placement(config)
	local hysteresis = validate_hysteresis(config)
	local constraints = validate_constraints(config)
	local anchor, anchor_reason = resolve_anchor(ctx, placement, members, boss, origin)
	if anchor == nil then
		return error_result(anchor_reason)
	end
	local axis, axis_reason = resolve_axis(placement, members, boss, boss_heading)
	if placement.mode == 'polar_band' and axis == nil then
		return error_result(axis_reason)
	end
	local required_members, member_reason = resolve_required_members(constraints, members)
	if required_members == nil then
		return error_result(member_reason)
	end
	if constraints.safe_origin_radius ~= nil and origin == nil then
		return error_result('FORMATION_ENCOUNTER_ORIGIN_UNRESOLVED')
	end
	local resolved = {
		constraints = constraints,
		boss = boss,
		origin = origin,
		required_members = required_members,
		hazards = resolve_hazards(constraints, hazards),
	}
	local detail = diagnostic_base(placement, anchor, axis)
	local current_constraints_valid, current_constraint_reason = constraints_valid(me, resolved)
	local current_placement_valid, current_placement_reason = placement_valid(me, anchor, axis, placement)
	if current_constraints_valid and current_placement_valid then
		detail.current_position_valid = true
		detail.current_constraint = 'VALID'
		return hold_result('FORMATION_POSITION_VALID', detail)
	end

	local candidates = enumerate_candidates(anchor, axis, placement)
	local nearest_geometry = nil
	local nearest_geometry_distance_squared = nil
	local best = nil
	local best_score = nil
	local valid_count = 0
	local rejections = {}
	for i = 1, #candidates do
		local candidate = candidates[i]
		local geometry_distance = distance_squared(me, candidate)
		if nearest_geometry == nil or geometry_distance < nearest_geometry_distance_squared then
			nearest_geometry = candidate
			nearest_geometry_distance_squared = geometry_distance
		end
		local candidate_valid, rejection = constraints_valid(candidate, resolved)
		if candidate_valid then
			valid_count = valid_count + 1
			local score = candidate_score(candidate, me, placement)
			if score_less(score, best_score) then
				best = candidate
				best_score = score
			end
		else
			rejections[rejection] = (rejections[rejection] or 0) + 1
		end
	end

	detail.current_position_valid = false
	detail.failed_constraint = current_constraints_valid
		and current_placement_reason or current_constraint_reason
	detail.candidate_count = #candidates
	detail.valid_candidate_count = valid_count
	detail.rejection_counts = rejections
	if nearest_geometry ~= nil then
		detail.nearest_geometry_candidate = copy_point(nearest_geometry)
		detail.distance_to_geometry = math.sqrt(nearest_geometry_distance_squared)
	end
	if current_constraints_valid and nearest_geometry ~= nil then
		local tolerance = ctx.was_moving and hysteresis.stop_distance or hysteresis.start_distance
		local within_tolerance = detail.distance_to_geometry <= tolerance + EPSILON
		if not ctx.was_moving and hysteresis.start_distance > hysteresis.stop_distance then
			within_tolerance = detail.distance_to_geometry < tolerance - EPSILON
		end
		if within_tolerance then
			detail.hysteresis_tolerance = tolerance
			return hold_result('FORMATION_POSITION_HYSTERESIS', detail)
		end
	end
	if best == nil then
		return error_result('FORMATION_UNSATISFIED', detail)
	end
	detail.selected_candidate = copy_point(best)
	detail.selected_radius = best.radius
	detail.selected_angle_deg = best.angle_deg
	detail.travel_distance = math.sqrt(best_score.travel)
	return move_result(best, detail)
end

M.MAX_CANDIDATES = MAX_CANDIDATES

return M
