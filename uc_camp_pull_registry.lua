local M = {}

local IPC_PREFIX = 'uc_camp_pull_registry_v1'

local VALID_STATES = {
	ACTIVE_PULL = true,
	FOREIGN_CLAIMED = true,
	ORPHANED_HOSTILE = true,
	FORFEITED_IDLE = true,
	ENDED = true,
}

local state = {
	zone_id = 0,
	next_order = 1,
	records = {},
}

local function positive_integer(value, name)
	local number = tonumber(value)
	if number == nil or number <= 0 or number % 1 ~= 0 then
		error(name .. ' must be a positive integer')
	end
	return number
end

local function nonnegative_integer(value, name)
	local number = tonumber(value)
	if number == nil or number < 0 or number % 1 ~= 0 then
		error(name .. ' must be a nonnegative integer')
	end
	return number
end

local function require_function(value, name)
	if type(value) ~= 'function' then
		error(name .. ' must be a function')
	end
	return value
end

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function safe_name(value)
	if type(value) ~= 'string' or value == '' or value:find('|', 1, true) then
		error('camp pull registry mob name is invalid')
	end
	return value
end

local function split_pipe(message)
	local parts = {}
	for part in tostring(message):gmatch('[^|]+') do
		parts[#parts + 1] = part
	end
	return parts
end

local function install_zone(zone_id)
	local zone = positive_integer(zone_id, 'camp pull registry zone id')
	if state.zone_id ~= 0 and state.zone_id ~= zone then
		error(('camp pull registry zone mismatch: current=%d observed=%d'):format(state.zone_id, zone))
	end
	state.zone_id = zone
	return zone
end

local function encode_record(record)
	return ('%s|upsert|%d|%d|%d|%s|%d|%s'):format(
		IPC_PREFIX,
		record.zone_id,
		record.id,
		record.pull_order,
		record.state,
		record.foreign_seen and 1 or 0,
		record.name
	)
end

local function broadcast_record(record, send_ipc_message)
	require_function(send_ipc_message, 'camp pull registry IPC sender')(encode_record(record))
end

local function broadcast_remove(zone_id, mob_id, send_ipc_message)
	require_function(send_ipc_message, 'camp pull registry IPC sender')(
		('%s|remove|%d|%d'):format(IPC_PREFIX, zone_id, mob_id)
	)
end

local function derive_state(record, mob, friendly_claims)
	local hpp = tonumber(mob.hpp)
	if hpp ~= nil and hpp <= 0 then
		return 'ENDED', record.foreign_seen
	end
	if record.state == 'ENDED' then
		return 'ENDED', record.foreign_seen
	end
	if mob.valid_target ~= true then
		return record.state, record.foreign_seen
	end
	if hpp == nil then
		error('valid tracked camp pull mob HPP is unavailable')
	end
	local claim_id = tonumber(mob.claim_id)
	if claim_id == nil or claim_id < 0 or claim_id % 1 ~= 0 then
		error('tracked camp pull mob claim id is invalid')
	end
	if claim_id > 0 then
		if friendly_claims[claim_id] == true then
			return 'ACTIVE_PULL', record.foreign_seen
		end
		return 'FOREIGN_CLAIMED', true
	end
	local status = tonumber(mob.status)
	if status == nil or status % 1 ~= 0 then
		error('tracked camp pull mob status is invalid')
	end
	if status == 1 then
		if record.foreign_seen then
			return 'ORPHANED_HOSTILE', true
		end
		return 'ACTIVE_PULL', false
	end
	return 'FORFEITED_IDLE', record.foreign_seen
end

local function install_record(spec)
	require_table(spec, 'camp pull registry record')
	local zone_id = install_zone(spec.zone_id)
	local id = positive_integer(spec.id, 'camp pull registry mob id')
	local pull_order = positive_integer(spec.pull_order, 'camp pull registry pull order')
	local record_state = tostring(spec.state or '')
	if VALID_STATES[record_state] ~= true then
		error('camp pull registry state is invalid: ' .. record_state)
	end
	local record = {
		zone_id = zone_id,
		id = id,
		name = safe_name(spec.name),
		pull_order = pull_order,
		state = record_state,
		foreign_seen = spec.foreign_seen == true,
	}
	state.records[id] = record
	if pull_order >= state.next_order then
		state.next_order = pull_order + 1
	end
	return record
end

function M.register_reacted(mob, friendly_claims, zone_id, send_ipc_message)
	require_table(mob, 'camp pull registry reacted mob')
	require_table(friendly_claims, 'camp pull registry friendly claims')
	local id = positive_integer(mob.id, 'camp pull registry mob id')
	if state.records[id] ~= nil then
		error(('camp pull registry duplicate registration for mob id %d'):format(id))
	end
	local record = install_record({
		zone_id = zone_id,
		id = id,
		name = mob.name,
		pull_order = state.next_order,
		state = 'ACTIVE_PULL',
		foreign_seen = false,
	})
	record.state, record.foreign_seen = derive_state(record, mob, friendly_claims)
	broadcast_record(record, send_ipc_message)
	return record.state
end

function M.observe(mobs, friendly_claims, zone_id, send_ipc_message)
	require_table(mobs, 'camp pull registry mobs')
	require_table(friendly_claims, 'camp pull registry friendly claims')
	install_zone(zone_id)
	require_function(send_ipc_message, 'camp pull registry IPC sender')
	local by_id = {}
	for _, mob in pairs(mobs) do
		local id = tonumber(mob and mob.id) or 0
		if id > 0 then
			by_id[id] = mob
		end
	end
	local removals = {}
	for id, record in pairs(state.records) do
		local mob = by_id[id]
		if mob ~= nil then
			local fresh_spawn = record.state == 'ENDED'
				and mob.valid_target == true
				and tonumber(mob.spawn_type) == 16
				and tonumber(mob.hpp) == 100
				and tonumber(mob.status) == 0
				and (tonumber(mob.claim_id) or 0) == 0
			if fresh_spawn then
				removals[#removals + 1] = id
			else
				local next_state, foreign_seen = derive_state(record, mob, friendly_claims)
				if next_state ~= record.state or foreign_seen ~= record.foreign_seen then
					record.state = next_state
					record.foreign_seen = foreign_seen
					broadcast_record(record, send_ipc_message)
				end
			end
		end
	end
	for i = 1, #removals do
		local id = removals[i]
		state.records[id] = nil
		broadcast_remove(state.zone_id, id, send_ipc_message)
	end
end

function M.candidate_excluded(mob_id)
	local id = positive_integer(mob_id, 'camp pull registry candidate id')
	return state.records[id] ~= nil
end

function M.quota_eligible(mob, friendly_claims)
	require_table(mob, 'camp pull registry quota mob')
	require_table(friendly_claims, 'camp pull registry friendly claims')
	local id = positive_integer(mob.id, 'camp pull registry quota mob id')
	local record = state.records[id]
	if record == nil then
		return false
	end
	local spawn_type = tonumber(mob.spawn_type)
	local hpp = tonumber(mob.hpp)
	local claim_id = tonumber(mob.claim_id)
	local status = tonumber(mob.status)
	if spawn_type == nil or hpp == nil or claim_id == nil or status == nil then
		error('tracked camp pull quota mob state is incomplete')
	end
	if mob.valid_target ~= true or spawn_type ~= 16 or hpp <= 0 then
		return false
	end
	if record.state == 'ENDED' then
		return false
	end
	if claim_id > 0 then
		return friendly_claims[claim_id] == true
	end
	if status ~= 1 then
		return false
	end
	return true
end

function M.combat_order(mob, friendly_claims)
	if not M.quota_eligible(mob, friendly_claims) then
		return nil
	end
	return state.records[tonumber(mob.id)].pull_order
end

function M.note_death(mob_id)
	local id = positive_integer(mob_id, 'camp pull registry death mob id')
	local record = state.records[id]
	if record == nil then
		return false
	end
	record.state = 'ENDED'
	return true
end

function M.summary()
	local summary = {
		tracked_count = 0,
		active_count = 0,
		foreign_claimed_count = 0,
		orphaned_hostile_count = 0,
		forfeited_idle_count = 0,
		ended_count = 0,
	}
	for _, record in pairs(state.records) do
		summary.tracked_count = summary.tracked_count + 1
		if record.state == 'ACTIVE_PULL' then
			summary.active_count = summary.active_count + 1
		elseif record.state == 'FOREIGN_CLAIMED' then
			summary.foreign_claimed_count = summary.foreign_claimed_count + 1
		elseif record.state == 'ORPHANED_HOSTILE' then
			summary.orphaned_hostile_count = summary.orphaned_hostile_count + 1
		elseif record.state == 'FORFEITED_IDLE' then
			summary.forfeited_idle_count = summary.forfeited_idle_count + 1
		elseif record.state == 'ENDED' then
			summary.ended_count = summary.ended_count + 1
		else
			error('camp pull registry contains an invalid state: ' .. tostring(record.state))
		end
	end
	return summary
end

function M.snapshot()
	local records = {}
	for id, record in pairs(state.records) do
		records[id] = {
			zone_id = record.zone_id,
			id = record.id,
			name = record.name,
			pull_order = record.pull_order,
			state = record.state,
			foreign_seen = record.foreign_seen,
		}
	end
	return {
		zone_id = state.zone_id,
		next_order = state.next_order,
		records = records,
	}
end

function M.on_ipc_message(message, current_zone_id)
	if type(message) ~= 'string' or message:sub(1, #IPC_PREFIX + 1) ~= IPC_PREFIX .. '|' then
		return false
	end
	local parts = split_pipe(message)
	if parts[1] ~= IPC_PREFIX then
		return false
	end
	local zone_id = tonumber(current_zone_id)
	if zone_id == nil or zone_id <= 0 or zone_id % 1 ~= 0 then
		return true, false, 'PULL_REGISTRY_CURRENT_ZONE_UNAVAILABLE'
	end
	if parts[2] == 'upsert' then
		if #parts ~= 8 then
			return true, false, 'PULL_REGISTRY_IPC_INVALID'
		end
		local message_zone = nonnegative_integer(parts[3], 'camp pull registry IPC zone id')
		if message_zone ~= zone_id then
			return true, false, 'PULL_REGISTRY_IPC_ZONE_MISMATCH'
		end
		local foreign_seen
		if parts[7] == '1' then
			foreign_seen = true
		elseif parts[7] == '0' then
			foreign_seen = false
		else
			return true, false, 'PULL_REGISTRY_IPC_INVALID'
		end
		local ok, record = pcall(install_record, {
			zone_id = parts[3],
			id = parts[4],
			pull_order = parts[5],
			state = parts[6],
			foreign_seen = foreign_seen,
			name = parts[8],
		})
		if not ok then
			return true, false, 'PULL_REGISTRY_IPC_INVALID:' .. tostring(record)
		end
		return true, true, 'PULL_REGISTRY_UPDATED'
	end
	if parts[2] == 'remove' then
		if #parts ~= 4 then
			return true, false, 'PULL_REGISTRY_IPC_INVALID'
		end
		local message_zone = nonnegative_integer(parts[3], 'camp pull registry IPC zone id')
		if message_zone ~= zone_id then
			return true, false, 'PULL_REGISTRY_IPC_ZONE_MISMATCH'
		end
		local id = positive_integer(parts[4], 'camp pull registry IPC mob id')
		state.records[id] = nil
		return true, true, 'PULL_REGISTRY_REMOVED'
	end
	return true, false, 'PULL_REGISTRY_IPC_INVALID'
end

function M.reset(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('camp pull registry reset requires a reason')
	end
	state.zone_id = 0
	state.next_order = 1
	state.records = {}
end

return M
