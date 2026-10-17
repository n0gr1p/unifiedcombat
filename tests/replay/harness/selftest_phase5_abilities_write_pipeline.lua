package.path = './?.lua;' .. package.path

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
        abilities = {
            enabled = true,
            allow_unengaged = false,
            configured = { 'Sentinel', 'Rampart', 'Provoke' },
            legacy_slots = { 'Warcry', 'Berserk' },
            wsabilities = {},
        },
    },
})

local ok, err = pcall(function()
    local configured = active_config.get_path('config.abilities.configured')
    local changed, reason = active_config.replace_string_list(
        'config.abilities.configured',
        { ' Sentinel ', 'sentinel', 'Rampart', 'Provoke', 'Holy Circle', 'Shield Bash', 'Invincible', 'Cover' }
    )
    assert_true(changed, 'ability replace should succeed')
    assert_equal(reason, 'REPLACED', 'ability replace reason')
    assert_equal(#configured, 7, 'configured abilities must trim/dedupe case-insensitively')
    assert_equal(configured[1], 'Sentinel', 'configured ability 1')
    assert_equal(configured[7], 'Cover', 'configured ability 7')

    assert_equal(#configured, 7, 'canonical abilities list must preserve all configured entries')
    assert_equal(configured[1], 'Sentinel', 'canonical ability 1')
    assert_equal(configured[2], 'Rampart', 'canonical ability 2')
    assert_equal(configured[6], 'Invincible', 'canonical ability 6')
    assert_equal(configured[7], 'Cover', 'canonical ability beyond legacy slot count')

    changed, reason = active_config.replace_string_list('config.abilities.configured', {})
    assert_true(changed, 'ability clear should succeed')
    assert_equal(reason, 'REPLACED', 'ability clear reason')

    assert_equal(#configured, 0, 'canonical configured ability list must clear')
    local legacy_slots = active_config.get_path('config.abilities.legacy_slots')
    assert_equal(legacy_slots[1], 'Warcry', 'legacy compatibility slot 1 remains canonical compatibility data')
    assert_equal(legacy_slots[2], 'Berserk', 'legacy compatibility slot 2 remains canonical compatibility data')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
if not ok then error(err, 0) end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
local adapter = read_all('UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs')
local pipeline = read_all('uc_ability_pipeline.lua')
local core = read_all('unified_combat_core.lua')

local bridge_block = extract(
    bridge,
    "elseif op == 'set_abilities' then",
    "elseif op == 'tank_enmity_replace_actions' then"
)
assert_not_contains(bridge_block, 'UC_SETTINGS',
    'set_abilities bridge path must not mutate flat settings')
assert_contains(bridge_block, "'replace_string_list'",
    'set_abilities bridge path must use canonical list editing')
assert_contains(bridge_block, "'config.abilities.configured'",
    'set_abilities bridge path must edit canonical configured abilities')

local ability_ui = extract(
    ui,
    '    private void SendAbilitiesUpdate()',
    '    private void IgnoreAddByName()'
)
assert_not_contains(ability_ui, '"set_abilities"',
    'WinForms ability edits must not emit live set_abilities traffic')
assert_not_contains(ability_ui, 'Forward(',
    'WinForms ability edit helper must remain local-only')
assert_contains(ability_ui, 'CaptureWorkingProfileFromUi(sid);',
    'WinForms ability edits must capture working Profile V2')

assert_contains(writer, '.Add("configured", configured)',
    'structured writer must persist abilities_selected to canonical configured')
assert_contains(writer, '.Add("legacy_slots", EmptyList())',
    'new structured profiles must not duplicate configured abilities into canonical legacy slots')
assert_contains(adapter,
    'CopyStringArrayAsPipe(profile, "abilities", "abilities_selected");',
    'editor adapter must rebuild ability selections from canonical projection')
assert_contains(pipeline, 'local configured = type(abilities.configured)',
    'runtime ability pipeline must consume canonical configured list')
assert_contains(pipeline, "if #out == 0 then",
    'runtime ability pipeline must retain canonical legacy-slot fallback')
assert_contains(core, 'view.abilities = abilities.configured or {}',
    'scheduler-facing runtime view must consume canonical configured abilities')

print('selftest_phase5_abilities_write_pipeline: OK (canonical abilities + projected legacy slots)')
