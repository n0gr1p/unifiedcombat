local scheduler_path = "unified_scheduler.lua"
local command_helper_path = "uc_scheduler_command_ownership.lua"
local run_stop_helper_path = "uc_scheduler_run_stop_ownership.lua"
local target_helper_path = "uc_scheduler_target_ownership.lua"
local turn_helper_path = "uc_scheduler_turn_ownership.lua"

local PROMOTED_FLAGS = {
    "UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP",
}

local DEFAULT_OFF_FLAGS = {
    "UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP",
    "UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP",
}

local VECTOR_FLAG = "UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP"

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

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local command_helper = dofile(command_helper_path)
    local run_stop_helper = dofile(run_stop_helper_path)
    local target_helper = dofile(target_helper_path)
    local turn_helper = dofile(turn_helper_path)

    assert_contains(
        scheduler_source,
        "UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP",
        "scheduler must expose promoted ownership kill switch name"
    )
    assert_contains(
        scheduler_source,
        "local function promoted_ownership_kill_switch_enabled()",
        "scheduler must define promoted ownership kill switch helper"
    )

    for _, flag in ipairs(PROMOTED_FLAGS) do
        assert_contains(
            scheduler_source,
            "ownership_enabled = (_G." .. flag .. " == true)",
            "promoted flag must preserve explicit true check marker: " .. flag
        )
        assert_contains(
            scheduler_source,
            "ownership_disabled = (_G." .. flag .. " == false)",
            "promoted flag must support explicit false opt-out: " .. flag
        )
    end

    assert_equal(
        count_plain(scheduler_source, "promoted_default_on = true"),
        20,
        "expected promoted_default_on marker on the 20 promoted scheduler callsites"
    )
    assert_equal(
        count_plain(scheduler_source, "promoted_kill_switch = promoted_ownership_kill_switch_enabled()"),
        20,
        "expected promoted kill-switch marker on the 20 promoted scheduler callsites"
    )

    for _, flag in ipairs(DEFAULT_OFF_FLAGS) do
        assert_contains(
            scheduler_source,
            "ownership_enabled = (_G." .. flag .. " == true)",
            "default-off flag must remain explicit true-only: " .. flag
        )
        if scheduler_source:find("ownership_disabled = %(_G%." .. flag .. " == false%)", 1) then
            error("default-off flag must not gain promoted false opt-out semantics: " .. flag)
        end
    end

    assert_contains(
        scheduler_source,
        "ownership_enabled = (_G." .. VECTOR_FLAG .. " == true)",
        "vector run flag must remain explicit true-only"
    )
    if scheduler_source:find("ownership_disabled = %(_G%." .. VECTOR_FLAG .. " == false%)", 1) then
        error("vector run flag must not be promoted")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = command_helper.apply_command_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = true, executed = true, reason = "" }
                end,
            },
            direct_send_command = function()
                direct_calls = direct_calls + 1
            end,
            send_command = function()
            end,
            ownership_enabled = false,
            promoted_default_on = true,
            ownership_disabled = false,
            promoted_kill_switch = false,
            intent = { kind = "send_command" },
            command = "input /echo test",
        })
        assert_equal(status.ownership_enabled, true, "promoted command path must be default-on when unset")
        assert_equal(dispatch_calls, 1, "promoted command path must dispatch when unset")
        assert_equal(direct_calls, 0, "promoted command path must not use direct send when dispatch succeeds")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = command_helper.apply_command_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = true, executed = true, reason = "" }
                end,
            },
            direct_send_command = function()
                direct_calls = direct_calls + 1
            end,
            send_command = function()
            end,
            ownership_enabled = false,
            promoted_default_on = true,
            ownership_disabled = true,
            promoted_kill_switch = false,
            intent = { kind = "send_command" },
            command = "input /echo test",
        })
        assert_equal(status.ownership_enabled, false, "explicit false must disable promoted command path")
        assert_equal(dispatch_calls, 0, "explicit false must skip dispatcher for promoted command path")
        assert_equal(direct_calls, 1, "explicit false must preserve legacy direct command path")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = run_stop_helper.apply_run_stop_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = true, executed = true, reason = "" }
                end,
            },
            direct_run = function()
                direct_calls = direct_calls + 1
            end,
            run = function()
            end,
            ownership_enabled = false,
            promoted_default_on = true,
            ownership_disabled = false,
            promoted_kill_switch = true,
            intent = { kind = "run_stop" },
        })
        assert_equal(status.ownership_enabled, false, "global kill switch must disable promoted run_stop path")
        assert_equal(dispatch_calls, 0, "global kill switch must skip dispatcher for promoted run_stop path")
        assert_equal(direct_calls, 1, "global kill switch must preserve legacy direct run_stop path")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = target_helper.apply_target_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = true, executed = true, dep_result = true, reason = "" }
                end,
            },
            direct_select_target = function()
                direct_calls = direct_calls + 1
                return true
            end,
            set_target = function()
                return true
            end,
            ownership_enabled = false,
            promoted_default_on = true,
            ownership_disabled = false,
            promoted_kill_switch = false,
            intent = { kind = "select_target" },
            target_id = 123,
        })
        assert_equal(status.ownership_enabled, true, "promoted target path must be default-on when unset")
        assert_equal(status.selected, true, "promoted target path must preserve successful select semantics")
        assert_equal(dispatch_calls, 1, "promoted target path must dispatch when unset")
        assert_equal(direct_calls, 0, "promoted target path must not use direct select when dispatch succeeds")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = turn_helper.apply_turn_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = true, executed = true, reason = "" }
                end,
            },
            direct_turn = function()
                direct_calls = direct_calls + 1
            end,
            turn = function()
            end,
            ownership_enabled = false,
            promoted_default_on = false,
            ownership_disabled = false,
            promoted_kill_switch = false,
            intent = { kind = "turn", heading = 1.0 },
        })
        assert_equal(status.ownership_enabled, false, "default-off turn semantics must stay off without promotion")
        assert_equal(dispatch_calls, 0, "non-promoted turn path must not dispatch when unset")
        assert_equal(direct_calls, 1, "non-promoted turn path must preserve legacy direct turn path")
    end

    local direct_call_patterns = {
        "windower.send_command(",
        "windower.ffxi.run(",
        "windower.ffxi.turn(",
        "uc_settarget.select_by_id(",
    }
    for _, pattern in ipairs(direct_call_patterns) do
        if count_plain(scheduler_source, pattern) ~= 0 then
            error("closure invariant broken by promotion changes for pattern: " .. pattern)
        end
    end

    io.stdout:write("selftest_scheduler_ownership_promotion_static: OK\n")
end

main()
