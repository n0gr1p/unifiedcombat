local scheduler_path = "unified_scheduler.lua"
local helper_path = "uc_scheduler_target_ownership.lua"

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

local function main()
    local source = read_file(scheduler_path)
    local helper_source = read_file(helper_path)
    local target_block = slice_between(
        source,
        "local target_ownership_status = require('uc_scheduler_target_ownership').apply_target_ownership({",
        "selected = target_ownership_status.selected,"
    )

    assert_contains(
        target_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP == true)",
        "ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        helper_source,
        "dispatcher.dispatch_intent(intent, {",
        "helper flag-on path must dispatch the existing select_target intent"
    )
    assert_contains(helper_source, "execute = true", "dispatcher execute mode must be enabled in helper flag-on path")
    assert_contains(
        helper_source,
        "set_target = set_target",
        "helper must use injected set_target dependency for dispatcher"
    )
    assert_contains(
        target_block,
        "set_target = uc_settarget.select_by_id",
        "dispatcher set_target dependency must inject uc_settarget.select_by_id"
    )
    assert_contains(
        helper_source,
        "direct_select_target(target_id)",
        "helper fallback/default path must preserve direct select call via injection"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE",
        "target validation status global must remain"
    )

    local required_status_fields = {
        "ownership_enabled",
        "dispatched",
        "dispatch_ok",
        "dispatch_reason",
        "fallback_used",
        "selected",
    }
    for _, field in ipairs(required_status_fields) do
        assert_contains(target_block, field .. " = target_ownership_status." .. field, "missing status field: " .. field)
        assert_contains(helper_source, field .. " = ", "missing helper status field: " .. field)
    end

    if count_plain(source, "uc_settarget.select_by_id(") ~= 0 then
        error("expected no direct textual uc_settarget.select_by_id( callsite after helper seam")
    end

    if count_plain(source, "uc_settarget.select_by_id") ~= 3 then
        error("expected exactly three uc_settarget.select_by_id references including type check and helper injections")
    end

    io.stdout:write("selftest_target_ownership_static: OK\n")
end

main()
