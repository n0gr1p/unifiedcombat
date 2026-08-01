local party_state = require('uc_scheduler_party_state')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local player = {
	id = 100,
	name = 'Player|Unsafe',
	vitals = {
		hp = 900,
		hpp = 90,
		max_hp = 1000,
		mp = 400,
		max_mp = 500,
		mpp = 80,
	},
	buffs = { 33, 0, 40 },
}

local payload = party_state.encode_payload(player, 200, 10.25)
assert_equal(
	payload,
	'ucps|1|100|Player_Unsafe|200|900|90|1000|400|500|80|33,40|10.250',
	'encoded payload'
)

local now_value = 10.25
local sent = {}
local state = {
	by_id = {},
	last_sent_at = 0,
	send_interval = 1,
	ttl = 4,
}
local deps = {
	now = function()
		return now_value
	end,
	get_player = function()
		return player
	end,
	current_zone_id = function()
		return 200
	end,
	send_ipc_message = function(message)
		sent[#sent + 1] = message
	end,
}

assert_equal(party_state.maybe_broadcast(state, deps), true, 'first broadcast')
assert_equal(#sent, 1, 'first payload sent')
assert_equal(state.last_sent_at, 10.25, 'send timestamp recorded')
now_value = 10.5
assert_equal(party_state.maybe_broadcast(state, deps), false, 'broadcast throttled')
assert_equal(#sent, 1, 'throttled payload not sent')

now_value = 11
assert_equal(party_state.apply_message(state, payload, deps), true, 'payload applied')
local entry = party_state.get_entry(state, 100, 'player_unsafe', deps)
assert_equal(entry.name, 'Player_Unsafe', 'name stored')
assert_equal(entry.buffs[1], 33, 'first buff decoded')
assert_equal(entry.buffs[2], 40, 'second buff decoded')

local older = payload:gsub('10%.250$', '9.000')
assert_equal(party_state.apply_message(state, older, deps), false, 'older payload rejected')
assert_equal(state.by_id[100].seq_ts, 10.25, 'newer payload retained')

now_value = 15.1
assert_equal(party_state.get_entry(state, 100, 'Player_Unsafe', deps), nil, 'expired entry removed')
assert_equal(state.by_id[100], nil, 'expired entry deleted')

assert_equal(party_state.apply_message(state, 'other|1|100|Name|200|1|1|1|1|1|1||1', deps), false, 'foreign prefix rejected')

io.stdout:write('selftest_scheduler_party_state: OK\n')
