local fixtures = require("tests.replay.fixtures.rank_output.rank_output_fixtures")
local runner = require("tests.replay.harness.rank_output_fixture_runner")

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
        suite_id = "rank_output",
    })

    assert_true(result.ok, "rank output suite should fully pass")
    assert_equal(result.suite_id, "rank_output", "suite id mismatch")
    assert_equal(result.total, 8, "fixture count mismatch")
    assert_equal(result.passed, 8, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local top3 = find_entry(result.entries, "rank_output_format_top3_basic")
    assert_true(top3 ~= nil, "top3 fixture missing")
    assert_true(type(top3.actual.result) == "string", "top3 result should be string")

    local lines = find_entry(result.entries, "rank_output_format_topn_lines_n2")
    assert_true(lines ~= nil, "topn lines fixture missing")
    assert_equal(lines.actual.result[1], "1) 10.25 combat/combat.main Provoke u=1.50 rp=0.25", "topn first line mismatch")

    local reject = find_entry(result.entries, "rank_output_reject_top_best_reason")
    assert_true(reject ~= nil, "reject top fixture missing")
    assert_equal(reject.actual.result, "out_of_range:4", "reject top mismatch")

    io.stdout:write("selftest_rank_output_fixtures: OK\n")
end

main()
