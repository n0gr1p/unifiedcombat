local M = {}

local ARRIVAL_YALMS = 0.45
local SETTLE_SECONDS = 0.35
local STALL_SECONDS = 2.0
local MAX_MOVE_SECONDS = 8.0
local PROGRESS_YALMS = 0.25
local GEOMETRY_EPSILON = 0.0001
local URGENT_PARTIAL_THRESHOLD = 0.90

local state = {
	phase = 'idle',
	reason = 'idle',
	target_x = nil,
	target_y = nil,
	coverage_count = 0,
	recipient_count = 0,
	full_coverage = false,
	recipient_ids = {},
	geometry_signature = '',
	started_at = 0,
	settle_until = 0,
	last_progress_at = 0,
	last_progress_distance = nil,
}

local function finite_number(value)
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	return number
end

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function point(value, name)
	require_table(value, name)
	local x = finite_number(value.x)
	local y = finite_number(value.y)
	if x == nil or y == nil then
		error(name .. ' requires finite x and y coordinates')
	end
	return { x = x, y = y }
end

local function distance(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function copy_ids(ids)
	local out = {}
	for i = 1, #(ids or {}) do
		out[i] = ids[i]
	end
	return out
end

local function ignored_names_set(names)
	local out = {}
	for i = 1, #(names or {}) do
		local name = tostring(names[i] or ''):lower()
		if name ~= '' then
			out[name] = true
		end
	end
	return out
end

local function eligible_recipients(members, ignore_names)
	local ignored = ignored_names_set(ignore_names)
	local recipients = {}
	for i = 1, #members do
		local member = require_table(members[i], ('party_members[%d]'):format(i))
		local id = tonumber(member.id) or 0
		local name = tostring(member.name or '')
		local eligible = member.is_self ~= true
			and id > 0
			and name ~= ''
			and (tonumber(member.hpp) or 0) > 0
			and member.is_npc ~= true
			and tonumber(member.spawn_type) ~= 14
			and ignored[name:lower()] ~= true
		if eligible then
			local x = finite_number(member.x)
			local y = finite_number(member.y)
			if x == nil or y == nil then
				return nil, 'BRD_REPOSITION_PARTY_GEOMETRY_UNAVAILABLE:' .. name
			end
			recipients[#recipients + 1] = {
				id = id,
				name = name,
				x = x,
				y = y,
			}
		end
	end
	table.sort(recipients, function(a, b)
		if a.id ~= b.id then
			return a.id < b.id
		end
		return a.name < b.name
	end)
	return recipients, ''
end

local function recipient_geometry_signature(recipients, radius, camp_anchor, camp_leash_yalms)
	local parts = {}
	for i = 1, #recipients do
		local recipient = recipients[i]
		parts[#parts + 1] = ('%d:%.1f:%.1f'):format(recipient.id, recipient.x, recipient.y)
	end
	parts[#parts + 1] = ('radius:%.2f'):format(radius)
	if camp_anchor ~= nil then
		parts[#parts + 1] = ('camp:%.1f:%.1f:%.2f'):format(camp_anchor.x, camp_anchor.y, camp_leash_yalms)
	else
		parts[#parts + 1] = 'camp:none'
	end
	return table.concat(parts, '|')
end

local function candidate_key(candidate)
	return ('%.4f:%.4f'):format(candidate.x, candidate.y)
end

local function add_candidate(candidates, seen, x, y)
	x = finite_number(x)
	y = finite_number(y)
	if x == nil or y == nil then
		error('Bard positioning candidate requires finite coordinates')
	end
	local candidate = { x = x, y = y }
	local key = candidate_key(candidate)
	if seen[key] ~= true then
		seen[key] = true
		candidates[#candidates + 1] = candidate
	end
end

local function add_subset_centroids(candidates, seen, recipients)
	local count = #recipients
	local subset_count = math.pow(2, count)
	for mask = 1, subset_count - 1 do
		local x = 0
		local y = 0
		local included = 0
		for index = 1, count do
			local bit = math.pow(2, index - 1)
			if math.floor(mask / bit) % 2 == 1 then
				x = x + recipients[index].x
				y = y + recipients[index].y
				included = included + 1
			end
		end
		add_candidate(candidates, seen, x / included, y / included)
	end
end

local function add_circle_intersections(candidates, seen, recipients, radius)
	for first = 1, #recipients - 1 do
		for second = first + 1, #recipients do
			local a = recipients[first]
			local b = recipients[second]
			local dx = b.x - a.x
			local dy = b.y - a.y
			local separation = math.sqrt(dx * dx + dy * dy)
			if separation > GEOMETRY_EPSILON and separation <= radius * 2 + GEOMETRY_EPSILON then
				local midpoint_x = (a.x + b.x) / 2
				local midpoint_y = (a.y + b.y) / 2
				local half = separation / 2
				local height_sq = radius * radius - half * half
				if height_sq < 0 and height_sq > -GEOMETRY_EPSILON then
					height_sq = 0
				end
				if height_sq >= 0 then
					local height = math.sqrt(height_sq)
					local perpendicular_x = -dy / separation
					local perpendicular_y = dx / separation
					add_candidate(candidates, seen, midpoint_x + perpendicular_x * height, midpoint_y + perpendicular_y * height)
					add_candidate(candidates, seen, midpoint_x - perpendicular_x * height, midpoint_y - perpendicular_y * height)
				end
			end
		end
	end
end

local function add_camp_circle_intersections(candidates, seen, recipients, radius, camp_anchor, camp_leash_yalms)
	if camp_anchor == nil then
		return
	end
	for i = 1, #recipients do
		local recipient = recipients[i]
		local dx = camp_anchor.x - recipient.x
		local dy = camp_anchor.y - recipient.y
		local separation = math.sqrt(dx * dx + dy * dy)
		local minimum_separation = math.abs(radius - camp_leash_yalms)
		local maximum_separation = radius + camp_leash_yalms
		if separation > GEOMETRY_EPSILON
			and separation >= minimum_separation - GEOMETRY_EPSILON
			and separation <= maximum_separation + GEOMETRY_EPSILON then
			local along = (radius * radius - camp_leash_yalms * camp_leash_yalms + separation * separation)
				/ (2 * separation)
			local height_sq = radius * radius - along * along
			if height_sq < 0 and height_sq > -GEOMETRY_EPSILON then
				height_sq = 0
			end
			if height_sq >= 0 then
				local base_x = recipient.x + dx * along / separation
				local base_y = recipient.y + dy * along / separation
				local height = math.sqrt(height_sq)
				local perpendicular_x = -dy / separation
				local perpendicular_y = dx / separation
				add_candidate(candidates, seen, base_x + perpendicular_x * height, base_y + perpendicular_y * height)
				add_candidate(candidates, seen, base_x - perpendicular_x * height, base_y - perpendicular_y * height)
			end
		end
	end
end

local function coverage(candidate, recipients, radius)
	local ids = {}
	local maximum_distance = 0
	for i = 1, #recipients do
		local recipient = recipients[i]
		local recipient_distance = distance(candidate, recipient)
		if recipient_distance <= radius + GEOMETRY_EPSILON then
			ids[#ids + 1] = recipient.id
			if recipient_distance > maximum_distance then
				maximum_distance = recipient_distance
			end
		end
	end
	return ids, radius - maximum_distance
end

local function candidate_is_camp_viable(candidate, camp_anchor, camp_leash_yalms)
	if camp_anchor == nil then
		return true, 0
	end
	local camp_distance = distance(candidate, camp_anchor)
	return camp_distance <= camp_leash_yalms + GEOMETRY_EPSILON, camp_distance
end

local function candidate_better(candidate, best)
	if best == nil then
		return true
	end
	if candidate.coverage_count ~= best.coverage_count then
		return candidate.coverage_count > best.coverage_count
	end
	if math.abs(candidate.move_distance - best.move_distance) > GEOMETRY_EPSILON then
		return candidate.move_distance < best.move_distance
	end
	if math.abs(candidate.clearance - best.clearance) > GEOMETRY_EPSILON then
		return candidate.clearance > best.clearance
	end
	if math.abs(candidate.camp_distance - best.camp_distance) > GEOMETRY_EPSILON then
		return candidate.camp_distance < best.camp_distance
	end
	if math.abs(candidate.x - best.x) > GEOMETRY_EPSILON then
		return candidate.x < best.x
	end
	return candidate.y < best.y
end

function M.select_position(opts)
	opts = require_table(opts, 'opts')
	local me = point(opts.me, 'opts.me')
	local radius = finite_number(opts.radius)
	if radius == nil or radius < 1.0 or radius > 20.0 then
		error('opts.radius must be within 1.0..20.0')
	end
	local recipients, recipient_reason = eligible_recipients(
		require_table(opts.party_members, 'opts.party_members'),
		require_table(opts.ignore_names, 'opts.ignore_names')
	)
	if recipients == nil then
		return nil, recipient_reason
	end
	local camp_anchor = nil
	local camp_leash_yalms = nil
	if opts.camp_anchor ~= nil then
		camp_anchor = point(opts.camp_anchor, 'opts.camp_anchor')
		camp_leash_yalms = finite_number(opts.camp_leash_yalms)
		if camp_leash_yalms == nil or camp_leash_yalms < 1.0 or camp_leash_yalms > 100.0 then
			error('opts.camp_leash_yalms must be within 1.0..100.0 when camp_anchor is provided')
		end
	end
	local geometry_signature = recipient_geometry_signature(recipients, radius, camp_anchor, camp_leash_yalms)
	if #recipients == 0 then
		return {
			x = me.x,
			y = me.y,
			coverage_count = 0,
			recipient_count = 0,
			recipient_ids = {},
			full_coverage = true,
			clearance = radius,
			camp_distance = camp_anchor and distance(me, camp_anchor) or 0,
			move_distance = 0,
			geometry_signature = geometry_signature,
		}, 'BRD_REPOSITION_FULL_PARTY'
	end

	local candidates = {}
	local seen = {}
	add_candidate(candidates, seen, me.x, me.y)
	add_subset_centroids(candidates, seen, recipients)
	add_circle_intersections(candidates, seen, recipients, radius)
	if camp_anchor ~= nil then
		add_candidate(candidates, seen, camp_anchor.x, camp_anchor.y)
		add_camp_circle_intersections(candidates, seen, recipients, radius, camp_anchor, camp_leash_yalms)
	end

	local best = nil
	for i = 1, #candidates do
		local candidate = candidates[i]
		local viable, camp_distance = candidate_is_camp_viable(candidate, camp_anchor, camp_leash_yalms)
		if viable then
			local ids, clearance = coverage(candidate, recipients, radius)
			local evaluated = {
				x = candidate.x,
				y = candidate.y,
				coverage_count = #ids,
				recipient_count = #recipients,
				recipient_ids = ids,
				full_coverage = #ids == #recipients,
				clearance = clearance,
				camp_distance = camp_distance,
				move_distance = distance(candidate, me),
			}
			if candidate_better(evaluated, best) then
				best = evaluated
			end
		end
	end
	if best == nil or best.coverage_count == 0 then
		return nil, 'BRD_REPOSITION_NO_CAMP_VIABLE_POSITION'
	end
	best.geometry_signature = geometry_signature
	return best, best.full_coverage and 'BRD_REPOSITION_FULL_PARTY' or 'BRD_REPOSITION_LARGEST_CLUSTER'
end

local function action_is_targeted(action)
	local reason = tostring(action.reason_code or '')
	local detail = type(action.detail) == 'table' and action.detail or {}
	return detail.targeted == true
		or tonumber(detail.targeted_recipient_id) ~= nil
		or reason:find('targeted', 1, true) ~= nil
end

local function action_requires_full_coverage(action)
	local reason = tostring(action.reason_code or '')
	local detail = type(action.detail) == 'table' and action.detail or {}
	return tostring(action.action_type or '') == 'ja'
		or detail.is_dummy == true
		or tostring(action.action_name or '') == 'Clarion Call'
		or reason:find('capacity', 1, true) ~= nil
		or reason:find('dummy', 1, true) ~= nil
end

local function partial_coverage_allowed(action)
	local urgency = tonumber(action.urgency)
	if urgency == nil then
		error('Bard positioning action urgency must be numeric')
	end
	return urgency >= URGENT_PARTIAL_THRESHOLD and not action_requires_full_coverage(action)
end

local function reset_state(reason)
	state.phase = 'idle'
	state.reason = tostring(reason or 'reset')
	state.target_x = nil
	state.target_y = nil
	state.coverage_count = 0
	state.recipient_count = 0
	state.full_coverage = false
	state.recipient_ids = {}
	state.geometry_signature = ''
	state.started_at = 0
	state.settle_until = 0
	state.last_progress_at = 0
	state.last_progress_distance = nil
end

function M.reset(reason)
	reset_state(reason)
end

local function install_plan(plan, signature, now)
	state.phase = plan.move_distance <= ARRIVAL_YALMS and 'settling' or 'moving'
	state.reason = plan.full_coverage and 'BRD_REPOSITION_FULL_PARTY' or 'BRD_REPOSITION_URGENT_CLUSTER'
	state.target_x = plan.x
	state.target_y = plan.y
	state.coverage_count = plan.coverage_count
	state.recipient_count = plan.recipient_count
	state.full_coverage = plan.full_coverage
	state.recipient_ids = copy_ids(plan.recipient_ids)
	state.geometry_signature = signature
	state.started_at = now
	state.settle_until = state.phase == 'settling' and now + SETTLE_SECONDS or 0
	state.last_progress_at = now
	state.last_progress_distance = plan.move_distance
end

function M.prepare(opts)
	opts = require_table(opts, 'opts')
	if type(opts.enabled) ~= 'boolean' then
		error('opts.enabled must be boolean')
	end
	local action = require_table(opts.action, 'opts.action')
	if opts.enabled ~= true or action_is_targeted(action) then
		reset_state(opts.enabled and 'targeted_action' or 'disabled')
		return true, state.reason
	end
	local now = finite_number(opts.now)
	if now == nil then
		error('opts.now must be finite')
	end
	local party_members = require_table(opts.party_members, 'opts.party_members')
	local plan, plan_reason = M.select_position({
		me = opts.me,
		party_members = party_members,
		ignore_names = opts.ignore_names,
		radius = opts.radius,
		camp_anchor = opts.camp_anchor,
		camp_leash_yalms = opts.camp_leash_yalms,
	})
	if plan == nil then
		state.phase = 'waiting'
		state.reason = plan_reason
		state.target_x = nil
		state.target_y = nil
		state.coverage_count = 0
		state.recipient_count = 0
		state.full_coverage = false
		state.recipient_ids = {}
		state.geometry_signature = ''
		return false, state.reason
	end
	local signature = plan.geometry_signature
	if plan.full_coverage ~= true and not partial_coverage_allowed(action) then
		state.phase = 'waiting'
		state.reason = action_requires_full_coverage(action)
			and 'BRD_REPOSITION_WAIT_FULL_PARTY_RESOURCE'
			or 'BRD_REPOSITION_WAIT_FULL_PARTY'
		state.target_x = plan.x
		state.target_y = plan.y
		state.coverage_count = plan.coverage_count
		state.recipient_count = plan.recipient_count
		state.full_coverage = false
		state.recipient_ids = copy_ids(plan.recipient_ids)
		state.geometry_signature = signature
		return false, state.reason
	end
	local me = point(opts.me, 'opts.me')
	if plan.move_distance <= ARRIVAL_YALMS and state.phase ~= 'settling' then
		if plan.move_distance <= GEOMETRY_EPSILON then
			reset_state(plan.full_coverage and 'BRD_REPOSITION_ALREADY_COVERED' or 'BRD_REPOSITION_URGENT_CLUSTER_CURRENT')
			return true, state.reason
		end
		install_plan(plan, signature, now)
		return false, state.reason
	end
	if state.phase == 'failed' and state.geometry_signature == signature then
		return false, state.reason
	end
	local same_target = state.target_x ~= nil
		and state.geometry_signature == signature
	if state.phase == 'moving' and same_target then
		return false, state.reason
	end
	if state.phase == 'settling' and same_target then
		if now < state.settle_until then
			return false, 'BRD_REPOSITION_SETTLING'
		end
		local target = { x = state.target_x, y = state.target_y }
		if distance(me, target) > ARRIVAL_YALMS then
			install_plan(plan, signature, now)
			return false, 'BRD_REPOSITION_RANGE_CHANGED'
		end
		reset_state(plan.full_coverage and 'BRD_REPOSITION_READY_FULL_PARTY' or 'BRD_REPOSITION_READY_URGENT_CLUSTER')
		return true, state.reason
	end
	install_plan(plan, signature, now)
	return false, state.reason
end

local function fail_movement(reason)
	state.phase = 'failed'
	state.reason = reason
	state.settle_until = 0
	state.last_progress_distance = nil
	return {
		kind = 'stop',
		reason = reason,
	}
end

function M.fail(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('Bard positioning failure reason must be a non-empty string')
	end
	return fail_movement(reason)
end

function M.movement_request(me_value, now_value)
	local now = finite_number(now_value)
	if now == nil then
		error('Bard positioning movement time must be finite')
	end
	if state.phase == 'idle' then
		return nil
	end
	if state.phase == 'waiting' or state.phase == 'failed' then
		return {
			kind = 'stop',
			reason = state.reason,
		}
	end
	local me = point(me_value, 'me')
	local target = {
		x = state.target_x,
		y = state.target_y,
	}
	local remaining = distance(me, target)
	if state.phase == 'settling' or remaining <= ARRIVAL_YALMS then
		if state.phase ~= 'settling' then
			state.phase = 'settling'
			state.reason = 'BRD_REPOSITION_SETTLING'
			state.settle_until = now + SETTLE_SECONDS
		end
		return {
			kind = 'stop',
			reason = state.reason,
			remaining = remaining,
		}
	end
	if now - state.started_at >= MAX_MOVE_SECONDS then
		return fail_movement('BRD_REPOSITION_TIMEOUT')
	end
	if state.last_progress_distance == nil or remaining <= state.last_progress_distance - PROGRESS_YALMS then
		state.last_progress_at = now
		state.last_progress_distance = remaining
	elseif now - state.last_progress_at >= STALL_SECONDS then
		return fail_movement('BRD_REPOSITION_STALLED')
	end
	local dx = target.x - me.x
	local dy = target.y - me.y
	return {
		kind = 'run',
		reason = state.reason,
		run_x = dx / remaining,
		run_y = dy / remaining,
		remaining = remaining,
		target_x = target.x,
		target_y = target.y,
		coverage_count = state.coverage_count,
		recipient_count = state.recipient_count,
		full_coverage = state.full_coverage,
	}
end

function M.status()
	return {
		phase = state.phase,
		reason = state.reason,
		target_x = state.target_x,
		target_y = state.target_y,
		coverage_count = state.coverage_count,
		recipient_count = state.recipient_count,
		full_coverage = state.full_coverage,
		settle_until = state.settle_until,
	}
end

return M
