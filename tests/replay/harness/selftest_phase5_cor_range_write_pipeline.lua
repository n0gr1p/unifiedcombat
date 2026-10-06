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

local previous_windower = rawget(_G, 'windower')
local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')
local previous_resources = package.loaded.resources
local previous_time = package.loaded.uc_time
local previous_active_module = package.loaded.uc_active_config
local previous_cor = package.loaded.uc_cor_maintenance

local range_distance = 9
local range_member = {
    id = 77,
    name = 'Redrogue',
    hpp = 100,
    distance = { sqrt = function() return range_distance end },
}

rawset(_G, 'windower', {
    ffxi = {
        get_player = function()
            return {
                id = 100,
                name = 'Corsair',
                main_job = 'COR',
                sub_job = 'DNC',
                status = 0,
                buffs = {},
            }
        end,
        get_party = function()
            return {
                p0 = { mob = { id = 100, name = 'Corsair' } },
                p1 = { mob = { id = 77, name = 'Redrogue' } },
                p2 = { mob = { id = 88, name = 'Nyoourke' } },
            }
        end,
        get_mob_by_name = function(name)
            if name == 'Redrogue' then return range_member end
            if name == 'Nyoourke' then
                return {
                    id = 88, name = name, hpp = 100,
                    distance = { sqrt = function() return 4 end },
                }
            end
            return nil
        end,
        get_mob_by_id = function(id)
            if tonumber(id) == 77 then return range_member end
            if tonumber(id) == 88 then
                return {
                    id = 88, name = 'Nyoourke', hpp = 100,
                    distance = { sqrt = function() return 4 end },
                }
            end
            return nil
        end,
        get_ability_recasts = function()
            return { [96] = 0, [193] = 0, [194] = 0, [197] = 0, [198] = 0 }
        end,
        get_items = function()
            return { enabled = false }
        end,
        get_mob_by_target = function()
            return nil
        end,
    },
})

package.loaded.resources = {
    job_abilities = {
        [131] = { id = 131, en = 'Light Shot', recast_id = 195 },
    },
}
package.loaded.uc_time = { now = function() return 100 end }
package.loaded.uc_active_config = nil

local active_config = require('uc_active_config')

rawset(_G, 'UC_ACTIVE_PROFILE', {
    version = 2,
    profile = {
        schema_version = 2,
        engine = 'UC',
        character = 'Corsair',
        main_job = 'COR',
        sub_job = 'DNC',
        source = 'SELFTEST',
    },
    config = {
        maintenance = {
            enabled = true,
            cor = {
                roll_1 = 'Chaos Roll',
                roll_2 = 'Samurai Roll',
                crooked_roll_slot = 0,
                elevens = false,
                luzaf_range_override = false,
                light_shot_dia = false,
                range_selected = 'Redrogue|Offline Ally',
                range_require_ids = { 999 },
            },
        },
        abilities = { configured = {} },
    },
})

local ok, err = pcall(function()
    local cor_cfg = active_config.get_path('config.maintenance.cor')
    local changed, reason = active_config.replace_pipe_string_list(
        'config.maintenance.cor.range_selected',
        { ' Redrogue ', 'redrogue', 'Offline Ally' }
    )
    assert_true(changed, 'COR range participant replace should succeed')
    assert_equal(reason, 'REPLACED', 'COR range participant replace reason')
    assert_equal(cor_cfg.range_selected, 'Redrogue|Offline Ally',
        'COR durable participant names must trim/dedupe and preserve offline policy')
    assert_equal(#cor_cfg.range_require_ids, 0,
        'canonical range IDs must clear whenever durable participant names are edited')

    local projected, projection_err = active_config.project_flat_settings(
        rawget(_G, 'UC_ACTIVE_PROFILE'),
        {}
    )
    assert_true(type(projected) == 'table', 'COR participant names must project')
    assert_equal(projection_err, nil, 'COR participant projection error')
    assert_equal(projected.cor_roll_range_selected, 'Redrogue|Offline Ally',
        'flat selected names must preserve durable policy')
    assert_equal(#projected.cor_roll_range_require_ids, 1,
        'only currently resolvable participant names derive live IDs')
    assert_equal(projected.cor_roll_range_require_ids[1], 77,
        'Redrogue must derive the current party ID')

    package.loaded.uc_cor_maintenance = nil
    local cor = require('uc_cor_maintenance')
    local root = {
        maintenance = { cor = cor_cfg },
        abilities = { configured = {} },
    }

    range_distance = 9
    local action = cor.propose(root)
    assert_equal(action, nil,
        'canonical selected participant outside normal roll range must block the roll')

    range_distance = 7
    action = cor.propose(root)
    assert_true(type(action) == 'table',
        'canonical selected participant inside roll range must allow a roll')
    assert_equal(action.action_name, 'Chaos Roll',
        'COR runtime must continue normal roll selection after name-based range gate passes')

    cor_cfg.range_selected = ''
    cor_cfg.range_require_ids = { 77 }
    range_distance = 9
    action = cor.propose(root)
    assert_equal(action, nil,
        'legacy canonical range IDs remain fallback when durable selected names are empty')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
rawset(_G, 'windower', previous_windower)
package.loaded.resources = previous_resources
package.loaded.uc_time = previous_time
package.loaded.uc_active_config = previous_active_module
package.loaded.uc_cor_maintenance = previous_cor

if not ok then error(err, 0) end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
local cor_source = read_all('uc_cor_maintenance.lua')

local bridge_block = extract(
    bridge,
    "elseif op == 'cor_roll_range_replace_names' then",
    "elseif op == 'add_priority_replace_names' then"
)
assert_not_contains(bridge_block, 'UC_SETTINGS',
    'COR range bridge path must not mutate flat settings')
assert_contains(bridge_block, "'replace_pipe_string_list'",
    'COR range bridge path must edit canonical pipe-delimited name policy')
assert_contains(bridge_block, "'config.maintenance.cor.range_selected'",
    'COR range bridge path must target canonical selected names')

local ui_handler = extract(
    ui,
    '    private void OnCorRangePartySelectionChanged()',
    '    private void OnPathPartyGateChanged()'
)
assert_not_contains(ui_handler, 'Forward(',
    'COR range checkbox edits must not emit live bridge mutations')
assert_contains(ui_handler, 'CaptureWorkingProfileFromUi(sid);',
    'COR range checkbox edits must capture working Profile V2')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"cor_roll_range_replace_names"',
    'full form push must not carry COR durable participant policy to the addon')

assert_contains(writer, '.Add("range_selected", ReadString(flatProfile, "cor_roll_range_selected", ""))',
    'structured writer must persist COR participant names')
assert_contains(writer, '.Add("range_require_ids", EmptyList())',
    'new structured profiles must not persist live COR participant IDs')
assert_contains(cor_source, 'local function selected_range_ids(cor)',
    'COR runtime must derive current IDs from canonical selected names')
assert_contains(cor_source, "if #names == 0 then",
    'COR runtime must preserve legacy ID fallback only when no names are configured')
assert_contains(cor_source, "windower.ffxi.get_party",
    'COR runtime participant resolution must use live party observation')

print('selftest_phase5_cor_range_write_pipeline: OK (durable COR names + derived live IDs)')
