local structural_compare = require("tests.replay.harness.structural_compare")
local pending_record = require("uc_scheduler_pending_record")

local M = {}

local function call_helper(fixture)
    if fixture.helper ~= "p1_record_legacy_dispatch" then
        error("unknown helper: " .. tostring(fixture.helper))
    end

    local input = fixture.input or {}
    local scheduler = input.scheduler or {}
    local ctx = input.ctx or {}
    local p1_number = input.p1_number
    if type(p1_number) ~= "function" then
        error("fixture input.p1_number must be a function")
    end

    local result = pending_record.p1_record_legacy_dispatch(scheduler, ctx, p1_number)
    local phase1 = scheduler.phase1 or {}

    return {
        result = result,
        phase1_pending = phase1.pending,
        phase1_recent_duplicate_until = phase1.recent_duplicate_until,
    }
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("pending_record_fixture_runner.run_fixture expects fixture table")
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
        error("pending_record_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "pending_record_suite"
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
