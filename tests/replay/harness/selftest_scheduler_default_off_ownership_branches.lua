local scheduler_path = "unified_scheduler.lua"
local command_helper_path = "uc_scheduler_command_ownership.lua"
local run_stop_helper_path = "uc_scheduler_run_stop_ownership.lua"

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

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text present: " .. needle))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
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

local function explicit_true_only(value)
    return value == true
end

local function assert_default_off_gate(block, flag_name, helper_call, injected_dependency, status_prefix)
    assert_contains(
        block,
        "ownership_enabled = (_G." .. flag_name .. " == true)",
        "branch must use explicit true-only default-off gate: " .. flag_name
    )
    assert_not_contains(
        block,
        "ownership_disabled = ",
        "default-off branch must not support promoted false opt-out semantics: " .. flag_name
    )
    assert_not_contains(
        block,
        "promoted_default_on = true",
        "default-off branch must not be promoted: " .. flag_name
    )
    assert_not_contains(
        block,
        "promoted_kill_switch = ",
        "default-off branch must not wire promoted kill switch semantics: " .. flag_name
    )
    assert_contains(block, helper_call, "branch must route through expected helper seam: " .. flag_name)
    assert_contains(block, injected_dependency, "branch must inject expected direct dependency: " .. flag_name)

    local required_status_fields = {
        "ownership_enabled",
        "dispatched",
        "dispatch_ok",
        "dispatch_reason",
        "fallback_used",
    }
    for _, field in ipairs(required_status_fields) do
        assert_contains(
            block,
            field .. " = " .. status_prefix .. "." .. field,
            "missing branch status field " .. field .. " for " .. flag_name
        )
    end
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local command_helper = dofile(command_helper_path)
    local run_stop_helper = dofile(run_stop_helper_path)

    local doom_run_stop_block = slice_between_nth(
        scheduler_source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,",
        1
    )
    local doom_command_block = slice_between_nth(
        scheduler_source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        1
    )
    local combat_spell_settle_run_stop_block = slice_between_nth(
        scheduler_source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,",
        7
    )
    local combat_spell_prep_wait_run_stop_block = slice_between_nth(
        scheduler_source,
        "local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "stop = run_stop_ownership_status.stop,",
        8
    )

    assert_equal(explicit_true_only(nil), false, "unset flag must stay disabled under explicit true-only semantics")
    assert_equal(explicit_true_only(false), false, "false flag must stay disabled under explicit true-only semantics")
    assert_equal(explicit_true_only(true), true, "true flag must enable explicit true-only semantics")

    assert_default_off_gate(
        doom_command_block,
        "UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP",
        "require('uc_scheduler_command_ownership').apply_command_ownership({",
        "send_command = windower.send_command",
        "command_ownership_status"
    )
    assert_contains(
        doom_command_block,
        "command_present = command_ownership_status.command_present",
        "doom command branch must preserve command_present status field"
    )

    assert_default_off_gate(
        doom_run_stop_block,
        "UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP",
        "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "run = windower.ffxi.run",
        "run_stop_ownership_status"
    )
    assert_contains(
        doom_run_stop_block,
        "stop = run_stop_ownership_status.stop",
        "doom run_stop branch must preserve stop status field"
    )

    assert_default_off_gate(
        combat_spell_prep_wait_run_stop_block,
        "UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP",
        "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({",
        "run = windower.ffxi.run",
        "run_stop_ownership_status"
    )
    assert_contains(
        combat_spell_prep_wait_run_stop_block,
        "stop = run_stop_ownership_status.stop",
        "combat spell prep-wait branch must preserve stop status field"
    )

    assert_contains(
        scheduler_source,
        "_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE",
        "doom command validation status global must remain"
    )
    assert_contains(
        scheduler_source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE",
        "doom run_stop validation status global must remain"
    )
    assert_contains(
        scheduler_source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE",
        "combat spell settle validation status global must remain"
    )
    assert_contains(
        scheduler_source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE",
        "combat spell prep-wait validation status global must remain"
    )

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
            direct_send_command = function(command)
                assert_equal(command, "input /item \"Holy Water\" <me>", "direct doom command fallback path must preserve command text")
                direct_calls = direct_calls + 1
            end,
            send_command = function()
            end,
            ownership_enabled = false,
            intent = { kind = "send_command", command = "input /item \"Holy Water\" <me>" },
            command = "input /item \"Holy Water\" <me>",
        })
        assert_equal(status.ownership_enabled, false, "doom command helper must remain default-off when branch gate is false")
        assert_equal(dispatch_calls, 0, "doom command helper must not dispatch while default-off")
        assert_equal(direct_calls, 1, "doom command helper must preserve one direct send while default-off")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = command_helper.apply_command_ownership({
            dispatcher = {
                dispatch_intent = function(intent, deps)
                    dispatch_calls = dispatch_calls + 1
                    assert_equal(intent.kind, "send_command", "doom command true-path must dispatch send_command intent")
                    assert_equal(type(deps.send_command), "function", "doom command true-path must inject send_command dependency")
                    return { ok = true, executed = true, reason = "" }
                end,
            },
            direct_send_command = function()
                direct_calls = direct_calls + 1
            end,
            send_command = function()
            end,
            ownership_enabled = true,
            intent = { kind = "send_command", command = "input /item \"Holy Water\" <me>" },
            command = "input /item \"Holy Water\" <me>",
        })
        assert_equal(status.ownership_enabled, true, "doom command helper must dispatch when explicitly enabled")
        assert_equal(status.dispatched, true, "doom command helper must mark dispatched on explicit true")
        assert_equal(status.dispatch_ok, true, "doom command helper must report dispatcher success")
        assert_equal(status.fallback_used, false, "doom command helper must not fall back after dispatcher success")
        assert_equal(dispatch_calls, 1, "doom command helper must dispatch once on explicit true")
        assert_equal(direct_calls, 0, "doom command helper must not use direct send after dispatcher success")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = command_helper.apply_command_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = false, executed = false, reason = "forced_failure" }
                end,
            },
            direct_send_command = function()
                direct_calls = direct_calls + 1
            end,
            send_command = function()
            end,
            ownership_enabled = true,
            intent = { kind = "send_command", command = "input /item \"Holy Water\" <me>" },
            command = "input /item \"Holy Water\" <me>",
        })
        assert_equal(status.dispatch_ok, false, "doom command helper fallback case must surface failed dispatch")
        assert_equal(status.fallback_used, true, "doom command helper fallback case must preserve direct fallback")
        assert_equal(dispatch_calls, 1, "doom command helper fallback case must try dispatcher once")
        assert_equal(direct_calls, 1, "doom command helper fallback case must send directly once")
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
            direct_run = function(value)
                assert_equal(value, false, "default-off run_stop path must preserve direct run(false)")
                direct_calls = direct_calls + 1
            end,
            run = function()
            end,
            ownership_enabled = false,
            intent = { kind = "run_stop" },
        })
        assert_equal(status.ownership_enabled, false, "default-off run_stop helper must stay disabled when branch gate is false")
        assert_equal(dispatch_calls, 0, "default-off run_stop helper must not dispatch while default-off")
        assert_equal(direct_calls, 1, "default-off run_stop helper must preserve one direct run(false) while default-off")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = run_stop_helper.apply_run_stop_ownership({
            dispatcher = {
                dispatch_intent = function(intent, deps)
                    dispatch_calls = dispatch_calls + 1
                    assert_equal(intent.kind, "run_stop", "explicit true run_stop path must dispatch run_stop intent")
                    assert_equal(type(deps.run), "function", "explicit true run_stop path must inject run dependency")
                    return { ok = true, executed = true, reason = "" }
                end,
            },
            direct_run = function()
                direct_calls = direct_calls + 1
            end,
            run = function()
            end,
            ownership_enabled = true,
            intent = { kind = "run_stop" },
        })
        assert_equal(status.ownership_enabled, true, "explicit true run_stop path must dispatch")
        assert_equal(status.dispatched, true, "explicit true run_stop path must mark dispatched")
        assert_equal(status.dispatch_ok, true, "explicit true run_stop path must report dispatcher success")
        assert_equal(status.fallback_used, false, "explicit true run_stop path must not fall back after dispatcher success")
        assert_equal(dispatch_calls, 1, "explicit true run_stop path must dispatch once")
        assert_equal(direct_calls, 0, "explicit true run_stop path must not use direct stop after dispatcher success")
    end

    do
        local direct_calls = 0
        local dispatch_calls = 0
        local status = run_stop_helper.apply_run_stop_ownership({
            dispatcher = {
                dispatch_intent = function()
                    dispatch_calls = dispatch_calls + 1
                    return { ok = false, executed = false, reason = "forced_failure" }
                end,
            },
            direct_run = function(value)
                assert_equal(value, false, "run_stop fallback path must preserve direct run(false)")
                direct_calls = direct_calls + 1
            end,
            run = function()
            end,
            ownership_enabled = true,
            intent = { kind = "run_stop" },
        })
        assert_equal(status.dispatch_ok, false, "run_stop fallback case must surface failed dispatch")
        assert_equal(status.fallback_used, true, "run_stop fallback case must preserve direct fallback")
        assert_equal(dispatch_calls, 1, "run_stop fallback case must try dispatcher once")
        assert_equal(direct_calls, 1, "run_stop fallback case must execute direct fallback once")
    end

    local direct_call_patterns = {
        "windower.send_command(",
        "windower.ffxi.run(",
        "windower.ffxi.turn(",
        "uc_settarget.select_by_id(",
    }
    for _, pattern in ipairs(direct_call_patterns) do
        if count_plain(scheduler_source, pattern) ~= 0 then
            error("scheduler closure invariant broken for pattern: " .. pattern)
        end
    end

    io.stdout:write("selftest_scheduler_default_off_ownership_branches: OK\n")
end

main()
