package.path = './?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then
        error(message or ('expected true, got ' .. tostring(value)))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
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

local function read_all(path)
    local fh, err = io.open(path, 'rb')
    if not fh then
        error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
    end
    local source = fh:read('*a')
    fh:close()
    return source
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

local active_config = require('uc_active_config')
local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')

rawset(_G, 'UC_ACTIVE_PROFILE', {
    version = 2,
    profile = {
        schema_version = 2,
        engine = 'UC',
        character = 'Selftest',
        main_job = 'WAR',
        sub_job = 'SAM',
        source = 'SELFTEST',
    },
    config = {
        movement = {
            path = {
                hunter_targets = { 'Elemental', 'Apex Bat' },
                hunter_max_z_delta = 2.0,
                hunter_max_target_range = 20.0,
                hunter_claim_timeout_s = 4.0,
                hunter_ignore_cooldown_s = 20.0,
            },
        },
    },
})

local ok, err = pcall(function()
    local targets = active_config.get_path('config.movement.path.hunter_targets')
    assert_equal(#targets, 2, 'initial hunter target count')

    local changed, reason = active_config.append_string_list(
        'config.movement.path.hunter_targets',
        ' elemental '
    )
    assert_true(changed, 'duplicate hunter target append is a successful no-op')
    assert_equal(reason, 'ALREADY', 'duplicate hunter target reason')
    assert_equal(#targets, 2, 'duplicate hunter target must not grow list')

    changed, reason = active_config.append_string_list(
        'config.movement.path.hunter_targets',
        'Wind Cluster'
    )
    assert_true(changed, 'hunter target append should succeed')
    assert_equal(reason, 'ADDED', 'hunter target append reason')
    assert_equal(targets[3], 'Wind Cluster', 'hunter target append value')

    changed, reason = active_config.remove_string_list_index(
        'config.movement.path.hunter_targets',
        2
    )
    assert_true(changed, 'hunter target remove should succeed')
    assert_equal(reason, 'REMOVED', 'hunter target remove reason')
    assert_equal(targets[2], 'Wind Cluster', 'hunter target removal preserves order')

    changed, reason = active_config.replace_string_list(
        'config.movement.path.hunter_targets',
        { ' Apex Crab ', 'apex crab', 'Elemental' }
    )
    assert_true(changed, 'hunter target replace should succeed')
    assert_equal(reason, 'REPLACED', 'hunter target replace reason')
    assert_equal(#targets, 2, 'hunter target replace must trim/dedupe')
    assert_equal(targets[1], 'Apex Crab', 'hunter target replace first')
    assert_equal(targets[2], 'Elemental', 'hunter target replace second')

    assert_equal(#targets, 2, 'canonical hunter target count')
    assert_equal(targets[1], 'Apex Crab', 'canonical hunter target first')
    assert_equal(targets[2], 'Elemental', 'canonical hunter target second')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
if not ok then
    error(err, 0)
end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
local editor_adapter = read_all('UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs')
local path_config = read_all('uc_path_config.lua')
local core = read_all('unified_combat_core.lua')

assert_not_contains(bridge, "require('uc_path_hunter')",
    'path-hunter bridge must not use the flat settings edit helper')
assert_contains(bridge, "'config.movement.path.hunter_targets'",
    'path-hunter bridge must edit canonical Profile V2')
assert_not_contains(bridge, 's.path_hunter_targets =',
    'bridge must not assign flat path-hunter authority')
assert_contains(bridge, 'uc_apply_active_list_edit(',
    'path-hunter bridge must reuse canonical active-profile list editing')

local hunter_ui = extract(
    ui,
    '    private void OnPathHunterAdd()',
    '    private static string NormalizeTankEnmityEntry'
)
assert_not_contains(hunter_ui, 'Forward(',
    'path-hunter editor actions must not emit live bridge mutations')
assert_contains(hunter_ui, 'CaptureWorkingProfileFromUi(sid);',
    'path-hunter editor actions must capture working Profile V2')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"path_hunter_replace_names"',
    'full form push must not carry hunter durable policy to the addon')

assert_contains(writer,
    '.Add("hunter_targets", ParseNameList(ReadString(flatProfile, "path_hunter_entries", "")))',
    'WinForms writer must persist path-hunter rows into movement.path.hunter_targets')
assert_contains(editor_adapter,
    'CopyNameArrayAsEntries(profile, "path_hunter_targets", "path_hunter_entries");',
    'runtime editor adapter must reconstruct local path-hunter rows from canonical config')
assert_contains(path_config,
    'function M.hunter_targets(config)',
    'canonical path adapter must expose hunter targets')
assert_contains(path_config,
    "return clone_list(value(config, 'hunter_targets'))",
    'canonical path adapter must source hunter targets from movement.path')
assert_contains(core,
    "uc_path_hunter.matches_mob(settings, cur.name or '')",
    'runtime hunter matching remains a runtime consumer, not an editor authority')

print('selftest_phase5_path_hunter_write_pipeline: OK (canonical path-hunter list pipeline)')
