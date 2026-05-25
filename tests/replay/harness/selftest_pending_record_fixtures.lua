local fixtures = require("tests.replay.fixtures.pending_record.pending_record_fixtures")
local runner = require("tests.replay.harness.pending_record_fixture_runner")

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
        suite_id = "pending_record",
    })

    assert_true(result.ok, "pending record suite should fully pass")
    assert_equal(result.suite_id, "pending_record", "suite id mismatch")
    assert_equal(result.total, 5, "fixture count mismatch")
    assert_equal(result.passed, 5, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local basic = find_entry(result.entries, "pending_record_basic_spell")
    assert_true(basic ~= nil, "basic spell fixture missing")
    assert_equal(basic.actual.phase1_pending.pending_id, "pend.123450.7", "pending id mismatch")
    assert_equal(basic.actual.phase1_recent_duplicate_until["dup.heal.alice"], 124.2, "duplicate suppression deadline mismatch")

    local noop = find_entry(result.entries, "pending_record_missing_selected_noop")
    assert_true(noop ~= nil, "missing selected fixture missing")
    assert_true(noop.actual.phase1_pending.keep == true, "missing selected should preserve prior pending")

    local coerce = find_entry(result.entries, "pending_record_field_coercions")
    assert_true(coerce ~= nil, "coercion fixture missing")
    assert_equal(coerce.actual.phase1_pending.target_id, 0, "target_id coercion mismatch")
    assert_equal(coerce.actual.phase1_pending.proposal_id, "777", "proposal_id coercion mismatch")

    io.stdout:write("selftest_pending_record_fixtures: OK\n")
end

main()
