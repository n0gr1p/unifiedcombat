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
    auto_engage_enabled_from_config = function()
        return true
    end,
}
package.loaded['uc_scheduler_config'] = {
    combat_autotarget = function(settings)
        return type(settings) == 'table' and settings.autotarget == true
    end,
    combat_autotarget_from_config = function()
        return true
    end,
    movement_spacing_from_config = function(config)
        local movement = type(config) == 'table' and config.movement or nil
        local spacing = type(movement) == 'table' and movement.spacing or nil
        return type(spacing) == 'table' and spacing or nil
    end,
}

local run_calls = {}
local stop_calls = 0

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
        run = function(arg)
            run_calls[#run_calls + 1] = arg
            return true
        end,
        turn = function() return true end,
    },
}

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
    _G.UC_SPACING_DIAG = nil
    _G.UC_PREENGAGE_APPROACH_ACTIVE = false
end

local function spacing(enabled, band_min, band_max, model_size_floor)
    return {
        enabled = enabled,
        band_min = band_min,
        band_max = band_max,
        model_size_floor = model_size_floor,
        use_prediction = false,
        lookahead_s = 0.10,
        repel_hold_ticks = 2,
        overlap_deadband = 0.20,
        repel_weight = 0.80,
        band_deadband = 0.05,
    }
end

local function config(spacing_config)
    return {
        combat = {
            autotarget = true,
            auto_engage = true,
        },
        movement = {
            spacing = spacing_config,
        },
    }
end

