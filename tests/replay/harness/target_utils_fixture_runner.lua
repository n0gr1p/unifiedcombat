local structural_compare = require("tests.replay.harness.structural_compare")
local target_utils = require("uc_scheduler_target_utils")

local M = {}

local function apply_globals(globals_spec)
    local prev = {
        windower = rawget(_G, "windower"),
    }

    if globals_spec and globals_spec.windower ~= nil then
        _G.windower = globals_spec.windower
    else
        _G.windower = nil
    end

    return prev
end

local function restore_globals(prev)
    _G.windower = prev.windower
end

local function call_helper(helper, input)
    if helper == "p1_is_tank_enmity_selected" then
        return target_utils.p1_is_tank_enmity_selected(input and input.scheduler, input and input.selected)
    end
    if helper == "p1_target_distance_to_id" then
        local distance, mob = target_utils.p1_target_distance_to_id(input and input.scheduler, input and input.target_id)
        return {
            distance = distance,
            mob_id = mob and mob.id or nil,
        }
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("target_utils_fixture_runner.run_fixture expects fixture table")
    end

    local prev = apply_globals(fixture.globals)
    local ok_call, actual_result = pcall(function()
        return call_helper(fixture.helper, fixture.input or {})
    end)
    restore_globals(prev)

    if not ok_call then
        error(actual_result)
    end

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
        error("target_utils_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "target_utils_suite"
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
