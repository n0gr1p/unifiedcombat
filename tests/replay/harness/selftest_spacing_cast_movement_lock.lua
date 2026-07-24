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
local hold_body = function_body(
	source,
	'function scheduler.apply_cast_movement_hold(reason, at)',
	'local function current_zone_id()'
)
local movement_body = function_body(
	source,
	'local function run_movement_coordinator_tick()',
	'local function p1_number'
)

assert_contains(hold_body, "kind = 'run_stop'", 'cast movement hold must construct run_stop intent')
assert_contains(hold_body, "source = 'unified_scheduler:cast_movement_hold'", 'cast movement hold source mismatch')
assert_contains(hold_body, "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({", 'cast movement hold must use dispatcher-owned run_stop')
assert_contains(hold_body, "_G.UC_MOVEMENT_OWNER = 'scheduler'", 'cast movement hold must claim scheduler movement ownership')
assert_contains(hold_body, "_G.UC_MOVEMENT_LOCK_UNTIL = math.max(current_lock_until, now_value + 0.6)", 'cast movement hold must refresh a bounded lock')
assert_contains(hold_body, "current_owner ~= 'nyzul_hold'", 'cast movement hold must preserve an active Nyzul hold')
assert_contains(hold_body, "'CAST_MOVEMENT_HOLD'", 'cast movement hold must publish timeline evidence')

local cast_branches = {
	{
		call = "scheduler.apply_cast_movement_hold('MOVE_COORD_CASTING_STATUS', now)",
		result = "return false, 'MOVE_COORD_CASTING_STATUS'",
	},
	{
		call = "scheduler.apply_cast_movement_hold('MOVE_COORD_CAST_FREEZE_COOLDOWN', now)",
		result = "return false, 'MOVE_COORD_CAST_FREEZE_COOLDOWN'",
	},
	{
		call = "scheduler.apply_cast_movement_hold('MOVE_COORD_CASTING_ACTION', now)",
		result = "return false, 'MOVE_COORD_CASTING_ACTION'",
	},
}
for _, branch in ipairs(cast_branches) do
	assert_contains(movement_body, branch.call, 'cast-freeze branch must stop existing movement: ' .. branch.call)
	assert_before(movement_body, branch.call, branch.result, 'cast movement stop must occur before the branch returns')
end

assert_before(
	movement_body,
	"scheduler.apply_cast_movement_hold('MOVE_COORD_CASTING_ACTION', now)",
	'combat_core.apply_movement_for_scheduler(s, movement_executor)',
	'cast movement hold must run before spacing/core movement execution'
)

io.stdout:write('selftest_spacing_cast_movement_lock: OK\n')
