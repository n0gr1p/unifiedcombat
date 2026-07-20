local function assert_true(value, message)
	if not value then error(message or 'assertion failed') end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function set_u32_le(bytes, position, value)
	bytes[position] = value % 0x100
	bytes[position + 1] = math.floor(value / 0x100) % 0x100
	bytes[position + 2] = math.floor(value / 0x10000) % 0x100
	bytes[position + 3] = math.floor(value / 0x1000000) % 0x100
end

local function set_buff(bytes, entry_position, slot, buff_id)
	bytes[entry_position + 16 + slot - 1] = buff_id % 0x100
	local mask_position = entry_position + 8 + math.floor((slot - 1) / 4)
	local shift = 4 ^ ((slot - 1) % 4)
	local prior = bytes[mask_position]
	local prior_high = math.floor(prior / shift) % 4
	bytes[mask_position] = prior + ((math.floor(buff_id / 0x100) % 4) - prior_high) * shift
end

local function make_packet(entries)
	local bytes = {}
	for i = 1, 4 + 5 * 48 do bytes[i] = 0 end
	for entry_index = 1, #entries do
		local entry_position = 5 + (entry_index - 1) * 48
		local entry = entries[entry_index]
		set_u32_le(bytes, entry_position, entry.id)
		for slot = 1, #entry.buffs do
			set_buff(bytes, entry_position, slot, entry.buffs[slot])
		end
	end
	return string.char(unpack(bytes))
end

package.loaded.uc_party_buff_tracker = nil
local tracker = require('uc_party_buff_tracker')
local charun_id = 560699
local packet = make_packet({
	{ id = charun_id, buffs = { 214, 198, 198, 33, 499 } },
	{ id = 400018, buffs = { 214, 196 } },
})

local parsed, parse_err = tracker.parse_packet(packet)
assert_true(type(parsed) == 'table', 'valid 0x076 packet must parse: ' .. tostring(parse_err))
assert_equal(parsed[charun_id].buffs[1], 214, 'first Charun buff mismatch')
assert_equal(parsed[charun_id].buffs[2], 198, 'second Charun buff mismatch')
assert_equal(parsed[charun_id].buffs[5], 499, 'high-ID Charun buff mismatch')
assert_equal(parsed[400018].buffs[2], 196, 'second party member buff mismatch')

local ingest_ok, ingest_err = tracker.ingest(packet, 100)
assert_true(ingest_ok, 'valid 0x076 packet must ingest: ' .. tostring(ingest_err))
assert_equal(tracker.get(charun_id).buffs[3], 198, 'tracked Charun buff mismatch')
assert_equal(tracker._test.state.received_at, 100, 'party buff receive time mismatch')

tracker.reset()
local seed_ok, seed_err = tracker.seed_cached(function(packet_id)
	assert_equal(packet_id, 0x076, 'cached party buff packet id mismatch')
	return packet
end, 101)
assert_true(seed_ok, 'cached 0x076 packet must seed: ' .. tostring(seed_err))
assert_equal(tracker.get(charun_id).buffs[1], 214, 'seeded Charun buff mismatch')

local party_song_state = require('uc_brd_party_song_state')
party_song_state.reset()
party_song_state.observe({
	{
		id = charun_id,
		name = 'Charun',
		hpp = 100,
		spawn_type = 13,
		is_npc = false,
		in_song_range = true,
		buffs = tracker.get(charun_id).buffs,
		buff_source = 'packet_076',
	},
}, {}, { [214] = true, [198] = true, [196] = true }, 102)
local action = party_song_state.next_action({
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', "Mage's Ballad III" },
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
}, 5, false, false)
assert_true(type(action) == 'table', 'three-song non-UC recipient must start recovery')
assert_equal(action.action_name, "Army's Paeon", 'three-song non-UC recovery must start with a capacity dummy')
assert_equal(action.member_id, charun_id, 'non-UC recovery member mismatch')

party_song_state.reset()
party_song_state.observe({
	{
		id = charun_id,
		name = 'Charun',
		hpp = 100,
		spawn_type = 13,
		is_npc = false,
		in_song_range = true,
		buffs = nil,
		buff_source = 'missing',
	},
}, {}, { [214] = true, [198] = true, [196] = true }, 103)
assert_true(party_song_state.next_action({ songs = { 'A', 'B', 'C', 'D', 'E' }, dummy_songs = { 'Dummy' } }, 5, false, false) == nil,
	'missing remote buff data must remain unknown and must not trigger false-zero recovery')

tracker.reset()
assert_true(tracker.get(charun_id) == nil, 'party buff reset must clear tracked members')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'rb'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(scheduler_source:find("if nid == 0x076 and type%(data%) == 'string' then"),
	'scheduler must ingest incoming 0x076 party buff packets')
assert_true(scheduler_source:find("buff_source = 'packet_076'", 1, true),
	'scheduler must expose packet-backed party buffs')
assert_true(not scheduler_source:find('local buffs = entry.buffs or {}', 1, true),
	'scheduler must not convert absent remote buffs into a confirmed empty list')

io.stdout:write('selftest_party_buff_tracker: OK\n')
