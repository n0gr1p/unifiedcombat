local M = {}

local IPC_PREFIX_V2 = 'uc_camp_anchor_v2'
local IPC_PREFIX_V3 = 'uc_camp_anchor_v3'
local targeting_common = require('uc_targeting_common')

local state = {
	known = false,
	active = false,
	zone_id = 0,
	x = nil,
	y = nil,
	z = nil,
	author_name = '',
	author_id = 0,
	revision = nil,
	source = 'unknown',
	coordinate_version = 0,
}

-- Revisions are Lamport-style tuples: wall-clock seconds, a logical counter,
-- and the author name as a deterministic final tie-breaker. Receiving a
-- revision advances the local clock; replaying it never creates a new one.
local revision_clock = {
	timestamp = 0,
	counter = 0,
}

local request_pending = false
local last_group_fingerprint = nil

local function finite_number(value)
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

local function valid_integer(value, minimum, maximum)
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	if n % 1 ~= 0 or n < minimum or n > maximum then
		return nil
	end
	return n
end

local function valid_name(value)
	if type(value) ~= 'string' or #value < 1 or #value > 15 then
		return nil
	end
	if not value:match('^[A-Za-z]+$') then
		return nil
	end
	return value
end

local function current_zone_id()
	local info = windower.ffxi.get_info()
	if type(info) ~= 'table' then
		return nil
	end
	return valid_integer(info.zone, 1, 65535)
end

