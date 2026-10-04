package.path = './?.lua;' .. package.path

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
    is_mob_blocked = function() return false end,
}
package.loaded['uc_partner_list'] = {
    as_ordered_ids = function() return {} end,
}
package.loaded['uc_fight_leader'] = {
    resolve_mid_override = function() return 0 end,
}
package.loaded['uc_add_control'] = {
    enabled = function() return false end,
    pick = function() return 0 end,
}
package.loaded['uc_targeting_common'] = {
    build_party_claims = function() return {}, {} end,
    build_friendly_claims = function() return {}, {} end,
    is_friendly_party_or_alliance_member_id = function() return false end,
}
package.loaded['uc_settarget'] = {
    select_by_id = function() return true end,
}
package.loaded['uc_attack'] = {
    switch_target = function() return true end,
    engage_target = function() return true end,
}
package.loaded['uc_path_hunter'] = {
    matches_mob = function() return false end,
}
package.loaded['uc_combat_extension_config'] = {
    auto_engage_enabled = function(settings)
        return type(settings) ~= 'table' or settings.auto_engage ~= false
    end,
    auto_engage_enabled_from_config = function(config)
        local combat = type(config) == 'table' and config.combat or nil
        return type(combat) == 'table' and combat.auto_engage == true
    end,
}
package.loaded['uc_scheduler_config'] = {
    combat_autotarget = function(settings)
        return type(settings) == 'table' and settings.autotarget == true
    end,
    combat_autotarget_from_config = function(config)
        local combat = type(config) == 'table' and config.combat or nil
        return type(combat) == 'table' and combat.autotarget == true
    end,
    movement_spacing_from_config = function(config)
        local movement = type(config) == 'table' and config.movement or nil
        local spacing = type(movement) == 'table' and movement.spacing or nil
        return type(spacing) == 'table' and spacing or nil
    end,
}

local function distance(value)
    return {
        sqrt = function()
            return value
        end,
    }
end

_G.__TEST_NOW = 100
_G.__TEST_ME = { id = 1, x = 0, y = 0, z = 0, model_size = 0 }
_G.__TEST_TARGET = {
    id = 1001,
    valid_target = true,
    spawn_type = 16,
    hpp = 100,
    status = 1,
    claim_id = 0,
    x = 3,
    y = 0,
    z = 0,
    model_size = 0,
    distance = distance(3),
}

windower = {
    addon_path = '',
    register_event = function() end,
    send_ipc_message = function() end,
    dir_exists = function() return true end,
    create_dir = function() end,
    ffxi = {
        get_player = function()
            return { status = 1, id = 1, vitals = { tp = 1000 } }
        end,
        get_mob_by_target = function(name)
            if name == 'me' then return _G.__TEST_ME end
            if name == 't' then return _G.__TEST_TARGET end
            return nil
        end,
        get_mob_by_id = function(id)
            if tonumber(id) == 1 then return _G.__TEST_ME end
            return nil
        end,
        get_mob_by_index = function() return nil end,
        get_mob_array = function() return {} end,
        get_party = function() return {} end,
        get_info = function() return { zone = 0 } end,
        run = function() return true end,
        turn = function() return true end,
    },
}

local movement_config = require('uc_movement_config')
local core = dofile('unified_combat_core.lua')
core.mover = false

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

local function count_plain(source, needle)
    local count = 0
    local start = 1
    while true do
        local at = source:find(needle, start, true)
        if at == nil then break end
        count = count + 1
        start = at + #needle
    end
    return count
end

