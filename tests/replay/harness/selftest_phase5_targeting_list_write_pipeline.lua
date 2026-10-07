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
        main_job = 'PLD',
        sub_job = 'WAR',
        source = 'SELFTEST',
    },
    config = {
        targeting = {
            target_ignore_names = { 'Ignore One' },
            targets = { 'Priority One', 'Priority Two' },
        },
    },
})

local ok, err = pcall(function()
    local changed, reason = active_config.replace_string_list(
        'config.targeting.target_ignore_names',
        { ' Mob A ', 'mob a', '', 'Mob B' }
    )
    assert_true(changed, 'target-ignore replace should succeed')
    assert_equal(reason, 'REPLACED', 'target-ignore replace reason')
    local ignored = active_config.get_path('config.targeting.target_ignore_names')
    assert_equal(#ignored, 2, 'target-ignore replace must trim/dedupe names')
    assert_equal(ignored[1], 'Mob A', 'target-ignore first name')
    assert_equal(ignored[2], 'Mob B', 'target-ignore second name')

    changed, reason = active_config.append_string_list('config.targeting.target_ignore_names', 'mob b')
    assert_true(changed, 'duplicate target-ignore append is a successful no-op')
    assert_equal(reason, 'ALREADY', 'target-ignore duplicate reason')
    assert_equal(#ignored, 2, 'duplicate target-ignore append must not grow list')

    changed, reason = active_config.append_string_list('config.targeting.target_ignore_names', 'Mob C')
    assert_true(changed, 'target-ignore append should succeed')
    assert_equal(reason, 'ADDED', 'target-ignore append reason')
    assert_equal(ignored[3], 'Mob C', 'target-ignore appended name')

    changed, reason = active_config.remove_string_list_index('config.targeting.target_ignore_names', 2)
    assert_true(changed, 'target-ignore remove should succeed')
    assert_equal(reason, 'REMOVED', 'target-ignore remove reason')
    assert_equal(ignored[2], 'Mob C', 'target-ignore remove must preserve order')

    changed, reason = active_config.replace_string_list(
        'config.targeting.targets',
        { 'Apex Bat', 'Apex Crab', 'apex bat' }
    )
    assert_true(changed, 'add-priority replace should succeed')
    assert_equal(reason, 'REPLACED', 'add-priority replace reason')
    local priorities = active_config.get_path('config.targeting.targets')
    assert_equal(#priorities, 2, 'add-priority replace must dedupe case-insensitively')
    assert_equal(priorities[1], 'Apex Bat', 'priority first')
    assert_equal(priorities[2], 'Apex Crab', 'priority second')

    changed, reason = active_config.move_string_list_index('config.targeting.targets', 2, -1)
    assert_true(changed, 'add-priority move should succeed')
    assert_equal(reason, 'MOVED', 'add-priority move reason')
    assert_equal(priorities[1], 'Apex Crab', 'priority move first')
    assert_equal(priorities[2], 'Apex Bat', 'priority move second')

    local projected, projection_err = active_config.project_flat_settings(
        rawget(_G, 'UC_ACTIVE_PROFILE'),
        {}
    )
    assert_true(type(projected) == 'table', 'canonical targeting lists must project to compatibility settings')
    assert_equal(projection_err, nil, 'targeting list projection error')
    assert_equal(projected.target_ignore_names[1], 'Mob A', 'target-ignore compatibility projection')
    assert_equal(projected.add_priority_names[1], 'Apex Crab', 'add-priority compatibility projection')
    assert_equal(projected.targets[1], 'Apex Crab', 'legacy targets compatibility projection')
end)
rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
if not ok then
    error(err, 0)
end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')

assert_not_contains(bridge, "require('uc_target_ignore')",
    'target-ignore bridge must not use the flat settings helper')
assert_not_contains(bridge, "require('uc_add_priority')",
    'add-priority bridge must not use the flat settings helper')
assert_contains(bridge, "'config.targeting.target_ignore_names'",
    'target-ignore bridge must edit canonical Profile V2')
assert_contains(bridge, "'config.targeting.targets'",
    'add-priority bridge must edit durable canonical targeting.targets')
assert_not_contains(bridge, 's.target_ignore_names =',
    'bridge must not assign flat target-ignore authority')
assert_not_contains(bridge, 's.add_priority_names =',
    'bridge must not assign flat add-priority authority')
assert_not_contains(bridge, 'uc_sync_active_config_flat_projection',
    'Phase 6 bridge edits must not republish canonical durable policy into flat settings')
assert_not_contains(bridge, 'sync_flat_settings_in_place(',
    'Phase 6 bridge edit path must contain no flat compatibility publication')
assert_contains(bridge, 'current_target_name = current_target_name',
    'remote state must expose current target name as runtime observation')
assert_contains(bridge, 'current_target_id = current_target_id',
    'remote state must expose current target id as runtime observation')

local target_ignore_ui = extract(
    ui,
    '    private void TargetIgnAddByName()',
    '    private void NoSkillchainTargetAddByName()'
)
assert_not_contains(target_ignore_ui, 'Forward(',
    'target-ignore editor actions must not emit live bridge mutations')
assert_contains(target_ignore_ui, 'CaptureWorkingProfileFromUi(sid);',
    'target-ignore editor actions must capture working Profile V2')
assert_contains(target_ignore_ui, 'CurrentRuntimeTargetName()',
    'target-ignore Add Current must consume runtime observation')

local add_priority_ui = extract(
    ui,
    '    private void AddPriorityByName()',
    '    private void SleepSpellSetOnly()'
)
assert_not_contains(add_priority_ui, 'Forward(',
    'add-priority editor actions must not emit live bridge mutations')
assert_contains(add_priority_ui, 'CaptureWorkingProfileFromUi(sid);',
    'add-priority editor actions must capture working Profile V2')
assert_contains(add_priority_ui, 'CurrentRuntimeTargetName()',
    'add-priority Add Current must consume runtime observation')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"target_ignore_replace_names"',
    'full form push must not carry target-ignore durable policy to the addon')
assert_not_contains(full_push, '"add_priority_replace_names"',
    'full form push must not carry add-priority durable policy to the addon')

print('selftest_phase5_targeting_list_write_pipeline: OK (target-ignore + add-priority canonical write pipeline)')
