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

local previous_windower = rawget(_G, 'windower')
local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')

rawset(_G, 'windower', {
    ffxi = {
        get_party = function()
            return {
                p0 = { mob = { id = 100, name = 'Selftest' } },
                p1 = { mob = { id = 201, name = 'Niightsiide' } },
                p2 = { mob = { id = 202, name = 'Ponponponponpon' } },
            }
        end,
        get_mob_by_name = function(name)
            if name == 'Niightsiide' then
                return { id = 201, name = name }
            elseif name == 'Ponponponponpon' then
                return { id = 202, name = name }
            end
            return nil
        end,
    },
})

package.loaded.uc_active_config = nil
local active_config = require('uc_active_config')

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
                wait_ignore_names = { 'Niightsiide', 'Offline Ally' },
            },
        },
    },
})

local ok, err = pcall(function()
    local names = active_config.get_path('config.combat.weaponskill.wait_ignore_names')
    assert_equal(#names, 2, 'initial wait-ignore durable name count')
    assert_equal(names[1], 'Niightsiide', 'first durable wait-ignore name')
    assert_equal(names[2], 'Offline Ally', 'offline durable name must remain canonical')

    local projected, projection_err = active_config.project_flat_settings(
        rawget(_G, 'UC_ACTIVE_PROFILE'),
        {}
    )
    assert_true(type(projected) == 'table', 'wait-ignore canonical policy must project')
    assert_equal(projection_err, nil, 'wait-ignore projection error')
    assert_equal(#projected.wait_ignore_names, 2, 'compatibility names must preserve all durable names')
    assert_equal(projected.wait_ignore_names[1], 'Niightsiide', 'compatibility first name')
    assert_equal(projected.wait_ignore_names[2], 'Offline Ally', 'offline durable name survives projection')
    assert_equal(#projected.ignore, 1, 'only currently resolvable names derive live ids')
    assert_equal(projected.ignore[1], 201, 'Niightsiide must derive current runtime party id')

    local changed, reason = active_config.append_string_list(
        'config.combat.weaponskill.wait_ignore_names',
        ' Ponponponponpon '
    )
    assert_true(changed, 'wait-ignore append should succeed')
    assert_equal(reason, 'ADDED', 'wait-ignore append reason')
    assert_equal(names[3], 'Ponponponponpon', 'canonical append preserves normalized user spelling')

    changed, reason = active_config.append_string_list(
        'config.combat.weaponskill.wait_ignore_names',
        'NIIGHTSIIDE'
    )
    assert_true(changed, 'case-only duplicate is a successful no-op')
    assert_equal(reason, 'ALREADY', 'case-only wait-ignore duplicate reason')
    assert_equal(#names, 3, 'case-only duplicate must not grow durable names')

    changed, reason = active_config.remove_string_list_value(
        'config.combat.weaponskill.wait_ignore_names',
        'offline ally'
    )
    assert_true(changed, 'remove-by-name should succeed case-insensitively')
    assert_equal(reason, 'REMOVED', 'wait-ignore remove-by-name reason')
    assert_equal(#names, 2, 'wait-ignore remove-by-name count')
    assert_equal(names[1], 'Niightsiide', 'first durable name remains')
    assert_equal(names[2], 'Ponponponponpon', 'ordered names close after removal')

    projected, projection_err = active_config.project_flat_settings(
        rawget(_G, 'UC_ACTIVE_PROFILE'),
        {}
    )
    assert_true(type(projected) == 'table', 'updated wait-ignore policy must project')
    assert_equal(projection_err, nil, 'updated wait-ignore projection error')
    assert_equal(#projected.ignore, 2, 'two currently resolvable names derive runtime ids')
    assert_equal(projected.ignore[1], 201, 'first derived id')
    assert_equal(projected.ignore[2], 202, 'second derived id')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
rawset(_G, 'windower', previous_windower)
package.loaded.uc_active_config = nil

if not ok then
    error(err, 0)
end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local core = read_all('unified_combat_core.lua')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')

assert_not_contains(bridge, "require('uc_ignore')",
    'wait-ignore bridge must not mutate legacy ignore ids through uc_ignore')
assert_contains(bridge, "'config.combat.weaponskill.wait_ignore_names'",
    'wait-ignore bridge must edit canonical durable names')
assert_not_contains(bridge, 's.wait_ignore_names =',
    'bridge must not assign flat wait-ignore name authority')
assert_not_contains(bridge, 's.ignore =',
    'bridge must not assign derived runtime ignore ids')
assert_contains(bridge, "local _, _, id_to_name = uc_get_party_name_maps(true)",
    'legacy remove-by-id compatibility must resolve live id back to a durable name')
assert_contains(bridge, "'remove_string_list_value'",
    'legacy remove-by-id compatibility must remove canonical name policy')
assert_contains(core, 'not uc_ignore.is_name_blocked(settings, value.name)',
    'WS coordination runtime must consume wait-ignore by ally name')

local ignore_ui = extract(
    ui,
    '    private void IgnoreAddByName()',
    '    private void PartnerAddByName()'
)
assert_not_contains(ignore_ui, 'Forward(',
    'wait-ignore editor actions must not emit live bridge mutations')
assert_contains(ignore_ui, 'CaptureWorkingProfileFromUi(sid);',
    'wait-ignore editor actions must capture working Profile V2')
assert_contains(ignore_ui, 'CurrentRuntimeTargetName()',
    'wait-ignore Add Current must consume runtime target observation')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"ignore_replace_names"',
    'full form push must not carry wait-ignore durable policy to the addon')

assert_contains(writer,
    '.Add("wait_ignore_names", ParseNameList(ReadString(flatProfile, "ignore_entries", "")))',
    'WinForms writer must persist wait-ignore rows as canonical durable names')

print('selftest_phase5_wait_ignore_write_pipeline: OK (durable names + derived runtime ids)')