local function test_canonical_on_flat_off()
    reset_motion()
    _G.__TEST_TARGET.x = 3
    _G.__TEST_TARGET.distance = distance(3)
    local flat = {
        move = true,
        spacing = false,
        spacing_band_min = -5,
        spacing_band_max = 5,
        spacing_model_size_floor = 0,
        spacing_use_prediction = true,
        spacing_lookahead_s = 1.5,
        spacing_repel_hold_ticks = 8,
        spacing_overlap_deadband = 1,
        spacing_repel_weight = 0.05,
        spacing_band_deadband = 1,
    }
    local moved = core.apply_movement_for_scheduler(
        flat,
        movement_executor,
        config(spacing(true, -0.9, 0.4, 0.9))
    )
    assert_true(moved, 'canonical spacing ON + flat OFF must produce spacing movement')
    assert_true(#run_calls > 0, 'canonical spacing ON must issue movement')
    assert_true(type(_G.UC_SPACING_DIAG) == 'string' and _G.UC_SPACING_DIAG ~= '',
        'canonical spacing ON must execute spacing solver diagnostics')
end

local function test_canonical_off_flat_on()
    reset_motion()
    _G.__TEST_TARGET.x = 3
    _G.__TEST_TARGET.distance = distance(3)
    local flat = {
        move = true,
        spacing = true,
        spacing_band_min = -0.9,
        spacing_band_max = 0.4,
        spacing_model_size_floor = 0.9,
        spacing_use_prediction = true,
        spacing_lookahead_s = 1.0,
        spacing_repel_hold_ticks = 8,
        spacing_overlap_deadband = 0.05,
        spacing_repel_weight = 1.5,
        spacing_band_deadband = 0.05,
    }
    local moved = core.apply_movement_for_scheduler(
        flat,
        movement_executor,
        config(spacing(false, -0.9, 5.0, 0))
    )
    assert_false(moved, 'canonical spacing OFF + flat ON must use canonical non-spacing stop band')
    assert_equal(#run_calls, 0, 'canonical spacing OFF must not execute flat spacing movement')
    assert_equal(_G.UC_SPACING_DIAG, nil, 'canonical spacing OFF must not run spacing solver')
end

local function test_canonical_values_beat_flat()
    reset_motion()
    _G.__TEST_TARGET.x = 3
    _G.__TEST_TARGET.distance = distance(3)
    local flat = {
        move = true,
        spacing = false,
        spacing_band_min = -5,
        spacing_band_max = 5,
        spacing_model_size_floor = 0,
    }
    local moved = core.apply_movement_for_scheduler(
        flat,
        movement_executor,
        config(spacing(false, -0.9, 0.4, 0.9))
    )
    assert_true(moved, 'canonical band_max must beat conflicting flat band_max while spacing is disabled')
    assert_true(#run_calls > 0, 'canonical non-spacing close band must produce movement')

    reset_motion()
    _G.__TEST_TARGET.x = 1
    _G.__TEST_TARGET.distance = distance(1)
    flat.spacing_band_max = 0.4
    flat.spacing_model_size_floor = 0
    moved = core.apply_movement_for_scheduler(
        flat,
        movement_executor,
        config(spacing(false, -0.9, 0.4, 1.0))
    )
    assert_false(moved, 'canonical model_size_floor must beat conflicting flat floor')
    assert_equal(#run_calls, 0, 'canonical model-size floor must affect combat-close stop distance')
end

local function test_static_wiring()
    local core_source = read_all('unified_combat_core.lua')
    local scheduler_config_source = read_all('uc_scheduler_config.lua')
    local scheduler_source = read_all('unified_scheduler.lua')

    assert_contains(scheduler_config_source, 'function M.movement_spacing_from_config(config)',
        'scheduler config must expose canonical movement spacing')
    assert_contains(core_source, "require('uc_scheduler_config').movement_spacing_from_config(config)",
        'combat movement must resolve spacing from canonical config')
    assert_contains(core_source, 'local spacing = movement_spacing_config(settings, config)',
        'combat movement must capture one spacing view per movement tick')
    assert_contains(core_source, 'local spacing_on = setting_enabled(spacing.enabled)',
        'spacing enablement must use canonical spacing view')
    assert_contains(core_source, 'local max_range = tonumber(spacing.band_max) or 0.4',
        'spacing maximum band must use canonical spacing view')
    assert_contains(core_source, 'local min_range = tonumber(spacing.band_min) or -0.9',
        'spacing minimum band must use canonical spacing view')
    assert_contains(core_source, 'local n = tonumber(spacing and spacing.model_size_floor)',
        'movement model-size floor must use canonical spacing view')
    assert_contains(core_source, 'local use_prediction = setting_enabled(spacing.use_prediction)',
        'spacing prediction gate must use canonical spacing view')
    assert_contains(core_source, 'local lookahead_s = tonumber(spacing.lookahead_s) or 0.25',
        'spacing lookahead must use canonical spacing view')
    assert_contains(core_source, 'local hold_s = tonumber(spacing.repel_hold_ticks) or 5',
        'spacing repel hold must use canonical spacing view')
    assert_contains(core_source, 'local repel_deadband = tonumber(spacing.overlap_deadband) or 0.10',
        'spacing overlap deadband must use canonical spacing view')
    assert_contains(core_source, 'local repel_weight = tonumber(spacing.repel_weight) or 0.35',
        'spacing repel weight must use canonical spacing view')
    assert_contains(core_source, 'local band_dead = tonumber(spacing.band_deadband) or 0.20',
        'spacing band deadband must use canonical spacing view')
    assert_contains(scheduler_source,
        'combat_core.apply_movement_for_scheduler(s, movement_executor, config)',
        'scheduler movement coordinator must pass its canonical config into core movement')
    local legacy_spacing_tokens = {
        'settings.spacing)',
        'settings.spacing_band_min',
        'settings.spacing_band_max',
        'settings.spacing_model_size_floor',
        'settings.spacing_use_prediction',
        'settings.spacing_lookahead_s',
        'settings.spacing_repel_hold_ticks',
        'settings.spacing_overlap_deadband',
        'settings.spacing_repel_weight',
        'settings.spacing_band_deadband',
    }
    for _, token in ipairs(legacy_spacing_tokens) do
        assert_equal(count_plain(core_source, token), 1,
            'legacy spacing token must exist only in the explicit no-config compatibility projection: ' .. token)
    end
end

local function main()
    test_canonical_on_flat_off()
    test_canonical_off_flat_on()
    test_canonical_values_beat_flat()
    test_static_wiring()
    io.stdout:write('selftest_phase3_spacing_authority: OK (enablement + band + model floor + solver settings)\n')
end

main()
