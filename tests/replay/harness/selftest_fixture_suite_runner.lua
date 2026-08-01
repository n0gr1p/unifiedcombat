local fixtures = require("tests.replay.fixtures.shared.basic_structural_fixtures")
local suite_runner = require("tests.replay.harness.fixture_suite_runner")

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
    local result = suite_runner.run(fixtures, {
        suite_id = "shared_basic_structural",
    })

    assert_true(result.ok, "suite should pass when actual outcomes match expected runner_ok")
    assert_equal(result.suite_id, "shared_basic_structural", "suite id mismatch")
    assert_equal(result.total, 6, "fixture count mismatch")
    assert_equal(result.matched, 6, "all fixture expectations should match")
    assert_equal(result.mismatched, 0, "no fixture expectation should mismatch")

    local pass_entry = find_entry(result.entries, "shared_equal_nested_pass")
    assert_true(pass_entry ~= nil, "pass entry should exist")
    assert_true(pass_entry.actual_runner_ok, "shared_equal_nested_pass should pass runner")
    assert_true(pass_entry.expectation_matched, "shared_equal_nested_pass expectation should match")

    local expected_fail_entry = find_entry(result.entries, "shared_side_effect_attempt_expected_fail")
    assert_true(expected_fail_entry ~= nil, "expected fail entry should exist")
    assert_true(not expected_fail_entry.actual_runner_ok, "expected fail fixture should fail runner")
    assert_true(expected_fail_entry.expectation_matched, "expected fail fixture should still match runner_ok expectation")

    io.stdout:write("selftest_fixture_suite_runner: OK\n")
end

main()
