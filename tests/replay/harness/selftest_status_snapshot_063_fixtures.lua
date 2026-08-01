local fixtures = require("tests.replay.fixtures.parser.status_snapshot_063_fixtures")
local runner = require("tests.replay.harness.status_snapshot_063_fixture_runner")

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
        suite_id = "status_snapshot_063_parser",
    })

    assert_true(result.ok, "status snapshot suite should fully pass")
    assert_equal(result.suite_id, "status_snapshot_063_parser", "suite id mismatch")
    assert_equal(result.total, 8, "fixture count mismatch")
    assert_equal(result.passed, 8, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local nil_entry = find_entry(result.entries, "status063_invalid_non_string")
    assert_true(nil_entry ~= nil, "invalid_non_string fixture missing")
    assert_true(nil_entry.ok, "invalid_non_string fixture should pass")
    assert_true(nil_entry.actual == nil, "invalid_non_string should return nil")

    local aggregate_entry = find_entry(result.entries, "status063_full_32_no_sentinel")
    assert_true(aggregate_entry ~= nil, "full_32 fixture missing")
    assert_true(aggregate_entry.ok, "full_32 fixture should pass")
    assert_equal(aggregate_entry.actual[1].count, 32, "full_32 count mismatch")
    assert_equal(aggregate_entry.actual[1].endtimes[1], 1, "full_32 first endtime mismatch")
    assert_equal(aggregate_entry.actual[1].endtimes[32], 32, "full_32 last endtime mismatch")

    io.stdout:write("selftest_status_snapshot_063_fixtures: OK\n")
end

main()
