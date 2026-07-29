package.path = './?.lua;' .. package.path

local pet_tp_state = require('uc_pet_tp_state')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local parsed_packet = nil
local function parse_packet(direction, data)
	assert_equal(direction, 'incoming', 'packet direction')
	assert_equal(data, 'packet-data', 'packet data')
	return parsed_packet
end

local state = pet_tp_state.new()
pet_tp_state.observe_pet(state, true, 0x100001, 55)

parsed_packet = {
	['Message Type'] = 0x04,
	['Pet Index'] = 55,
	['Owner Index'] = 7,
	['Pet TP'] = 2000,
}
assert_true(
	pet_tp_state.ingest(state, 0x068, 'packet-data', 7, parse_packet),
	'0x068 current-player pet update must be ingested'
)
assert_equal(pet_tp_state.current_tp(state, 0x100001, 55), 2000, '0x068 pet TP')

parsed_packet = {
	['Message Type'] = 0x04,
	['Pet Index'] = 7,
	['Owner Index'] = 55,
	['Pet TP'] = 2999,
}
assert_true(
	pet_tp_state.ingest(state, 0x067, 'packet-data', 7, parse_packet),
	'0x067 swapped current-player pet update must be ingested'
)
assert_equal(pet_tp_state.current_tp(state, 0x100001, 55), 2999, '0x067 pet TP')

parsed_packet = {
	['Message Type'] = 0x04,
	['Pet Index'] = 55,
	['Owner Index'] = 8,
	['Pet TP'] = 3000,
}
assert_equal(
	pet_tp_state.ingest(state, 0x068, 'packet-data', 7, parse_packet),
	false,
	'other-player pet update must be ignored'
)
assert_equal(pet_tp_state.current_tp(state, 0x100001, 55), 2999, 'ignored packet must preserve TP')

pet_tp_state.observe_pet(state, true, 0x100002, 56)
assert_equal(pet_tp_state.current_tp(state, 0x100002, 56), nil, 'pet identity change must clear TP')

parsed_packet = {
	['Message Type'] = 0x04,
	['Pet Index'] = 56,
	['Owner Index'] = 7,
	['Pet TP'] = 3000,
}
assert_true(pet_tp_state.ingest(state, 0x068, 'packet-data', 7, parse_packet), 'new pet update')
assert_equal(pet_tp_state.current_tp(state, 0x100002, 56), 3000, 'new pet TP')

pet_tp_state.observe_pet(state, false, 0, 0)
assert_equal(state.tp, nil, 'pet disappearance must clear TP')

parsed_packet = {
	['Message Type'] = 0x04,
	['Pet Index'] = 56,
	['Owner Index'] = 7,
	['Pet TP'] = nil,
}
local malformed_ok = pcall(function()
	pet_tp_state.ingest(state, 0x068, 'packet-data', 7, parse_packet)
end)
assert_equal(malformed_ok, false, 'malformed current-player pet TP packet must fail fast')

print('selftest_pet_tp_state: OK')
