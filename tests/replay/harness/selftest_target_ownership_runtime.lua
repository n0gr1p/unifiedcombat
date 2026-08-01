local ownership = require("uc_scheduler_target_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local calls = {}
    local set_target = function(target_id)
        calls[#calls + 1] = target_id
        return true
    end
    local status = ownership.apply_target_ownership({
        dispatcher = {
            dispatch_intent = function(intent, deps)
                local selected = deps.set_target(intent.target_id)
                return { ok = selected, executed = selected, reason = selected and "executed" or "target_rejected", dep_result = selected }
            end,
        },
        set_target = set_target,
        intent = { kind = "select_target", target_id = 1001 },
        target_id = 1001,
    })
    assert_equal(#calls, 1, "target side-effect count")
    assert_equal(calls[1], 1001, "target id")
    assert_equal(status.selected, true, "selected status")
    assert_equal(status.fallback_used, false, "fallback status")

    local rejected_calls = 0
    local rejected = ownership.apply_target_ownership({
        dispatcher = {
            dispatch_intent = function(intent, deps)
                local selected = deps.set_target(intent.target_id)
                return { ok = false, executed = false, reason = "target_rejected", dep_result = selected }
            end,
        },
        set_target = function()
            rejected_calls = rejected_calls + 1
            return false
        end,
        intent = { kind = "select_target", target_id = 1002 },
        target_id = 1002,
    })
    assert_equal(rejected_calls, 1, "rejected target attempt count")
    assert_equal(rejected.selected, false, "rejected selected status")
    assert_equal(rejected.fallback_used, false, "rejected fallback status")

    local ok = pcall(function()
        ownership.apply_target_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "missing_dep:set_target" }
            end },
            set_target = set_target,
            intent = { kind = "select_target", target_id = 1003 },
            target_id = 1003,
        })
    end)
    assert_equal(ok, false, "missing dependency must fail fast")
    assert_equal(#calls, 1, "failure must not use a direct fallback")

    io.stdout:write("selftest_target_ownership_runtime: OK\n")
end

main()
