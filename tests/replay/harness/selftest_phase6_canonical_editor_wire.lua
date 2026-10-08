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
local adapter = read_all('UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs')
local canonical = read_all('UnifiedCombatWinForms/CanonicalRuntimeEditorProjection.cs')
local adapter_tests = read_all('UnifiedCombatWinForms/RuntimeProfileEditorAdapterTests.cs')

assert_equal(count_literal(bridge, 'project_flat_settings('), 0,
    'remote bridge must contain no canonical-to-flat projection')
assert_equal(count_literal(bridge, 'UC_SETTINGS'), 0,
    'remote bridge must remain independent from flat settings')
assert_contains(bridge, 'st.active_config = active_profile',
    'bridge state snapshot must publish canonical active Profile V2 directly')
assert_not_contains(bridge, 'active_settings.Start_Engine',
    'runtime engine state must not be injected into canonical active config')
assert_contains(bridge, 'Start_Engine = Start_Engine',
    'runtime engine state must remain on the surrounding session snapshot')

assert_contains(adapter, 'CanonicalRuntimeEditorProjection.Project(activeConfig)',
    'WinForms adapter must project canonical runtime config locally')
assert_contains(adapter, '"Start_Engine"',
    'WinForms adapter must hydrate runtime engine state from session snapshot')
assert_contains(adapter, '"engine"',
    'WinForms adapter must hydrate runtime engine identity from session snapshot')

assert_contains(canonical, 'if (root["config"] is not JsonObject config)',
    'canonical projector must recognize full Profile V2 payloads')
assert_contains(canonical, 'return (JsonObject)root.DeepClone();',
    'canonical projector must retain temporary legacy projected-snapshot compatibility')
assert_contains(canonical, '("follow.party.leader_name", "party_follow_leader_name")',
    'canonical projector must translate durable party-follow identity')
assert_contains(canonical, '("follow.partner.names", "partner_names")',
    'canonical projector must translate durable partner names')
assert_contains(canonical, '("maintenance.cor.range_selected", "cor_roll_range_selected")',
    'canonical projector must translate durable COR range names')
assert_contains(canonical, 'ProjectOwnership(config, editor);',
    'canonical projector must project canonical ownership gates')
assert_contains(canonical, 'ProjectMovementComplex(config, editor);',
    'canonical projector must project complex movement/formation state')
assert_contains(canonical, 'ProjectScholarComplex(config, editor);',
    'canonical projector must project Scholar editor state')
assert_not_contains(canonical, 'UC_SETTINGS',
    'WinForms canonical projector must not introduce addon flat-settings coupling')

assert_contains(adapter_tests, 'BuildCanonicalActiveProfile()',
    'WinForms reconnect tests must use a canonical Profile V2 fixture')
assert_contains(adapter_tests, 'TestLegacyProjectedSnapshotStillLoads()',
    'WinForms must retain bounded transition compatibility for older addon snapshots')
assert_contains(adapter_tests, 'StructuredProfileV2Writer.BuildStructuredProfileFile(',
    'canonical runtime editor projection must be round-tripped through the durable writer')

print('selftest_phase6_canonical_editor_wire: OK (canonical bridge payload + local WinForms editor projection)')
