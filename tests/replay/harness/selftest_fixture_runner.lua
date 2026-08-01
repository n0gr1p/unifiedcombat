local deep_copy = require("tests.replay.harness.deep_copy")
local fixture_runner = require("tests.replay.harness.fixture_runner")

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

local function base_fixture()
    return {
        fixture_id = "runner-001",
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
        },
    }
end

local function run_pass_case()
    local fixture = base_fixture()
    local result = fixture_runner.run(fixture)
    assert_true(result.ok, "baseline fixture should pass")
    assert_true(result.fixture_valid, "fixture should validate")
    assert_true(result.same_structure.matched, "same_structure should match expectation")
    assert_true(result.side_effects.forbidden_matched, "forbidden side-effects expectation should match")
end

local function run_same_structure_fail_case()
    local fixture = base_fixture()
    fixture.input.new_normalized.has_false = nil
    fixture.expected.same_structure = true
    local result = fixture_runner.run(fixture)
    assert_true(not result.ok, "same_structure mismatch should fail")
    assert_true(not result.same_structure.matched, "same_structure expectation should not match")
end

local function run_fixture_validation_fail_case()
    local fixture = base_fixture()
    fixture.fixture_id = ""
    local result = fixture_runner.run(fixture)
    assert_true(not result.ok, "invalid fixture should fail")
    assert_true(not result.fixture_valid, "fixture_valid should be false on validator failure")
    assert_true(type(result.errors) == "table" and #result.errors > 0, "validation errors should be populated")
end

local function run_side_effects_forbidden_fail_case()
    local fixture = base_fixture()
    fixture.input.old_normalized.side_effects = { { op = "send_command", payload = "x" } }
    fixture.input.new_normalized.side_effects = deep_copy.copy(fixture.input.old_normalized.side_effects)
    fixture.expected.side_effects_forbidden = true

    local result = fixture_runner.run(fixture)
    assert_true(not result.ok, "side effects present while forbidden should fail")
    assert_true(not result.side_effects.forbidden_matched, "forbidden expectation should not match")
end

local function run_side_effects_parity_fail_case()
    local fixture = base_fixture()
    fixture.input.old_normalized.side_effects = { { op = "send_command", payload = "x" } }
    fixture.input.new_normalized.side_effects = { { op = "send_command", payload = "y" } }
    fixture.expected.side_effects_forbidden = false

    local result = fixture_runner.run(fixture)
    assert_true(not result.ok, "side_effects structural mismatch should fail")
    assert_true(result.side_effects.checked, "side_effects should be checked when present")
    assert_true(not result.side_effects.parity_ok, "side_effects parity should fail")
end

local function main()
    run_pass_case()
    run_same_structure_fail_case()
    run_fixture_validation_fail_case()
    run_side_effects_forbidden_fail_case()
    run_side_effects_parity_fail_case()
    io.stdout:write("selftest_fixture_runner: OK\n")
end

main()
