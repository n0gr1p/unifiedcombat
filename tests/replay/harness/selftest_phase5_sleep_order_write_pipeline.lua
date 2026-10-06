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
        main_job = 'BRD',
        sub_job = 'WHM',
        source = 'SELFTEST',
    },
    config = {
        sleep = {
            enabled = true,
            order = { 'Horde Lullaby II', 'Sleep II', 'Repose' },
            legacy_primary = 'Horde Lullaby II',
            max_target_range = 6.0,
        },
    },
})

local ok, err = pcall(function()
    local order = active_config.get_path('config.sleep.order')
    local sleep = active_config.get_path('config.sleep')
    assert_equal(order[1], 'Horde Lullaby II', 'initial Sleep order first')
    assert_equal(sleep.legacy_primary, 'Horde Lullaby II', 'initial Sleep primary')

    local changed, reason = active_config.replace_string_list(
        'config.sleep.order',
        { ' Sleep II ', 'sleep ii', 'Repose' }
    )
    assert_true(changed, 'Sleep replace should succeed')
    assert_equal(reason, 'REPLACED', 'Sleep replace reason')
    assert_equal(#order, 2, 'Sleep replace must trim/dedupe')
    assert_equal(order[1], 'Sleep II', 'Sleep replace first')
    assert_equal(order[2], 'Repose', 'Sleep replace second')
    assert_equal(sleep.legacy_primary, 'Sleep II', 'Sleep primary must follow replace first')

    changed, reason = active_config.append_string_list('config.sleep.order', 'Horde Lullaby II')
    assert_true(changed, 'Sleep append should succeed')
    assert_equal(reason, 'ADDED', 'Sleep append reason')
    assert_equal(order[3], 'Horde Lullaby II', 'Sleep appended value')
    assert_equal(sleep.legacy_primary, 'Sleep II', 'Sleep append must preserve primary')

    changed, reason = active_config.move_string_list_index('config.sleep.order', 3, -1)
    assert_true(changed, 'Sleep move should succeed')
    assert_equal(reason, 'MOVED', 'Sleep move reason')
    assert_equal(order[2], 'Horde Lullaby II', 'Sleep move second')
    assert_equal(sleep.legacy_primary, 'Sleep II', 'non-primary move must preserve primary')

    changed, reason = active_config.move_string_list_index('config.sleep.order', 2, -1)
    assert_true(changed, 'Sleep move-to-primary should succeed')
    assert_equal(order[1], 'Horde Lullaby II', 'Sleep moved primary')
    assert_equal(sleep.legacy_primary, 'Horde Lullaby II', 'Sleep primary must follow move')

    changed, reason = active_config.remove_string_list_index('config.sleep.order', 1)
    assert_true(changed, 'Sleep primary remove should succeed')
    assert_equal(reason, 'REMOVED', 'Sleep primary remove reason')
    assert_equal(order[1], 'Sleep II', 'Sleep next entry becomes first')
    assert_equal(sleep.legacy_primary, 'Sleep II', 'Sleep primary must follow removal')

    local projected, projection_err = active_config.project_flat_settings(
        rawget(_G, 'UC_ACTIVE_PROFILE'),
        {}
    )
    assert_true(type(projected) == 'table', 'Sleep canonical policy must project')
    assert_equal(projection_err, nil, 'Sleep projection error')
    assert_equal(projected.sleepspells[1], 'Sleep II', 'projected Sleep first')
    assert_equal(projected.sleepspell, 'Sleep II', 'projected legacy Sleep primary')

    changed, reason = active_config.replace_string_list('config.sleep.order', {})
    assert_true(changed, 'Sleep clear should succeed')
    assert_equal(reason, 'REPLACED', 'Sleep clear reason')
    assert_equal(#order, 0, 'Sleep clear list')
    assert_equal(sleep.legacy_primary, '', 'Sleep primary must clear with empty order')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
if not ok then
    error(err, 0)
end

local addon = read_all('UnifiedCombat.lua')
local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
local adapter = read_all('UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs')
local scheduler = read_all('unified_scheduler.lua')

assert_contains(addon, 'function uc_sleep_spell.validate_names(names)',
    'Sleep helper must expose validation without mutation')
assert_contains(addon, "return nil, 'SLEEP_SPELL_UNKNOWN'",
    'Sleep validation must still reject unknown spell resources')
assert_contains(addon, "res.spells:with('en', spell_name)",
    'Sleep validation must still resolve spell names against resources')

local replace_block = extract(
    bridge,
    "elseif op == 'sleep_replace_spells' then",
    "elseif op == 'path_hunter_replace_names' then"
)
assert_not_contains(replace_block, 'UC_SETTINGS',
    'Sleep replace bridge path must not mutate flat settings')
assert_contains(replace_block, 'sleep_cfg.validate_names',
    'Sleep replace bridge path must validate names before canonical edit')
assert_contains(replace_block, "'config.sleep.order'",
    'Sleep replace bridge path must edit canonical order')

local sleep_edit_block = extract(
    bridge,
    "elseif op == 'sleep_add_spell' then",
    "elseif op == 'path_hunter_add' then"
)
assert_not_contains(sleep_edit_block, 'UC_SETTINGS',
    'Sleep add/remove/move bridge paths must not mutate flat settings')
assert_contains(sleep_edit_block, 'sleep_cfg.validate_names({ name })',
    'Sleep add bridge path must validate the candidate spell')
assert_contains(sleep_edit_block, "'append_string_list'",
    'Sleep add bridge path must use canonical list editing')
assert_contains(sleep_edit_block, "'remove_string_list_index'",
    'Sleep remove bridge path must use canonical list editing')
assert_contains(sleep_edit_block, "'move_string_list_index'",
    'Sleep move bridge path must use canonical list editing')

local sleep_ui = extract(
    ui,
    '    private void SleepSpellSetOnly()',
    '    private void SaveRemote()'
)
assert_not_contains(sleep_ui, 'Forward(',
    'Sleep editor actions must not emit live bridge mutations')
assert_contains(sleep_ui, 'CaptureWorkingProfileFromUi(sid);',
    'Sleep editor actions must capture working Profile V2')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"sleep_replace_spells"',
    'full form push must not carry Sleep durable ordering to the addon')

assert_contains(writer, '.Add("order", order)',
    'structured writer must persist canonical Sleep order')
assert_contains(writer, '.Add("legacy_primary", legacyPrimary)',
    'structured writer must keep Sleep legacy primary coupled to first order entry')
assert_contains(adapter,
    'CopyNameArrayAsEntries(profile, "sleepspells", "sleep_spell_entries");',
    'editor adapter must rebuild local Sleep rows from projected canonical order')
assert_contains(scheduler, 'function scheduler.sleep_spell_list_from_config(config)',
    'runtime Sleep selection must consume canonical config')
assert_contains(scheduler, 'return uc_scheduler_config.sleep_order_from_config(config)',
    'runtime Sleep ordering must come from canonical scheduler config')

print('selftest_phase5_sleep_order_write_pipeline: OK (validated canonical Sleep ordering)')
