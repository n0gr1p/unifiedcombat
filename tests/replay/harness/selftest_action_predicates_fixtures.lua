local fixtures = require("tests.replay.fixtures.action_predicates.action_predicates_fixtures")
local runner = require("tests.replay.harness.action_predicates_fixture_runner")

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
        suite_id = "action_predicates",
    })

    assert_true(result.ok, "action predicates suite should fully pass")
    assert_equal(result.suite_id, "action_predicates", "suite id mismatch")
    assert_equal(result.total, 12, "fixture count mismatch")
    assert_equal(result.passed, 12, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local enemy_entry = find_entry(result.entries, "action_pred_ja_targets_enemy_target_table_enemy_true")
    assert_true(enemy_entry ~= nil, "ja_targets_enemy table fixture missing")
    assert_true(enemy_entry.actual.result == true, "ja_targets_enemy table true mismatch")

    local shield_entry = find_entry(result.entries, "action_pred_ja_requires_engaged_front_name_shield_bash")
    assert_true(shield_entry ~= nil, "ja_requires_engaged_front shield bash fixture missing")
    assert_true(shield_entry.actual.result == true, "ja_requires_engaged_front shield bash mismatch")

    local false_entry = find_entry(result.entries, "action_pred_ja_requires_engaged_front_false")
    assert_true(false_entry ~= nil, "ja_requires_engaged_front false fixture missing")
    assert_true(false_entry.actual.result == false, "ja_requires_engaged_front false mismatch")

    io.stdout:write("selftest_action_predicates_fixtures: OK\n")
end

main()
