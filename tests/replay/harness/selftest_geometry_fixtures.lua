local fixtures = require("tests.replay.fixtures.geometry.geometry_fixtures")
local runner = require("tests.replay.harness.geometry_fixture_runner")

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
        suite_id = "geometry",
    })

    assert_true(result.ok, "geometry suite should fully pass")
    assert_equal(result.suite_id, "geometry", "suite id mismatch")
    assert_equal(result.total, 11, "fixture count mismatch")
    assert_equal(result.passed, 11, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local normalize_entry = find_entry(result.entries, "geometry_normalize_over_pi_wraps_negative")
    assert_true(normalize_entry ~= nil, "normalize wrap fixture missing")
    assert_equal(normalize_entry.actual.result, -math.pi + 0.1, "normalize wrap mismatch")

    local front_entry = find_entry(result.entries, "geometry_front_arc_target_straight_ahead_true")
    assert_true(front_entry ~= nil, "front-arc ahead fixture missing")
    assert_true(front_entry.actual.result == true, "front-arc ahead mismatch")

    local missing_entry = find_entry(result.entries, "geometry_front_arc_missing_me_returns_false")
    assert_true(missing_entry ~= nil, "front-arc missing me fixture missing")
    assert_true(missing_entry.actual.result == false, "front-arc missing me mismatch")

    io.stdout:write("selftest_geometry_fixtures: OK\n")
end

main()
