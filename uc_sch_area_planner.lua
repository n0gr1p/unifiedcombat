local M = {}

local ACCESSION_MODEL_KEY = 'Accession|party'

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_number(value, name)
	if type(value) ~= 'number' then
		error(name .. ' must be a number')
	end
	return value
end

function M.production_mechanics()
	return {
		confidence = 'unknown',
		model_key = ACCESSION_MODEL_KEY,
		reason = 'accession_geometry_unvalidated',
	}
end

local function validate_members(members)
	require_table(members, 'Scholar area planner members')
	if #members == 0 or #members > 6 then
		error('Scholar area planner requires one through six party members')
	end
	local by_id = {}
	for i = 1, #members do
		local member = require_table(members[i], 'Scholar area planner member')
		if type(member.id) ~= 'number' or member.id <= 0 or member.id % 1 ~= 0 then
			error('Scholar area planner member id must be a positive integer')
		end
		if by_id[member.id] ~= nil then
			error('Scholar area planner member ids must be unique')
		end
		if type(member.name) ~= 'string' or member.name == '' then
			error('Scholar area planner member name must be a non-empty string')
		end
		if type(member.hpp) ~= 'number' or member.hpp < 0 or member.hpp > 100 then
			error('Scholar area planner member hpp must be a number from 0 through 100')
		end
		by_id[member.id] = {
			member = member,
			party_order = i,
		}
	end
	return by_id
end

local function validate_id_set(values, name, by_id, require_living)
	require_table(values, name)
	local set = {}
	for i = 1, #values do
		local id = values[i]
		if type(id) ~= 'number' or id <= 0 or id % 1 ~= 0 then
			error(name .. ' entries must be positive integers')
		end
		if set[id] then
			error(name .. ' entries must be unique')
		end
		local row = by_id[id]
		if row == nil then
			error(name .. ' entry is not a party member')
		end
		if require_living and row.member.hpp <= 0 then
			error(name .. ' entry must identify a living member')
		end
		set[id] = true
	end
	return set
end

