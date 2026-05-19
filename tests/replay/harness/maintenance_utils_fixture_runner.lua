local structural_compare = require("tests.replay.harness.structural_compare")
local maintenance_utils = require("uc_scheduler_maintenance_utils")

local M = {}

local function call_helper(helper, input)
    if helper == "set_has" then
        return maintenance_utils.set_has(input and input.set, input and input.value)
    end
    if helper == "dedupe_numeric_ids" then
        return maintenance_utils.dedupe_numeric_ids(input and input.ids)
    end
    if helper == "split_actions" then
        return maintenance_utils.split_actions(input and input.raw)
    end
    if helper == "canon_name" then
        return maintenance_utils.canon_name(input and input.value)
    end
    if helper == "count_matching_buffs" then
        return maintenance_utils.count_matching_buffs(input and input.buff_list, input and input.id_set)
    end
    if helper == "count_buff_occurrences" then
        return maintenance_utils.count_buff_occurrences(input and input.buffs)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("maintenance_utils_fixture_runner.run_fixture expects fixture table")
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
        error("maintenance_utils_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "maintenance_utils_suite"
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
