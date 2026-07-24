local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    assert(not scheduler:find("UC_SCHED_P1_ENABLE_DISPATCHER_", 1, true), "Phase 2 must not retain dispatcher ownership feature flags")
    assert(not scheduler:find("ownership_enabled = (", 1, true), "scheduler callsites must not branch on ownership")
    assert(not scheduler:find("ownership_disabled =", 1, true), "scheduler callsites must not expose ownership opt-outs")
    io.stdout:write("selftest_scheduler_ownership_flags_static: OK\n")
end

main()
