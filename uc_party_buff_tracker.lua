local M = {}

local PARTY_BUFF_PACKET_ID = 0x076
local PARTY_ENTRY_COUNT = 5
local PARTY_ENTRY_SIZE = 48
local FIRST_ENTRY_POSITION = 5
local BUFF_SLOT_COUNT = 32

local state = {
	by_id = {},
	received_at = 0,
	seed_attempted = false,
}

local function read_u32_le(data, position)
	local b1, b2, b3, b4 = data:byte(position, position + 3)
	if b1 == nil or b2 == nil or b3 == nil or b4 == nil then
		return nil
	end
	return b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
end

local function parse_entry(data, entry_position)
	if entry_position + PARTY_ENTRY_SIZE - 1 > #data then
		return nil, 'truncated_party_buff_entry'
	end
	local member_id = read_u32_le(data, entry_position)
	if member_id == nil then
		return nil, 'missing_party_member_id'
	end
	if member_id == 0 then
		return false
	end
	local buffs = {}
	for slot = 1, BUFF_SLOT_COUNT do
		local low = data:byte(entry_position + 16 + slot - 1)
		local mask = data:byte(entry_position + 8 + math.floor((slot - 1) / 4))
		if low == nil or mask == nil then
			return nil, 'truncated_party_buff_data'
		end
		local high = math.floor(mask / (4 ^ ((slot - 1) % 4))) % 4
		local buff_id = low + high * 0x100
		if buff_id ~= 0 and buff_id ~= 0xFF then
			buffs[#buffs + 1] = buff_id
		end
	end
	return {
		id = member_id,
		buffs = buffs,
	}
end

function M.parse_packet(data)
	if type(data) ~= 'string' then
		return nil, 'party_buff_packet_must_be_string'
	end
	local by_id = {}
	for entry_index = 0, PARTY_ENTRY_COUNT - 1 do
		local entry, err = parse_entry(data, FIRST_ENTRY_POSITION + entry_index * PARTY_ENTRY_SIZE)
		if entry == nil then
			return nil, err
		end
		if entry == false then
			break
		end
		by_id[entry.id] = entry
	end
	return by_id
end

function M.ingest(data, now)
	local parsed, err = M.parse_packet(data)
	if type(parsed) ~= 'table' then
		return false, err
	end
	state.by_id = parsed
	state.received_at = tonumber(now) or os.time()
	state.seed_attempted = true
	return true
end

function M.seed_cached(last_incoming, now)
	assert(type(last_incoming) == 'function', 'party buff tracker requires last_incoming')
	if state.seed_attempted then
		return false, 'seed_already_attempted'
	end
	state.seed_attempted = true
	local data = last_incoming(PARTY_BUFF_PACKET_ID)
	if type(data) ~= 'string' then
		return false, 'cached_party_buff_packet_unavailable'
	end
	return M.ingest(data, now)
end

function M.get(member_id)
	return state.by_id[tonumber(member_id) or 0]
end

function M.reset()
	state.by_id = {}
	state.received_at = 0
	state.seed_attempted = false
end

M._test = {
	state = state,
	read_u32_le = read_u32_le,
}

return M
