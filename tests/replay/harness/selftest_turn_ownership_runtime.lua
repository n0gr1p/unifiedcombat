local ownership = require("uc_scheduler_turn_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local calls = {}
    local turn = function(heading)
        calls[#calls + 1] = heading
    end
    local status = ownership.apply_turn_ownership({
        dispatcher = {
            dispatch_intent = function(intent, deps)
                deps.turn(intent.heading)
                return { ok = true, executed = true, reason = "executed" }
            end,
        },
        turn = turn,
        intent = { kind = "turn", heading = 2.5 },
    })
    assert_equal(#calls, 1, "turn side-effect count")
    assert_equal(calls[1], 2.5, "turn heading")
    assert_equal(status.dispatch_ok, true, "dispatch status")
    assert_equal(status.fallback_used, false, "fallback status")
    assert_equal(status.ownership_enabled, true, "ownership status")

    local ok = pcall(function()
        ownership.apply_turn_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "commit_rejected" }
            end },
            turn = turn,
            intent = { kind = "turn", heading = 1 },
        })
    end)
    assert_equal(ok, false, "dispatcher rejection must fail fast")
    assert_equal(#calls, 1, "rejection must not use a direct fallback")

    io.stdout:write("selftest_turn_ownership_runtime: OK\n")
end

main()
