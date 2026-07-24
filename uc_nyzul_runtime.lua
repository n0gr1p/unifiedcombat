local uc_active_config = require('uc_active_config')
local movement_dispatcher = require('uc_movement_dispatcher').build({
	dispatcher = require('uc_scheduler_dispatcher'),
	run = windower.ffxi.run,
	source_prefix = 'nyzul_runtime',
})

local M = {}

local IPC_PREFIX = 'ucnyz|v1|'
local ROLE_NONE = 'none'
local ROLE_LAMP = 'lamp'
local ROLE_ANCHOR = 'anchor'

local local_role = ROLE_NONE
local run_state = {
	active = false,
	token = '',
	coordinator_name = '',
	anchor_name = '',
	parking_order = {},
	next_index = 1,
	parked_order = {},
	parked_by_name = {},
	pending_park = nil,
}

local function trim(value)
	if type(value) ~= 'string' then
		return ''
	end
	return value:match('^%s*(.-)%s*$') or ''
end

local function name_key(value)
	return trim(value):lower()
end

local function clone_array(values)
	local out = {}
	if type(values) ~= 'table' then
		return out
	end
	for i = 1, #values do
		out[i] = values[i]
	end
	return out
end

local function player_name()
	local player = windower.ffxi.get_player()
	return trim(player and player.name)
end

local function stop_local_movement()
	movement_dispatcher.stop({ reason = 'nyzul_hold' })
end

local function set_local_role(role)
	if role ~= ROLE_NONE and role ~= ROLE_LAMP and role ~= ROLE_ANCHOR then
		error('invalid Nyzul movement role: ' .. tostring(role))
	end
	if local_role == role then
		return
	end
	local_role = role
	_G.UC_NYZUL_MOVEMENT_HOLD = role ~= ROLE_NONE
	_G.UC_NYZUL_MOVEMENT_ROLE = role
	if role ~= ROLE_NONE then
		stop_local_movement()
		_G.UC_MOVEMENT_OWNER = 'nyzul_hold'
		_G.UC_MOVEMENT_LOCK_UNTIL = math.huge
	elseif rawget(_G, 'UC_MOVEMENT_OWNER') == 'nyzul_hold' then
		_G.UC_MOVEMENT_OWNER = 'none'
		_G.UC_MOVEMENT_LOCK_UNTIL = 0
	end
end

