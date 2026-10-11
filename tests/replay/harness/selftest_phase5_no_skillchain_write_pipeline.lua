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
        main_job = 'SAM',
        sub_job = 'WAR',
        source = 'SELFTEST',
    },
    config = {
        combat = {
            weaponskill = {
                no_skillchain_targets = { 'Gyre', 'Other Add' },
            },
        },
    },
})

local ok, err = pcall(function()
    local list = active_config.get_path('config.combat.weaponskill.no_skillchain_targets')
    assert_equal(#list, 2, 'initial no-skillchain list size')

    local changed, reason = active_config.append_string_list(
        'config.combat.weaponskill.no_skillchain_targets',
        ' gyre '
    )
    assert_true(changed, 'duplicate append should be a successful no-op')
    assert_equal(reason, 'ALREADY', 'duplicate no-skillchain reason')
    assert_equal(#list, 2, 'duplicate append must not grow list')

    changed, reason = active_config.append_string_list(
        'config.combat.weaponskill.no_skillchain_targets',
        'Lilith'
    )
    assert_true(changed, 'no-skillchain append should succeed')
    assert_equal(reason, 'ADDED', 'no-skillchain append reason')
    assert_equal(list[3], 'Lilith', 'no-skillchain appended name')

    changed, reason = active_config.remove_string_list_index(
        'config.combat.weaponskill.no_skillchain_targets',
        2
    )
    assert_true(changed, 'no-skillchain remove should succeed')
    assert_equal(reason, 'REMOVED', 'no-skillchain remove reason')
    assert_equal(list[2], 'Lilith', 'no-skillchain remove must preserve order')

    changed, reason = active_config.replace_string_list(
        'config.combat.weaponskill.no_skillchain_targets',
        { ' Mob A ', 'mob a', 'Mob B' }
    )
    assert_true(changed, 'no-skillchain replace should succeed')
    assert_equal(reason, 'REPLACED', 'no-skillchain replace reason')
    assert_equal(#list, 2, 'no-skillchain replace must trim/dedupe')
    assert_equal(list[1], 'Mob A', 'no-skillchain replace first')
    assert_equal(list[2], 'Mob B', 'no-skillchain replace second')

    assert_equal(list[1], 'Mob A', 'no-skillchain canonical first')
    assert_equal(list[2], 'Mob B', 'no-skillchain canonical second')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
if not ok then
    error(err, 0)
end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')

assert_not_contains(bridge, "require('uc_no_skillchain_targets')",
    'bridge must not use the flat no-skillchain settings helper')
assert_contains(bridge, "'config.combat.weaponskill.no_skillchain_targets'",
    'bridge must edit canonical no-skillchain Profile V2 policy')
assert_not_contains(bridge, 's.weaponskill_no_skillchain_targets =',
    'bridge must not assign flat no-skillchain authority')
assert_contains(bridge, 'uc_apply_active_list_edit(',
    'bridge must reuse canonical active-profile list editing')

local no_skillchain_ui = extract(
    ui,
    '    private void NoSkillchainTargetAddByName()',
    '    private void AddPriorityByName()'
)
assert_not_contains(no_skillchain_ui, 'Forward(',
    'no-skillchain editor actions must not emit live bridge mutations')
assert_contains(no_skillchain_ui, 'CaptureWorkingProfileFromUi(sid);',
    'no-skillchain editor actions must capture working Profile V2')
assert_contains(no_skillchain_ui, 'CurrentRuntimeTargetName()',
    'no-skillchain Add Current must consume runtime target observation')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"no_skillchain_target_replace_names"',
    'full form push must not carry no-skillchain durable policy to the addon')

local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
assert_contains(writer, '.Add("no_skillchain_targets", ParseNameList(ReadString(flatProfile, "no_skillchain_target_entries", "")))',
    'WinForms writer must persist no-skillchain rows into canonical Profile V2')

print('selftest_phase5_no_skillchain_write_pipeline: OK (canonical no-skillchain editor/bridge pipeline)')
