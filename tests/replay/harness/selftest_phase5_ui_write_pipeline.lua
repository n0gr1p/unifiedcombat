local function read_all(path)
    local fh, err = io.open(path, 'rb')
    if not fh then
        error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
    end
    local source = fh:read('*a')
    fh:close()
    return source
end

local function assert_true(value, message)
    if value ~= true then
        error(message or ('expected true, got ' .. tostring(value)))
    end
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then
        error(message or ('missing text: ' .. needle))
    end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then
        error(message or ('unexpected text: ' .. needle))
    end
end

local function extract(source, start_marker, end_marker)
    local start_pos = source:find(start_marker, 1, true)
    if not start_pos then
        error('missing source block start: ' .. start_marker)
    end
    local end_pos = source:find(end_marker, start_pos + #start_marker, true)
    if not end_pos then
        error('missing source block end: ' .. end_marker)
    end
    return source:sub(start_pos, end_pos - 1)
end

local main_form = read_all('UnifiedCombatWinForms/MainForm.cs')
local parity = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer_tests = read_all('UnifiedCombatWinForms/StructuredProfileV2WriterTests.cs')

local runtime_gate = extract(
    main_form,
    '    private static bool IsRuntimeSessionOutboundOp(string op)',
    '    private void Forward(string sid, Dictionary<string, object?> msg)'
)

assert_contains(runtime_gate, '"start_engine"', 'runtime gate must keep explicit engine start')
assert_contains(runtime_gate, '"stop_engine"', 'runtime gate must keep explicit engine stop')
assert_contains(runtime_gate, '"addon_reload"', 'runtime gate must keep explicit addon reload')
assert_contains(runtime_gate, '"camp_set"', 'runtime gate must keep explicit camp capture')
assert_contains(runtime_gate, '"camp_clear"', 'runtime gate must keep explicit camp clear')
assert_contains(runtime_gate, '"request_state"', 'runtime gate must keep state request')
assert_contains(runtime_gate, '"request_options"', 'runtime gate must keep option request')
assert_not_contains(runtime_gate, '"set"', 'generic set must never be classified as live runtime traffic')

local forward = extract(
    main_form,
    '    private void Forward(string sid, Dictionary<string, object?> msg)',
    '    private void ApplyMirrorLine(string line)'
)

assert_contains(
    forward,
    'if (string.Equals(op, "set", StringComparison.Ordinal))',
    'Forward must explicitly classify generic set as a durable editor mutation'
)
assert_contains(
    forward,
    'CaptureWorkingProfileFromUi(sid);',
    'generic set must update the per-session working profile'
)
assert_contains(
    forward,
    'if (!IsRuntimeSessionOutboundOp(op))',
    'non-runtime traffic must remain blocked after durable edit handling'
)
assert_contains(
    forward,
    '_mirror?.EnqueueForward(sid, msg);',
    'explicit runtime/session operations must still reach the mirror'
)

local durable_pos = assert(forward:find('if (string.Equals(op, "set", StringComparison.Ordinal))', 1, true))
local capture_pos = assert(forward:find('CaptureWorkingProfileFromUi(sid);', durable_pos, true))
local runtime_gate_pos = assert(forward:find('if (!IsRuntimeSessionOutboundOp(op))', capture_pos, true))
local enqueue_pos = assert(forward:find('_mirror?.EnqueueForward(sid, msg);', runtime_gate_pos, true))
assert_true(durable_pos < capture_pos and capture_pos < runtime_gate_pos and runtime_gate_pos < enqueue_pos,
    'durable set handling must return before the live mirror enqueue boundary')

assert_contains(
    parity,
    '["op"] = "set"',
    'legacy generic set emitters should remain centrally classified until their handler-by-handler cleanup slice'
)
assert_contains(
    writer_tests,
    'durable range controls must not emit live bridge traffic',
    'existing durable editor tests must continue to distinguish local edits from runtime traffic'
)
assert_contains(
    writer_tests,
    'UI save must not send a runtime save command',
    'Profile V2 Save must remain file-only'
)

print('selftest_phase5_ui_write_pipeline: OK (generic set => local working Profile V2; runtime ops stay explicit)')
