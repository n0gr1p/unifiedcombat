local target_ownership = require("uc_scheduler_target_ownership")

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

local function make_select_recorder(return_value)
    local calls = {}
    local fn = function(target_id)
        calls[#calls + 1] = target_id
        return return_value
    end
    return fn, calls
end

local function test_default_off_direct_true()
    local direct_select, direct_calls = make_select_recorder(true)
    local injected_set_target, injected_calls = make_select_recorder(true)
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function()
            dispatch_calls[#dispatch_calls + 1] = true
            return { ok = true, executed = true, reason = "executed", dep_result = true }
        end,
    }

    local status = target_ownership.apply_target_ownership({
        dispatcher = dispatcher,
        direct_select_target = direct_select,
        set_target = injected_set_target,
        ownership_enabled = false,
        intent = {
            kind = "select_target",
            target_id = 1001,
        },
        target_id = 1001,
    })

    assert_equal(#direct_calls, 1, "default-off direct select count")
    assert_equal(direct_calls[1], 1001, "default-off direct target id")
    assert_equal(#dispatch_calls, 0, "default-off dispatcher call count")
    assert_equal(#injected_calls, 0, "default-off injected set_target count")
    assert_equal(status.ownership_enabled, false, "default-off ownership status")
    assert_equal(status.dispatched, false, "default-off dispatched status")
    assert_equal(status.dispatch_ok, false, "default-off dispatch_ok status")
    assert_equal(status.dispatch_reason, "", "default-off dispatch_reason status")
    assert_equal(status.fallback_used, false, "default-off fallback status")
    assert_equal(status.selected, true, "default-off selected status")
end

local function test_default_off_direct_falsey()
    local direct_select, direct_calls = make_select_recorder(nil)
    local injected_set_target, injected_calls = make_select_recorder(true)
    local dispatcher = {
        dispatch_intent = function()
            error("default-off should not dispatch")
        end,
    }

    local status = target_ownership.apply_target_ownership({
        dispatcher = dispatcher,
        direct_select_target = direct_select,
        set_target = injected_set_target,
        ownership_enabled = false,
        intent = {
            kind = "select_target",
            target_id = 1002,
        },
        target_id = 1002,
    })

    assert_equal(#direct_calls, 1, "default-off falsey direct select count")
    assert_equal(#injected_calls, 0, "default-off falsey injected set_target count")
    assert_equal(status.selected, false, "default-off falsey selected status")
end

local function test_flag_on_dispatch_success_true()
    local direct_select, direct_calls = make_select_recorder(false)
    local injected_set_target, injected_calls = make_select_recorder(true)
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.set_target == injected_set_target, "dispatch set_target dependency mismatch")
            local dep_result = deps.set_target(intent.target_id)
            return { ok = true, executed = true, reason = "executed", dep_result = dep_result }
        end,
    }

    local status = target_ownership.apply_target_ownership({
        dispatcher = dispatcher,
        direct_select_target = direct_select,
        set_target = injected_set_target,
        ownership_enabled = true,
        intent = {
            kind = "select_target",
            target_id = 1003,
        },
        target_id = 1003,
    })

    assert_equal(#dispatch_calls, 1, "flag-on success dispatcher count")
    assert_equal(#injected_calls, 1, "flag-on success injected set_target count")
    assert_equal(injected_calls[1], 1003, "flag-on success injected target id")
    assert_equal(#direct_calls, 0, "flag-on success direct fallback count")
    assert_equal(status.ownership_enabled, true, "flag-on success ownership status")
    assert_equal(status.dispatched, true, "flag-on success dispatched status")
    assert_equal(status.dispatch_ok, true, "flag-on success dispatch_ok status")
    assert_equal(status.dispatch_reason, "executed", "flag-on success dispatch_reason status")
    assert_equal(status.fallback_used, false, "flag-on success fallback status")
    assert_equal(status.selected, true, "flag-on success selected status")
end

local function test_flag_on_dispatch_success_false()
    local direct_select, direct_calls = make_select_recorder(true)
    local injected_set_target, injected_calls = make_select_recorder(false)
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            local dep_result = deps.set_target(intent.target_id)
            return { ok = true, executed = true, reason = "executed", dep_result = dep_result }
        end,
    }

    local status = target_ownership.apply_target_ownership({
        dispatcher = dispatcher,
        direct_select_target = direct_select,
        set_target = injected_set_target,
        ownership_enabled = true,
        intent = {
            kind = "select_target",
            target_id = 1004,
        },
        target_id = 1004,
    })

    assert_equal(#injected_calls, 1, "flag-on false injected set_target count")
    assert_equal(#direct_calls, 0, "flag-on false direct fallback count")
    assert_equal(status.dispatch_ok, true, "flag-on false dispatch_ok status")
    assert_equal(status.fallback_used, false, "flag-on false fallback status")
    assert_equal(status.selected, false, "flag-on false selected status")
end

local function test_flag_on_dispatch_failure_fallback()
    local direct_select, direct_calls = make_select_recorder(true)
    local injected_set_target, injected_calls = make_select_recorder(true)
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.set_target == injected_set_target, "dispatch set_target dependency mismatch")
            return { ok = false, executed = false, reason = "missing_dep:set_target" }
        end,
    }

    local status = target_ownership.apply_target_ownership({
        dispatcher = dispatcher,
        direct_select_target = direct_select,
        set_target = injected_set_target,
        ownership_enabled = true,
        intent = {
            kind = "select_target",
            target_id = 1005,
        },
        target_id = 1005,
    })

    assert_equal(#dispatch_calls, 1, "flag-on failure dispatcher count")
    assert_equal(#injected_calls, 0, "flag-on failure injected set_target count")
    assert_equal(#direct_calls, 1, "flag-on failure direct fallback count")
    assert_equal(direct_calls[1], 1005, "flag-on failure direct target id")
    assert_equal(status.ownership_enabled, true, "flag-on failure ownership status")
    assert_equal(status.dispatched, true, "flag-on failure dispatched status")
    assert_equal(status.dispatch_ok, false, "flag-on failure dispatch_ok status")
    assert_equal(status.dispatch_reason, "missing_dep:set_target", "flag-on failure dispatch_reason status")
    assert_equal(status.fallback_used, true, "flag-on failure fallback status")
    assert_equal(status.selected, true, "flag-on failure selected status")
end

local function main()
    test_default_off_direct_true()
    test_default_off_direct_falsey()
    test_flag_on_dispatch_success_true()
    test_flag_on_dispatch_success_false()
    test_flag_on_dispatch_failure_fallback()
    io.stdout:write("selftest_target_ownership_runtime: OK\n")
end

main()
