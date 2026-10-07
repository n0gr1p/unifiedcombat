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

local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')
local previous_settings = rawget(_G, 'UC_SETTINGS')
local previous_windower = rawget(_G, 'windower')
local previous_active_module = package.loaded.uc_active_config
local previous_follow_module = package.loaded.uc_follow_config

rawset(_G, 'UC_SETTINGS', {
    party_follow_leader_name = 'FlatLeader',
    party_follow_id = 999,
    partner_names = { 'FlatPartner' },
    partner_ids = { 998 },
})

rawset(_G, 'windower', {
    ffxi = {
        get_party = function()
            return {
                p0 = { mob = { id = 10, name = 'Tester' } },
                p1 = { mob = { id = 101, name = 'CanonLeader' } },
                p2 = { mob = { id = 202, name = 'CanonPartner' } },
            }
        end,
    },
})

rawset(_G, 'UC_ACTIVE_PROFILE', {
    version = 2,
    profile = {
        schema_version = 2,
        engine = 'UC',
        character = 'Tester',
        main_job = 'WAR',
        sub_job = 'DNC',
        source = 'SELFTEST',
    },
    config = {
        follow = {
            enabled = true,
            party = {
                enabled = true,
                leader_name = '',
                leader_id = 0,
                min = 0.5,
                max = 50,
            },
            fight = {
                leader = false,
                leader_name = '',
                leader_id = 0,
                min = 3,
                hold_s = 8,
            },
            partner = {
                enabled = true,
                secondary_enabled = false,
                names = {},
                ids = {},
                puller = false,
                puller_name = '',
                puller_id = 0,
                leash_source = 'player',
                engage_range = 6,
                puller_distance_only = false,
            },
        },
    },
})

package.loaded.uc_active_config = nil
package.loaded.uc_follow_config = nil
local active_config = require('uc_active_config')
local follow_config = require('uc_follow_config')

local ok, err = pcall(function()
    local changed = active_config.replace_name(
        'config.follow.party.leader_name',
        'CanonLeader'
    )
    assert_true(changed, 'canonical party leader edit should succeed')
    changed = active_config.replace_string_list(
        'config.follow.partner.names',
        { 'CanonPartner' }
    )
    assert_true(changed, 'canonical partner edit should succeed')

    assert_equal(_G.UC_SETTINGS.party_follow_leader_name, 'FlatLeader',
        'canonical edit API must not republish durable party leader into flat settings')
    assert_equal(_G.UC_SETTINGS.party_follow_id, 999,
        'canonical edit API must not mutate stale flat runtime compatibility id')
    assert_equal(_G.UC_SETTINGS.partner_names[1], 'FlatPartner',
        'canonical edit API must not republish partner names into flat settings')
    assert_equal(_G.UC_SETTINGS.partner_ids[1], 998,
        'canonical edit API must not mutate stale flat partner ids')

    local config = active_config.get_path('config')
    assert_equal(follow_config.party_leader_name(config), 'CanonLeader',
        'runtime follow adapter must read canonical edited leader name')
    assert_equal(follow_config.party_leader_id(config), 101,
        'runtime follow adapter must derive current party id from canonical edited name')
    local partner_ids = follow_config.partner_ids(config)
    assert_equal(partner_ids[1], 202,
        'runtime follow adapter must derive partner id from canonical edited names')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
rawset(_G, 'UC_SETTINGS', previous_settings)
rawset(_G, 'windower', previous_windower)
package.loaded.uc_active_config = previous_active_module
package.loaded.uc_follow_config = previous_follow_module

if not ok then error(err, 0) end

local bridge = read_all('remote_bridge.lua')
local edit_helper = extract(
    bridge,
    'local function uc_apply_active_list_edit(method_name, path, ...)',
    'local function uc_targets_include_enemy(targets)'
)

assert_not_contains(edit_helper, 'project_flat_settings(',
    'bridge canonical edit helper must not rebuild a flat settings projection')
assert_not_contains(edit_helper, 'sync_flat_settings_in_place(',
    'bridge canonical edit helper must not publish flat compatibility state')
assert_not_contains(edit_helper, 'UC_SETTINGS',
    'bridge canonical edit helper must not touch flat settings directly')
assert_contains(edit_helper, 'last_state_send = 0',
    'bridge canonical edit helper must still invalidate the state snapshot after edits')

assert_equal(count_literal(bridge, 'project_flat_settings('), 1,
    'remote bridge must retain only the read-only state-snapshot projection')
assert_equal(count_literal(bridge, 'sync_flat_settings_in_place('), 0,
    'remote bridge must contain no flat settings publication')
assert_equal(count_literal(bridge, 'UC_SETTINGS'), 7,
    'remote bridge flat-surface baseline should now be 7 references after config-status decoupling')

local state_tick = extract(
    bridge,
    'function uc_remote_tick()',
    'function uc_remote_unload()'
)
assert_contains(state_tick, 'project_flat_settings(active_profile, {})',
    'the surviving bridge projection must be the read-only editor/state snapshot view')
assert_not_contains(state_tick, 'sync_flat_settings_in_place(',
    'state snapshot projection must not publish back into flat settings')

print('selftest_phase6_bridge_projection_retirement: OK (canonical bridge edits no longer republish flat settings)')
