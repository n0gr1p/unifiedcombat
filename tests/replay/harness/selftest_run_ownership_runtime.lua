local run_ownership = require("uc_scheduler_run_ownership")

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

    local status = run_ownership.apply_run_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = false,
        heading = 1.25,
        intent = {
            kind = "run",
            run_x = 0.1,
            run_y = 0.2,
        },
    })

    assert_equal(#direct_calls, 1, "default-off direct run call count")
    assert_equal(direct_calls[1][1], 1.25, "default-off direct run argument")
    assert_equal(#dispatch_calls, 0, "default-off dispatcher call count")
    assert_equal(#injected_calls, 0, "default-off injected run call count")
    assert_equal(status.ownership_enabled, false, "default-off ownership status")
    assert_equal(status.dispatched, false, "default-off dispatched status")
    assert_equal(status.dispatch_ok, false, "default-off dispatch_ok status")
    assert_equal(status.dispatch_reason, "", "default-off dispatch_reason status")
    assert_equal(status.fallback_used, false, "default-off fallback status")
    assert_equal(status.run_x, 0.1, "default-off run_x status")
    assert_equal(status.run_y, 0.2, "default-off run_y status")
    assert_equal(status.heading, 1.25, "default-off heading status")
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
            deps.run(0.5, -0.25)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = run_ownership.apply_run_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = true,
        heading = 0.75,
        intent = {
            kind = "run",
            run_x = 0.5,
            run_y = -0.25,
        },
    })

    assert_equal(#dispatch_calls, 1, "flag-on success dispatcher call count")
    assert_equal(#injected_calls, 1, "flag-on success injected run call count")
    assert_equal(injected_calls[1][1], 0.5, "flag-on success injected run_x")
    assert_equal(injected_calls[1][2], -0.25, "flag-on success injected run_y")
    assert_equal(#direct_calls, 0, "flag-on success direct fallback count")
    assert_equal(status.ownership_enabled, true, "flag-on success ownership status")
    assert_equal(status.dispatched, true, "flag-on success dispatched status")
    assert_equal(status.dispatch_ok, true, "flag-on success dispatch_ok status")
    assert_equal(status.dispatch_reason, "executed", "flag-on success dispatch_reason status")
    assert_equal(status.fallback_used, false, "flag-on success fallback status")
    assert_equal(status.run_x, 0.5, "flag-on success run_x status")
    assert_equal(status.run_y, -0.25, "flag-on success run_y status")
    assert_equal(status.heading, 0.75, "flag-on success heading status")
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

    local status = run_ownership.apply_run_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = true,
        heading = -0.5,
        intent = {
            kind = "run",
            run_x = 1,
            run_y = 0,
        },
    })

    assert_equal(#dispatch_calls, 1, "flag-on failure dispatcher call count")
    assert_equal(#injected_calls, 0, "flag-on failure injected run call count")
    assert_equal(#direct_calls, 1, "flag-on failure fallback direct count")
    assert_equal(direct_calls[1][1], -0.5, "flag-on failure fallback run argument")
    assert_equal(status.ownership_enabled, true, "flag-on failure ownership status")
    assert_equal(status.dispatched, true, "flag-on failure dispatched status")
    assert_equal(status.dispatch_ok, false, "flag-on failure dispatch_ok status")
    assert_equal(status.dispatch_reason, "missing_dep:run", "flag-on failure dispatch_reason status")
    assert_equal(status.fallback_used, true, "flag-on failure fallback status")
    assert_equal(status.run_x, 1, "flag-on failure run_x status")
    assert_equal(status.run_y, 0, "flag-on failure run_y status")
    assert_equal(status.heading, -0.5, "flag-on failure heading status")
end

local function test_heading_adapter_preserves_old_behavior()
    local direct_run_calls = {}
    local direct_run = function(heading)
        direct_run_calls[#direct_run_calls + 1] = heading
    end
    local adapter_calls = {}
    local dispatcher_run = function(run_x, run_y)
        adapter_calls[#adapter_calls + 1] = { run_x, run_y }
        direct_run(2.5)
    end
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            deps.run(intent.run_x, intent.run_y)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = run_ownership.apply_run_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = dispatcher_run,
        ownership_enabled = true,
        heading = 2.5,
        intent = {
            kind = "run",
            run_x = -0.8,
            run_y = 0.6,
        },
    })

    assert_equal(#adapter_calls, 1, "adapter dispatch call count")
    assert_equal(adapter_calls[1][1], -0.8, "adapter run_x input")
    assert_equal(adapter_calls[1][2], 0.6, "adapter run_y input")
    assert_equal(#direct_run_calls, 1, "adapter preserved direct heading call count")
    assert_equal(direct_run_calls[1], 2.5, "adapter preserved direct heading value")
    assert_equal(status.dispatch_ok, true, "adapter dispatch_ok status")
    assert_equal(status.fallback_used, false, "adapter fallback status")
    assert_equal(status.heading, 2.5, "adapter heading status")
end

local function main()
    test_default_off_direct_path()
    test_flag_on_dispatch_success()
    test_flag_on_dispatch_failure_fallback()
    test_heading_adapter_preserves_old_behavior()
    io.stdout:write("selftest_run_ownership_runtime: OK\n")
end

main()
