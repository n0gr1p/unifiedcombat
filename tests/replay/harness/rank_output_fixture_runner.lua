local structural_compare = require("tests.replay.harness.structural_compare")
local rank_output = require("uc_scheduler_rank_output")

local M = {}

local function call_helper(helper, input)
    if helper == "p1_format_top3" then
        return rank_output.p1_format_top3(input and input.scheduler, input and input.ranked or {}, input and input.p1_number)
    end
    if helper == "p1_format_top3_verbose" then
        return rank_output.p1_format_top3_verbose(input and input.scheduler, input and input.ranked or {}, input and input.p1_number)
    end
    if helper == "p1_format_topn_lines" then
        return rank_output.p1_format_topn_lines(input and input.scheduler, input and input.ranked or {}, input and input.n, input and input.p1_number)
    end
    if helper == "p1_capture_topn_items" then
        return rank_output.p1_capture_topn_items(input and input.scheduler, input and input.ranked or {}, input and input.n, input and input.p1_number)
    end
    if helper == "p1_reject_top" then
        return rank_output.p1_reject_top(input and input.scheduler, input and input.reject_counts or {}, input and input.proposal_count)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("rank_output_fixture_runner.run_fixture expects fixture table")
    end

    local actual_result = call_helper(fixture.helper, fixture.input or {})
    local actual_obj = { result = actual_result }
    local expected_obj = fixture.expected or {}
    local ok, mismatches = structural_compare.compare(actual_obj, expected_obj)

    return {
        fixture_id = fixture.fixture_id,
        helper = fixture.helper,
        ok = ok,
        actual = actual_obj,
        expected = expected_obj,
        mismatches = mismatches,
    }
end

function M.run_suite(fixtures, opts)
    if type(fixtures) ~= "table" then
        error("rank_output_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "rank_output_suite"
    local entries = {}
    local total = 0
    local passed = 0
    local failed = 0

    for i, fixture in ipairs(fixtures) do
        total = total + 1
        local entry = M.run_fixture(fixture)
        entry.index = i
        entries[#entries + 1] = entry
        if entry.ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    return {
        ok = failed == 0,
        suite_id = suite_id,
        total = total,
        passed = passed,
        failed = failed,
        entries = entries,
    }
end

return M
