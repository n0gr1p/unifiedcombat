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

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ('unexpected: ' .. tostring(needle)))
    end
end

local runtime_parse = read_file('tests/replay/harness/selftest_runtime_parse.lua')
local block = runtime_parse:match('local RUNTIME_LUA_FILES%s*=%s*{(.-)\n}')
if not block then
    error('could not parse runtime file list')
end

assert_contains(block, '"uc_time.lua"', 'canonical runtime clock must be parse-checked')

for path in block:gmatch('["\']([^"\']+%.lua)["\']') do
    if path ~= 'uc_time.lua' then
        local source = read_file(path)
        assert_not_contains(source, 'os.clock(', path .. ' must not use os.clock for runtime timing')
        assert_not_contains(source, "rawget(_G, 'socket')", path .. ' must not acquire the timing source directly')
        if source:match('socket%.gettime%s*%(') then
            error(path .. ' must route socket.gettime calls through uc_time')
        end
        if source:match('socket_mod%.gettime%s*%(') then
            error(path .. ' must route socket_mod.gettime calls through uc_time')
        end
        if source:match('%f[%w]s%.gettime%s*%(') then
            error(path .. ' must route s.gettime calls through uc_time')
        end
        for line in source:gmatch('[^\r\n]+') do
            local alias_assignment = line:match('^%s*local%s+socket_gettime%s*=')
                or line:match('^%s*socket_gettime%s*=')
            if alias_assignment and not line:find('uc_time.gettime', 1, true) then
                error(path .. ' socket_gettime alias must be sourced from uc_time')
            end
        end
    end
end

local clock = read_file('uc_time.lua')
assert_contains(clock, "pcall(require, 'socket')", 'uc_time must own LuaSocket timing acquisition')
assert_contains(clock, 'M.gettime', 'uc_time must expose availability-compatible gettime')
assert_contains(clock, 'function M.available()', 'uc_time must expose availability state')
assert_contains(clock, 'function M.now()', 'uc_time must expose canonical now()')

local agents = read_file('AGENTS.md')
assert_contains(agents, 'Canonical runtime time source', 'agent instructions must document the one-clock rule')
assert_contains(agents, 'uc_time.now()', 'agent instructions must name the canonical runtime clock API')

local core = read_file('unified_combat_core.lua')
assert_contains(core, "local uc_time = require('uc_time')", 'core must import canonical clock')
assert_contains(core, 'now = uc_time.now', 'skillchain runtime must use canonical clock')
assert_not_contains(core, 'os.clock(', 'skillchain runtime must not use os.clock')

local burst = read_file('uc_combat_extensions.lua')
assert_contains(burst, 'local remaining = mb_expires - (tonumber(ctx.now) or 0)', 'MB window must compare same-domain runtime timestamps')

io.stdout:write('selftest_time_source_contract: OK\n')
