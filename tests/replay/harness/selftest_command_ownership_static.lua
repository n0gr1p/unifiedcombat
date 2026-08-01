local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then error(message or ("missing: " .. needle)) end
end

local function count(text, needle)
    local total, at = 0, 1
    while true do
        local found = text:find(needle, at, true)
        if not found then return total end
        total, at = total + 1, found + #needle
    end
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local helper = read("uc_scheduler_command_ownership.lua")
    assert_contains(helper, "dispatcher.dispatch_intent(intent, {", "command helper must dispatch")
    assert_contains(helper, "send_command = send_command", "command helper must inject executor")
    assert_contains(helper, 'error("uc_scheduler_command_ownership dispatcher failed:', "command rejection must fail fast")
    assert_contains(helper, "fallback_used = false", "command fallback must remain disabled")
    assert(count(helper, "direct_send_command") == 0, "command helper must not expose a direct fallback")
    assert(count(scheduler, "apply_command_ownership({") == 7, "all seven active scheduler command seams must remain owned")
    assert(count(scheduler, "direct_send_command =") == 0, "scheduler must not inject command fallbacks")
    assert(count(scheduler, "windower.send_command(") == 0, "scheduler must not execute commands directly")
    io.stdout:write("selftest_command_ownership_static: OK\n")
end

main()
