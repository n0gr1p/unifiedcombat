package.loaded['packets'] = {}
package.loaded['socket'] = {
    gettime = function()
        return (_G.__TEST_NOW or 0)
    end,
}
package.loaded['files'] = {
    new = function()
        return {}
    end,
    write = function()
        return true
    end,
    exists = function()
        return false
    end,
    read = function()
        return ''
    end,
}
package.loaded['resources'] = {
    zones = {},
}

local fake_target = nil
local fake_player = { status = 0 }

windower = {
    addon_path = '',
    dir_exists = function()
        return true
    end,
    create_dir = function()
    end,
    register_event = function()
    end,
    send_ipc_message = function()
    end,
    ffxi = {
        get_player = function()
            return fake_player
        end,
        get_mob_by_target = function(name)
            if name == 't' then
                return fake_target
            end
            return nil
        end,
        get_info = function()
            return { zone = 0 }
        end,
        get_party = function()
            return nil
        end,
        get_mob_by_id = function()
            return nil
        end,
    },
}

_G.UC_IsCombatParticipant = function(settings)
    return settings and settings.combat_participant == true
end

local follow = dofile('uc_party_follow.lua')

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function set_state(tbl)
    _G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = tbl.flag
    _G.UC_COMBAT_INTENT_UNTIL = tbl.intent_until
    _G.UC_MOVEMENT_OWNER = tbl.owner
    _G.UC_MOVEMENT_LOCK_UNTIL = tbl.lock_until
    _G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL = tbl.fight_follow_until
    _G.UC_PREENGAGE_APPROACH_ACTIVE = tbl.preengage
    _G.__TEST_NOW = tbl.now
    fake_player.status = tbl.player_status or 0
    fake_target = tbl.target
end

local function main()
    local settings = { combat_participant = true }

    set_state({
        flag = false,
        now = 10,
        intent_until = 20,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    local suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'flag off must preserve old behavior')
    assert_equal(reason, 'flag_off', 'flag off reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 20,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = {
            valid_target = true,
            spawn_type = 16,
            hpp = 100,
        },
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, true, 'combat intent active must suppress')
    assert_equal(reason, 'combat_intent_target', 'combat intent reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'core',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, true, 'core movement lock must suppress')
    assert_equal(reason, 'movement_lock', 'movement lock reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 20,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'stale combat intent without target must release follow')
    assert_equal(reason, 'combat_intent_stale', 'stale combat intent reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'idle state must not suppress')
    assert_equal(reason, 'none', 'idle reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 20,
        preengage = false,
        target = {
            valid_target = true,
            spawn_type = 16,
            hpp = 100,
        },
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, true, 'fight follow hold with active target must suppress')
    assert_equal(reason, 'fight_follow_hold_target', 'fight follow hold reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 20,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'stale fight follow hold without target must release follow')
    assert_equal(reason, 'fight_follow_hold_stale', 'stale fight follow hold reason mismatch')

    set_state({
        flag = true,
        now = 25,
        intent_until = 20,
        owner = 'core',
        lock_until = 24,
        fight_follow_until = 24,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'suppression must expire when windows expire')
    assert_equal(reason, 'none', 'expiry reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = {
            valid_target = true,
            spawn_type = 16,
            hpp = 100,
        },
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'live target alone must not suppress after hardening')
    assert_equal(reason, 'none', 'live target fail-closed reason mismatch')

    set_state({
        flag = true,
        now = 30,
        intent_until = 50,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 40,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'combat ended with no target and no lock must not suppress')
    assert_equal(reason, 'combat_intent_stale', 'combat ended release reason mismatch')

    package.loaded['uc_party_follow'] = follow
    local pathing = dofile('uc_pathing.lua')
    if type(pathing) ~= 'table' then
        error('uc_pathing must load successfully with arbitration helper available')
    end

    if rawget(_G, 'UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP') ~= nil then
        error('movement arbitration test must not require ownership flags')
    end

    io.stdout:write('selftest_movement_priority_arbitration: OK\n')
end

main()
