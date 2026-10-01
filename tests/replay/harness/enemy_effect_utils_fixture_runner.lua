local structural_compare = require("tests.replay.harness.structural_compare")
local utils = require("uc_scheduler_enemy_effect_utils")

local M = {}

local function call_helper(helper, input)
    if helper == "normalize_status_removal_key" then
        return utils.normalize_status_removal_key(input and input.buff_res, input and input.buff_id)
    end
    if helper == "danger_weight_to_priority" then
        return utils.danger_weight_to_priority(input and input.w)
    end
    if helper == "enemy_dispel_claim_valid" then
        return utils.enemy_dispel_claim_valid(input and input.claim_id, input and input.party_claim_set)
    end
    if helper == "enemy_effect_log_label" then
        return utils.enemy_effect_log_label(input and input.deps, input and input.effect_id)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("enemy_effect_utils_fixture_runner.run_fixture expects fixture table")
    end

    local actual_result = call_helper(fixture.helper, fixture.input or {})
    local expected_obj = fixture.expected or {}
    local actual_obj = { result = actual_result }
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
        error("enemy_effect_utils_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "enemy_effect_utils_suite"
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
