local fixture_runner = require("tests.replay.harness.fixture_runner")

local M = {}

function M.run(fixtures, opts)
    if type(fixtures) ~= "table" then
        error("fixture_suite_runner.run expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "fixture_suite"

    local entries = {}
    local total = 0
    local suite_ok = true
    local matched_count = 0
    local mismatched_count = 0

    for i, fixture in ipairs(fixtures) do
        total = total + 1
        local run_result = fixture_runner.run(fixture)
        local expected_runner_ok = true
        if type(fixture) == "table"
            and type(fixture.expected) == "table"
            and rawget(fixture.expected, "runner_ok") ~= nil
        then
            expected_runner_ok = fixture.expected.runner_ok
        end

        local expectation_matched = (run_result.ok == expected_runner_ok)
        if expectation_matched then
            matched_count = matched_count + 1
        else
            mismatched_count = mismatched_count + 1
            suite_ok = false
        end

        entries[#entries + 1] = {
            index = i,
            fixture_id = type(fixture) == "table" and fixture.fixture_id or nil,
            expected_runner_ok = expected_runner_ok,
            actual_runner_ok = run_result.ok,
            expectation_matched = expectation_matched,
            run_result = run_result,
        }
    end

    return {
        ok = suite_ok,
        suite_id = suite_id,
        total = total,
        matched = matched_count,
        mismatched = mismatched_count,
        entries = entries,
    }
end

return M
