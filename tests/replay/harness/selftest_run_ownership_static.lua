local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local helper = read("uc_scheduler_run_ownership.lua")
    assert(helper:find("dispatcher.dispatch_intent(intent, {", 1, true), "run helper must dispatch")
    assert(helper:find("run = run", 1, true), "run helper must inject executor")
    assert(helper:find('error("uc_scheduler_run_ownership dispatcher failed:', 1, true), "run rejection must fail fast")
    assert(helper:find("fallback_used = false", 1, true), "run fallback must remain disabled")
    assert(not helper:find("direct_run", 1, true), "run helper must not expose a direct fallback")
    assert(not scheduler:find("windower.ffxi.run(", 1, true), "scheduler must not execute movement directly")
    assert(not scheduler:find("direct_run =", 1, true), "scheduler must not inject movement fallbacks")
    assert(not scheduler:find("UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP", 1, true), "retired vector flag must stay removed")
    io.stdout:write("selftest_run_ownership_static: OK\n")
end

main()
