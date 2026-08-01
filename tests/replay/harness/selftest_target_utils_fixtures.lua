local fixtures = require("tests.replay.fixtures.target.target_utils_fixtures")
local runner = require("tests.replay.harness.target_utils_fixture_runner")

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
        suite_id = "target_utils",
    })

    assert_true(result.ok, "target utils suite should fully pass")
    assert_equal(result.suite_id, "target_utils", "suite id mismatch")
    assert_equal(result.total, 7, "fixture count mismatch")
    assert_equal(result.passed, 7, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local tank_entry = find_entry(result.entries, "target_utils_tank_enmity_selected_true_family")
    assert_true(tank_entry ~= nil, "tank-enmity family fixture missing")
    assert_true(tank_entry.actual.result == true, "tank-enmity family mismatch")

    local dist_entry = find_entry(result.entries, "target_utils_target_distance_to_id_found")
    assert_true(dist_entry ~= nil, "distance fixture missing")
    assert_equal(dist_entry.actual.result.distance, 10, "distance sqrt result mismatch")
    assert_equal(dist_entry.actual.result.mob_id, 1234, "distance mob id mismatch")

    local missing_entry = find_entry(result.entries, "target_utils_target_distance_to_id_missing_mob")
    assert_true(missing_entry ~= nil, "missing-mob fixture missing")
    assert_true(missing_entry.actual.result.distance == nil, "missing-mob distance should be nil")

    io.stdout:write("selftest_target_utils_fixtures: OK\n")
end

main()
