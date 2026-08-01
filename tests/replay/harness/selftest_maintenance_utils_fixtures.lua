local fixtures = require("tests.replay.fixtures.maintenance.maintenance_utils_fixtures")
local runner = require("tests.replay.harness.maintenance_utils_fixture_runner")

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
        suite_id = "maintenance_utils",
    })

    assert_true(result.ok, "maintenance utils suite should fully pass")
    assert_equal(result.suite_id, "maintenance_utils", "suite id mismatch")
    assert_equal(result.total, 16, "fixture count mismatch")
    assert_equal(result.passed, 16, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local set_entry = find_entry(result.entries, "maintenance_utils_set_has_contains_method")
    assert_true(set_entry ~= nil, "set_has contains-method fixture missing")
    assert_true(set_entry.actual.result == true, "set_has contains-method mismatch")

    local split_entry = find_entry(result.entries, "maintenance_utils_split_actions_string_delimiters")
    assert_true(split_entry ~= nil, "split_actions fixture missing")
    assert_equal(split_entry.actual.result[2], "boost-str", "split_actions token normalization mismatch")

    local count_entry = find_entry(result.entries, "maintenance_utils_count_buff_occurrences_basic")
    assert_true(count_entry ~= nil, "count_buff_occurrences fixture missing")
    assert_equal(count_entry.actual.result[3], 3, "count_buff_occurrences count mismatch")

    io.stdout:write("selftest_maintenance_utils_fixtures: OK\n")
end

main()
