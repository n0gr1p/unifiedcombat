local M = {}

local VALID_KINDS = {
	release = true,
	assault = true,
	ward = true,
	rage = true,
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

function M.validate(command)
	command = require_table(command, 'pet command')
	local kind = require_nonempty_string(command.kind, 'pet command kind')
	if VALID_KINDS[kind] ~= true then
		error('unsupported pet command kind: ' .. kind)
	end
	require_nonempty_string(command.action_name, 'pet command action_name')
	require_positive_integer(command.pet_id, 'pet command pet_id')

	if kind == 'assault' or kind == 'rage' then
		require_positive_integer(command.target_id, 'pet command target_id')
		require_positive_integer(command.combat_generation, 'pet command combat_generation')
	end
	if kind == 'ward' or kind == 'rage' then
		require_positive_integer(command.action_id, 'pet command action_id')
		require_positive_integer(command.recast_id, 'pet command recast_id')
	end
	if kind == 'ward' then
		require_positive_integer(command.expected_effect_id, 'pet command expected_effect_id')
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
	if command.kind == 'release' or command.kind == 'ward' then
		return ('input /pet "%s" <me>'):format(action_name)
	end
	return ('input /pet "%s" %d'):format(action_name, command.target_id)
end

return M
