local command_ownership = require("uc_scheduler_command_ownership")

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

local function make_command_recorder()
    local calls = {}
    local fn = function(command)
        calls[#calls + 1] = command
    end
    return fn, calls
end

local function test_default_off_direct_path()
    local direct_send_command, direct_calls = make_command_recorder()
    local injected_send_command, injected_calls = make_command_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function()
            dispatch_calls[#dispatch_calls + 1] = true
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = command_ownership.apply_command_ownership({
        dispatcher = dispatcher,
        direct_send_command = direct_send_command,
        send_command = injected_send_command,
        ownership_enabled = false,
        intent = {
            kind = "send_command",
            command = "input /ja \"Corsair Roll\" <me>",
        },
        command = "input /ja \"Corsair Roll\" <me>",
    })

    assert_equal(#direct_calls, 1, "default-off direct send count")
    assert_equal(direct_calls[1], "input /ja \"Corsair Roll\" <me>", "default-off direct command")
    assert_equal(#dispatch_calls, 0, "default-off dispatcher count")
    assert_equal(#injected_calls, 0, "default-off injected send count")
    assert_equal(status.ownership_enabled, false, "default-off ownership status")
    assert_equal(status.dispatched, false, "default-off dispatched status")
    assert_equal(status.dispatch_ok, false, "default-off dispatch_ok status")
    assert_equal(status.dispatch_reason, "", "default-off dispatch_reason status")
    assert_equal(status.fallback_used, false, "default-off fallback status")
    assert_equal(status.command_present, true, "default-off command_present status")
end

local function test_flag_on_dispatch_success()
    local direct_send_command, direct_calls = make_command_recorder()
    local injected_send_command, injected_calls = make_command_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.send_command == injected_send_command, "dispatch send_command dependency mismatch")
            deps.send_command(intent.command)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = command_ownership.apply_command_ownership({
        dispatcher = dispatcher,
        direct_send_command = direct_send_command,
        send_command = injected_send_command,
        ownership_enabled = true,
        intent = {
            kind = "send_command",
            command = "input /ja \"Corsair Roll\" <me>",
        },
        command = "input /ja \"Corsair Roll\" <me>",
    })

    assert_equal(#dispatch_calls, 1, "flag-on success dispatcher count")
    assert_equal(#injected_calls, 1, "flag-on success injected send count")
    assert_equal(injected_calls[1], "input /ja \"Corsair Roll\" <me>", "flag-on success injected command")
    assert_equal(#direct_calls, 0, "flag-on success direct fallback count")
    assert_equal(status.ownership_enabled, true, "flag-on success ownership status")
    assert_equal(status.dispatched, true, "flag-on success dispatched status")
    assert_equal(status.dispatch_ok, true, "flag-on success dispatch_ok status")
    assert_equal(status.dispatch_reason, "executed", "flag-on success dispatch_reason status")
    assert_equal(status.fallback_used, false, "flag-on success fallback status")
    assert_equal(status.command_present, true, "flag-on success command_present status")
end

local function test_flag_on_dispatch_failure_fallback()
    local direct_send_command, direct_calls = make_command_recorder()
    local injected_send_command, injected_calls = make_command_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatch_calls[#dispatch_calls + 1] = {
                intent = intent,
                deps = deps,
            }
            assert_equal(deps.execute, true, "dispatch execute flag")
            assert_true(deps.send_command == injected_send_command, "dispatch send_command dependency mismatch")
            return { ok = false, executed = false, reason = "missing_dep:send_command" }
        end,
    }

    local status = command_ownership.apply_command_ownership({
        dispatcher = dispatcher,
        direct_send_command = direct_send_command,
        send_command = injected_send_command,
        ownership_enabled = true,
        intent = {
            kind = "send_command",
            command = "input /ja \"Corsair Roll\" <me>",
        },
        command = "input /ja \"Corsair Roll\" <me>",
    })

    assert_equal(#dispatch_calls, 1, "flag-on failure dispatcher count")
    assert_equal(#injected_calls, 0, "flag-on failure injected send count")
    assert_equal(#direct_calls, 1, "flag-on failure direct fallback count")
    assert_equal(direct_calls[1], "input /ja \"Corsair Roll\" <me>", "flag-on failure direct command")
    assert_equal(status.ownership_enabled, true, "flag-on failure ownership status")
    assert_equal(status.dispatched, true, "flag-on failure dispatched status")
    assert_equal(status.dispatch_ok, false, "flag-on failure dispatch_ok status")
    assert_equal(status.dispatch_reason, "missing_dep:send_command", "flag-on failure dispatch_reason status")
    assert_equal(status.fallback_used, true, "flag-on failure fallback status")
    assert_equal(status.command_present, true, "flag-on failure command_present status")
end

local function test_missing_command_skips_send_and_dispatch()
    local direct_send_command, direct_calls = make_command_recorder()
    local injected_send_command, injected_calls = make_command_recorder()
    local dispatch_calls = {}
    local dispatcher = {
        dispatch_intent = function()
            dispatch_calls[#dispatch_calls + 1] = true
            return { ok = true, executed = true, reason = "executed" }
        end,
    }

    local status = command_ownership.apply_command_ownership({
        dispatcher = dispatcher,
        direct_send_command = direct_send_command,
        send_command = injected_send_command,
        ownership_enabled = true,
        intent = {
            kind = "send_command",
            command = "",
        },
        command = "",
    })

    assert_equal(#dispatch_calls, 0, "missing command dispatcher count")
    assert_equal(#injected_calls, 0, "missing command injected send count")
    assert_equal(#direct_calls, 0, "missing command direct send count")
    assert_equal(status.ownership_enabled, true, "missing command ownership status")
    assert_equal(status.dispatched, false, "missing command dispatched status")
    assert_equal(status.dispatch_ok, false, "missing command dispatch_ok status")
    assert_equal(status.dispatch_reason, "missing_command", "missing command dispatch_reason status")
    assert_equal(status.fallback_used, false, "missing command fallback status")
    assert_equal(status.command_present, false, "missing command command_present status")
end

local function main()
    test_default_off_direct_path()
    test_flag_on_dispatch_success()
    test_flag_on_dispatch_failure_fallback()
    test_missing_command_skips_send_and_dispatch()
    io.stdout:write("selftest_command_ownership_runtime: OK\n")
end

main()