local function split_pipe(message)
	local parts = {}
	local start_at = 1
	while true do
		local separator_at = message:find('|', start_at, true)
		if separator_at == nil then
			parts[#parts + 1] = message:sub(start_at)
			return parts
		end
		parts[#parts + 1] = message:sub(start_at, separator_at - 1)
		start_at = separator_at + 1
	end
end

local function parse_revision(value)
	if type(value) ~= 'string' then
		return nil
	end
	local timestamp_text, counter_text, author_text = value:match('^(%d+):(%d+):([A-Za-z]+)$')
	local timestamp = valid_integer(timestamp_text, 1, 9999999999)
	local counter = valid_integer(counter_text, 0, 9999999999)
	local author = valid_name(author_text)
	if timestamp == nil or counter == nil or author == nil then
		return nil
	end
	return {
		timestamp = timestamp,
		counter = counter,
		author = author,
		text = ('%.0f:%.0f:%s'):format(timestamp, counter, author),
	}
end

local function compare_revisions(a, b)
	if a.timestamp ~= b.timestamp then
		return a.timestamp < b.timestamp and -1 or 1
	end
	if a.counter ~= b.counter then
		return a.counter < b.counter and -1 or 1
	end
	local a_author = a.author:lower()
	local b_author = b.author:lower()
	if a_author == b_author then
		return 0
	end
	return a_author < b_author and -1 or 1
end

local function observe_revision(revision)
	if revision.timestamp > revision_clock.timestamp then
		revision_clock.timestamp = revision.timestamp
		revision_clock.counter = revision.counter
	elseif revision.timestamp == revision_clock.timestamp and revision.counter > revision_clock.counter then
		revision_clock.counter = revision.counter
	end
end

local function mint_revision(author)
	local timestamp = os.time()
	if valid_integer(timestamp, 1, 9999999999) == nil then
		error('camp revision clock returned an invalid timestamp')
	end
	if timestamp > revision_clock.timestamp then
		revision_clock.timestamp = timestamp
		revision_clock.counter = 0
	else
		revision_clock.counter = revision_clock.counter + 1
	end
	local revision = {
		timestamp = revision_clock.timestamp,
		counter = revision_clock.counter,
		author = author,
	}
	revision.text = ('%.0f:%.0f:%s'):format(revision.timestamp, revision.counter, revision.author)
	return revision
end

local function current_identity()
	local player = windower.ffxi.get_player()
	if type(player) ~= 'table' then
		return nil, 'CAMP_PLAYER_UNAVAILABLE'
	end
	local name = valid_name(player.name)
	local id = valid_integer(player.id, 1, 4294967295)
	if name == nil or id == nil then
		return nil, 'CAMP_PLAYER_UNAVAILABLE'
	end
	if not targeting_common.is_friendly_combat_member_identity(name, id) then
		return nil, 'CAMP_GROUP_UNAVAILABLE'
	end
	return {
		name = name,
		id = id,
	}, nil
end

local function current_context()
	local identity, identity_reason = current_identity()
	if identity == nil then
		return nil, identity_reason
	end
	local zone_id = current_zone_id()
	if zone_id == nil then
		return nil, 'CAMP_ZONE_UNAVAILABLE'
	end
	identity.zone_id = zone_id
	return identity, nil
end

local function group_fingerprint()
	local members = targeting_common.get_friendly_combat_member_identities()
	if #members == 0 then
		return nil
	end
	local parts = {}
	for i = 1, #members do
		local member = members[i]
		local name = valid_name(member.name)
		local id = valid_integer(member.id, 1, 4294967295)
		if name == nil or id == nil then
			return nil
		end
		parts[#parts + 1] = ('%s:%.0f'):format(name:lower(), id)
	end
	table.sort(parts)
	return table.concat(parts, ',')
end

local function reset_runtime_state()
	state.known = false
	state.active = false
	state.zone_id = 0
	state.x = nil
	state.y = nil
	state.z = nil
	state.author_name = ''
	state.author_id = 0
	state.revision = nil
	state.source = 'unknown'
	state.coordinate_version = 0
end

local function validate_candidate(candidate)
	if type(candidate) ~= 'table' or candidate.known ~= true or type(candidate.active) ~= 'boolean' then
		return nil, 'CAMP_STATE_INVALID'
	end
	local zone_id = valid_integer(candidate.zone_id, 1, 65535)
	local author_name = valid_name(candidate.author_name)
	local author_id = valid_integer(candidate.author_id, 1, 4294967295)
	local revision = parse_revision(candidate.revision)
	local coordinate_version = valid_integer(candidate.coordinate_version, 2, 3)
	if zone_id == nil then
		return nil, 'CAMP_ZONE_INVALID'
	end
	if author_name == nil or author_id == nil then
		return nil, 'CAMP_AUTHOR_INVALID'
	end
	if revision == nil or revision.author:lower() ~= author_name:lower() then
		return nil, 'CAMP_REVISION_INVALID'
	end
	if coordinate_version == nil then
		return nil, 'CAMP_COORDINATE_VERSION_INVALID'
	end
	local x = nil
	local y = nil
	local z = nil
	if candidate.active then
		x = finite_number(candidate.x)
		y = finite_number(candidate.y)
		if x == nil or y == nil then
			return nil, 'CAMP_COORDINATES_INVALID'
		end
		if coordinate_version == 3 then
			z = finite_number(candidate.z)
			if z == nil then
				return nil, 'CAMP_COORDINATES_INVALID'
			end
		elseif candidate.z ~= nil then
			return nil, 'CAMP_COORDINATES_INVALID'
		end
	elseif candidate.x ~= nil or candidate.y ~= nil or candidate.z ~= nil then
		return nil, 'CAMP_COORDINATES_INVALID'
	end
	return {
		known = true,
		active = candidate.active,
		zone_id = zone_id,
		x = x,
		y = y,
		z = z,
		author_name = author_name,
		author_id = author_id,
		revision = revision,
		coordinate_version = coordinate_version,
	}, nil
end

local function equivalent_state(candidate)
	return state.known == true
		and state.active == candidate.active
		and state.zone_id == candidate.zone_id
		and state.x == candidate.x
		and state.y == candidate.y
		and (state.active ~= true
			or state.z == candidate.z
			or state.z == nil
			or candidate.z == nil)
		and state.author_name:lower() == candidate.author_name:lower()
		and state.author_id == candidate.author_id
end

local function apply_candidate(raw_candidate, source)
	local candidate, invalid_reason = validate_candidate(raw_candidate)
	if candidate == nil then
		return false, invalid_reason
	end
	if state.known then
		local current_revision = parse_revision(state.revision)
		if current_revision == nil then
			error('camp runtime state contains an invalid revision')
		end
		local comparison = compare_revisions(candidate.revision, current_revision)
		if comparison < 0 then
			return false, 'CAMP_REVISION_STALE'
		end
		if comparison == 0 then
			if not equivalent_state(candidate) then
				return false, 'CAMP_REVISION_CONFLICT'
			end
			if state.active and state.z == nil and candidate.z ~= nil then
				state.z = candidate.z
				state.coordinate_version = 3
				state.source = source
			elseif not state.active and candidate.coordinate_version > state.coordinate_version then
				state.coordinate_version = candidate.coordinate_version
			end
			return true, state.active and 'CAMP_SET' or 'CAMP_CLEARED'
		end
	end
	state.known = true
	state.active = candidate.active
	state.zone_id = candidate.zone_id
	state.x = candidate.x
	state.y = candidate.y
	state.z = candidate.z
	state.author_name = candidate.author_name
	state.author_id = candidate.author_id
	state.revision = candidate.revision.text
	state.source = source
	state.coordinate_version = candidate.coordinate_version
	observe_revision(candidate.revision)
	return true, state.active and 'CAMP_SET' or 'CAMP_CLEARED'
end

local function validate_remote_identity(name_value, id_value)
	local name = valid_name(name_value)
	local id = valid_integer(id_value, 1, 4294967295)
	if name == nil or id == nil then
		return nil, nil
	end
	if not targeting_common.is_friendly_combat_member_identity(name, id) then
		return nil, nil
	end
	return name, id
end

local function send_state_response(request_prefix, target_name, target_id, context)
	if not state.known or state.zone_id ~= context.zone_id then
		return false, 'CAMP_STATE_UNAVAILABLE'
	end
	local state_kind = state.active and 'set' or 'clear'
	local x_text = '-'
	local y_text = '-'
	local z_text = '-'
	if state.active then
		x_text = ('%.6f'):format(state.x)
		y_text = ('%.6f'):format(state.y)
		if state.z ~= nil then
			z_text = ('%.6f'):format(state.z)
		end
	end
	if request_prefix == IPC_PREFIX_V3 and (not state.active or state.z ~= nil) then
		windower.send_ipc_message(('%s|state|%s|%.0f|%d|%s|%s|%s|%s|%s|%.0f|%s|%s|%.0f'):format(
			IPC_PREFIX_V3,
			target_name,
			target_id,
			state.zone_id,
			state_kind,
			x_text,
			y_text,
			z_text,
			state.author_name,
			state.author_id,
			state.revision,
			context.name,
			context.id
		))
		return true, 'CAMP_STATE_SENT'
	end
	if request_prefix ~= IPC_PREFIX_V2 and request_prefix ~= IPC_PREFIX_V3 then
		error('camp state response requires a supported IPC prefix')
	end
	windower.send_ipc_message(('%s|state|%s|%.0f|%d|%s|%s|%s|%s|%.0f|%s|%s|%.0f'):format(
		IPC_PREFIX_V2,
		target_name,
		target_id,
		state.zone_id,
		state_kind,
		x_text,
		y_text,
		state.author_name,
		state.author_id,
		state.revision,
		context.name,
		context.id
	))
	return true, 'CAMP_STATE_SENT'
end

function M.clear()
	reset_runtime_state()
	return true, 'CAMP_CLEARED'
end

function M.set_current_position()
	local context, context_reason = current_context()
	if context == nil then
		return false, context_reason
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if type(me) ~= 'table' then
		return false, 'CAMP_POSITION_UNAVAILABLE'
	end
	local point_x = finite_number(me.x)
	local point_y = finite_number(me.y)
	local point_z = finite_number(me.z)
	if point_x == nil or point_y == nil or point_z == nil then
		return false, 'CAMP_COORDINATES_INVALID'
	end
	local revision = mint_revision(context.name)
	local ok, reason = apply_candidate({
		known = true,
		active = true,
		zone_id = context.zone_id,
		x = point_x,
		y = point_y,
		z = point_z,
		author_name = context.name,
		author_id = context.id,
		revision = revision.text,
		coordinate_version = 3,
	}, 'authored')
	if not ok then
		error('locally authored camp set failed validation: ' .. tostring(reason))
	end
	windower.send_ipc_message(('%s|set|%d|%.6f|%.6f|%.6f|%s|%.0f|%s'):format(
		IPC_PREFIX_V3,
		state.zone_id,
		state.x,
		state.y,
		state.z,
		state.author_name,
		state.author_id,
		state.revision
	))
	windower.send_ipc_message(('%s|set|%d|%.6f|%.6f|%s|%.0f|%s'):format(
		IPC_PREFIX_V2,
		state.zone_id,
		state.x,
		state.y,
		state.author_name,
		state.author_id,
		state.revision
	))
	return true, reason
end

function M.clear_shared()
	local context, context_reason = current_context()
	if context == nil then
		return false, context_reason
	end
	local revision = mint_revision(context.name)
	local ok, reason = apply_candidate({
		known = true,
		active = false,
		zone_id = context.zone_id,
		x = nil,
		y = nil,
		z = nil,
		author_name = context.name,
		author_id = context.id,
		revision = revision.text,
		coordinate_version = 3,
	}, 'authored')
	if not ok then
		error('locally authored camp clear failed validation: ' .. tostring(reason))
	end
	windower.send_ipc_message(('%s|clear|%d|%s|%.0f|%s'):format(
		IPC_PREFIX_V3,
		state.zone_id,
		state.author_name,
		state.author_id,
		state.revision
	))
	windower.send_ipc_message(('%s|clear|%d|%s|%.0f|%s'):format(
		IPC_PREFIX_V2,
		state.zone_id,
		state.author_name,
		state.author_id,
		state.revision
	))
	return true, reason
end

function M.request_current_state()
	local context, context_reason = current_context()
	if context == nil then
		request_pending = true
		return false, context_reason
	end
	local fingerprint = group_fingerprint()
	if fingerprint == nil then
		request_pending = true
		return false, 'CAMP_GROUP_UNAVAILABLE'
	end
	windower.send_ipc_message(('%s|request|%s|%.0f|%d'):format(
		IPC_PREFIX_V3,
		context.name,
		context.id,
		context.zone_id
	))
	windower.send_ipc_message(('%s|request|%s|%.0f|%d'):format(
		IPC_PREFIX_V2,
		context.name,
		context.id,
		context.zone_id
	))
	request_pending = false
	last_group_fingerprint = fingerprint
	return true, 'CAMP_STATE_REQUESTED'
end

function M.schedule_state_request()
	request_pending = true
	return true, 'CAMP_STATE_REQUEST_SCHEDULED'
end

function M.observe_runtime()
	local context = current_context()
	if context == nil then
		return false, 'CAMP_RUNTIME_UNAVAILABLE'
	end
	local fingerprint = group_fingerprint()
	if fingerprint == nil then
		return false, 'CAMP_GROUP_UNAVAILABLE'
	end
	if request_pending then
		return M.request_current_state()
	end
	if last_group_fingerprint == nil then
		last_group_fingerprint = fingerprint
		return false, 'CAMP_GROUP_INITIALIZED'
	end
	if fingerprint ~= last_group_fingerprint then
		return M.request_current_state()
	end
	return false, 'CAMP_GROUP_UNCHANGED'
end

function M.on_ipc_message(message)
	if type(message) ~= 'string' then
		return false
	end
	local parts = split_pipe(message)
	local prefix = parts[1]
	local coordinate_version = nil
	if prefix == IPC_PREFIX_V2 then
		coordinate_version = 2
	elseif prefix == IPC_PREFIX_V3 then
		coordinate_version = 3
	else
		return false
	end
	local operation = parts[2]
	if operation == 'set' then
		local expected_parts = coordinate_version == 3 and 9 or 8
		if #parts ~= expected_parts then
			return true, false, 'CAMP_IPC_INVALID'
		end
		local context = current_context()
		local author_index = coordinate_version == 3 and 7 or 6
		local author_name, author_id = validate_remote_identity(parts[author_index], parts[author_index + 1])
		local zone_id = valid_integer(parts[3], 1, 65535)
		if context == nil or author_name == nil or zone_id ~= context.zone_id then
			return true, false, 'CAMP_IPC_SCOPE_INVALID'
		end
		local ok, reason = apply_candidate({
			known = true,
			active = true,
			zone_id = zone_id,
			x = parts[4],
			y = parts[5],
			z = coordinate_version == 3 and parts[6] or nil,
			author_name = author_name,
			author_id = author_id,
			revision = parts[author_index + 2],
			coordinate_version = coordinate_version,
		}, 'synchronized')
		return true, ok, reason
	end
	if operation == 'clear' then
		if #parts ~= 6 then
			return true, false, 'CAMP_IPC_INVALID'
		end
		local context = current_context()
		local author_name, author_id = validate_remote_identity(parts[4], parts[5])
		local zone_id = valid_integer(parts[3], 1, 65535)
		if context == nil or author_name == nil or zone_id ~= context.zone_id then
			return true, false, 'CAMP_IPC_SCOPE_INVALID'
		end
		local ok, reason = apply_candidate({
			known = true,
			active = false,
			zone_id = zone_id,
			x = nil,
			y = nil,
			z = nil,
			author_name = author_name,
			author_id = author_id,
			revision = parts[6],
			coordinate_version = coordinate_version,
		}, 'synchronized')
		return true, ok, reason
	end
	if operation == 'request' then
		if #parts ~= 5 then
			return true, false, 'CAMP_IPC_INVALID'
		end
		local context = current_context()
		local requester_name, requester_id = validate_remote_identity(parts[3], parts[4])
		local requested_zone = valid_integer(parts[5], 1, 65535)
		if context == nil or requester_name == nil or requested_zone ~= context.zone_id then
			return true, false, 'CAMP_IPC_SCOPE_INVALID'
		end
		local ok, reason = send_state_response(prefix, requester_name, requester_id, context)
		return true, ok, reason
	end
	if operation == 'state' then
		local expected_parts = coordinate_version == 3 and 14 or 13
		if #parts ~= expected_parts then
			return true, false, 'CAMP_IPC_INVALID'
		end
		local context = current_context()
		local target_name = valid_name(parts[3])
		local target_id = valid_integer(parts[4], 1, 4294967295)
		local zone_id = valid_integer(parts[5], 1, 65535)
		local author_index = coordinate_version == 3 and 10 or 9
		local responder_index = coordinate_version == 3 and 13 or 12
		local responder_name, responder_id = validate_remote_identity(
			parts[responder_index],
			parts[responder_index + 1]
		)
		if context == nil
			or target_name == nil
			or target_id == nil
			or target_name:lower() ~= context.name:lower()
			or target_id ~= context.id
			or responder_name == nil
			or responder_id == nil
			or zone_id ~= context.zone_id
		then
			return true, false, 'CAMP_IPC_SCOPE_INVALID'
		end
		local active = nil
		local x = nil
		local y = nil
		local z = nil
		if parts[6] == 'set' then
			active = true
			x = parts[7]
			y = parts[8]
			z = coordinate_version == 3 and parts[9] or nil
		elseif parts[6] == 'clear'
			and parts[7] == '-'
			and parts[8] == '-'
			and (coordinate_version == 2 or parts[9] == '-') then
			active = false
		else
			return true, false, 'CAMP_IPC_INVALID'
		end
		local ok, reason = apply_candidate({
			known = true,
			active = active,
			zone_id = zone_id,
			x = x,
			y = y,
			z = z,
			author_name = parts[author_index],
			author_id = parts[author_index + 1],
			revision = parts[author_index + 2],
			coordinate_version = coordinate_version,
		}, 'synchronized')
		return true, ok, reason
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
	local point_z = finite_number(state.z)
	if state.z ~= nil and point_z == nil then
		return nil, 'CAMP_GEOMETRY_UNAVAILABLE'
	end
	local anchor = {
		x = point_x,
		y = point_y,
		z = point_z,
		zone_id = state.zone_id,
		set_by = state.author_name,
		revision = state.revision,
	}
	if point_z == nil then
		return anchor, 'CAMP_READY_XY_ONLY'
	end
	return anchor, 'CAMP_READY'
end

function M.status()
	local coordinate_mode = 'unset'
	if state.active then
		coordinate_mode = state.z == nil and 'xy' or 'xyz'
	end
	return {
		known = state.known,
		active = state.active,
		zone_id = state.zone_id,
		x = state.x,
		y = state.y,
		z = state.z,
		coordinate_mode = coordinate_mode,
		coordinate_version = state.coordinate_version,
		set_by = state.active and state.author_name or '',
		cleared_by = state.known and not state.active and state.author_name or '',
		author_id = state.author_id,
		revision = state.revision,
		source = state.source,
		request_pending = request_pending,
	}
end

return M
