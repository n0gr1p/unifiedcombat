local structural_compare = require("tests.replay.harness.structural_compare")
local dispatch_plan = require("uc_scheduler_dispatch_plan")

local M = {}

local function call_helper(fixture)
    local input = fixture.input or {}

    if fixture.helper == "p1_build_dispatch_plan" then
        return {
            result = dispatch_plan.p1_build_dispatch_plan(
                input.scheduler or {},
                input.ctx or {},
                input.selected,
                input.p1_number
            ),
        }
    end

    if fixture.helper == "p1_revalidate_plan_commit" then
        local ok, reason = dispatch_plan.p1_revalidate_plan_commit(
            input.scheduler or {},
            input.ctx or {},
            input.selected,
            input.plan,
            input.p1_number,
            input.windower
        )
        return {
            result = { ok, reason },
        }
    end

    error("unknown helper: " .. tostring(fixture.helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("dispatch_plan_fixture_runner.run_fixture expects fixture table")
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
        error("dispatch_plan_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "dispatch_plan_suite"
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
