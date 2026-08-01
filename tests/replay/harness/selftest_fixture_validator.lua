local deep_copy = require("tests.replay.harness.deep_copy")
local fixture_validator = require("tests.replay.harness.fixture_validator")

local function assert_true(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values are not equal") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function build_valid_fixture()
    return {
        fixture_id = "harness-shape-001",
        description = "minimal valid replay fixture skeleton",
        tags = { "harness", "skeleton" },
        input = {
            old_normalized = {
                [1] = "num-key",
                ["1"] = "string-key",
                has_false = false,
                has_empty = "",
            },
            new_normalized = {
                [1] = "num-key",
                ["1"] = "string-key",
                has_false = false,
                has_empty = "",
            },
        },
        expected = {
            same_structure = true,
            side_effects_forbidden = true,
            notes = "validator skeleton pass case",
            runner_ok = true,
        },
    }
end

local function run_valid_case()
    local fixture = build_valid_fixture()
    local result = fixture_validator.validate(fixture)
    assert_true(result.ok, "valid fixture should pass")
    assert_equal(#result.errors, 0, "valid fixture should have zero errors")
end

local function run_missing_required_case()
    local fixture = build_valid_fixture()
    fixture.expected.same_structure = nil
    local result = fixture_validator.validate(fixture)
    assert_true(not result.ok, "missing required field should fail")
    assert_true(#result.errors > 0, "missing required field should produce errors")
end

local function run_wrong_type_case()
    local fixture = build_valid_fixture()
    fixture.expected.side_effects_forbidden = "true"
    local result = fixture_validator.validate(fixture)
    assert_true(not result.ok, "wrong field type should fail")
    assert_true(#result.errors > 0, "wrong type should produce errors")
end

local function run_unexpected_key_case()
    local fixture = build_valid_fixture()
    fixture.unexpected = 123
    local result = fixture_validator.validate(fixture)
    assert_true(not result.ok, "unexpected top-level keys should fail")
    assert_true(#result.errors > 0, "unexpected key should produce errors")
end

local function run_nil_false_empty_string_semantics_case()
    local fixture = build_valid_fixture()
    fixture.input.new_normalized = deep_copy.copy(fixture.input.old_normalized)

    local result_ok = fixture_validator.validate(fixture)
    assert_true(result_ok.ok, "false and empty string are valid values inside normalized payloads")

    fixture.input.new_normalized.has_false = nil
    local result_nil = fixture_validator.validate(fixture)
    assert_true(result_nil.ok, "validator should not coerce payload internals during shape validation")
end

local function run_numeric_vs_string_key_semantics_case()
    local fixture = build_valid_fixture()
    assert_true(fixture.input.old_normalized[1] ~= nil, "numeric key must exist")
    assert_true(fixture.input.old_normalized["1"] ~= nil, "string key must exist")
    assert_true(fixture.input.old_normalized[1] ~= fixture.input.old_normalized["1"], "numeric and string keys are distinct")

    local result = fixture_validator.validate(fixture)
    assert_true(result.ok, "validator should accept payloads preserving numeric and string key differences")
end

local function run_assert_valid_case()
    local fixture = build_valid_fixture()
    local ok = fixture_validator.assert_valid(fixture)
    assert_true(ok, "assert_valid should return true for valid fixtures")

    fixture.fixture_id = ""
    local ok_bad, err_bad = pcall(function()
        fixture_validator.assert_valid(fixture)
    end)
    assert_true(not ok_bad, "assert_valid should error for invalid fixtures")
    assert_true(type(err_bad) == "string", "assert_valid should emit string error")
end

local function run_runner_ok_optional_case()
    local fixture = build_valid_fixture()
    fixture.expected.runner_ok = false
    local result = fixture_validator.validate(fixture)
    assert_true(result.ok, "expected.runner_ok boolean should be accepted")
end

local function main()
    run_valid_case()
    run_missing_required_case()
    run_wrong_type_case()
    run_unexpected_key_case()
    run_nil_false_empty_string_semantics_case()
    run_numeric_vs_string_key_semantics_case()
    run_assert_valid_case()
    run_runner_ok_optional_case()
    io.stdout:write("selftest_fixture_validator: OK\n")
end

main()
