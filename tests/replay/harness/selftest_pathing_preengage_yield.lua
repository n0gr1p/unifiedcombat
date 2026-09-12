local f = assert(io.open('uc_pathing.lua', 'rb'))
local source = f:read('*a')
f:close()

local tick_follow = source:match('local function tick_follow%(settings%)(.-)function mod%.tick%(%s*%)')
assert(type(tick_follow) == 'string', 'failed to capture uc_pathing tick_follow')

assert(
    tick_follow:find("local preengage_pause = (why == 'PREENGAGE')", 1, true),
    'PREENGAGE must be classified as a yield-only path pause'
)
assert(
    tick_follow:find("local combat_transition_pause = (why:find('^COMBAT_TRANSITION:', 1, false) ~= nil)", 1, true),
    'combat transition pauses must be classified as yield-only'
)
assert(
    tick_follow:find('local yield_only = owner_pause or pull_approach_pause or preengage_pause or combat_transition_pause', 1, true),
    'pathing yield-only arbitration must include preengage and combat transitions'
)
assert(
    tick_follow:find('if not yield_only then', 1, true),
    'pathing must gate stop_move behind the yield-only check'
)

local yield_gate = tick_follow:match('(local yield_only.-follow_pause_reason)')
assert(type(yield_gate) == 'string', 'failed to capture pathing yield gate')
assert(
    yield_gate:find('if not yield_only then%s*stop_move%(%s*%)'),
    'pathing may only stop movement when the combat pause is not yield-only'
)

local stop_move = source:match('local function stop_move%(%)(.-)local function run_to_point')
assert(type(stop_move) == 'string', 'failed to capture uc_pathing stop_move')
assert(
    stop_move:find("if tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or '') ~= 'path' then", 1, true),
    'pathing stop_move must refuse to stop movement owned by another subsystem'
)
assert(
    stop_move:find('return false', 1, true),
    'pathing stop_move must return without dispatching a stop when path does not own movement'
)
local ownership_guard_pos = stop_move:find("if tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or '') ~= 'path' then", 1, true)
local dispatcher_stop_pos = stop_move:find('movement_dispatcher.stop()', 1, true)
assert(
    ownership_guard_pos and dispatcher_stop_pos and ownership_guard_pos < dispatcher_stop_pos,
    'path ownership guard must execute before movement_dispatcher.stop()'
)
assert(
    stop_move:find("_G.UC_MOVEMENT_OWNER = 'none'", 1, true),
    'path-owned stop must release movement ownership'
)
assert(
    stop_move:find('_G.UC_MOVEMENT_LOCK_UNTIL = uc_now_s()', 1, true),
    'path-owned stop must release the movement lock immediately'
)
assert(
    stop_move:find('return true', 1, true),
    'path-owned stop must report that a stop was executed'
)

io.stdout:write('selftest_pathing_preengage_yield: OK\n')
