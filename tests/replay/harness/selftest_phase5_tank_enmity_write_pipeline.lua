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
        tank = {
            enabled = true,
            enmity = {
                actions = { 'ja:Provoke', 'spell:Flash' },
                include_pets = false,
            },
        },
    },
})

local ok, err = pcall(function()
    local actions = active_config.get_path('config.tank.enmity.actions')
    assert_equal(#actions, 2, 'initial tank enmity action count')

    local changed, reason = active_config.replace_string_list(
        'config.tank.enmity.actions',
        { ' ja:Provoke ', 'JA:provoke', 'spell:Flash', 'Provoke' }
    )
    assert_true(changed, 'tank enmity replace should succeed')
    assert_equal(reason, 'REPLACED', 'tank enmity replace reason')
    assert_equal(#actions, 3, 'full-entry dedupe must preserve typed-vs-bare distinction')
    assert_equal(actions[1], 'ja:Provoke', 'typed JA entry')
    assert_equal(actions[2], 'spell:Flash', 'typed spell entry')
    assert_equal(actions[3], 'Provoke', 'legacy bare entry must remain distinct')

    changed, reason = active_config.move_string_list_index('config.tank.enmity.actions', 2, -1)
    assert_true(changed, 'tank enmity move should succeed')
    assert_equal(reason, 'MOVED', 'tank enmity move reason')
    assert_equal(actions[1], 'spell:Flash', 'tank enmity move first')
    assert_equal(actions[2], 'ja:Provoke', 'tank enmity move second')

    changed, reason = active_config.remove_string_list_index('config.tank.enmity.actions', 3)
    assert_true(changed, 'tank enmity remove should succeed')
    assert_equal(reason, 'REMOVED', 'tank enmity remove reason')
    assert_equal(#actions, 2, 'tank enmity remove count')

    assert_equal(actions[1], 'spell:Flash', 'canonical typed spell entry')
    assert_equal(actions[2], 'ja:Provoke', 'canonical typed JA entry')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
if not ok then
    error(err, 0)
end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
local adapter = read_all('UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs')
local core = read_all('unified_combat_core.lua')
local provider = read_all('uc_provider_tank_enmity.lua')

local bridge_block = extract(
    bridge,
    "elseif op == 'tank_enmity_replace_actions' then",
    "elseif op == 'ignore_replace_names' then"
)
assert_not_contains(bridge_block, 'UC_SETTINGS',
    'tank-enmity bridge path must not mutate flat settings')
assert_contains(bridge_block, "'replace_string_list'",
    'tank-enmity bridge path must use canonical list editing')
assert_contains(bridge_block, "'config.tank.enmity.actions'",
    'tank-enmity bridge path must edit canonical actions')

local ui_block = extract(
    ui,
    '    private static string NormalizeTankEnmityEntry',
    '	private void OnCampSet()'
)
assert_not_contains(ui_block, 'Forward(',
    'tank-enmity editor actions must not emit live bridge mutations')
assert_not_contains(ui_block, 'PushTankEnmityActions',
    'retired tank-enmity live push helper must be removed')
assert_contains(ui_block, 'return n.Length == 0 ? "" : $"{t}:{n}";',
    'WinForms must preserve explicit type:name entry structure')
assert_contains(ui_block, 'CaptureWorkingProfileFromUi(sid);',
    'tank-enmity editor actions must capture working Profile V2')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"tank_enmity_replace_actions"',
    'full form push must not carry tank-enmity durable policy to the addon')

assert_contains(writer,
    '.Add("actions", SplitPipeList(ReadString(flatProfile, "tank_enmity_actions", "")))',
    'structured writer must persist tank-enmity actions into canonical config')
assert_contains(adapter,
    'CopyStringArrayAsPipe(profile, "tank_enmity_actions", "tank_enmity_actions");',
    'runtime editor adapter must rebuild tank-enmity editor state from canonical projection')

assert_contains(core, "local k, n = raw:match('^(%a+)%s*:%s*(.+)$')",
    'runtime tank parser must preserve explicit type:name parsing')
assert_contains(core, "if kind ~= 'ja' and kind ~= 'spell' then",
    'runtime tank parser must preserve legacy bare-name type inference')
assert_contains(provider, 'scheduler_config.tank_enmity_actions_from_config(config)',
    'tank-enmity provider must consume canonical actions directly')

print('selftest_phase5_tank_enmity_write_pipeline: OK (canonical typed tank-enmity action pipeline)')
