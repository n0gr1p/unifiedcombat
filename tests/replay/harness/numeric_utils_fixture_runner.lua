local structural_compare = require("tests.replay.harness.structural_compare")
local numeric_utils = require("uc_scheduler_numeric_utils")

local M = {}

local function call_helper(helper, input)
    if helper == "p1_number" then
        return numeric_utils.p1_number(input and input.value, input and input.default)
    end
    if helper == "p1_clamp_urgency" then
        return numeric_utils.p1_clamp_urgency(input and input.value)
    end
    if helper == "bool_setting" then
        return numeric_utils.bool_setting(input and input.value, input and input.default)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("numeric_utils_fixture_runner.run_fixture expects fixture table")
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
        error("numeric_utils_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "numeric_utils_suite"
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
