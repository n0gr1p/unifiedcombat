local scheduler_path = "unified_scheduler.lua"

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

local function main()
    local source = read_file(scheduler_path)

    local direct_call_patterns = {
        "windower.send_command(",
        "windower.ffxi.run(",
        "windower.ffxi.turn(",
        "uc_settarget.select_by_id(",
    }

    for _, pattern in ipairs(direct_call_patterns) do
        if count_plain(source, pattern) ~= 0 then
            error("expected zero direct textual scheduler side-effect call expressions for pattern: " .. pattern)
        end
    end

    local required_helpers = {
        "require('uc_scheduler_command_ownership')",
        "require('uc_scheduler_run_stop_ownership')",
        "require('uc_scheduler_run_ownership')",
        "require('uc_scheduler_target_ownership')",
        "require('uc_scheduler_turn_ownership')",
    }
    for _, needle in ipairs(required_helpers) do
        assert_contains(source, needle, "scheduler must require/use helper: " .. needle)
    end

    assert_contains(source, "send_command = windower.send_command", "scheduler must still inject send_command dependencies instead of calling them directly")
    assert_contains(source, "run = windower.ffxi.run", "scheduler must still inject run dependencies instead of calling them directly")
    assert_contains(source, "local direct_run = windower.ffxi.run", "scheduler must alias direct run injection for vector ownership")
    assert_contains(source, "turn = windower.ffxi.turn", "scheduler must still inject turn dependencies instead of calling them directly")
    assert_contains(source, "set_target = uc_settarget.select_by_id", "scheduler must still inject target dependencies instead of calling them directly")

    io.stdout:write("selftest_scheduler_ownership_closure_static: OK\n")
end

main()
