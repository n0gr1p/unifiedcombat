local ownership = require("uc_scheduler_command_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local sends = {}
    local dispatches = 0
    local send = function(command)
        sends[#sends + 1] = command
    end
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatches = dispatches + 1
            deps.send_command(intent.command)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }
    local status = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = { kind = "send_command", command = "input /ja Test <me>" },
        command = "input /ja Test <me>",
    })
    assert_equal(dispatches, 1, "dispatcher call count")
    assert_equal(#sends, 1, "side-effect call count")
    assert_equal(status.dispatch_ok, true, "dispatch status")
    assert_equal(status.fallback_used, false, "fallback status")
    assert_equal(status.ownership_enabled, true, "ownership status")

    local ok = pcall(function()
        ownership.apply_command_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "commit_rejected" }
            end },
            send_command = send,
            intent = { kind = "send_command", command = "input /ja Blocked <me>" },
            command = "input /ja Blocked <me>",
        })
    end)
    assert_equal(ok, false, "dispatcher rejection must fail fast")
    assert_equal(#sends, 1, "rejection must not use a direct fallback")

    local missing = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = { kind = "send_command", command = "" },
        command = "",
    })
    assert_equal(missing.dispatched, false, "missing command dispatch status")
    assert_equal(missing.dispatch_reason, "missing_command", "missing command reason")
    assert_equal(#sends, 1, "missing command must not execute")

    io.stdout:write("selftest_command_ownership_runtime: OK\n")
end

main()
