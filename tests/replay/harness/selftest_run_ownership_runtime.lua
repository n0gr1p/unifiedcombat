local ownership = require("uc_scheduler_run_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local calls = {}
    local run = function(x, y)
        calls[#calls + 1] = { x, y }
    end
    local status = ownership.apply_run_ownership({
        dispatcher = {
            dispatch_intent = function(intent, deps)
                deps.run(intent.run_x, intent.run_y)
                return { ok = true, executed = true, reason = "executed" }
            end,
        },
        run = run,
        heading = 0.75,
        intent = { kind = "run", run_x = 0.5, run_y = -0.25 },
    })
    assert_equal(#calls, 1, "run side-effect count")
    assert_equal(calls[1][1], 0.5, "run x")
    assert_equal(calls[1][2], -0.25, "run y")
    assert_equal(status.dispatch_ok, true, "dispatch status")
    assert_equal(status.fallback_used, false, "fallback status")
    assert_equal(status.ownership_enabled, true, "ownership status")

    local ok = pcall(function()
        ownership.apply_run_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "commit_rejected" }
            end },
            run = run,
            heading = 1,
            intent = { kind = "run", run_x = 1, run_y = 0 },
        })
    end)
    assert_equal(ok, false, "dispatcher rejection must fail fast")
    assert_equal(#calls, 1, "rejection must not use a direct fallback")

    io.stdout:write("selftest_run_ownership_runtime: OK\n")
end

main()
