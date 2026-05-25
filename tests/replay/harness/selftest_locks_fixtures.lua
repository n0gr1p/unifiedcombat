local fixtures = require("tests.replay.fixtures.locks.locks_fixtures")
local runner = require("tests.replay.harness.locks_fixture_runner")

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
        suite_id = "locks",
    })

    assert_true(result.ok, "locks suite should fully pass")
    assert_equal(result.suite_id, "locks", "suite id mismatch")
    assert_equal(result.total, 10, "fixture count mismatch")
    assert_equal(result.passed, 10, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local dup = find_entry(result.entries, "locks_duplicate_suppressed_by_recent_until")
    assert_true(dup ~= nil, "duplicate suppression fixture missing")
    assert_true(dup.actual.result == true, "duplicate should be suppressed")

    local summary = find_entry(result.entries, "locks_build_lock_summary_from_input")
    assert_true(summary ~= nil, "summary fixture missing")
    assert_equal(summary.actual.result, "zone_guard_lock|movement_lock|duplicate_lock", "summary mismatch")

    local reset = find_entry(result.entries, "locks_reset_runtime_locks")
    assert_true(reset ~= nil, "reset fixture missing")
    assert_equal(reset.actual.state.cooldown_until, 0, "reset cooldown mismatch")
    assert_equal(reset.actual.globals.UC_MOVE_FREEZE_PREP_UNTIL, 0, "reset freeze-until mismatch")

    io.stdout:write("selftest_locks_fixtures: OK\n")
end

main()
