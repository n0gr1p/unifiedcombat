local fixtures = require("tests.replay.fixtures.action_metadata.action_metadata_fixtures")
local runner = require("tests.replay.harness.action_metadata_fixture_runner")

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

local function find_entry(entries, fixture_id)
    for _, entry in ipairs(entries) do
        if entry.fixture_id == fixture_id then
            return entry
        end
    end
    return nil
end

local function main()
    local result = runner.run_suite(fixtures, {
        suite_id = "action_metadata",
    })

    assert_true(result.ok, "action metadata suite should fully pass")
    assert_equal(result.suite_id, "action_metadata", "suite id mismatch")
    assert_equal(result.total, 20, "fixture count mismatch")
    assert_equal(result.passed, 20, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local known_entry = find_entry(result.entries, "action_meta_spell_known_true_boolean")
    assert_true(known_entry ~= nil, "spell_known fixture missing")
    assert_true(known_entry.actual.result == true, "spell_known true mismatch")

    local range_entry = find_entry(result.entries, "action_meta_effective_range_gt20_scaled")
    assert_true(range_entry ~= nil, "effective range fixture missing")
    assert_equal(range_entry.actual.result, 0.25, "effective range scaling mismatch")

    local target_entry = find_entry(result.entries, "action_meta_target_mode_self_only_spell")
    assert_true(target_entry ~= nil, "target mode fixture missing")
    assert_equal(target_entry.actual.result, "self_only", "target mode self_only mismatch")

    io.stdout:write("selftest_action_metadata_fixtures: OK\n")
end

main()
