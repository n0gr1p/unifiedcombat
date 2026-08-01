local fixtures = require("tests.replay.fixtures.text.text_utils_fixtures")
local runner = require("tests.replay.harness.text_utils_fixture_runner")

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
        suite_id = "text_utils",
    })

    assert_true(result.ok, "text utils suite should fully pass")
    assert_equal(result.suite_id, "text_utils", "suite id mismatch")
    assert_equal(result.total, 19, "fixture count mismatch")
    assert_equal(result.passed, 19, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local roman_entry = find_entry(result.entries, "text_to_roman_basic_3")
    assert_true(roman_entry ~= nil, "roman fixture missing")
    assert_equal(roman_entry.actual.result, "III", "roman conversion mismatch")

    local normalize_entry = find_entry(result.entries, "text_normalize_whitespace_and_roman")
    assert_true(normalize_entry ~= nil, "normalize fixture missing")
    assert_equal(normalize_entry.actual.result, "cure II", "normalize roman token mismatch")

    local split_entry = find_entry(result.entries, "text_split_pipe_empty_tokens")
    assert_true(split_entry ~= nil, "split_pipe fixture missing")
    assert_equal(split_entry.actual.result[2], "", "split_pipe empty token mismatch")

    io.stdout:write("selftest_text_utils_fixtures: OK\n")
end

main()
