local ownership = require("uc_scheduler_run_stop_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local calls = {}
    local run = function(value)
        calls[#calls + 1] = value
    end
    local status = ownership.apply_run_stop_ownership({
        dispatcher = {
            dispatch_intent = function(_, deps)
                deps.run(false)
                return { ok = true, executed = true, reason = "executed" }
            end,
        },
        run = run,
        intent = { kind = "run_stop" },
    })
    assert_equal(#calls, 1, "run-stop side-effect count")
    assert_equal(calls[1], false, "run-stop argument")
    assert_equal(status.dispatch_ok, true, "dispatch status")
    assert_equal(status.fallback_used, false, "fallback status")
    assert_equal(status.ownership_enabled, true, "ownership status")

    local ok = pcall(function()
        ownership.apply_run_stop_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "commit_rejected" }
            end },
            run = run,
            intent = { kind = "run_stop" },
        })
    end)
    assert_equal(ok, false, "dispatcher rejection must fail fast")
    assert_equal(#calls, 1, "rejection must not use a direct fallback")

    io.stdout:write("selftest_run_stop_ownership_runtime: OK\n")
end

main()
