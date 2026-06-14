local run_stop_ownership = require("uc_scheduler_run_stop_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values are not equal") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function assert_true(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function make_run_recorder()
    local calls = {}
    local fn = function(...)
        calls[#calls + 1] = { ... }
    end
    return fn, calls
end

local function test_default_off_direct_path()
    local direct_run, direct_calls = make_run_recorder()
    local injected_run, injected_calls = make_run_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function()
            dispatch_calls[#dispatch_calls + 1] = true
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = false,
        intent = {
            kind = "run_stop",
        },
    })

    assert_equal(#direct_calls, 1, "default-off direct run call count")
    assert_equal(direct_calls[1][1], false, "default-off direct run argument")
    assert_equal(#dispatch_calls, 0, "default-off dispatcher call count")
    assert_equal(#injected_calls, 0, "default-off injected run call count")
    assert_equal(status.ownership_enabled, false, "default-off ownership status")
    assert_equal(status.dispatched, false, "default-off dispatched status")
    assert_equal(status.dispatch_ok, false, "default-off dispatch_ok status")
    assert_equal(status.dispatch_reason, "", "default-off dispatch_reason status")
    assert_equal(status.fallback_used, false, "default-off fallback status")
    assert_equal(status.stop, true, "default-off stop status")
end

local function test_flag_on_dispatch_success()
    local direct_run, direct_calls = make_run_recorder()
    local injected_run, injected_calls = make_run_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.run == injected_run, "dispatch run dependency mismatch")
            deps.run(false)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = true,
        intent = {
            kind = "run_stop",
        },
    })

    assert_equal(#dispatch_calls, 1, "flag-on success dispatcher call count")
    assert_equal(#injected_calls, 1, "flag-on success injected run call count")
    assert_equal(injected_calls[1][1], false, "flag-on success injected run argument")
    assert_equal(#direct_calls, 0, "flag-on success direct fallback count")
    assert_equal(status.ownership_enabled, true, "flag-on success ownership status")
    assert_equal(status.dispatched, true, "flag-on success dispatched status")
    assert_equal(status.dispatch_ok, true, "flag-on success dispatch_ok status")
    assert_equal(status.dispatch_reason, "executed", "flag-on success dispatch_reason status")
    assert_equal(status.fallback_used, false, "flag-on success fallback status")
    assert_equal(status.stop, true, "flag-on success stop status")
end

local function test_flag_on_dispatch_failure_fallback()
    local direct_run, direct_calls = make_run_recorder()
    local injected_run, injected_calls = make_run_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.run == injected_run, "dispatch run dependency mismatch")
            return { ok = false, executed = false, reason = "missing_dep:run" }
        end,
    }

    local status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = true,
        intent = {
            kind = "run_stop",
        },
    })

    assert_equal(#dispatch_calls, 1, "flag-on failure dispatcher call count")
    assert_equal(#injected_calls, 0, "flag-on failure injected run call count")
    assert_equal(#direct_calls, 1, "flag-on failure fallback direct count")
    assert_equal(direct_calls[1][1], false, "flag-on failure fallback run argument")
    assert_equal(status.ownership_enabled, true, "flag-on failure ownership status")
    assert_equal(status.dispatched, true, "flag-on failure dispatched status")
    assert_equal(status.dispatch_ok, false, "flag-on failure dispatch_ok status")
    assert_equal(status.dispatch_reason, "missing_dep:run", "flag-on failure dispatch_reason status")
    assert_equal(status.fallback_used, true, "flag-on failure fallback status")
    assert_equal(status.stop, true, "flag-on failure stop status")
end

local function main()
    test_default_off_direct_path()
    test_flag_on_dispatch_success()
    test_flag_on_dispatch_failure_fallback()
    io.stdout:write("selftest_run_stop_ownership_runtime: OK\n")
end

main()
