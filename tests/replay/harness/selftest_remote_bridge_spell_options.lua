local function read_file(path)
    local f = assert(io.open(path, 'r'))
    local text = f:read('*a')
    f:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ('missing: ' .. tostring(needle)))
    end
end

local bridge = read_file('remote_bridge.lua')
local scheduler = read_file('unified_scheduler.lua')

assert_contains(bridge, "local jp = type(p.job_points) == 'table' and p.job_points or nil", 'bridge must read job points for spell capability')
assert_contains(bridge, "jp_spent = tonumber(row and row.jp_spent) or 0", 'bridge must read current main-job JP spent')
assert_contains(bridge, "main_lvl >= req_main or jp_spent >= req_main", 'bridge must admit main-job JP-gift spells')
assert_contains(bridge, "sub_lvl >= req_sub", 'bridge must keep subjob eligibility level-only')
assert_contains(bridge, "table.concat({ main_job, sub_job, level_sync, tostring(jp_spent) }, '|')", 'spell option cache signature must change when main-job JP spent changes')

assert_contains(scheduler, "main_lvl >= req_main or jp_spent >= req_main", 'scheduler and bridge spell capability semantics must stay aligned')
assert_contains(scheduler, "sub_lvl >= req_sub", 'scheduler and bridge subjob semantics must stay aligned')

io.stdout:write('selftest_remote_bridge_spell_options: OK\n')