local function configured_names()
	local coordinator = trim(uc_active_config.get_path('config.follow.nyzul.coordinator_name'))
	local anchor = trim(uc_active_config.get_path('config.follow.nyzul.anchor_name'))
	local raw_order = uc_active_config.get_path('config.follow.nyzul.parking_order')
	local order = {}
	local seen = {}
	if type(raw_order) == 'table' then
		for i = 1, #raw_order do
			local name = trim(raw_order[i])
			local key = name_key(name)
			if name ~= '' and not seen[key] then
				seen[key] = true
				order[#order + 1] = name
			end
		end
	end
	if coordinator == '' then
		return nil, 'coordinator name is not configured'
	end
	if anchor == '' then
		return nil, 'anchor name is not configured'
	end
	if #order == 0 then
		return nil, 'parking order is empty'
	end
	local coordinator_key = name_key(coordinator)
	local anchor_key = name_key(anchor)
	if coordinator_key == anchor_key then
		return nil, 'coordinator and anchor must be different characters'
	end
	for i = 1, #order do
		local key = name_key(order[i])
		if key == coordinator_key then
			return nil, 'parking order contains coordinator ' .. coordinator
		end
		if key == anchor_key then
			return nil, 'parking order contains anchor ' .. anchor
		end
	end
	return {
		coordinator_name = coordinator,
		anchor_name = anchor,
		parking_order = order,
	}
end

local function party_name_set()
	local party = windower.ffxi.get_party()
	local out = {}
	if type(party) ~= 'table' then
		return out
	end
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local entry = party[key]
		local mob = entry and entry.mob
		local name = trim(mob and mob.name)
		if name ~= '' then
			out[name_key(name)] = true
		end
	end
	return out
end

local function next_token()
	local socket = require('socket')
	return ('%s:%d'):format(name_key(player_name()), math.floor(socket.gettime() * 1000))
end

local function encode_name(value)
	local name = trim(value)
	if name:find('|', 1, true) then
		error('Nyzul character names cannot contain |')
	end
	return name
end

local function send_event(operation, token, coordinator, target)
	local message = IPC_PREFIX .. table.concat({
		encode_name(operation),
		encode_name(token),
		encode_name(coordinator),
		encode_name(target),
	}, '|')
	M.ipc_message(message)
	windower.send_ipc_message(message)
end

local function send_ack(token, coordinator, target)
	local message = IPC_PREFIX .. table.concat({
		'ack',
		encode_name(token),
		encode_name(coordinator),
		encode_name(target),
	}, '|')
	windower.send_ipc_message(message)
end

local function reset_coordinator_state()
	run_state.active = false
	run_state.token = ''
	run_state.coordinator_name = ''
	run_state.anchor_name = ''
	run_state.parking_order = {}
	run_state.next_index = 1
	run_state.parked_order = {}
	run_state.parked_by_name = {}
	run_state.pending_park = nil
end

local function require_coordinator_run()
	if not run_state.active then
		return false, 'Nyzul run is not active; use //uc nyzul begin'
	end
	if name_key(player_name()) ~= name_key(run_state.coordinator_name) then
		return false, 'Nyzul queue commands must be run by ' .. run_state.coordinator_name
	end
	return true
end

function M.begin()
	local config, config_error = configured_names()
	if not config then
		return false, config_error
	end
	if name_key(player_name()) ~= name_key(config.coordinator_name) then
		return false, 'Nyzul begin must be run by ' .. config.coordinator_name
	end
	local present = party_name_set()
	if not present[name_key(config.anchor_name)] then
		return false, 'configured anchor is not in the current party: ' .. config.anchor_name
	end
	reset_coordinator_state()
	run_state.active = true
	run_state.token = next_token()
	run_state.coordinator_name = config.coordinator_name
	run_state.anchor_name = config.anchor_name
	run_state.parking_order = clone_array(config.parking_order)
	send_event('begin', run_state.token, run_state.coordinator_name, run_state.anchor_name)
	return true, ('Nyzul run started; anchor=%s, parkers=%d'):format(run_state.anchor_name, #run_state.parking_order)
end

function M.park_next()
	local ok, reason = require_coordinator_run()
	if not ok then
		return false, reason
	end
	if type(run_state.pending_park) == 'table' then
		local pending = run_state.pending_park
		send_event('park', run_state.token, run_state.coordinator_name, pending.name)
		return true, 'retrying pending parker ' .. pending.name .. '; awaiting acknowledgement'
	end
	local present = party_name_set()
	local selected_index = nil
	local selected_name = nil
	for i = run_state.next_index, #run_state.parking_order do
		local candidate = run_state.parking_order[i]
		local key = name_key(candidate)
		if present[key] and not run_state.parked_by_name[key] then
			selected_index = i
			selected_name = candidate
			break
		end
	end
	if not selected_name then
		return false, 'no configured, present Nyzul parkers remain'
	end
	run_state.pending_park = {
		name = selected_name,
		index = selected_index,
	}
	send_event('park', run_state.token, run_state.coordinator_name, selected_name)
	return true, 'parking ' .. selected_name .. '; awaiting acknowledgement'
end

function M.regroup()
	local ok, reason = require_coordinator_run()
	if not ok then
		return false, reason
	end
	if type(run_state.pending_park) == 'table' then
		return false, 'cannot regroup while awaiting ' .. run_state.pending_park.name
	end
	local released = #run_state.parked_order
	send_event('regroup', run_state.token, run_state.coordinator_name, '*')
	run_state.next_index = 1
	run_state.parked_order = {}
	run_state.parked_by_name = {}
	return true, ('regrouped %d lamp parker(s); anchor=%s remains parked'):format(released, run_state.anchor_name)
end

function M.undo()
	local ok, reason = require_coordinator_run()
	if not ok then
		return false, reason
	end
	if type(run_state.pending_park) == 'table' then
		return false, 'cannot undo while awaiting ' .. run_state.pending_park.name
	end
	local count = #run_state.parked_order
	if count == 0 then
		return false, 'no lamp parker is available to undo'
	end
	local name = run_state.parked_order[count]
	run_state.parked_order[count] = nil
	run_state.parked_by_name[name_key(name)] = nil
	for i = 1, #run_state.parking_order do
		if name_key(run_state.parking_order[i]) == name_key(name) then
			run_state.next_index = i
			break
		end
	end
	send_event('release', run_state.token, run_state.coordinator_name, name)
	return true, 'released ' .. name .. '; next=' .. name
end

function M.finish()
	local ok, reason = require_coordinator_run()
	if not ok then
		return false, reason
	end
	local anchor = run_state.anchor_name
	local token = run_state.token
	local coordinator = run_state.coordinator_name
	send_event('end', token, coordinator, '*')
	reset_coordinator_state()
	return true, 'Nyzul run ended; released anchor ' .. anchor .. ' and all lamp parkers'
end

function M.status()
	return {
		active = run_state.active,
		role = local_role,
		coordinator_name = run_state.coordinator_name,
		anchor_name = run_state.anchor_name,
		parked_order = clone_array(run_state.parked_order),
		next_index = run_state.next_index,
		parking_order = clone_array(run_state.parking_order),
		pending_park = run_state.pending_park and run_state.pending_park.name or nil,
	}
end

function M.is_movement_held()
	return local_role ~= ROLE_NONE
end

function M.movement_hold_reason()
	if local_role == ROLE_NONE then
		return nil
	end
	return 'NYZUL_' .. local_role:upper() .. '_HOLD'
end

function M.enforce_movement_hold()
	if local_role == ROLE_NONE then
		return false
	end
	stop_local_movement()
	_G.UC_MOVEMENT_OWNER = 'nyzul_hold'
	_G.UC_MOVEMENT_LOCK_UNTIL = math.huge
	return true
end

function M.ipc_message(message)
	if type(message) ~= 'string' or message:sub(1, #IPC_PREFIX) ~= IPC_PREFIX then
		return false
	end
	local fields = {}
	for field in message:sub(#IPC_PREFIX + 1):gmatch('[^|]+') do
		fields[#fields + 1] = field
	end
	if #fields ~= 4 then
		return false
	end
	local operation = fields[1]
	local target = fields[4]
	local self_key = name_key(player_name())
	local target_key = name_key(target)
	if operation == 'begin' then
		if self_key ~= name_key(fields[3]) then
			reset_coordinator_state()
			run_state.active = true
			run_state.token = fields[2]
			run_state.coordinator_name = fields[3]
			run_state.anchor_name = target
		end
		set_local_role(target_key == self_key and ROLE_ANCHOR or ROLE_NONE)
	elseif operation == 'park' and target_key == self_key then
		set_local_role(ROLE_LAMP)
		send_ack(fields[2], fields[3], player_name())
	elseif operation == 'ack'
		and self_key == name_key(fields[3])
		and fields[2] == run_state.token
		and type(run_state.pending_park) == 'table'
		and target_key == name_key(run_state.pending_park.name) then
		local pending = run_state.pending_park
		run_state.pending_park = nil
		run_state.next_index = pending.index + 1
		run_state.parked_order[#run_state.parked_order + 1] = pending.name
		run_state.parked_by_name[name_key(pending.name)] = true
		local present = party_name_set()
		local next_name = 'none'
		for i = run_state.next_index, #run_state.parking_order do
			local candidate = run_state.parking_order[i]
			if present[name_key(candidate)] and not run_state.parked_by_name[name_key(candidate)] then
				next_name = candidate
				break
			end
		end
		windower.add_to_chat(207, ('UC Nyzul: parked %s (%d/%d); next=%s'):format(
			pending.name,
			#run_state.parked_order,
			#run_state.parking_order,
			next_name
		))
	elseif operation == 'release' and target_key == self_key and local_role == ROLE_LAMP then
		set_local_role(ROLE_NONE)
	elseif operation == 'regroup' and local_role == ROLE_LAMP then
		set_local_role(ROLE_NONE)
	elseif operation == 'end' then
		set_local_role(ROLE_NONE)
		reset_coordinator_state()
	end
	return true
end

function M.reset()
	reset_coordinator_state()
	set_local_role(ROLE_NONE)
end

if not M._ipc_registered then
	M._ipc_registered = true
	windower.register_event('ipc message', function(message)
		M.ipc_message(message)
	end)
end

return M
