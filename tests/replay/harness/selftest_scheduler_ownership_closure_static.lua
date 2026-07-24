local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local direct_calls = {
        "windower.send_command(",
        "windower.ffxi.run(",
        "windower.ffxi.turn(",
        "uc_settarget.select_by_id(",
        "uc_attack.engage_target(",
        "uc_attack.switch_target(",
        "uc_attack.disengage(",
    }
    for _, pattern in ipairs(direct_calls) do
        assert(not scheduler:find(pattern, 1, true), "scheduler monopoly broken by direct call: " .. pattern)
    end
    local required = {
        "require('uc_scheduler_command_ownership')",
        "require('uc_scheduler_run_stop_ownership')",
        "require('uc_scheduler_target_ownership')",
        "require('uc_scheduler_turn_ownership')",
        "require('uc_scheduler_dispatcher').dispatch_intent({",
    }
    for _, pattern in ipairs(required) do
        assert(scheduler:find(pattern, 1, true), "missing scheduler ownership route: " .. pattern)
    end
    assert(not scheduler:find("direct_send_command =", 1, true), "command fallback injection must stay removed")
    assert(not scheduler:find("direct_run =", 1, true), "movement fallback injection must stay removed")
    assert(not scheduler:find("direct_turn =", 1, true), "turn fallback injection must stay removed")
    assert(not scheduler:find("direct_select_target =", 1, true), "target fallback injection must stay removed")
    io.stdout:write("selftest_scheduler_ownership_closure_static: OK\n")
end

main()
