local fixtures = require("tests.replay.fixtures.reject_history.reject_history_fixtures")
local runner = require("tests.replay.harness.reject_history_fixture_runner")

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
        suite_id = "reject_history",
    })

    assert_true(result.ok, "reject history suite should fully pass")
    assert_equal(result.suite_id, "reject_history", "suite id mismatch")
    assert_equal(result.total, 4, "fixture count mismatch")
    assert_equal(result.passed, 4, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local basic = find_entry(result.entries, "reject_history_basic_append")
    assert_true(basic ~= nil, "basic append fixture missing")
    assert_equal(basic.actual.phase1_recent_rejects[1], "t42 defensive/combat.defense Stoneskin :: not_ready", "basic reject line mismatch")

    local init_empty = find_entry(result.entries, "reject_history_initializes_tables_on_empty_input")
    assert_true(init_empty ~= nil, "empty input fixture missing")
    assert_true(type(init_empty.actual.phase1_recent_rejects) == "table", "recent_rejects should be table")
    assert_true(type(init_empty.actual.phase1_recent_reject_items) == "table", "recent_reject_items should be table")

    local trim = find_entry(result.entries, "reject_history_trims_to_25")
    assert_true(trim ~= nil, "trim fixture missing")
    assert_equal(#trim.actual.phase1_recent_rejects, 25, "recent_rejects max keep mismatch")
    assert_equal(trim.actual.phase1_recent_rejects[1], "old.2", "trim should drop oldest reject line")

    io.stdout:write("selftest_reject_history_fixtures: OK\n")
end

main()
