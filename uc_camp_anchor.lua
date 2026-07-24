local M = {}

local IPC_PREFIX = 'uc_camp_anchor_v1'

local state = {
	active = false,
	zone_id = 0,
	x = nil,
	y = nil,
	set_by = '',
}

local function finite_number(value)
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

local function current_zone_id()
	local info = windower.ffxi.get_info()
	if type(info) ~= 'table' then
		return nil
	end
	local zone_id = tonumber(info.zone)
	if zone_id == nil or zone_id <= 0 then
		return nil
	end
	return math.floor(zone_id)
end

local function split_pipe(message)
	local parts = {}
	for part in tostring(message):gmatch('[^|]+') do
		parts[#parts + 1] = part
	end
	return parts
end

local function install(zone_id, x, y, set_by)
	local zone = tonumber(zone_id)
	local point_x = finite_number(x)
	local point_y = finite_number(y)
	if type(set_by) ~= 'string' then
		return false, 'CAMP_SETTER_INVALID'
	end
	local setter = set_by
	if zone == nil or zone <= 0 or zone % 1 ~= 0 then
		return false, 'CAMP_ZONE_INVALID'
	end
	if point_x == nil or point_y == nil then
		return false, 'CAMP_COORDINATES_INVALID'
	end
	if setter == '' or setter:find('|', 1, true) then
		return false, 'CAMP_SETTER_INVALID'
	end
	state.active = true
	state.zone_id = zone
	state.x = point_x
	state.y = point_y
	state.set_by = setter
	return true, 'CAMP_SET'
end

function M.clear()
	state.active = false
	state.zone_id = 0
	state.x = nil
	state.y = nil
	state.set_by = ''
	return true, 'CAMP_CLEARED'
end

function M.set_current_position()
	local zone_id = current_zone_id()
	if zone_id == nil then
		return false, 'CAMP_ZONE_UNAVAILABLE'
	end
	local player = windower.ffxi.get_player()
	local me = windower.ffxi.get_mob_by_target('me')
	if type(player) ~= 'table' or type(player.name) ~= 'string' or player.name == '' then
		return false, 'CAMP_PLAYER_UNAVAILABLE'
	end
	if type(me) ~= 'table' then
		return false, 'CAMP_POSITION_UNAVAILABLE'
	end
	local ok, reason = install(zone_id, me.x, me.y, player.name)
	if not ok then
		return false, reason
	end
	windower.send_ipc_message(('%s|set|%d|%.6f|%.6f|%s'):format(
		IPC_PREFIX,
		state.zone_id,
		state.x,
		state.y,
		state.set_by
	))
	return true, reason
end

function M.clear_shared()
	local player = windower.ffxi.get_player()
	if type(player) ~= 'table' or type(player.name) ~= 'string' or player.name == '' then
		return false, 'CAMP_PLAYER_UNAVAILABLE'
	end
	M.clear()
	windower.send_ipc_message(('%s|clear|%s'):format(IPC_PREFIX, player.name))
	return true, 'CAMP_CLEARED'
end

function M.on_ipc_message(message)
	if type(message) ~= 'string' or message:sub(1, #IPC_PREFIX + 1) ~= IPC_PREFIX .. '|' then
		return false
	end
	local parts = split_pipe(message)
	if parts[1] ~= IPC_PREFIX then
		return false
	end
	if parts[2] == 'set' then
		if #parts ~= 6 then
			return true, false, 'CAMP_IPC_INVALID'
		end
		local ok, reason = install(parts[3], parts[4], parts[5], parts[6])
		return true, ok, reason
	end
	if parts[2] == 'clear' then
		if #parts ~= 3 or parts[3] == '' then
			return true, false, 'CAMP_IPC_INVALID'
		end
		M.clear()
		return true, true, 'CAMP_CLEARED'
	end
	return true, false, 'CAMP_IPC_INVALID'
end

function M.resolve_current_anchor()
	if not state.active then
		return nil, 'CAMP_UNSET'
	end
	local zone_id = current_zone_id()
	if zone_id == nil then
		return nil, 'CAMP_ZONE_UNAVAILABLE'
	end
	if state.zone_id ~= zone_id then
		return nil, 'CAMP_ZONE_MISMATCH'
	end
	local point_x = finite_number(state.x)
	local point_y = finite_number(state.y)
	if point_x == nil or point_y == nil then
		return nil, 'CAMP_GEOMETRY_UNAVAILABLE'
	end
	return {
		x = point_x,
		y = point_y,
		zone_id = state.zone_id,
		set_by = state.set_by,
	}, 'CAMP_READY'
end

function M.status()
	return {
		active = state.active,
		zone_id = state.zone_id,
		x = state.x,
		y = state.y,
		set_by = state.set_by,
	}
end

return M
