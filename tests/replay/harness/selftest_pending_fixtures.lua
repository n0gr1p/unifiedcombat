local fixtures = require("tests.replay.fixtures.pending.pending_fixtures")
local runner = require("tests.replay.harness.pending_fixture_runner")

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
        suite_id = "pending",
    })

    assert_true(result.ok, "pending suite should fully pass")
    assert_equal(result.suite_id, "pending", "suite id mismatch")
    assert_equal(result.total, 8, "fixture count mismatch")
    assert_equal(result.passed, 8, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local timeout = find_entry(result.entries, "pending_update_live_effect_timeout")
    assert_true(timeout ~= nil, "timeout fixture missing")
    assert_equal(timeout.actual.pending.state, "timed_out", "timeout state mismatch")

    local globals = find_entry(result.entries, "pending_set_globals_from_pending_state")
    assert_true(globals ~= nil, "set globals fixture missing")
    assert_equal(globals.actual.global_state, "acknowledged", "pending global state mismatch")

    local complete = find_entry(result.entries, "pending_mark_complete_sets_fields_and_duplicate_window")
    assert_true(complete ~= nil, "mark complete fixture missing")
    assert_equal(complete.actual.pending.completion_deadline, 50.75, "completion deadline mismatch")

    io.stdout:write("selftest_pending_fixtures: OK\n")
end

main()
