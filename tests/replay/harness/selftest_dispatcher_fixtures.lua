local fixtures = require("tests.replay.fixtures.dispatcher.dispatcher_fixtures")
local runner = require("tests.replay.harness.dispatcher_fixture_runner")

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
        suite_id = "dispatcher",
    })

    assert_true(result.ok, "dispatcher suite should fully pass")
    assert_equal(result.suite_id, "dispatcher", "suite id mismatch")
    assert_equal(result.total, 14, "fixture count mismatch")
    assert_equal(result.passed, 14, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local dryrun = find_entry(result.entries, "dispatcher_dispatch_dryrun_valid_vector_no_calls")
    assert_true(dryrun ~= nil, "dryrun vector fixture missing")
    assert_equal(dryrun.actual.result.reason, "dry_run", "dryrun reason mismatch")

    local execute = find_entry(result.entries, "dispatcher_dispatch_execute_run_calls_deps")
    assert_true(execute ~= nil, "execute run fixture missing")
    assert_equal(execute.actual.result.executed, true, "execute flag mismatch")

    local invalid_x = find_entry(result.entries, "dispatcher_validate_run_invalid_run_x")
    assert_true(invalid_x ~= nil, "invalid run_x fixture missing")
    assert_equal(invalid_x.actual.result[2], "invalid_run_x", "invalid run_x reason mismatch")

    local normalize_meta = find_entry(result.entries, "dispatcher_normalize_preserves_meta_heading")
    assert_true(normalize_meta ~= nil, "normalize meta fixture missing")
    assert_equal(normalize_meta.actual.result.meta.heading, 1.5708, "meta heading mismatch")

    local missing = find_entry(result.entries, "dispatcher_dispatch_execute_missing_dep")
    assert_true(missing ~= nil, "missing dep fixture missing")
    assert_equal(missing.actual.result.reason, "missing_dep:turn", "missing dep reason mismatch")

    io.stdout:write("selftest_dispatcher_fixtures: OK\n")
end

main()
