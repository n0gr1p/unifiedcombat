local structural_compare = require("tests.replay.harness.structural_compare")
local reject_history = require("uc_scheduler_reject_history")

local M = {}

local function call_helper(fixture)
    if fixture.helper ~= "p1_push_recent_rejects" then
        error("unknown helper: " .. tostring(fixture.helper))
    end

    local input = fixture.input or {}
    local scheduler = input.scheduler or {}
    local ctx = input.ctx or {}
    local rejected = input.rejected

    local result = reject_history.p1_push_recent_rejects(scheduler, ctx, rejected)
    local phase1 = scheduler.phase1 or {}

    return {
        result = result,
        phase1_recent_rejects = phase1.recent_rejects,
        phase1_recent_reject_items = phase1.recent_reject_items,
    }
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("reject_history_fixture_runner.run_fixture expects fixture table")
    end

    local ok_call, actual = pcall(function()
        return call_helper(fixture)
    end)

    if not ok_call then
        error(actual)
    end

    local expected = fixture.expected or {}
    local ok, mismatches = structural_compare.compare(actual, expected)

    return {
        fixture_id = fixture.fixture_id,
        helper = fixture.helper,
        ok = ok,
        actual = actual,
        expected = expected,
        mismatches = mismatches,
    }
end

function M.run_suite(fixtures, opts)
    if type(fixtures) ~= "table" then
        error("reject_history_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "reject_history_suite"
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