local function sorted_relevant_rows(members, relevant)
	local rows = {}
	for i = 1, #members do
		if relevant[members[i].id] then
			rows[#rows + 1] = members[i]
		end
	end
	return rows
end

local function distance(left, right, metric)
	local dx = left.x - right.x
	local dy = left.y - right.y
	local squared = dx * dx + dy * dy
	if metric == 'three_dimensional' then
		local dz = left.z - right.z
		squared = squared + dz * dz
	end
	return math.sqrt(squared)
end

local function candidate_is_better(candidate, best)
	if best == nil then
		return true
	end
	if candidate.coverage_count ~= best.coverage_count then
		return candidate.coverage_count > best.coverage_count
	end
	if candidate.party_order ~= best.party_order then
		return candidate.party_order < best.party_order
	end
	return candidate.anchor_id < best.anchor_id
end

function M.select(input)
	require_table(input, 'Scholar area planner input')
	local now = require_number(input.now, 'Scholar area planner time')
	if now < 0 then
		error('Scholar area planner time must be non-negative')
	end
	local minimum_coverage = input.minimum_coverage
	if type(minimum_coverage) ~= 'number'
		or minimum_coverage <= 0
		or minimum_coverage % 1 ~= 0 then
		error('Scholar area planner minimum_coverage must be a positive integer')
	end
	local members = require_table(input.members, 'Scholar area planner members')
	local by_id = validate_members(members)
	local eligible = validate_id_set(
		input.eligible_recipient_ids,
		'Scholar area planner eligible_recipient_ids',
		by_id,
		true
	)
	local unsafe = validate_id_set(
		input.unsafe_recipient_ids,
		'Scholar area planner unsafe_recipient_ids',
		by_id,
		true
	)
	for id in pairs(eligible) do
		if unsafe[id] then
			error('Scholar area planner recipient cannot be both eligible and unsafe')
		end
	end
	local mechanics = require_table(input.mechanics, 'Scholar area planner mechanics')
	if mechanics.confidence ~= 'confirmed' and mechanics.confidence ~= 'unknown' then
		error('Scholar area planner mechanics confidence must be confirmed or unknown')
	end
	if mechanics.model_key ~= ACCESSION_MODEL_KEY then
		error('Scholar area planner mechanics model_key must identify party Accession')
	end
	local result = {
		state = 'blocked',
		blocker = '',
		mechanics_confidence = mechanics.confidence,
		mechanics_model_key = mechanics.model_key,
		mechanics_source = '',
		mechanics_reason = '',
		candidates = {},
		selected = nil,
		missing_coordinate_ids = {},
		stale_coordinate_ids = {},
	}
	if mechanics.confidence == 'unknown' then
		if type(mechanics.reason) ~= 'string' or mechanics.reason == '' then
			error('Scholar unknown area mechanics reason must be a non-empty string')
		end
		if mechanics.source ~= nil
			or mechanics.radius_yalms ~= nil
			or mechanics.max_coordinate_age_s ~= nil
			or mechanics.distance_metric ~= nil then
			error('Scholar unknown area mechanics must not claim confirmed parameters')
		end
		result.mechanics_reason = mechanics.reason
		result.blocker = 'accession_geometry_unvalidated'
		return result
	end
	if mechanics.reason ~= nil then
		error('Scholar confirmed area mechanics must not include an unknown reason')
	end
	if type(mechanics.source) ~= 'string' or mechanics.source == '' then
		error('Scholar confirmed area mechanics source must be a non-empty string')
	end
	result.mechanics_source = mechanics.source
	local radius = require_number(mechanics.radius_yalms, 'Scholar area planner radius_yalms')
	if radius <= 0 then
		error('Scholar area planner radius_yalms must be positive')
	end
	local max_age = require_number(
		mechanics.max_coordinate_age_s,
		'Scholar area planner max_coordinate_age_s'
	)
	if max_age < 0 then
		error('Scholar area planner max_coordinate_age_s must be non-negative')
	end
	local metric = mechanics.distance_metric
	if metric ~= 'horizontal' and metric ~= 'three_dimensional' then
		error('Scholar area planner distance_metric must be horizontal or three_dimensional')
	end
	result.radius_yalms = radius
	result.max_coordinate_age_s = max_age
	result.distance_metric = metric
	local relevant = {}
	for id in pairs(eligible) do
		relevant[id] = true
	end
	for id in pairs(unsafe) do
		relevant[id] = true
	end
	local relevant_rows = sorted_relevant_rows(members, relevant)
	for i = 1, #relevant_rows do
		local member = relevant_rows[i]
		if type(member.x) ~= 'number'
			or type(member.y) ~= 'number'
			or (metric == 'three_dimensional' and type(member.z) ~= 'number')
			or type(member.coordinate_observed_at) ~= 'number' then
			result.missing_coordinate_ids[#result.missing_coordinate_ids + 1] = member.id
		elseif member.coordinate_observed_at < 0
			or member.coordinate_observed_at > now then
			error('Scholar area planner coordinate observation time is outside the valid range')
		elseif now - member.coordinate_observed_at > max_age then
			result.stale_coordinate_ids[#result.stale_coordinate_ids + 1] = member.id
		end
	end
	if #result.missing_coordinate_ids > 0 or #result.stale_coordinate_ids > 0 then
		result.blocker = 'coverage_unknown'
		return result
	end
	local best = nil
	for i = 1, #members do
		local anchor = members[i]
		if eligible[anchor.id] then
			local candidate = {
				anchor_id = anchor.id,
				anchor_name = anchor.name,
				party_order = i,
				expected_recipient_ids = {},
				unsafe_recipient_ids = {},
				coverage_count = 0,
				safe = true,
			}
			for member_index = 1, #members do
				local member = members[member_index]
				if relevant[member.id] and distance(anchor, member, metric) <= radius then
					if eligible[member.id] then
						candidate.expected_recipient_ids[#candidate.expected_recipient_ids + 1] = member.id
					elseif unsafe[member.id] then
						candidate.unsafe_recipient_ids[#candidate.unsafe_recipient_ids + 1] = member.id
					end
				end
			end
			candidate.coverage_count = #candidate.expected_recipient_ids
			candidate.safe = #candidate.unsafe_recipient_ids == 0
			result.candidates[#result.candidates + 1] = candidate
			if candidate.safe and candidate_is_better(candidate, best) then
				best = candidate
			end
		end
	end
	if best == nil or best.coverage_count < minimum_coverage then
		result.blocker = 'coverage_below_minimum'
		return result
	end
	result.state = 'ready'
	result.selected = best
	return result
end

return M
