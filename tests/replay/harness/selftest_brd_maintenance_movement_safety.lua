local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local text = fh:read('*a')
	fh:close()
	return text
end

local function function_body(source, signature, next_marker)
	local start_at = assert(source:find(signature, 1, true), 'missing function: ' .. signature)
	local end_at = assert(source:find(next_marker, start_at + #signature, true), 'missing function boundary: ' .. next_marker)
	return source:sub(start_at, end_at - 1)
end

local function assert_contains(text, needle, message)
	if not text:find(needle, 1, true) then
		error(message or ('missing expected text: ' .. needle))
	end
end

local function assert_before(text, first, second, message)
	local first_at = assert(text:find(first, 1, true), 'missing ordering token: ' .. first)
	local second_at = assert(text:find(second, 1, true), 'missing ordering token: ' .. second)
	if first_at >= second_at then
		error(message or (first .. ' must precede ' .. second))
	end
end

local source = read_file('unified_scheduler.lua')
local brd_source = read_file('uc_brd_maintenance.lua')
local lock_body = function_body(
	source,
	'function scheduler.apply_brd_maintenance_movement_lock(action_name, target_id, reason, at)',
	'local function current_zone_id()'
)
local dispatch_body = function_body(
	source,
	'function scheduler.p1_dispatch_maintenance_brd(selected, settings)',
	'local function p1_dispatch_defensive_internal'
)

assert_contains(lock_body, "kind = 'run_stop'", 'Bard maintenance movement lock must construct run_stop intent')
assert_contains(lock_body, "source = 'unified_scheduler:brd_maintenance_movement_lock'", 'Bard run_stop source mismatch')
assert_contains(lock_body, "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({", 'Bard movement lock must use dispatcher-owned run_stop')
assert_contains(lock_body, "scheduler.refresh_brd_maintenance_movement_lock(reason, now_value)", 'Bard action stop must claim the bounded movement lock')
assert_contains(source, "function scheduler.refresh_brd_maintenance_movement_lock(reason, at)", 'Bard lane movement-lock refresh helper missing')
assert_contains(source, "_G.UC_MOVEMENT_LOCK_UNTIL = math.max(current_lock_until, now_value + 0.6)", 'Bard movement lock must remain refreshed while the action lane is reserved')
assert_contains(source, "if current_owner == 'nyzul_hold' and current_lock_until > now_value then", 'Bard movement lock must not replace an active Nyzul hold')

assert_contains(dispatch_body, 'scheduler.apply_brd_maintenance_movement_lock(', 'Bard dispatch must stop movement')
assert_before(
	dispatch_body,
	'scheduler.apply_brd_maintenance_movement_lock(',
	'local blocked, block_reason = action_dispatch_blocked()',
	'Bard movement must stop even when an existing action temporarily blocks song dispatch'
)
assert_before(
	dispatch_body,
	'scheduler.apply_brd_maintenance_movement_lock(',
	"kind = 'send_command'",
	'Bard movement must stop before the song or setup command is dispatched'
)
assert_contains(
	source,
	'scheduler.refresh_brd_maintenance_movement_lock(brd_lane_reason, now_s())',
	'Bard action-lane holds must refresh movement ownership while scheduler movement is suppressed'
)
assert_contains(source, "'BRD_MOVEMENT_HOLD'", 'Bard movement stops must be visible in the action timeline')
assert_contains(brd_source, "local PIANISSIMO_CONFIRM_TIMEOUT_S = 2.0", 'Pianissimo confirmation must have a bounded late-packet window')
assert_contains(brd_source, "block('pianissimo_confirmation_pending_recast:' .. member.name)", 'consumed Pianissimo recast must retain the targeted transaction')
assert_contains(brd_source, 'state.targeted_transaction.pianissimo_dispatched_at = dispatched_at', 'Pianissimo retry planning must retain evidence from the last actual dispatch')
assert_contains(brd_source, 'local last_dispatch_at = tonumber(transaction.pianissimo_dispatched_at)', 'undispatched Pianissimo retries must preserve the original confirmation window')
assert_contains(brd_source, "if type(state.targeted_transaction) == 'table' or state.pianissimo_consumed_wait then", 'active Pianissimo transactions must receive atomic planner priority')
assert_before(
	brd_source,
	"if type(state.targeted_transaction) == 'table' or state.pianissimo_consumed_wait then",
	'local urgent, remaining, urgent_recipient, urgent_blocker = urgent_song(',
	'active Pianissimo transactions must continue before ordinary Bard maintenance planning'
)

io.stdout:write('selftest_brd_maintenance_movement_safety: OK\n')
