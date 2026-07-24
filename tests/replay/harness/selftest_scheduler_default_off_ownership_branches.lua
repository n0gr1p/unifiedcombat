local command_ownership = require("uc_scheduler_command_ownership")
local run_stop_ownership = require("uc_scheduler_run_stop_ownership")

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local source = read("unified_scheduler.lua")
    assert(source:find("_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE", 1, true), "Doom command diagnostics must remain")
    assert(source:find("_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE", 1, true), "Doom stop diagnostics must remain")
    assert(not source:find("UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_", 1, true), "Doom ownership flags must be retired")

    local command_calls, stop_calls = 0, 0
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            if intent.kind == "send_command" then
                deps.send_command(intent.command)
            elseif intent.kind == "run_stop" then
                deps.run(false)
            else
                error("unexpected Doom intent kind")
            end
            return { ok = true, executed = true, reason = "executed" }
        end,
    }
    local command_status = command_ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = function() command_calls = command_calls + 1 end,
        intent = { kind = "send_command", command = "input /item \"Holy Water\" <me>" },
        command = "input /item \"Holy Water\" <me>",
    })
    local stop_status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = dispatcher,
        run = function(value)
            assert_equal(value, false, "Doom stop argument")
            stop_calls = stop_calls + 1
        end,
        intent = { kind = "run_stop" },
    })
    assert_equal(command_calls, 1, "Doom command exactly-once execution")
    assert_equal(stop_calls, 1, "Doom stop exactly-once execution")
    assert_equal(command_status.fallback_used, false, "Doom command fallback status")
    assert_equal(stop_status.fallback_used, false, "Doom stop fallback status")

    local ok = pcall(function()
        command_ownership.apply_command_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "commit_rejected" }
            end },
            send_command = function() command_calls = command_calls + 1 end,
            intent = { kind = "send_command", command = "input /item \"Holy Water\" <me>" },
            command = "input /item \"Holy Water\" <me>",
        })
    end)
    assert_equal(ok, false, "Doom dispatcher rejection must fail fast")
    assert_equal(command_calls, 1, "Doom rejection must not execute a fallback")

    io.stdout:write("selftest_scheduler_default_off_ownership_branches: OK\n")
end

main()
