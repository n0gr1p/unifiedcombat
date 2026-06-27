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

local function test_promoted_default_on_path()
    local direct_run, direct_calls = make_run_recorder()
    local injected_run, injected_calls = make_run_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "promoted dispatch execute flag")
            assert_true(deps.run == injected_run, "promoted dispatch run dependency mismatch")
            deps.run(false)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = false,
        promoted_default_on = true,
        ownership_disabled = false,
        promoted_kill_switch = false,
        intent = {
            kind = "run_stop",
        },
    })

    assert_equal(#dispatch_calls, 1, "promoted default-on dispatcher call count")
    assert_equal(#injected_calls, 1, "promoted default-on injected run call count")
    assert_equal(injected_calls[1][1], false, "promoted default-on injected run argument")
    assert_equal(#direct_calls, 0, "promoted default-on direct fallback count")
    assert_equal(status.ownership_enabled, true, "promoted default-on ownership status")
    assert_equal(status.dispatched, true, "promoted default-on dispatched status")
    assert_equal(status.dispatch_ok, true, "promoted default-on dispatch_ok status")
    assert_equal(status.dispatch_reason, "executed", "promoted default-on dispatch_reason status")
    assert_equal(status.fallback_used, false, "promoted default-on fallback status")
    assert_equal(status.stop, true, "promoted default-on stop status")
end

local function test_promoted_false_opt_out_and_kill_switch()
    local direct_run, direct_calls = make_run_recorder()
    local injected_run, injected_calls = make_run_recorder()
    local dispatch_calls = 0
    local dispatcher = {
        dispatch_intent = function()
            dispatch_calls = dispatch_calls + 1
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local false_opt_out_status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = dispatcher,
        direct_run = direct_run,
        run = injected_run,
        ownership_enabled = false,
        promoted_default_on = true,
        ownership_disabled = true,
        promoted_kill_switch = false,
        intent = {
            kind = "run_stop",
        },
    })

    assert_equal(#direct_calls, 1, "promoted false opt-out direct run call count")
    assert_equal(direct_calls[1][1], false, "promoted false opt-out direct run argument")
    assert_equal(dispatch_calls, 0, "promoted false opt-out dispatcher call count")
    assert_equal(#injected_calls, 0, "promoted false opt-out injected run call count")
    assert_equal(false_opt_out_status.ownership_enabled, false, "promoted false opt-out ownership status")

    local kill_switch_direct_run, kill_switch_direct_calls = make_run_recorder()
    local kill_switch_injected_run, kill_switch_injected_calls = make_run_recorder()
    local kill_switch_dispatch_calls = 0
    local kill_switch_status = run_stop_ownership.apply_run_stop_ownership({
        dispatcher = {
            dispatch_intent = function()
                kill_switch_dispatch_calls = kill_switch_dispatch_calls + 1
                return { ok = true, executed = true, reason = "executed" }
            end,
        },
        direct_run = kill_switch_direct_run,
        run = kill_switch_injected_run,
        ownership_enabled = false,
        promoted_default_on = true,
        ownership_disabled = false,
        promoted_kill_switch = true,
        intent = {
            kind = "run_stop",
        },
    })

    assert_equal(#kill_switch_direct_calls, 1, "promoted kill-switch direct run call count")
    assert_equal(kill_switch_direct_calls[1][1], false, "promoted kill-switch direct run argument")
    assert_equal(kill_switch_dispatch_calls, 0, "promoted kill-switch dispatcher call count")
    assert_equal(#kill_switch_injected_calls, 0, "promoted kill-switch injected run call count")
    assert_equal(kill_switch_status.ownership_enabled, false, "promoted kill-switch ownership status")
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
    test_promoted_default_on_path()
    test_promoted_false_opt_out_and_kill_switch()
    test_flag_on_dispatch_success()
    test_flag_on_dispatch_failure_fallback()
    io.stdout:write("selftest_run_stop_ownership_runtime: OK\n")
end

main()
