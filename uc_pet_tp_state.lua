local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_integer(value, name, minimum, maximum)
	if type(value) ~= 'number'
		or value % 1 ~= 0
		or value < minimum
		or value > maximum then
		error(('%s must be an integer from %d to %d'):format(name, minimum, maximum))
	end
	return value
end

local function clear_report(state)
	state.reported_pet_index = 0
	state.tp = nil
end

function M.new()
	return {
		active_pet_id = 0,
		active_pet_index = 0,
		reported_pet_index = 0,
		tp = nil,
	}
end

function M.reset(state)
	state = require_table(state, 'pet TP state')
	state.active_pet_id = 0
	state.active_pet_index = 0
	clear_report(state)
end

function M.observe_pet(state, present, pet_id, pet_index)
	state = require_table(state, 'pet TP state')
	if present ~= true then
		M.reset(state)
		return
	end
	pet_id = require_integer(pet_id, 'active pet id', 1, 0xFFFFFFFF)
	pet_index = require_integer(pet_index, 'active pet index', 1, 0xFFFF)
	if state.active_pet_id > 0
		and (state.active_pet_id ~= pet_id or state.active_pet_index ~= pet_index) then
		clear_report(state)
	end
	state.active_pet_id = pet_id
	state.active_pet_index = pet_index
	if state.reported_pet_index > 0 and state.reported_pet_index ~= pet_index then
		clear_report(state)
	end
end

function M.ingest(state, packet_id, data, player_index, parse_packet)
	state = require_table(state, 'pet TP state')
	packet_id = require_integer(packet_id, 'pet TP packet id', 0, 0xFFFF)
	if packet_id ~= 0x067 and packet_id ~= 0x068 then
		return false
	end
	if type(data) ~= 'string' then
		error('pet TP packet data must be a string')
	end
	player_index = require_integer(player_index, 'pet TP player index', 1, 0xFFFF)
	if type(parse_packet) ~= 'function' then
		error('pet TP packet parser must be a function')
	end
	local packet = parse_packet('incoming', data)
	if type(packet) ~= 'table' then
		error('pet TP packet parser must return a table')
	end
	local message_type = require_integer(packet['Message Type'], 'pet TP message type', 0, 0xFF)
	local pet_index = require_integer(packet['Pet Index'], 'reported pet index', 0, 0xFFFF)
	local owner_index = require_integer(packet['Owner Index'], 'reported pet owner index', 0, 0xFFFF)
	if message_type == 0x04 and packet_id == 0x067 then
		pet_index, owner_index = owner_index, pet_index
	end
	if message_type ~= 0x04 or owner_index ~= player_index then
		return false
	end
	if pet_index == 0 then
		clear_report(state)
		return true
	end
	local pet_tp = require_integer(packet['Pet TP'], 'reported pet TP', 0, 3000)
	state.reported_pet_index = pet_index
	state.tp = pet_tp
	return true
end

function M.current_tp(state, pet_id, pet_index)
	state = require_table(state, 'pet TP state')
	pet_id = require_integer(pet_id, 'current pet id', 1, 0xFFFFFFFF)
	pet_index = require_integer(pet_index, 'current pet index', 1, 0xFFFF)
	if state.active_pet_id ~= pet_id
		or state.active_pet_index ~= pet_index
		or state.reported_pet_index ~= pet_index then
		return nil
	end
	return state.tp
end

return M
