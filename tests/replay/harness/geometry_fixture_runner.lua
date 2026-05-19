local structural_compare = require("tests.replay.harness.structural_compare")
local geometry = require("uc_scheduler_geometry")

local M = {}

local function call_with_windower_stub(input, fn)
    local previous_windower = _G.windower
    _G.windower = {
        ffxi = {
            get_mob_by_target = function(target_name)
                if target_name == "me" then
                    return input and input.me or nil
                end
                return nil
            end,
        },
    }

    local ok, result = pcall(fn)
    _G.windower = previous_windower

    if not ok then
        error(result)
    end
    return result
end

local function call_helper(helper, input)
    if helper == "normalize_angle_rad" then
        return geometry.normalize_angle_rad(input and input.angle)
    end
    if helper == "target_is_in_front_arc" then
        return call_with_windower_stub(input, function()
            return geometry.target_is_in_front_arc(input and input.target, input and input.arc)
        end)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("geometry_fixture_runner.run_fixture expects fixture table")
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
        error("geometry_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "geometry_suite"
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
