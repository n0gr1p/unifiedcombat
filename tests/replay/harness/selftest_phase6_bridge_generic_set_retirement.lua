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
local main_form = read_all('UnifiedCombatWinForms/MainForm.cs')
local parity = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')

assert_not_contains(bridge, 'local function apply_set(',
    'generic bridge flat writer must remain retired')
assert_not_contains(bridge, 'apply_set(',
    'bridge must contain no generic flat setter calls')
assert_not_contains(bridge, "op == 'set'",
    'bridge protocol must no longer accept generic set messages')
assert_not_contains(bridge, 'cfg_version',
    'generic-set version gate must be removed with the retired protocol')
assert_equal(count_literal(bridge, 'UC_SETTINGS'), 0,
    'remote bridge must now contain zero direct UC_SETTINGS references')
assert_equal(count_literal(bridge, 'project_flat_settings('), 1,
    'bridge must retain only the read-only active-config editor snapshot projection')
assert_equal(count_literal(bridge, 'sync_flat_settings_in_place('), 0,
    'bridge must contain no flat compatibility publication')

local runtime_gate = extract(
    main_form,
    '    private static bool IsRuntimeSessionOutboundOp(string op)',
    '    private void Forward(string sid, Dictionary<string, object?> msg)'
)
assert_not_contains(runtime_gate, '"set"',
    'WinForms runtime outbound allowlist must continue excluding generic set')
assert_contains(runtime_gate, '"start_engine"',
    'explicit runtime engine start command must remain supported')
assert_contains(runtime_gate, '"stop_engine"',
    'explicit runtime engine stop command must remain supported')
assert_contains(runtime_gate, '"addon_reload"',
    'explicit addon reload command must remain supported')
assert_contains(runtime_gate, '"camp_set"',
    'explicit camp capture command must remain supported')
assert_contains(runtime_gate, '"camp_clear"',
    'explicit camp clear command must remain supported')
assert_contains(runtime_gate, '"request_state"',
    'read-only state request must remain supported')
assert_contains(runtime_gate, '"request_options"',
    'read-only options request must remain supported')

local forward = extract(
    main_form,
    '    private void Forward(string sid, Dictionary<string, object?> msg)',
    '    private void ApplyMirrorLine(string line)'
)
assert_contains(forward, 'if (string.Equals(op, "set", StringComparison.Ordinal))',
    'local durable edit marker may remain inside WinForms Forward')
assert_contains(forward, 'CaptureWorkingProfileFromUi(sid);',
    'local generic set marker must capture the working Profile V2')
assert_contains(forward, 'return;',
    'local generic set marker must stop before outbound runtime routing')

local set_pos = assert(forward:find('if (string.Equals(op, "set", StringComparison.Ordinal))', 1, true))
local capture_pos = assert(forward:find('CaptureWorkingProfileFromUi(sid);', set_pos, true))
local runtime_gate_pos = assert(forward:find('if (!IsRuntimeSessionOutboundOp(op))', capture_pos, true))
local enqueue_pos = assert(forward:find('_mirror?.EnqueueForward(sid, msg);', runtime_gate_pos, true))
assert_true(set_pos < capture_pos and capture_pos < runtime_gate_pos and runtime_gate_pos < enqueue_pos,
    'local generic set handling must remain entirely before the outbound mirror boundary')

assert_contains(parity, '["op"] = "set"',
    'local editor handlers may continue using generic set as an internal capture signal')
assert_not_contains(bridge, 'DEF_CFG_SET_OP',
    'retired generic set diagnostics must not survive in the bridge')

print('selftest_phase6_bridge_generic_set_retirement: OK (generic bridge set protocol retired; local durable capture preserved)')
