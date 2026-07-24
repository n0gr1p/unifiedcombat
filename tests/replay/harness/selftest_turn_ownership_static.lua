local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local helper = read("uc_scheduler_turn_ownership.lua")
    assert(helper:find("dispatcher.dispatch_intent(intent, {", 1, true), "turn helper must dispatch")
    assert(helper:find("turn = turn", 1, true), "turn helper must inject executor")
    assert(helper:find('error("uc_scheduler_turn_ownership dispatcher failed:', 1, true), "turn rejection must fail fast")
    assert(helper:find("fallback_used = false", 1, true), "turn fallback must remain disabled")
    assert(not helper:find("direct_turn", 1, true), "turn helper must not expose a direct fallback")
    assert(scheduler:find("apply_turn_ownership({", 1, true), "scheduler turn seam must remain owned")
    assert(not scheduler:find("windower.ffxi.turn(", 1, true), "scheduler must not turn directly")
    assert(not scheduler:find("direct_turn =", 1, true), "scheduler must not inject turn fallbacks")
    io.stdout:write("selftest_turn_ownership_static: OK\n")
end

main()