local run_calls = {}
local stop_calls = 0
local movement_executor = {
    stop = function()
        stop_calls = stop_calls + 1
    end,
    run_heading = function(heading)
        run_calls[#run_calls + 1] = heading
    end,
    run_forward = function()
        run_calls[#run_calls + 1] = 'forward'
    end,
    turn = function() end,
    move_towards = function()
        run_calls[#run_calls + 1] = 'towards'
    end,
    move_away_from = function()
        run_calls[#run_calls + 1] = 'away'
    end,
}

local function reset_motion()
    run_calls = {}
    stop_calls = 0
    core.last_run_active = false
    core.move_guard = {}
    core.spacing = {
        target_prev_x = nil,
        target_prev_y = nil,
        target_prev_t = nil,
        tick = 0,
    }
    _G.UC_PREENGAGE_APPROACH_ACTIVE = false
end

local function canonical(opts)
    opts = opts or {}
    return {
        ownership = {
            domain_combat_enabled = opts.combat_domain ~= false,
            domain_movement_enabled = opts.movement_domain ~= false,
        },
        combat = {
            autotarget = opts.autotarget == true,
            auto_engage = opts.auto_engage == true,
            manual = opts.manual == true,
            static = opts.static == true,
            face = opts.face == true,
        },
        movement = {
            move = opts.move == true,
            formation = {
                enabled = opts.formation == true,
            },
            named_formations = {
                enabled = opts.named_formations == true,
                entries = {},
            },
            spacing = {
                enabled = opts.spacing == true,
                band_min = -0.9,
                band_max = 0.4,
                model_size_floor = 0.9,
                use_prediction = false,
                lookahead_s = 0.25,
                repel_hold_ticks = 5,
                overlap_deadband = 0.10,
                repel_weight = 0.35,
                band_deadband = 0.20,
            },
            path = {
                follow_enabled = opts.path_follow == true,
            },
        },
        follow = {
            partner = {
                puller = opts.puller == true,
            },
        },
        targeting = {
            add_control = opts.add_control == true,
        },
        tank = {
            enabled = opts.tank == true,
        },
        legacy = {
            hunter = opts.hunter == true,
        },
    }
end

local function run_core(flat, config)
    reset_motion()
    return core.apply_movement_for_scheduler(flat, movement_executor, config)
end

local function test_move_authority()
    local moved = run_core(
        { move = false, manual = false, static = false, autotarget = false, auto_engage = false },
        canonical({ move = true })
    )
    assert_true(moved, 'canonical move ON must beat flat OFF and own combat-close movement')
    assert_true(#run_calls > 0, 'canonical move ON must issue movement')

    moved = run_core(
        { move = true, manual = false, static = false, autotarget = true, auto_engage = true },
        canonical({ move = false })
    )
    assert_false(moved, 'canonical move OFF must beat flat ON when canonical autotarget/auto-engage are OFF')
    assert_equal(#run_calls, 0, 'flat move ON must not revive canonical-disabled movement')
end

local function test_manual_static_authority()
    local moved = run_core(
        { move = true, manual = false, static = false },
        canonical({ move = true, manual = true })
    )
    assert_false(moved, 'canonical manual ON must block movement despite flat manual OFF')

    moved = run_core(
        { move = false, manual = true, static = false },
        canonical({ move = true, manual = false })
    )
    assert_true(moved, 'canonical manual OFF must beat flat manual ON')

    moved = run_core(
        { move = true, manual = false, static = false },
        canonical({ move = true, static = true })
    )
    assert_false(moved, 'canonical static ON must block movement despite flat static OFF')

    moved = run_core(
        { move = false, manual = false, static = true },
        canonical({ move = true, static = false })
    )
    assert_true(moved, 'canonical static OFF must beat flat static ON')
end

local function test_participant_and_face_policy()
    local cfg = canonical({})
    assert_false(movement_config.combat_participant(cfg), 'empty canonical combat participation must be OFF')
    assert_false(movement_config.movement_participant(cfg), 'empty canonical movement participation must be OFF')

    cfg = canonical({ spacing = true })
    assert_false(movement_config.combat_participant(cfg), 'spacing alone is not combat participation')
    assert_true(movement_config.movement_participant(cfg), 'canonical spacing must qualify movement participation')

    cfg = canonical({ formation = true })
    assert_true(movement_config.combat_participant(cfg), 'canonical formation must qualify combat participation')
    assert_true(movement_config.movement_participant(cfg), 'canonical formation must qualify movement participation')

    cfg = canonical({ move = true, movement_domain = false })
    assert_false(movement_config.movement_participant(cfg), 'canonical movement domain OFF must beat movement features')

    cfg = canonical({ autotarget = true, combat_domain = false })
    assert_false(movement_config.combat_participant(cfg), 'canonical combat domain OFF must beat combat features')

    cfg = canonical({ face = true })
    assert_true(movement_config.face_enabled(cfg), 'canonical face ON')
    cfg.combat.face = false
    assert_false(movement_config.face_enabled(cfg), 'canonical face OFF')
end

local function test_static_wiring()
    local core_source = read_all('unified_combat_core.lua')
    local scheduler_source = read_all('unified_scheduler.lua')
    local addon_source = read_all('UnifiedCombat.lua')

    assert_contains(core_source, "require('uc_movement_config').controls(config)",
        'core movement must consume canonical movement controls')
    assert_equal(count_plain(core_source, 'settings.move'), 1,
        'flat move may remain only in explicit no-config compatibility branch')
    assert_equal(count_plain(core_source, 'settings.manual'), 1,
        'flat manual may remain only in explicit no-config compatibility branch')
    assert_equal(count_plain(core_source, 'settings.static'), 1,
        'flat static may remain only in explicit no-config compatibility branch')

    assert_contains(scheduler_source, "local movement_config = require('uc_movement_config')",
        'scheduler must require canonical movement config')
    assert_contains(scheduler_source, 'local function run_movement_coordinator_tick(config)',
        'movement coordinator must receive the canonical tick snapshot explicitly')
    assert_contains(scheduler_source, 'move_acted, move_reason = run_movement_coordinator_tick(get_tick_ctx().config)',
        'process tick must pass its stable canonical snapshot into movement')
    assert_contains(scheduler_source, "require('uc_run_no_tp').target_id(s, p, t, config)",
        'movement coordinator no-TP facing must reuse the same canonical snapshot')
    assert_contains(scheduler_source, "require('uc_follow_config').fight(config)",
        'fight-follow timing in movement must use the explicit canonical snapshot')
    assert_not_contains(scheduler_source, 's.fight_follow_hold_s',
        'movement coordinator must not fall back to flat fight-follow hold')
    assert_contains(scheduler_source,
        'p1_apply_face_to_target = function(settings, target_id, turn_away, force_face, source_override, config)',
        'face helper must accept canonical config')
    assert_contains(scheduler_source, 'and movement_config.face_enabled(config)',
        'face helper must derive ordinary facing from canonical config')
    assert_equal(count_plain(scheduler_source, 'settings and settings.face'), 1,
        'flat face may remain only in explicit no-config compatibility branch')

    local coordinator_start = assert(scheduler_source:find('local function run_movement_coordinator_tick(config)', 1, true))
    local coordinator_end = assert(scheduler_source:find('local function tank_enmity_diag', coordinator_start, true))
    local coordinator = scheduler_source:sub(coordinator_start, coordinator_end)
    assert_not_contains(coordinator, 'get_tick_ctx().config',
        'movement coordinator must not reach out to process_tick local state')
    assert_contains(coordinator, 'combat_core.apply_movement_for_scheduler(s, movement_executor, config)',
        'core movement must receive coordinator canonical snapshot')
    assert_contains(coordinator, "p1_apply_face_to_target(s, tid, false, false, nil, config)",
        'ordinary coordinator facing must receive canonical snapshot')

    local combat_start = assert(addon_source:find('local function uc_is_combat_participant', 1, true))
    local combat_end = assert(addon_source:find('local function uc_is_defensive_participant', combat_start, true))
    local combat_body = addon_source:sub(combat_start, combat_end)
    assert_contains(combat_body, "require('uc_movement_config').combat_participant(active_config)",
        'combat participant classification must use canonical config')
    assert_not_contains(combat_body, 'UC_SETTINGS',
        'combat participant classification must not consult flat settings')

    local movement_start = assert(addon_source:find('local function uc_is_movement_participant', 1, true))
    local movement_end = assert(addon_source:find('local function uc_is_follow_participant', movement_start, true))
    local movement_body = addon_source:sub(movement_start, movement_end)
    assert_contains(movement_body, "require('uc_movement_config').movement_participant(active_config)",
        'movement participant classification must use canonical config')
    assert_not_contains(movement_body, 'UC_SETTINGS',
        'movement participant classification must not consult flat settings')
end

test_move_authority()
test_manual_static_authority()
test_participant_and_face_policy()
test_static_wiring()

io.stdout:write('selftest_phase3_movement_authority: OK (move + manual/static + face + participation)\n')
