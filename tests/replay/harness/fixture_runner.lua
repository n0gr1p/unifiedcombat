local fixture_validator = require("tests.replay.harness.fixture_validator")
local structural_compare = require("tests.replay.harness.structural_compare")

local M = {}

local function has_side_effects(normalized)
    return type(normalized) == "table" and rawget(normalized, "side_effects") ~= nil
end

local function compare_side_effects(old_normalized, new_normalized)
    local old_present = has_side_effects(old_normalized)
    local new_present = has_side_effects(new_normalized)

    if not old_present and not new_present then
        return {
            checked = false,
            present_old = false,
            present_new = false,
            parity_ok = true,
            mismatches = {},
        }
    end

    if old_present ~= new_present then
        return {
            checked = true,
            present_old = old_present,
            present_new = new_present,
            parity_ok = false,
            mismatches = { "$.side_effects: presence mismatch between old/new normalized payloads" },
        }
    end

    local ok, mismatches = structural_compare.compare(
        old_normalized.side_effects,
        new_normalized.side_effects
    )

    return {
        checked = true,
        present_old = true,
        present_new = true,
        parity_ok = ok,
        mismatches = mismatches,
    }
end

local function side_effects_activity_present(side_effects)
    if type(side_effects) ~= "table" then
        return false
    end

    if rawget(side_effects, "attempted") == true then
        return true
    end

    for k, v in pairs(side_effects) do
        if type(v) == "number" and v > 0 then
            return true
        end
        if type(v) == "table" then
            local nested = rawget(v, "count")
            if type(nested) == "number" and nested > 0 then
                return true
            end
        end
        if type(k) == "number" then
            return true
        end
    end

    return false
end

function M.run(fixture)
    local validation = fixture_validator.validate(fixture)
    if not validation.ok then
        return {
            ok = false,
            fixture_valid = false,
            errors = validation.errors,
            same_structure = nil,
            side_effects = nil,
        }
    end

    local old_normalized = fixture.input.old_normalized
    local new_normalized = fixture.input.new_normalized
    local expected_same_structure = fixture.expected.same_structure
    local expected_side_effects_forbidden = fixture.expected.side_effects_forbidden

    local same_structure_ok, same_structure_mismatches = structural_compare.compare(
        old_normalized,
        new_normalized
    )
    local same_structure_match = (same_structure_ok == expected_same_structure)

    local se = compare_side_effects(old_normalized, new_normalized)
    local side_effects_forbidden_actual = true
    if se.present_old and se.present_new then
        side_effects_forbidden_actual = not side_effects_activity_present(old_normalized.side_effects)
            and not side_effects_activity_present(new_normalized.side_effects)
    elseif se.present_old or se.present_new then
        side_effects_forbidden_actual = false
    end
    local side_effects_forbidden_match =
        (side_effects_forbidden_actual == expected_side_effects_forbidden)

    local errors = {}
    if not same_structure_match then
        errors[#errors + 1] = "same_structure expectation mismatch"
    end
    if not side_effects_forbidden_match then
        errors[#errors + 1] = "side_effects_forbidden expectation mismatch"
    end
    if se.checked and not se.parity_ok then
        errors[#errors + 1] = "side_effects structural mismatch"
    end

    return {
        ok = #errors == 0,
        fixture_valid = true,
        errors = errors,
        same_structure = {
            actual = same_structure_ok,
            expected = expected_same_structure,
            matched = same_structure_match,
            mismatches = same_structure_mismatches,
        },
        side_effects = {
            checked = se.checked,
            present_old = se.present_old,
            present_new = se.present_new,
            parity_ok = se.parity_ok,
            parity_mismatches = se.mismatches,
            forbidden_actual = side_effects_forbidden_actual,
            forbidden_expected = expected_side_effects_forbidden,
            forbidden_matched = side_effects_forbidden_match,
        },
    }
end

return M
