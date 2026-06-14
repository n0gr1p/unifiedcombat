local scheduler_path = "unified_scheduler.lua"
local helper_path = "uc_scheduler_run_ownership.lua"

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
    local run_block = slice_between(
        source,
        "local run_ownership_status = require('uc_scheduler_run_ownership').apply_run_ownership({",
        "fallback_used = run_ownership_status.fallback_used,"
    )

    assert_contains(
        run_block,
        "ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP == true)",
        "run ownership flag must use explicit default-off true comparison"
    )
    assert_contains(
        helper_source,
        "dispatcher.dispatch_intent(intent, {",
        "helper flag-on path must dispatch the existing run intent"
    )
    assert_contains(helper_source, "execute = true", "dispatcher execute mode must be enabled in helper flag-on path")
    assert_contains(
        helper_source,
        "run = run",
        "helper must use injected run dependency for dispatcher"
    )
    assert_contains(
        helper_source,
        "direct_run(heading)",
        "helper fallback/default path must preserve direct heading run via injection"
    )
    assert_contains(
        run_block,
        "direct_run = direct_run",
        "scheduler must inject the aliased direct run dependency"
    )
    assert_contains(
        source,
        "local direct_run = windower.ffxi.run",
        "scheduler must alias windower.ffxi.run before helper injection"
    )
    assert_contains(
        run_block,
        "run = dispatcher_run",
        "scheduler must inject the heading-preserving dispatcher adapter"
    )
    assert_contains(
        source,
        "local dispatcher_run = function(run_x, run_y)",
        "scheduler must define a run adapter for dispatcher execution"
    )
    assert_contains(
        source,
        "return direct_run(heading)",
        "scheduler dispatcher adapter must preserve the original heading call shape"
    )
    assert_contains(
        source,
        "_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE",
        "run validation status global must remain"
    )

    local required_status_fields = {
        "run_x",
        "run_y",
        "heading",
        "ownership_enabled",
        "dispatched",
        "dispatch_ok",
        "dispatch_reason",
        "fallback_used",
    }
    for _, field in ipairs(required_status_fields) do
        assert_contains(run_block, field .. " = run_ownership_status." .. field, "missing status field: " .. field)
        assert_contains(helper_source, field .. " = ", "missing helper status field: " .. field)
    end

    if count_plain(source, "windower.ffxi.run(") ~= 0 then
        error("expected no direct textual windower.ffxi.run( callsites after run ownership seam")
    end

    io.stdout:write("selftest_run_ownership_static: OK\n")
end

main()
