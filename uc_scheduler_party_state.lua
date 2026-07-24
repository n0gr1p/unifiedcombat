local M = {}

local PREFIX = 'ucps'
local VERSION = '1'

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_scheduler_party_state requires function dependency: ' .. tostring(name))
	end
	return fn
end

local function split_pipe(text)
	local out = {}
	for part in (tostring(text or '') .. '|'):gmatch('(.-)|') do
		out[#out + 1] = part
	end
	return out
end

local function split_csv_numbers(text)
	local out = {}
	for token in tostring(text or ''):gmatch('[^,]+') do
		local value = tonumber(token)
		if value then
			out[#out + 1] = value
		end
	end
	return out
end

function M.encode_payload(player, zone_id, now)
	if not player or not player.name or not player.id or not player.vitals then
		return nil
	end
	local zone = tonumber(zone_id) or 0
	if zone <= 0 then
		return nil
	end
	local hp = tonumber(player.vitals.hp) or 0
	local hpp = tonumber(player.vitals.hpp) or 100
	local max_hp = tonumber(player.vitals.max_hp) or 0
	local mp = tonumber(player.vitals.mp) or 0
	local max_mp = tonumber(player.vitals.max_mp) or 0
	local mpp = tonumber(player.vitals.mpp)
		or ((max_mp > 0) and math.floor((mp / max_mp) * 100) or 100)
	local buff_parts = {}
	for i = 1, #(player.buffs or {}) do
		local buff_id = tonumber(player.buffs[i]) or 0
		if buff_id > 0 then
			buff_parts[#buff_parts + 1] = tostring(buff_id)
		end
	end
	local name = tostring(player.name):gsub('|', '_')
	return table.concat({
		PREFIX,
		VERSION,
		tostring(tonumber(player.id) or 0),
		name,
		tostring(zone),
		tostring(hp),
		tostring(hpp),
		tostring(max_hp),
		tostring(mp),
		tostring(max_mp),
		tostring(mpp),
		table.concat(buff_parts, ','),
		('%.3f'):format(now),
	}, '|')
end

function M.maybe_broadcast(state, deps)
	if type(state) ~= 'table' then
		error('uc_scheduler_party_state requires state')
	end
	local now = require_function(deps, 'now')()
	local last_sent_at = tonumber(state.last_sent_at) or 0
	if (now - last_sent_at) < (tonumber(state.send_interval) or 1.0) then
		return false
	end
	local payload = M.encode_payload(
		require_function(deps, 'get_player')(),
		require_function(deps, 'current_zone_id')(),
		now
	)
	if not payload then
		return false
	end
	state.last_sent_at = now
	require_function(deps, 'send_ipc_message')(payload)
	return true
end

function M.apply_message(state, message, deps)
	if type(state) ~= 'table' then
		error('uc_scheduler_party_state requires state')
	end
	local parts = split_pipe(message)
	if #parts < 13 or tostring(parts[1]) ~= PREFIX or tostring(parts[2]) ~= VERSION then
		return false
	end
	local actor_id = tonumber(parts[3]) or 0
	local actor_name = tostring(parts[4] or '')
	local zone = tonumber(parts[5]) or 0
	if actor_id <= 0 or actor_name == '' or zone <= 0 then
		return false
	end
	if zone ~= require_function(deps, 'current_zone_id')() then
		return false
	end
	local hp = tonumber(parts[6]) or 0
	local hpp = tonumber(parts[7]) or 100
	local max_hp = tonumber(parts[8]) or 0
	local mp = tonumber(parts[9]) or 0
	local max_mp = tonumber(parts[10]) or 0
	local mpp = tonumber(parts[11])
		or ((max_mp > 0) and math.floor((mp / max_mp) * 100) or 100)
	local stamp = tonumber(parts[13])
	if stamp == nil then
		stamp = require_function(deps, 'now')()
	end
	state.by_id = state.by_id or {}
	local previous = state.by_id[actor_id]
	if previous and tonumber(previous.seq_ts or 0) > stamp then
		return false
	end
	state.by_id[actor_id] = {
		id = actor_id,
		name = actor_name,
		zone = zone,
		hp = hp,
		hpp = hpp,
		max_hp = max_hp,
		mp = mp,
		max_mp = max_mp,
		mpp = mpp,
		buffs = split_csv_numbers(parts[12] or ''),
		seq_ts = stamp,
		rcv_ts = require_function(deps, 'now')(),
	}
	return true
end

function M.get_entry(state, member_id, member_name, deps)
	if type(state) ~= 'table' then
		error('uc_scheduler_party_state requires state')
	end
	state.by_id = state.by_id or {}
	local id = tonumber(member_id) or 0
	local entry = state.by_id[id]
	if not entry then
		return nil
	end
	local now = require_function(deps, 'now')()
	if (now - (tonumber(entry.rcv_ts) or 0)) > (tonumber(state.ttl) or 4.0) then
		state.by_id[id] = nil
		return nil
	end
	if tonumber(entry.zone) ~= require_function(deps, 'current_zone_id')() then
		return nil
	end
	local name = tostring(member_name or '')
	if name ~= '' and tostring(entry.name or ''):lower() ~= name:lower() then
		return nil
	end
	return entry
end

return M
