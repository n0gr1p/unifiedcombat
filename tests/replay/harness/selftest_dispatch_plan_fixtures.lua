local fixtures = require("tests.replay.fixtures.dispatch_plan.dispatch_plan_fixtures")
local runner = require("tests.replay.harness.dispatch_plan_fixture_runner")

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
        suite_id = "dispatch_plan",
    })

    assert_true(result.ok, "dispatch plan suite should fully pass")
    assert_equal(result.suite_id, "dispatch_plan", "suite id mismatch")
    assert_equal(result.total, 10, "fixture count mismatch")
    assert_equal(result.passed, 10, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local basic = find_entry(result.entries, "dispatch_plan_build_basic")
    assert_true(basic ~= nil, "build basic fixture missing")
    assert_equal(basic.actual.result.plan_id, "plan.123450.7", "plan id mismatch")

    local invalid = find_entry(result.entries, "dispatch_plan_revalidate_invalid_plan")
    assert_true(invalid ~= nil, "invalid-plan fixture missing")
    assert_equal(invalid.actual.result[2], "invalid_plan", "invalid-plan reason mismatch")

    local ally = find_entry(result.entries, "dispatch_plan_revalidate_ally_valid")
    assert_true(ally ~= nil, "ally fixture missing")
    assert_true(ally.actual.result[1] == true, "ally should pass")

    io.stdout:write("selftest_dispatch_plan_fixtures: OK\n")
end

main()
