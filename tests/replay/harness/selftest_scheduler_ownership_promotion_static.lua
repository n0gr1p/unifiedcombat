local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local helpers = {
        "uc_scheduler_command_ownership.lua",
        "uc_scheduler_run_ownership.lua",
        "uc_scheduler_run_stop_ownership.lua",
        "uc_scheduler_target_ownership.lua",
        "uc_scheduler_turn_ownership.lua",
    }
    assert(not scheduler:find("UC_SCHED_P1_ENABLE_DISPATCHER_", 1, true), "transitional ownership flags must be retired")
    assert(not scheduler:find("UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP", 1, true), "promotion kill switch must be retired")
    assert(not scheduler:find("promoted_default_on", 1, true), "promotion markers must be retired")
    assert(not scheduler:find("promoted_kill_switch", 1, true), "promotion kill-switch markers must be retired")
    for _, path in ipairs(helpers) do
        local source = read(path)
        assert(source:find("ownership_enabled = true", 1, true), path .. " must report dispatcher ownership")
        assert(source:find("fallback_used = false", 1, true), path .. " must report no fallback")
        assert(not source:find("promoted_default_on", 1, true), path .. " must not retain promotion branching")
    end
    io.stdout:write("selftest_scheduler_ownership_promotion_static: OK\n")
end

main()
