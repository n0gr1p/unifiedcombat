local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then error(message or ('missing text: ' .. needle)) end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then error(message or ('unexpected text: ' .. needle)) end
end

local function read_all(path)
    local fh, err = io.open(path, 'rb')
    if not fh then error('failed to open ' .. tostring(path) .. ': ' .. tostring(err)) end
    local source = fh:read('*a')
    fh:close()
    return source
end

local function extract(source, start_marker, end_marker)
    local start_pos = source:find(start_marker, 1, true)
    if not start_pos then error('missing source block start: ' .. start_marker) end
    local end_pos = source:find(end_marker, start_pos + #start_marker, true)
    if not end_pos then error('missing source block end: ' .. end_marker) end
    return source:sub(start_pos, end_pos - 1)
end

local function count_literal(source, literal)
    local count = 0
    local from = 1
    while true do
        local first, last = source:find(literal, from, true)
        if not first then return count end
        count = count + 1
        from = last + 1
    end
end

local bridge = read_all('remote_bridge.lua')
local addon = read_all('UnifiedCombat.lua')
local engine = read_all('unified_engine.lua')

assert_equal(count_literal(bridge, 'UC_SETTINGS'), 0,
    'remote bridge must contain zero direct flat settings references')
assert_not_contains(bridge, 'UC_SETTINGS.engine_enabled',
    'bridge engine commands must not mirror runtime state into flat settings')

local bridge_commands = extract(
    bridge,
    "elseif op == 'toggle' and msg.key == 'Start_Engine' then",
    "elseif op == 'addon_reload' then"
)
assert_contains(bridge_commands, 'Start_Engine = not Start_Engine',
    'bridge toggle must mutate Start_Engine directly')
assert_contains(bridge_commands, 'Start_Engine = true',
    'bridge start command must mutate Start_Engine directly')
assert_contains(bridge_commands, 'Start_Engine = false',
    'bridge stop command must mutate Start_Engine directly')
assert_not_contains(bridge_commands, 'UC_SETTINGS',
    'bridge engine command block must not touch flat settings')

local domain_gate = extract(
    addon,
    'local function uc_domain_enabled(s, key)',
    'local function uc_is_combat_participant'
)
assert_contains(domain_gate, "rawget(_G, 'Start_Engine') ~= true",
    'domain engine gate must read Start_Engine live command state')
assert_not_contains(domain_gate, 'engine_enabled',
    'domain engine gate must not depend on flat engine_enabled')

assert_contains(addon, 'engine_enabled = Start_Engine == true',
    'profile contract status/default compatibility must derive engine state from live Start_Engine')
assert_not_contains(addon, 'UC_SETTINGS.engine_enabled',
    'addon must contain no direct live flat engine mirror reads or writes')

local addon_commands = extract(
    addon,
    "windower.register_event('addon command', function(...)",
    "windower.register_event('prerender'"
)
assert_contains(addon_commands, 'Start_Engine = true',
    'slash start command must set live Start_Engine')
assert_contains(addon_commands, 'Start_Engine = false',
    'slash stop command must clear live Start_Engine')
assert_not_contains(addon_commands, 'UC_SETTINGS.engine_enabled',
    'slash engine commands must not mirror live state into flat settings')

assert_contains(engine,
    "('EngineEnabled: %s'):format(tostring(rawget(_G, 'Start_Engine') == true))",
    'scheduler overlay must report live Start_Engine state')
assert_not_contains(engine, 'bool_setting(s.engine_enabled',
    'scheduler overlay must not report flat engine mirror')

print('selftest_phase6_engine_command_authority: OK (Start_Engine is sole live engine command state)')
