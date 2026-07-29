local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
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
    local helper = read("uc_scheduler_run_stop_ownership.lua")
    assert(helper:find("dispatcher.dispatch_intent(intent, {", 1, true), "run-stop helper must dispatch")
    assert(helper:find("run = run", 1, true), "run-stop helper must inject executor")
    assert(helper:find('error("uc_scheduler_run_stop_ownership dispatcher failed:', 1, true), "run-stop rejection must fail fast")
    assert(helper:find("fallback_used = false", 1, true), "run-stop fallback must remain disabled")
    assert(not helper:find("direct_run", 1, true), "run-stop helper must not expose a direct fallback")
    assert(count(scheduler, "apply_run_stop_ownership({") == 12, "all twelve scheduler stop seams must remain owned")
    assert(not scheduler:find("windower.ffxi.run(", 1, true), "scheduler must not execute movement directly")
    assert(not scheduler:find("direct_run =", 1, true), "scheduler must not inject movement fallbacks")
    io.stdout:write("selftest_run_stop_ownership_static: OK\n")
end

main()
