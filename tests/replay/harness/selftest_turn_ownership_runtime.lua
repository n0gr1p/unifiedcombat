local turn_ownership = require("uc_scheduler_turn_ownership")

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

local function make_turn_recorder()
    local calls = {}
    local fn = function(heading)
        calls[#calls + 1] = heading
    end
    return fn, calls
end

local function test_default_off_direct_path()
    local direct_turn, direct_calls = make_turn_recorder()
    local injected_turn, injected_calls = make_turn_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function()
            dispatch_calls[#dispatch_calls + 1] = true
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = turn_ownership.apply_turn_ownership({
        dispatcher = dispatcher,
        direct_turn = direct_turn,
        turn = injected_turn,
        ownership_enabled = false,
        intent = {
            kind = "turn",
            heading = 1.25,
        },
    })

    assert_equal(#direct_calls, 1, "default-off direct turn call count")
    assert_equal(direct_calls[1], 1.25, "default-off direct heading")
    assert_equal(#dispatch_calls, 0, "default-off dispatcher call count")
    assert_equal(#injected_calls, 0, "default-off injected turn call count")
    assert_equal(status.ownership_enabled, false, "default-off ownership status")
    assert_equal(status.dispatched, false, "default-off dispatched status")
    assert_equal(status.dispatch_ok, false, "default-off dispatch_ok status")
    assert_equal(status.dispatch_reason, "", "default-off dispatch_reason status")
    assert_equal(status.fallback_used, false, "default-off fallback status")
end

local function test_flag_on_dispatch_success()
    local direct_turn, direct_calls = make_turn_recorder()
    local injected_turn, injected_calls = make_turn_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.turn == injected_turn, "dispatch turn dependency mismatch")
            deps.turn(intent.heading)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = turn_ownership.apply_turn_ownership({
        dispatcher = dispatcher,
        direct_turn = direct_turn,
        turn = injected_turn,
        ownership_enabled = true,
        intent = {
            kind = "turn",
            heading = 2.5,
        },
    })

    assert_equal(#dispatch_calls, 1, "flag-on success dispatcher call count")
    assert_equal(#injected_calls, 1, "flag-on success injected turn call count")
    assert_equal(injected_calls[1], 2.5, "flag-on success injected heading")
    assert_equal(#direct_calls, 0, "flag-on success direct fallback count")
    assert_equal(status.ownership_enabled, true, "flag-on success ownership status")
    assert_equal(status.dispatched, true, "flag-on success dispatched status")
    assert_equal(status.dispatch_ok, true, "flag-on success dispatch_ok status")
    assert_equal(status.dispatch_reason, "executed", "flag-on success dispatch_reason status")
    assert_equal(status.fallback_used, false, "flag-on success fallback status")
end

local function test_flag_on_dispatch_failure_fallback()
    local direct_turn, direct_calls = make_turn_recorder()
    local injected_turn, injected_calls = make_turn_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.turn == injected_turn, "dispatch turn dependency mismatch")
            return { ok = false, executed = false, reason = "missing_dep:turn" }
        end,
    }

    local status = turn_ownership.apply_turn_ownership({
        dispatcher = dispatcher,
        direct_turn = direct_turn,
        turn = injected_turn,
        ownership_enabled = true,
        intent = {
            kind = "turn",
            heading = 3.75,
        },
    })

    assert_equal(#dispatch_calls, 1, "flag-on failure dispatcher call count")
    assert_equal(#injected_calls, 0, "flag-on failure injected turn call count")
    assert_equal(#direct_calls, 1, "flag-on failure fallback direct count")
    assert_equal(direct_calls[1], 3.75, "flag-on failure fallback heading")
    assert_equal(status.ownership_enabled, true, "flag-on failure ownership status")
    assert_equal(status.dispatched, true, "flag-on failure dispatched status")
    assert_equal(status.dispatch_ok, false, "flag-on failure dispatch_ok status")
    assert_equal(status.dispatch_reason, "missing_dep:turn", "flag-on failure dispatch_reason status")
    assert_equal(status.fallback_used, true, "flag-on failure fallback status")
end

local function main()
    test_default_off_direct_path()
    test_flag_on_dispatch_success()
    test_flag_on_dispatch_failure_fallback()
    io.stdout:write("selftest_turn_ownership_runtime: OK\n")
end

main()
