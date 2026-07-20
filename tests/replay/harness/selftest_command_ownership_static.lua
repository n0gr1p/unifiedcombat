local scheduler_path = "unified_scheduler.lua"
local helper_path = "uc_scheduler_command_ownership.lua"

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

local function slice_between(text, start_needle, end_needle, start_occurrence)
    local start_pos = find_nth_plain(text, start_needle, start_occurrence or 1)
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
    local doom_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        1
    )
    local internal_dispatch_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        2
    )
    local ja_target_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        3
    )
    local ja_self_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        4
    )
    local spell_target_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        5
    )
    local spell_self_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        6
    )
    local maintenance_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "command_present = command_ownership_status.command_present,",
        8
    )
    local defensive_command_block = slice_between(
        source,
        "local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({",
        "fallback_used = command_ownership_status.fallback_used,",
        7
    )

    assert_contains(
        doom_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP == true)",
        "doom ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        internal_dispatch_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP == true)",
        "internal dispatch ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        defensive_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == true)",
        "defensive ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        ja_target_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true)",
        "JA target ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        ja_self_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true)",
        "JA self ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        spell_target_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true)",
        "spell target ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        spell_self_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true)",
        "spell self ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        maintenance_command_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == true)",
        "maintenance ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        helper_source,
        "dispatcher.dispatch_intent(intent, {",
        "helper flag-on path must dispatch the existing send_command intent"
    )
    assert_contains(helper_source, "execute = true", "dispatcher execute mode must be enabled in helper flag-on path")
    assert_contains(
        helper_source,
        "send_command = send_command",
        "helper must use injected send_command dependency for dispatcher"
    )
    assert_contains(
        internal_dispatch_command_block,
        "send_command = windower.send_command",
        "internal dispatch dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        doom_command_block,
        "send_command = windower.send_command",
        "doom dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        maintenance_command_block,
        "send_command = windower.send_command",
        "maintenance dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        defensive_command_block,
        "send_command = windower.send_command",
        "defensive dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        ja_target_command_block,
        "send_command = windower.send_command",
        "JA target dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        ja_self_command_block,
        "send_command = windower.send_command",
        "JA self dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        spell_target_command_block,
        "send_command = windower.send_command",
        "spell target dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        spell_self_command_block,
        "send_command = windower.send_command",
        "spell self dispatcher send_command dependency must inject windower.send_command"
    )
    assert_contains(
        helper_source,
        "direct_send_command(command)",
        "helper fallback/default path must preserve direct send call via injection"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE",
        "Doom Holy Water validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_DISPATCH_VALIDATE",
        "internal dispatch validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_MAINTENANCE_COR_COMMAND_VALIDATE",
        "maintenance COR validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE",
        "defensive_internal validation status global must remain"
    )
    assert_contains(
        source,
        "combat_core.try_dispatch_ws_with_intent(ws, expected_tid, settings, selected.skillchain_plan)",
        "scheduler WS dispatch must use the core intent owner and pass the skillchain plan"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE",
        "JA target validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE",
        "JA self validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_SPELL_TARGET_COMMAND_VALIDATE",
        "spell target validation status global must remain"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE",
        "spell self validation status global must remain"
    )

    local required_status_fields = {
        "ownership_enabled",
        "dispatched",
        "dispatch_ok",
        "dispatch_reason",
        "fallback_used",
        "command_present",
    }
    for _, field in ipairs(required_status_fields) do
        assert_contains(doom_command_block, field .. " = command_ownership_status." .. field, "missing doom status field: " .. field)
        assert_contains(internal_dispatch_command_block, field .. " = command_ownership_status." .. field, "missing internal dispatch status field: " .. field)
        assert_contains(maintenance_command_block, field .. " = command_ownership_status." .. field, "missing maintenance status field: " .. field)
        assert_contains(defensive_command_block, field .. " = command_ownership_status." .. field, "missing defensive status field: " .. field)
        assert_contains(ja_target_command_block, field .. " = command_ownership_status." .. field, "missing JA target status field: " .. field)
        assert_contains(ja_self_command_block, field .. " = command_ownership_status." .. field, "missing JA self status field: " .. field)
        assert_contains(spell_target_command_block, field .. " = command_ownership_status." .. field, "missing spell target status field: " .. field)
        assert_contains(spell_self_command_block, field .. " = command_ownership_status." .. field, "missing spell self status field: " .. field)
        assert_contains(helper_source, field .. " = ", "missing helper status field: " .. field)
    end

    if count_plain(source, "windower.send_command(") ~= 0 then
        error("expected eight helper-owned command paths and zero remaining textual windower.send_command( callsites")
    end

    io.stdout:write("selftest_command_ownership_static: OK\n")
end

main()
