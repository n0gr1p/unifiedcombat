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
	'function scheduler.cast_movement_settle_blocked(selected)'
)
local settle_body = function_body(
	source,
	'function scheduler.cast_movement_settle_blocked(selected)',
	'local function current_zone_id()'
)
local movement_body = function_body(
	source,
	'local function run_movement_coordinator_tick()',
	'local function p1_number'
)
local combat_dispatch_body = function_body(
	source,
	'local function p1_dispatch_combat(selected, settings, phase, config)',
	'local function p1_dispatch_summoner_maintenance(selected, settings)'
)
local selected_dispatch_body = function_body(
	source,
	'function scheduler.dispatch_selected_plan(settings)',
	'function scheduler.process_tick(cadence)'
)

assert_contains(hold_body, "kind = 'run_stop'", 'cast movement hold must construct run_stop intent')
assert_contains(hold_body, "source = 'unified_scheduler:cast_movement_hold'", 'cast movement hold source mismatch')
assert_contains(hold_body, "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({", 'cast movement hold must use dispatcher-owned run_stop')
assert_contains(hold_body, "_G.UC_MOVEMENT_OWNER = 'scheduler'", 'cast movement hold must claim scheduler movement ownership')
assert_contains(hold_body, "_G.UC_MOVEMENT_LOCK_UNTIL = math.max(current_lock_until, now_value + 0.6)", 'cast movement hold must refresh a bounded lock')
assert_contains(hold_body, "current_owner ~= 'nyzul_hold'", 'cast movement hold must preserve an active Nyzul hold')
assert_contains(hold_body, "'CAST_MOVEMENT_HOLD'", 'cast movement hold must publish timeline evidence')

assert_contains(source, 'local CAST_MOVEMENT_SETTLE_SECONDS = 0.1', 'cast movement settle must remain 0.1 seconds')
assert_contains(settle_body, "local actor = rawget(_G, 'UC_SCHED_CAST_LOCAL_ACTOR')", 'cast settle must retain movement observation state')
assert_contains(settle_body, 'local moving = actor:is_moving() == true', 'cast settle must inspect actual player movement')
assert_contains(settle_body, 'settle_until = now + CAST_MOVEMENT_SETTLE_SECONDS', 'movement observation must refresh the settle deadline')
assert_contains(settle_body, "scheduler.apply_cast_movement_hold('MOVE_COORD_CAST_SETTLE', now)", 'cast settle must stop scheduler movement')
assert_contains(settle_body, "return true, 'BLOCK_SCHED_CAST_MOVEMENT_SETTLE'", 'cast settle must defer spell dispatch')
assert_before(
	selected_dispatch_body,
	'scheduler.cast_movement_settle_blocked(selected)',
	"if provider == 'combat' or provider == 'encounter_kei' or provider == 'encounter_saved_by_bell' then",
	'all scheduler spell providers must pass through movement settle before dispatch'
)
if combat_dispatch_body:find('COMBAT_SPELL_SETTLE', 1, true)
	or combat_dispatch_body:find('COMBAT_SPELL_PREP_WAIT', 1, true) then
	error('combat dispatch must not retain the stale spell/target-keyed prep gate')
end

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
	'combat_core.apply_movement_for_scheduler(s, movement_executor, get_tick_ctx().config)',
	'cast movement hold must run before spacing/core movement execution'
)

io.stdout:write('selftest_spacing_cast_movement_lock: OK\n')
