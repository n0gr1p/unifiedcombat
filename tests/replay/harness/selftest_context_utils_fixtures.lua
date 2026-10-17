local fixtures = require("tests.replay.fixtures.context.context_utils_fixtures")
local runner = require("tests.replay.harness.context_utils_fixture_runner")

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
        suite_id = "context_utils",
    })

    assert_true(result.ok, "context utils suite should fully pass")
    assert_equal(result.suite_id, "context_utils", "suite id mismatch")
    assert_equal(result.total, 14, "fixture count mismatch")
    assert_equal(result.passed, 14, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local zone_entry = find_entry(result.entries, "context_current_zone_id_reads_zone")
    assert_true(zone_entry ~= nil, "current_zone_id fixture missing")
    assert_equal(zone_entry.actual.result, 245, "current_zone_id mismatch")

    local city_entry = find_entry(result.entries, "context_city_zone_blocked_name_true")
    assert_true(city_entry ~= nil, "city zone fixture missing")
    assert_true(city_entry.actual.result == true, "is_city_zone blocked-name mismatch")

    local party_entry = find_entry(result.entries, "context_p1_build_party_id_set_basic")
    assert_true(party_entry ~= nil, "party id set fixture missing")
    assert_true(party_entry.actual.result[101] == true, "party id 101 should be present")
    assert_true(party_entry.actual.result[202] == true, "party id 202 should be present")

    io.stdout:write("selftest_context_utils_fixtures: OK\n")
end

main()
