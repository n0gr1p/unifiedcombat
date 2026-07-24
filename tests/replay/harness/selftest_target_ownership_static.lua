local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local helper = read("uc_scheduler_target_ownership.lua")
    assert(helper:find("dispatcher.dispatch_intent(intent, {", 1, true), "target helper must dispatch")
    assert(helper:find("set_target = set_target", 1, true), "target helper must inject executor")
    assert(helper:find("fallback_used = false", 1, true), "target fallback must remain disabled")
    assert(not helper:find("direct_select_target", 1, true), "target helper must not expose a direct fallback")
    assert(scheduler:find("apply_target_ownership({", 1, true), "scheduler target seam must remain owned")
    assert(not scheduler:find("uc_settarget.select_by_id(", 1, true), "scheduler must not select targets directly")
    assert(not scheduler:find("direct_select_target =", 1, true), "scheduler must not inject target fallbacks")
    io.stdout:write("selftest_target_ownership_static: OK\n")
end

main()
