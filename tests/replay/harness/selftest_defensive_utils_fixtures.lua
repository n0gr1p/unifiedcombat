local fixtures = require("tests.replay.fixtures.defensive.defensive_utils_fixtures")
local runner = require("tests.replay.harness.defensive_utils_fixture_runner")

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
        suite_id = "defensive_utils",
    })

    assert_true(result.ok, "defensive utils suite should fully pass")
    assert_equal(result.suite_id, "defensive_utils", "suite id mismatch")
    assert_equal(result.total, 25, "fixture count mismatch")
    assert_equal(result.passed, 25, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local doom_entry = find_entry(result.entries, "defensive_resolve_doom_buff_id_from_resources")
    assert_true(doom_entry ~= nil, "resolve_doom fixture missing")
    assert_equal(doom_entry.actual.result, 42, "resolve_doom resource lookup mismatch")

    local cure_entry = find_entry(result.entries, "defensive_cure_tier_for_missing_hp_downshift")
    assert_true(cure_entry ~= nil, "cure tier fixture missing")
    assert_equal(cure_entry.actual.result, 1, "cure tier downshift mismatch")

    local song_entry = find_entry(result.entries, "defensive_is_bard_song_by_skill")
    assert_true(song_entry ~= nil, "bard song fixture missing")
    assert_true(song_entry.actual.result == true, "bard song by skill mismatch")

    io.stdout:write("selftest_defensive_utils_fixtures: OK\n")
end

main()
