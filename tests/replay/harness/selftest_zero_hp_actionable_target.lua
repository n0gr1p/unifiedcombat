package.loaded['socket'] = {
    gettime = function()
        return (_G.__TEST_NOW or 0)
    end,
}
_G.socket = package.loaded['socket']

package.loaded['resources'] = {
    weapon_skills = {},
    job_abilities = {},
    spells = {},
    buffs = {},
    items = {},
    monster_abilities = {},
}
package.loaded['skills'] = {}
package.loaded['uc_ability_pipeline'] = {}
package.loaded['uc_ws_gate'] = {}
package.loaded['uc_ws_memory'] = {}
package.loaded['uc_ignore'] = {}
package.loaded['uc_target_ignore'] = {
    is_mob_blocked = function()
        return false
    end,
}
package.loaded['uc_partner_list'] = {
    as_ordered_ids = function()
        return {}
    end,
}
package.loaded['uc_fight_leader'] = {
    resolve_mid_override = function()
        return 0
    end,
}
package.loaded['uc_add_control'] = {
    enabled = function()
        return false
    end,
    pick = function()
        return 0
    end,
}
package.loaded['uc_targeting_common'] = {
    build_party_claims = function()
        return {}, {}
    end,
}
package.loaded['uc_settarget'] = {
    select_by_id = function()
        return true
    end,
}
package.loaded['uc_attack'] = {
    switch_target = function()
        return true
    end,
    engage_target = function()
        return true
    end,
}
package.loaded['uc_path_hunter'] = {
    matches_mob = function()
        return false
    end,
}

windower = {
    addon_path = '',
    register_event = function()
    end,
    send_ipc_message = function()
    end,
    dir_exists = function()
        return true
    end,
    create_dir = function()
    end,
    ffxi_run_calls = {},
    ffxi = {
        get_player = function()
            return { status = 0, id = 1, vitals = { tp = 1000 } }
        end,
        get_mob_by_target = function(name)
            if name == 'me' then
                return _G.__TEST_ME
            end
            if name == 't' then
                return _G.__TEST_TARGET
            end
            return nil
        end,
        get_mob_by_id = function()
            return nil
        end,
        get_mob_by_index = function()
            return nil
        end,
        get_mob_array = function()
            return {}
        end,
        get_party = function()
            return {}
        end,
        get_info = function()
            return { zone = 0 }
        end,
        run = function(arg)
            table.insert(windower.ffxi_run_calls, arg)
            return true
        end,
    },
}

local core = dofile('unified_combat_core.lua')

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

local function make_target(tbl)
    local target = {
        id = 1001,
        valid_target = true,
        spawn_type = 16,
        hpp = 50,
    }
    if tbl then
        for key, value in pairs(tbl) do
            target[key] = value
        end
    end
    return target
end

local function main()
    if type(core.is_live_actionable_combat_target) ~= 'function' then
        error('unified_combat_core must export is_live_actionable_combat_target')
    end

    _G.__TEST_NOW = 100
    core.last_death_target_id = 0
    core.last_death_at = 0

    assert_true(core.is_live_actionable_combat_target(make_target(), _G.__TEST_NOW, true), 'valid live target must pass')
    assert_false(core.is_live_actionable_combat_target(make_target({ hpp = 0 }), _G.__TEST_NOW, true), 'hpp zero must fail')
    assert_false(core.is_live_actionable_combat_target(make_target({ hpp = -5 }), _G.__TEST_NOW, true), 'negative hpp must fail')
    assert_false(core.is_live_actionable_combat_target({
        id = 1001,
        valid_target = true,
        spawn_type = 16,
    }, _G.__TEST_NOW, true), 'missing hpp must fail')

    core.last_death_target_id = 1001
    core.last_death_at = 99.5
    assert_false(core.is_live_actionable_combat_target(make_target({ id = 1001, hpp = 40 }), _G.__TEST_NOW, true), 'recent-death target id must fail')
    assert_true(core.is_live_actionable_combat_target(make_target({ id = 1002, hpp = 40 }), _G.__TEST_NOW, true), 'different target id must not be blocked by recent death')

    core.last_death_target_id = 1001
    core.last_death_at = 90
    assert_true(core.is_live_actionable_combat_target(make_target({ id = 1001, hpp = 40 }), _G.__TEST_NOW, true), 'expired recent-death window must preserve normal valid behavior')

    assert_false(core.is_live_actionable_combat_target(nil, _G.__TEST_NOW, true), 'nil target must fail')
    assert_false(core.is_live_actionable_combat_target({}, _G.__TEST_NOW, true), 'malformed target must fail')
    assert_false(core.is_live_actionable_combat_target(make_target({ id = 0 }), _G.__TEST_NOW, true), 'missing id must fail')
    assert_false(core.is_live_actionable_combat_target(make_target({ valid_target = false }), _G.__TEST_NOW, true), 'invalid target flag must fail')
    assert_false(core.is_live_actionable_combat_target(make_target({ spawn_type = 0 }), _G.__TEST_NOW, true), 'non-combat spawn type must fail')

    windower.ffxi_run_calls = {}
    _G.__TEST_ME = { id = 1, x = 0, y = 0 }
    _G.__TEST_TARGET = make_target({ id = 1001, hpp = 0, x = 10, y = 0 })
    local moved = core.apply_movement_for_scheduler({ move = true }, core.legacy_movement_executor)
    assert_false(moved, 'zero-hp target must not produce movement intent')
    assert_equal(#windower.ffxi_run_calls, 0, 'zero-hp target must not call run')

    windower.ffxi_run_calls = {}
    core.last_death_target_id = 1001
    core.last_death_at = 99.5
    _G.__TEST_TARGET = make_target({ id = 1001, hpp = 40, x = 10, y = 0 })
    moved = core.apply_movement_for_scheduler({ move = true }, core.legacy_movement_executor)
    assert_false(moved, 'recent-death same id must not produce movement intent')
    assert_equal(#windower.ffxi_run_calls, 0, 'recent-death same id must not call run')

    windower.ffxi_run_calls = {}
    core.last_death_target_id = 1001
    core.last_death_at = 99.5
    _G.__TEST_TARGET = make_target({ id = 1002, hpp = 40, x = 10, y = 0 })
    moved = core.apply_movement_for_scheduler({ move = true }, core.legacy_movement_executor)
    assert_true(moved, 'different live target must still produce movement intent')
    assert_equal(#windower.ffxi_run_calls > 0, true, 'different live target must still call run')

    io.stdout:write('selftest_zero_hp_actionable_target: OK\n')
end

main()
