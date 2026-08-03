local M = {}

local function require_number(value, name)
	if type(value) ~= 'number' then
		error(name .. ' must be a number')
	end
	return value
end

local function clone_members(members)
	local out = {}
	for i = 1, #members do
		local member = members[i]
		local copy = {}
		for key, value in pairs(member) do
			if type(value) == 'table' then
				local nested = {}
				for nested_key, nested_value in pairs(value) do
					nested[nested_key] = nested_value
				end
				copy[key] = nested
			else
				copy[key] = value
			end
		end
		out[i] = copy
	end
	return out
end

local function observed_members(members, now)
	local out = clone_members(members)
	for i = 1, #out do
		local member = out[i]
		local coordinate_fields = { 'x', 'y', 'z' }
		for field_index = 1, #coordinate_fields do
			local field = coordinate_fields[field_index]
			if member[field] ~= nil and type(member[field]) ~= 'number' then
				error('Scholar party member ' .. field .. ' must be numeric when present')
			end
		end
		member.coordinate_observed_at = nil
		if type(member.x) == 'number' and type(member.y) == 'number' then
			member.coordinate_observed_at = now
		end
	end
	return out
end

local function validate_members(members)
	if type(members) ~= 'table' then
		error('Scholar party members must be a table')
	end
	if #members > 6 then
		error('Scholar party members must contain no more than six entries')
	end
	local seen_ids = {}
	local roster = {}
	for i = 1, #members do
		local member = members[i]
		if type(member) ~= 'table' then
			error('Scholar party member must be a table')
		end
		local id = member.id
		if type(id) ~= 'number' or id <= 0 or id % 1 ~= 0 then
			error('Scholar party member id must be a positive integer')
		end
		if seen_ids[id] then
			error('Scholar party member ids must be unique')
		end
		seen_ids[id] = true
		local name = member.name
		if type(name) ~= 'string' or name == '' then
			error('Scholar party member name must be a non-empty string')
		end
		local normalized_name = name:lower()
		roster[#roster + 1] = ('%d:%d:%s'):format(id, #normalized_name, normalized_name)
	end
	for key in pairs(members) do
		if type(key) ~= 'number' or key < 1 or key > #members or key % 1 ~= 0 then
			error('Scholar party members must be a contiguous array')
		end
	end
	table.sort(roster)
	return table.concat(roster, '|')
end

function M.new_tracker()
	return {
		generation = 0,
		roster_signature = nil,
		observed_at = 0,
		members = {},
	}
end

function M.observe(tracker, members, at)
	if type(tracker) ~= 'table' then
		error('Scholar party tracker must be a table')
	end
	if type(tracker.generation) ~= 'number'
		or tracker.generation < 0
		or tracker.generation % 1 ~= 0 then
		error('Scholar party tracker generation must be a non-negative integer')
	end
	local now = require_number(at, 'Scholar party observation time')
	local roster_signature = validate_members(members)
	local snapshot_members = observed_members(members, now)
	if tracker.roster_signature ~= roster_signature then
		tracker.generation = tracker.generation + 1
		tracker.roster_signature = roster_signature
	end
	tracker.observed_at = now
	tracker.members = snapshot_members
	return {
		generation = tracker.generation,
		roster_signature = tracker.roster_signature,
		observed_at = tracker.observed_at,
		members = clone_members(tracker.members),
	}
end

return M
