local fixtures = require("tests.replay.fixtures.proposal_keys.proposal_keys_fixtures")
local runner = require("tests.replay.harness.proposal_keys_fixture_runner")

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
        suite_id = "proposal_keys",
    })

    assert_true(result.ok, "proposal keys suite should fully pass")
    assert_equal(result.suite_id, "proposal_keys", "suite id mismatch")
    assert_equal(result.total, 10, "fixture count mismatch")
    assert_equal(result.passed, 10, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local family_entry = find_entry(result.entries, "proposal_keys_family_basic")
    assert_true(family_entry ~= nil, "family_key basic fixture missing")
    assert_equal(family_entry.actual.result, "Alice:33", "family_key basic mismatch")

    local attempt_entry = find_entry(result.entries, "proposal_keys_attempt_basic")
    assert_true(attempt_entry ~= nil, "attempt_key basic fixture missing")
    assert_equal(attempt_entry.actual.result, "buff_refresh::Alice::Cure IV", "attempt_key basic mismatch")

    local nil_entry = find_entry(result.entries, "proposal_keys_attempt_nil_fields")
    assert_true(nil_entry ~= nil, "attempt_key nil fixture missing")
    assert_equal(nil_entry.actual.result, "nil::nil::nil", "attempt_key nil behavior mismatch")

    io.stdout:write("selftest_proposal_keys_fixtures: OK\n")
end

main()
