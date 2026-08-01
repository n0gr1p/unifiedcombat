local fixtures = require("tests.replay.fixtures.enemy_effect.enemy_effect_utils_fixtures")
local runner = require("tests.replay.harness.enemy_effect_utils_fixture_runner")

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
        suite_id = "enemy_effect_utils",
    })

    assert_true(result.ok, "enemy_effect utils suite should fully pass")
    assert_equal(result.suite_id, "enemy_effect_utils", "suite id mismatch")
    assert_true(result.total >= 25, "fixture count should be at least 25 after edge-case top-up")
    assert_equal(result.passed, result.total, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local norm_entry = find_entry(result.entries, "enemy_utils_normalize_blindness_to_blind")
    assert_true(norm_entry ~= nil, "normalize fixture missing")
    assert_equal(norm_entry.actual.result, "blind", "normalize blindness mismatch")

    local claim_entry = find_entry(result.entries, "enemy_utils_claim_valid_true")
    assert_true(claim_entry ~= nil, "claim-valid fixture missing")
    assert_true(claim_entry.actual.result == true, "claim-valid true mismatch")

    local label_entry = find_entry(result.entries, "enemy_utils_log_label_named_effect")
    assert_true(label_entry ~= nil, "log-label fixture missing")
    assert_equal(label_entry.actual.result, "Slow(13)", "log label mismatch")

    local key_strict_entry = find_entry(result.entries, "enemy_utils_claim_invalid_string_key_in_set")
    assert_true(key_strict_entry ~= nil, "numeric-key strictness fixture missing")
    assert_true(key_strict_entry.actual.result == false, "numeric-key strictness expectation mismatch")

    local unknown_label_entry = find_entry(result.entries, "enemy_utils_label_unknown_buff_fallback")
    assert_true(unknown_label_entry ~= nil, "unknown label fallback fixture missing")
    assert_equal(unknown_label_entry.actual.result, "id:9999", "unknown label fallback mismatch")

    local numeric_string_weight_entry = find_entry(result.entries, "enemy_utils_danger_weight_string_numeric_3_priority_82")
    assert_true(numeric_string_weight_entry ~= nil, "string-numeric weight fixture missing")
    assert_equal(numeric_string_weight_entry.actual.result, 82, "string-numeric weight mapping mismatch")

    io.stdout:write("selftest_enemy_effect_utils_fixtures: OK\n")
end

main()
