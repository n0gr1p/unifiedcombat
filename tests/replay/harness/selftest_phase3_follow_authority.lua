package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    assert_equal(value, true, message)
end

local function assert_false(value, message)
    assert_equal(value, false, message)
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then
        error(message or ('missing expected text: ' .. tostring(needle)))
    end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then
        error(message or ('unexpected text: ' .. tostring(needle)))
    end
end

local function read_all(path)
    local fh = assert(io.open(path, 'rb'))
    local source = fh:read('*a')
    fh:close()
    return source
end

local canonical = {
    follow = {
        enabled = true,
        party = {
            enabled = true,
            leader_id = 999,
            leader_name = 'CanonLeader',
            min = 2.5,
            max = 18,
        },
        fight = {
            leader = false,
            leader_id = 998,
            leader_name = 'FightCanon',
            min = 4.0,
            hold_s = 6.5,
        },
        partner = {
            enabled = true,
            secondary_enabled = false,
            names = { 'PartnerCanon' },
            ids = { 777 },
            puller = true,
            puller_name = 'PullCanon',
            puller_id = 776,
            leash_source = 'player',
            engage_range = 9.0,
            puller_distance_only = true,
        },
        nyzul = {
            coordinator_name = '',
            anchor_name = '',
            parking_order = {},
        },
    },
    ownership = {
        domain_follow_enabled = true,
    },
}

local previous_windower = rawget(_G, 'windower')
local previous_active_config = package.loaded['uc_active_config']
local previous_follow_config = package.loaded['uc_follow_config']
local previous_runtime_overrides = package.loaded['uc_runtime_overrides']

local party = {
    p0 = { mob = { id = 10, name = 'Tester' } },
    p1 = { mob = { id = 200, name = 'CanonLeader' } },
    p2 = { mob = { id = 300, name = 'PartnerCanon' } },
    p3 = { mob = { id = 400, name = 'PullCanon' } },
    p4 = { mob = { id = 500, name = 'FightCanon' } },
}

rawset(_G, 'windower', {
    ffxi = {
        get_party = function() return party end,
        get_mob_by_name = function(name)
            for _, entry in pairs(party) do
                local mob = entry and entry.mob
                if mob and mob.name == name then return mob end
            end
            return nil
        end,
    },
})

package.loaded['uc_active_config'] = {
    get_config = function() return canonical end,
    get_path = function(path)
        local node = { config = canonical }
        for part in tostring(path):gmatch('[^.]+') do
            node = type(node) == 'table' and node[part] or nil
        end
        return node
    end,
}
package.loaded['uc_follow_config'] = nil
package.loaded['uc_runtime_overrides'] = nil

local follow_config = require('uc_follow_config')
local runtime_overrides = require('uc_runtime_overrides')

