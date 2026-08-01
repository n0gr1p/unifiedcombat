local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local text = fh:read('*a')
	fh:close()
	return text
end

local function assert_contains(text, needle, label)
	if not text:find(needle, 1, true) then
		error((label or 'missing expected text') .. ': ' .. needle)
	end
end

local function assert_not_contains(text, needle, label)
	if text:find(needle, 1, true) then
		error((label or 'unexpected text') .. ': ' .. needle)
	end
end

local scheduler_source = read_file('unified_scheduler.lua')
local party_source = read_file('uc_scheduler_party_state.lua')

assert_contains(
	scheduler_source,
	"require('uc_scheduler_party_state').maybe_broadcast(",
	'scheduler broadcast wrapper must use extracted party state'
)
assert_contains(
	scheduler_source,
	"require('uc_scheduler_party_state').apply_message(",
	'scheduler IPC receive wrapper must use extracted party state'
)
assert_contains(
	scheduler_source,
	"require('uc_scheduler_party_state').get_entry(",
	'scheduler party lookup wrapper must use extracted party state'
)
assert_contains(
	party_source,
	'function M.encode_payload(player, zone_id, now)',
	'party module must own payload encoding'
)
assert_contains(
	party_source,
	"require_function(deps, 'send_ipc_message')(payload)",
	'party module must own IPC emission'
)
assert_not_contains(
	scheduler_source,
	'windower.send_ipc_message(payload)',
	'scheduler must not directly emit party-state IPC'
)
assert_not_contains(
	scheduler_source,
	"local PARTY_STATE_IPC_PREFIX = 'ucps'",
	'scheduler must not own the party protocol prefix'
)

io.stdout:write('selftest_scheduler_party_state_static: OK\n')
