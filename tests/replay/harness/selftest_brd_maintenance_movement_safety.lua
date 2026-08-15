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
local provider_source = read_file('uc_provider_maintenance.lua')
local refresh_body = function_body(
	source,
	'function scheduler.refresh_brd_maintenance_movement_lock(reason, at)',
	'function scheduler.apply_brd_maintenance_movement_lock(action_name, target_id, reason, at)'
)
local lock_body = function_body(
	source,
	'function scheduler.apply_brd_maintenance_movement_lock(action_name, target_id, reason, at)',
	'local function current_zone_id()'
)
local lane_movement_body = function_body(
	source,
	'function scheduler.apply_brd_maintenance_lane_movement(reason, at)',
	'function scheduler.apply_cast_movement_hold(reason, at)'
)
local dispatch_body = function_body(
	source,
	'function scheduler.p1_dispatch_maintenance_brd(selected, settings)',
	'local function p1_dispatch_defensive_internal'
)

assert_contains(refresh_body, "kind = 'run_stop'", 'every Bard lane refresh must construct a run_stop intent')
assert_contains(refresh_body, "source = 'unified_scheduler:brd_maintenance_movement_lock'", 'Bard run_stop source mismatch')
assert_contains(refresh_body, "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({", 'Bard lane refresh must use dispatcher-owned run_stop')
assert_contains(refresh_body, "_G.UC_MOVEMENT_LOCK_UNTIL = math.max(current_lock_until, now_value + 0.6)", 'Bard movement lock must remain refreshed while the action lane is reserved')
assert_contains(refresh_body, "if current_owner == 'nyzul_hold' and current_lock_until > now_value then", 'Bard movement lock must not replace an active Nyzul hold')
assert_before(
	refresh_body,
	"if current_owner == 'nyzul_hold' and current_lock_until > now_value then",
	"kind = 'run_stop'",
	'Bard lane refresh must preserve an active Nyzul hold before dispatching run_stop'
)
assert_contains(lock_body, "scheduler.refresh_brd_maintenance_movement_lock(reason, now_value)", 'Bard action stop must reassert the physical and bounded lane lock')
assert_contains(lane_movement_body, "require('uc_brd_positioning')", 'Bard lane movement must consume the positioning request')
assert_contains(lane_movement_body, "source_prefix = 'scheduler_brd_positioning'", 'Bard reposition vectors must use dispatcher-owned movement')
assert_contains(lane_movement_body, "_G.UC_MOVEMENT_OWNER = 'scheduler_brd'", 'Bard reposition must publish distinct movement ownership')
assert_contains(lane_movement_body, "return scheduler.refresh_brd_maintenance_movement_lock(", 'non-running Bard positioning phases must reassert a physical stop')

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
	'scheduler.apply_brd_maintenance_lane_movement(brd_lane_reason, now_s())',
	'Bard action-lane holds must drive positioning or refresh movement stops while scheduler movement is suppressed'
)
assert_contains(provider_source, "require('uc_brd_positioning')", 'Bard maintenance provider must load the positioning planner')
assert_contains(provider_source, 'brd_positioning.prepare({', 'Bard maintenance proposals must pass through positioning readiness')
assert_contains(provider_source, "formation_status.kind == 'generic'", 'only generic formation may relax full-party song coverage')
assert_contains(provider_source, "formation_status.phase == 'active'", 'formation song coverage relaxation must require the active phase')
assert_contains(provider_source, 'allow_formation_partial = allow_formation_partial', 'Bard positioning must receive active generic-formation context')
assert_contains(provider_source, 'brd_maintenance.defer_positioning(positioning_reason)', 'waiting positioning must release the Bard action lane')
assert_contains(provider_source, 'member.x = ctx.me.x', 'Bard positioning must use the current local-player coordinates')
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
