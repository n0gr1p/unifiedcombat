local scheduler_path = "unified_scheduler.lua"
local helper_path = "uc_scheduler_run_stop_ownership.lua"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function count_plain(text, needle)
    local count = 0
    local index = 1
    while true do
        local found = text:find(needle, index, true)
        if not found then
            return count
        end
        count = count + 1
        index = found + #needle
    end
end

local function slice_between(text, start_needle, end_needle)
    local start_pos = text:find(start_needle, 1, true)
    if not start_pos then
        error("missing slice start: " .. start_needle)
    end
    local end_pos = text:find(end_needle, start_pos, true)
    if not end_pos then
        error("missing slice end: " .. end_needle)
    end
    return text:sub(start_pos, end_pos + #end_needle - 1)
end

local function find_nth_plain(text, needle, index_wanted)
    local index = 1
    local count = 0
    while true do
        local found = text:find(needle, index, true)
        if not found then
            return nil
        end
        count = count + 1
        if count == index_wanted then
            return found
        end
        index = found + #needle
    end
end

local function slice_between_nth(text, start_needle, end_needle, start_occurrence)
    local start_pos = find_nth_plain(text, start_needle, start_occurrence)
    if not start_pos then
        error("missing slice start: " .. start_needle)
    end
    local end_pos = text:find(end_needle, start_pos, true)
    if not end_pos then
        error("missing slice end: " .. end_needle)
    end
    return text:sub(start_pos, end_pos + #end_needle - 1)
end

local function main()
    local source = read_file(scheduler_path)
    local helper_source = read_file(helper_path)
    local doom_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,1
    )
    local cast_freeze_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,2
    )
    local pull_cast_hold_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,3
    )
    local pull_spell_wait_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,4
    )
    local combat_spell_settle_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,7
    )
    local combat_spell_prep_wait_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,8
    )
    local tank_enmity_spell_target_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,10
    )
    local tank_enmity_spell_self_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,11
    )
    local tank_action_settle_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,5
    )
    local tank_enmity_ja_self_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,6
    )
    local tank_spell_settle_run_stop_block = slice_between_nth(
        source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,"
        ,9
    )

    assert_contains(
        doom_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP == true)",
        "doom run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        cast_freeze_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP == true)",
        "cast-freeze run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        pull_cast_hold_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP == true)",
        "pull-cast-hold run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        pull_spell_wait_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP == true)",
        "pull-spell-wait run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        combat_spell_settle_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP == true)",
        "combat-spell-settle run_stop ownership flag must use explicit true comparison"
    )
    assert_contains(
        combat_spell_settle_run_stop_block,
        "promoted_default_on = true",
        "combat-spell-settle run_stop ownership flag must be promoted default-on"
    )
    assert_contains(
        combat_spell_settle_run_stop_block,
        "ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP == false)",
        "combat-spell-settle run_stop ownership flag must preserve explicit false opt-out"
    )
    assert_contains(
        combat_spell_settle_run_stop_block,
        "promoted_kill_switch = promoted_ownership_kill_switch_enabled()",
        "combat-spell-settle run_stop ownership flag must use shared promoted kill switch"
    )
    assert_contains(
        combat_spell_prep_wait_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP == true)",
        "combat-spell-prep-wait run_stop ownership flag must use explicit true comparison"
    )
    assert_contains(
        combat_spell_prep_wait_run_stop_block,
        "promoted_default_on = true",
        "combat-spell-prep-wait run_stop ownership flag must be promoted default-on"
    )
    assert_contains(
        combat_spell_prep_wait_run_stop_block,
        "ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP == false)",
        "combat-spell-prep-wait run_stop ownership flag must preserve explicit false opt-out"
    )
    assert_contains(
        combat_spell_prep_wait_run_stop_block,
        "promoted_kill_switch = promoted_ownership_kill_switch_enabled()",
        "combat-spell-prep-wait run_stop ownership flag must use shared promoted kill switch"
    )
    assert_contains(
        tank_enmity_spell_target_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP == true)",
        "tank-enmity-spell-target run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        tank_enmity_spell_self_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP == true)",
        "tank-enmity-spell-self run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        tank_action_settle_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP == true)",
        "tank-action-settle run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        tank_enmity_ja_self_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP == true)",
        "tank-enmity-ja-self run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        tank_spell_settle_run_stop_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP == true)",
        "tank-spell-settle run_stop ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        helper_source,
        "dispatcher.dispatch_intent(intent, {",
        "helper flag-on path must dispatch the existing run_stop intent"
    )
    assert_contains(helper_source, "execute = true", "dispatcher execute mode must be enabled in helper flag-on path")
    assert_contains(
        helper_source,
        "run = run",
        "helper must use injected run dependency for dispatcher"
    )
    assert_contains(
        doom_run_stop_block,
        "run = windower.ffxi.run",
        "doom dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        cast_freeze_run_stop_block,
        "run = windower.ffxi.run",
        "cast-freeze dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        pull_cast_hold_run_stop_block,
        "run = windower.ffxi.run",
        "pull-cast-hold dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        pull_spell_wait_run_stop_block,
        "run = windower.ffxi.run",
        "pull-spell-wait dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        combat_spell_settle_run_stop_block,
        "run = windower.ffxi.run",
        "combat-spell-settle dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        combat_spell_prep_wait_run_stop_block,
        "run = windower.ffxi.run",
        "combat-spell-prep-wait dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        tank_enmity_spell_target_run_stop_block,
        "run = windower.ffxi.run",
        "tank-enmity-spell-target dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        tank_enmity_spell_self_run_stop_block,
        "run = windower.ffxi.run",
        "tank-enmity-spell-self dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        tank_action_settle_run_stop_block,
        "run = windower.ffxi.run",
        "tank-action-settle dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        tank_enmity_ja_self_run_stop_block,
        "run = windower.ffxi.run",
        "tank-enmity-ja-self dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        tank_spell_settle_run_stop_block,
        "run = windower.ffxi.run",
        "tank-spell-settle dispatcher run dependency must inject windower.ffxi.run"
    )
    assert_contains(
        helper_source,
        "direct_run(false)",
        "helper fallback/default path must preserve direct run(false) via injection"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE",
        "doom run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE",
        "cast-freeze run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE",
        "pull-cast-hold run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE",
        "pull-spell-wait run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE",
        "combat-spell-settle run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE",
        "combat-spell-prep-wait run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE",
        "tank-enmity-spell-target run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE",
        "tank-enmity-spell-self run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE",
        "tank-action-settle run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE",
        "tank-enmity-ja-self run_stop validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE",
        "tank-spell-settle run_stop validation status global must remain"
    )

    local required_status_fields = {
        "ownership_enabled",
        "dispatched",
        "dispatch_ok",
        "dispatch_reason",
        "fallback_used",
        "stop",
    }
    for _, field in ipairs(required_status_fields) do
        assert_contains(doom_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing doom status field: " .. field)
        assert_contains(cast_freeze_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing cast-freeze status field: " .. field)
        assert_contains(pull_cast_hold_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing pull-cast-hold status field: " .. field)
        assert_contains(pull_spell_wait_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing pull-spell-wait status field: " .. field)
        assert_contains(combat_spell_settle_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing combat-spell-settle status field: " .. field)
        assert_contains(combat_spell_prep_wait_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing combat-spell-prep-wait status field: " .. field)
        assert_contains(tank_enmity_spell_target_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing tank-enmity-spell-target status field: " .. field)
        assert_contains(tank_enmity_spell_self_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing tank-enmity-spell-self status field: " .. field)
        assert_contains(tank_action_settle_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing tank-action-settle status field: " .. field)
        assert_contains(tank_enmity_ja_self_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing tank-enmity-ja-self status field: " .. field)
        assert_contains(tank_spell_settle_run_stop_block, field .. " = run_stop_ownership_status." .. field, "missing tank-spell-settle status field: " .. field)
        assert_contains(helper_source, field .. " = ", "missing helper status field: " .. field)
    end

    if count_plain(source, "windower.ffxi.run(") ~= 0 then
        error("expected no direct textual windower.ffxi.run( callsites after eleven run_stop ownership slices plus the vector run seam")
    end

    io.stdout:write("selftest_run_stop_ownership_static: OK\n")
end

main()