local function test_name_resolution_and_runtime_projection()
    assert_true(follow_config.enabled(canonical), 'canonical follow feature gate')
    assert_equal(follow_config.party_leader_id(canonical), 200,
        'party leader name must resolve live and beat stored legacy id')
    assert_equal(follow_config.fight_leader_id(canonical), 500,
        'fight leader name must resolve live and beat stored legacy id')

    local ids = follow_config.partner_ids(canonical)
    assert_equal(#ids, 1, 'canonical partner name list must resolve exactly one live partner')
    assert_equal(ids[1], 300, 'canonical partner name must beat legacy partner ids')
    assert_equal(follow_config.puller_id(canonical), 400,
        'canonical puller name must resolve live and beat legacy puller id')

    local flat = {
        domain_follow_enabled = false,
        party_follow = false,
        party_follow_id = 111,
        party_follow_leader_name = 'FlatLeader',
        party_follow_min = 0.5,
        party_follow_max = 50,
        fight_leader = true,
        fight_leader_id = 222,
        fight_leader_name = 'FlatFight',
        fight_follow_min = 1.0,
        fight_follow_hold_s = 20,
        partner = false,
        partner_ids = { 333 },
        puller = false,
        puller_id = 444,
        puller_name = 'FlatPuller',
        puller_engage_range = 2,
        puller_distance_only = false,
    }
    local view = {}
    for key, value in pairs(flat) do view[key] = value end
    follow_config.apply_runtime_view(view, canonical)

    assert_true(view.domain_follow_enabled, 'canonical follow enabled must beat flat disabled')
    assert_true(view.party_follow, 'canonical party follow enabled must beat flat disabled')
    assert_equal(view.party_follow_id, 200, 'runtime party leader id must be live canonical resolution')
    assert_equal(view.party_follow_leader_name, 'CanonLeader', 'canonical party leader name')
    assert_equal(view.party_follow_min, 2.5, 'canonical party minimum distance')
    assert_equal(view.party_follow_max, 18, 'canonical party maximum distance')
    assert_false(view.fight_leader, 'canonical fight leader disabled must beat flat enabled')
    assert_equal(view.fight_leader_id, 500, 'canonical fight leader identity must remain resolved')
    assert_equal(view.fight_follow_min, 4.0, 'canonical fight follow minimum')
    assert_equal(view.fight_follow_hold_s, 6.5, 'canonical fight follow hold')
    assert_true(view.partner, 'canonical partner enabled must beat flat disabled')
    assert_equal(view.partner_ids[1], 300, 'canonical partner runtime ids')
    assert_true(view.puller, 'canonical puller enabled must beat flat disabled')
    assert_equal(view.puller_id, 400, 'canonical puller runtime id')
    assert_equal(view.puller_engage_range, 9.0, 'canonical puller engage range')
    assert_true(view.puller_distance_only, 'canonical puller distance-only policy')
end

local function test_fight_leader_runtime_reader_authority()
    local flat = {
        fight_leader = true,
        fight_leader_id = 222,
        fight_leader_name = 'FlatFight',
    }
    assert_false(runtime_overrides.fight_leader_enabled(flat),
        'canonical fight leader OFF + flat ON must stay disabled')
    assert_equal(runtime_overrides.fight_leader_id(flat), 500,
        'canonical fight leader identity must beat conflicting flat identity')

    canonical.follow.fight.leader = true
    assert_true(runtime_overrides.fight_leader_enabled({
        fight_leader = false,
        fight_leader_id = 222,
    }), 'canonical fight leader ON + flat OFF must stay enabled')
    assert_equal(runtime_overrides.fight_leader_name(flat), 'FightCanon',
        'canonical fight leader name must beat conflicting flat name')
    canonical.follow.fight.leader = false
end

local function test_camp_leash_has_no_runtime_player_id()
    canonical.follow.partner.leash_source = 'camp'
    assert_equal(follow_config.puller_id(canonical), 0,
        'camp leash must not retain or resolve a player puller id')
    canonical.follow.partner.leash_source = 'player'
end

local function test_static_wiring()
    local party_follow = read_all('uc_party_follow.lua')
    local pathing = read_all('uc_pathing.lua')
    local core = read_all('unified_combat_core.lua')
    local scheduler = read_all('unified_scheduler.lua')
    local addon = read_all('UnifiedCombat.lua')
    local overrides = read_all('uc_runtime_overrides.lua')

    assert_not_contains(party_follow, 'active_value_or_flat(',
        'party follow must not retain active-value-or-flat follow readers')
    assert_contains(party_follow, "local uc_follow_config = require('uc_follow_config')",
        'party follow must use canonical follow adapter')
    assert_contains(party_follow, 'uc_follow_config.party_leader_id(active_follow_config())',
        'party follow identity must resolve from canonical follow config')
    assert_contains(pathing, "local uc_follow_config = require('uc_follow_config')",
        'pathing follow ownership must use canonical follow adapter')
    assert_contains(core, "require('uc_follow_config').apply_runtime_view(view, config)",
        'core scheduler runtime view must project canonical follow policy')
    assert_contains(core, "require('uc_follow_config').apply_runtime_view(puller_settings, config)",
        'core movement puller gate must use canonical follow partner policy')
    assert_contains(scheduler, "local follow_config = require('uc_follow_config')",
        'scheduler partner arbitration must use canonical follow adapter')
    assert_contains(scheduler, "local fight_cfg = require('uc_follow_config').fight(get_tick_ctx().config)",
        'scheduler fight-follow hold must use canonical fight config')
    assert_contains(addon, "get_path('config.ownership.domain_follow_enabled')",
        'follow domain participation must use canonical ownership gate')
    assert_contains(addon, "local follow_config = require('uc_follow_config')",
        'follow participant test must consume canonical follow feature config')
    assert_contains(overrides, 'uc_follow_config.fight_leader_id(config)',
        'fight leader runtime reader must resolve canonical identity')
end

local ok, err = pcall(function()
    test_name_resolution_and_runtime_projection()
    test_fight_leader_runtime_reader_authority()
    test_camp_leash_has_no_runtime_player_id()
    test_static_wiring()
    io.stdout:write('selftest_phase3_follow_authority: OK (party + fight + partner + puller)\n')
end)

rawset(_G, 'windower', previous_windower)
package.loaded['uc_active_config'] = previous_active_config
package.loaded['uc_follow_config'] = previous_follow_config
package.loaded['uc_runtime_overrides'] = previous_runtime_overrides

if not ok then error(err, 0) end
