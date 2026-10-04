local fixtures = require("tests.replay.fixtures.action_state.action_state_fixtures")
local runner = require("tests.replay.harness.action_state_fixture_runner")

local function assert_true(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values are not equal") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function find_entry(entries, fixture_id)
    for _, entry in ipairs(entries) do
        if entry.fixture_id == fixture_id then
            return entry
        end
    end
    return nil
end

local function main()
    local result = runner.run_suite(fixtures, {
        suite_id = "action_state",
    })

    if not result.ok then
        for _, entry in ipairs(result.entries or {}) do
            if entry.ok ~= true then
                io.stdout:write(("action_state fixture failed: %s\n"):format(tostring(entry.fixture_id)))
                for _, mismatch in ipairs(entry.mismatches or {}) do
                    io.stdout:write("  - " .. tostring(mismatch) .. "\n")
                end
            end
        end
    end
    assert_true(result.ok, "action state suite should fully pass")
    assert_equal(result.suite_id, "action_state", "suite id mismatch")
    assert_equal(result.total, 10, "fixture count mismatch")
    assert_equal(result.passed, 10, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local sent = find_entry(result.entries, "action_mark_sent_sets_fields_and_cooldown")
    assert_true(sent ~= nil, "mark sent fixture missing")
    assert_equal(sent.actual.scheduler_action_state.last_send_kind, "spell", "last_send_kind mismatch")

    local blocked = find_entry(result.entries, "action_dispatch_blocked_acting_with_log")
    assert_true(blocked ~= nil, "dispatch blocked fixture missing")
    assert_true(blocked.actual.result[1] == true, "acting should block dispatch")
    assert_true(#blocked.actual.diag_calls == 1, "expected one diag call")

    local clear = find_entry(result.entries, "action_dispatch_not_blocked")
    assert_true(clear ~= nil, "dispatch clear fixture missing")
    assert_true(clear.actual.result[1] == false, "expected not blocked")

    io.stdout:write("selftest_action_state_fixtures: OK\n")
end

main()
