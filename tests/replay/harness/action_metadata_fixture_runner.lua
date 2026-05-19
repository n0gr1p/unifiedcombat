local structural_compare = require("tests.replay.harness.structural_compare")
local action_metadata = require("uc_scheduler_action_metadata")

local M = {}

local function call_helper(helper, input)
    if helper == "spell_known_flag" then
        return action_metadata.spell_known_flag(input and input.value)
    end
    if helper == "job_id_by_short" then
        return action_metadata.job_id_by_short(input and input.deps, input and input.short_name)
    end
    if helper == "action_status_id" then
        return action_metadata.action_status_id(input and input.deps, input and input.name)
    end
    if helper == "action_duration_seconds" then
        return action_metadata.action_duration_seconds(input and input.deps, input and input.name, input and input.default_seconds)
    end
    if helper == "action_effective_range" then
        return action_metadata.action_effective_range(input and input.deps, input and input.raw_range)
    end
    if helper == "action_target_mode" then
        return action_metadata.action_target_mode(input and input.deps, input and input.action_name, input and input.action_kind)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("action_metadata_fixture_runner.run_fixture expects fixture table")
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
        error("action_metadata_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "action_metadata_suite"
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
