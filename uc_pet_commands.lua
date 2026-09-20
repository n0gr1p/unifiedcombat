local M = {}

local VALID_KINDS = {
	activate = true,
	release = true,
	assault = true,
	deploy = true,
	ward = true,
	rage = true,
	maneuver = true,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_nonempty_string(value, name)
	if type(value) ~= 'string' or value == '' then
		error(name .. ' must be a non-empty string')
	end
	return value
end

local function require_positive_integer(value, name)
	local number = tonumber(value)
	if number == nil or number <= 0 or number ~= math.floor(number) then
		error(name .. ' must be a positive integer')
	end
	return number
end

local function require_positive_integer_list(value, name)
	local list = require_table(value, name)
	if #list == 0 then
		error(name .. ' must contain at least one positive integer')
	end
	local seen = {}
	for key, item in pairs(list) do
		if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #list then
			error(name .. ' must be a contiguous array')
		end
		local number = require_positive_integer(item, ('%s[%d]'):format(name, key))
		if seen[number] then
			error(name .. ' must not contain duplicate effect ids')
		end
		seen[number] = true
	end
	return list
end

function M.validate(command)
	command = require_table(command, 'pet command')
	local kind = require_nonempty_string(command.kind, 'pet command kind')
	if VALID_KINDS[kind] ~= true then
		error('unsupported pet command kind: ' .. kind)
	end
	require_nonempty_string(command.action_name, 'pet command action_name')
	if command.astral_conduit ~= nil then
		if kind ~= 'rage' then
			error('pet command astral_conduit is only valid for Rage commands')
		end
		if type(command.astral_conduit) ~= 'boolean' then
			error('pet command astral_conduit must be boolean')
		end
	end
	if kind ~= 'activate' then
		require_positive_integer(command.pet_id, 'pet command pet_id')
	end

	if kind == 'assault' or kind == 'deploy' or kind == 'rage' then
		require_positive_integer(command.target_id, 'pet command target_id')
		require_positive_integer(command.combat_generation, 'pet command combat_generation')
	end
	if kind == 'ward' or kind == 'rage' or kind == 'maneuver' then
		require_positive_integer(command.action_id, 'pet command action_id')
		require_positive_integer(command.recast_id, 'pet command recast_id')
	end
	if kind == 'activate' then
		require_positive_integer(command.recast_id, 'pet command recast_id')
	end
	if kind == 'ward' then
		require_positive_integer_list(command.expected_effect_ids, 'pet command expected_effect_ids')
	end
	return true
end

function M.classify(command)
	M.validate(command)
	return 'pet', command.kind
end

function M.serialize(command)
	M.validate(command)
	local action_name = command.action_name
	if action_name:find('"', 1, true) then
		error('pet command action_name must not contain quotes')
	end
	if command.kind == 'activate' then
		return ('input /ja "%s" <me>'):format(action_name)
	end
	if command.kind == 'release' or command.kind == 'ward' or command.kind == 'maneuver' then
		return ('input /pet "%s" <me>'):format(action_name)
	end
	return ('input /pet "%s" %d'):format(action_name, command.target_id)
end

return M
