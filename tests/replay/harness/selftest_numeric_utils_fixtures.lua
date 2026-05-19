local fixtures = require("tests.replay.fixtures.numeric.numeric_utils_fixtures")
local runner = require("tests.replay.harness.numeric_utils_fixture_runner")

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
        suite_id = "numeric_utils",
    })

    assert_true(result.ok, "numeric utils suite should fully pass")
    assert_equal(result.suite_id, "numeric_utils", "suite id mismatch")
    assert_equal(result.total, 18, "fixture count mismatch")
    assert_equal(result.passed, 18, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local num_entry = find_entry(result.entries, "numeric_p1_number_string_numeric")
    assert_true(num_entry ~= nil, "p1_number fixture missing")
    assert_equal(num_entry.actual.result, 12.5, "p1_number conversion mismatch")

    local clamp_entry = find_entry(result.entries, "numeric_p1_clamp_urgency_high_clamped")
    assert_true(clamp_entry ~= nil, "p1_clamp fixture missing")
    assert_equal(clamp_entry.actual.result, 1, "p1_clamp upper bound mismatch")

    local bool_entry = find_entry(result.entries, "numeric_bool_setting_string_on_upper")
    assert_true(bool_entry ~= nil, "bool_setting fixture missing")
    assert_true(bool_entry.actual.result == true, "bool_setting uppercase on mismatch")

    io.stdout:write("selftest_numeric_utils_fixtures: OK\n")
end

main()
