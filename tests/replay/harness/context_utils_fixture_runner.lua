local structural_compare = require("tests.replay.harness.structural_compare")
local context_utils = require("uc_scheduler_context_utils")

local M = {}

local function apply_globals(globals_spec)
    local prev = {
        windower = rawget(_G, "windower"),
        res = rawget(_G, "res"),
        UC_SETTINGS = rawget(_G, "UC_SETTINGS"),
    }

    if globals_spec then
        if globals_spec.windower ~= nil then
            _G.windower = globals_spec.windower
        else
            _G.windower = nil
        end

        if globals_spec.res ~= nil then
            _G.res = globals_spec.res
        else
            _G.res = nil
        end

        if globals_spec.UC_SETTINGS ~= nil then
            _G.UC_SETTINGS = globals_spec.UC_SETTINGS
        else
            _G.UC_SETTINGS = nil
        end
    else
        _G.windower = nil
        _G.res = nil
        _G.UC_SETTINGS = nil
    end

    return prev
end

local function restore_globals(prev)
    _G.windower = prev.windower
    _G.res = prev.res
    _G.UC_SETTINGS = prev.UC_SETTINGS
end

local function call_helper(helper, input)
    if helper == "current_zone_id" then
        return context_utils.current_zone_id()
    end
    if helper == "get_settings" then
        return context_utils.get_settings()
    end
    if helper == "is_city_zone_for_maintenance" then
        return context_utils.is_city_zone_for_maintenance(input and input.maintenance_blocked_zone_names or {})
    end
    if helper == "build_partner_target_set" then
        return context_utils.build_partner_target_set(input and input.deps, input and input.settings)
    end
    if helper == "p1_build_party_id_set" then
        return context_utils.p1_build_party_id_set(input and input.deps)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("context_utils_fixture_runner.run_fixture expects fixture table")
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
        error("context_utils_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "context_utils_suite"
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
