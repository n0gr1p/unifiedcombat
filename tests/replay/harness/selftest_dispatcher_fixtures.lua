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
    assert_equal(result.total, 32, "fixture count mismatch")
    assert_equal(result.passed, 32, "all fixtures should pass")
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

    local send_command_execute = find_entry(result.entries, "dispatcher_dispatch_execute_send_command_calls_deps")
    assert_true(send_command_execute ~= nil, "send_command execute fixture missing")
    assert_equal(send_command_execute.actual.calls.send_command[1][1], "input /ma Flash <t>", "send_command argument mismatch")

    local select_target_validate = find_entry(result.entries, "dispatcher_validate_select_target_ok")
    assert_true(select_target_validate ~= nil, "select_target validate fixture missing")
    assert_equal(select_target_validate.actual.result[1], true, "select_target validate ok mismatch")

    local select_target_execute = find_entry(result.entries, "dispatcher_dispatch_execute_select_target_calls_deps")
    assert_true(select_target_execute ~= nil, "select_target execute fixture missing")
    assert_equal(select_target_execute.actual.calls.set_target[1][1], 5678, "select_target execute argument mismatch")
    assert_equal(select_target_execute.actual.result.dep_result, true, "select_target execute dep_result mismatch")

    local run_missing = find_entry(result.entries, "dispatcher_dispatch_execute_run_missing_dep")
    assert_true(run_missing ~= nil, "run missing dep fixture missing")
    assert_equal(run_missing.actual.result.reason, "missing_dep:run", "run missing dep reason mismatch")

    local run_stop_validate = find_entry(result.entries, "dispatcher_validate_run_stop_ok")
    assert_true(run_stop_validate ~= nil, "run_stop validate fixture missing")
    assert_equal(run_stop_validate.actual.result[1], true, "run_stop validate ok mismatch")

    local run_stop_dryrun = find_entry(result.entries, "dispatcher_dispatch_dryrun_run_stop_no_calls")
    assert_true(run_stop_dryrun ~= nil, "run_stop dryrun fixture missing")
    assert_equal(run_stop_dryrun.actual.result.reason, "dry_run", "run_stop dryrun reason mismatch")

    local run_stop_execute = find_entry(result.entries, "dispatcher_dispatch_execute_run_stop_calls_deps")
    assert_true(run_stop_execute ~= nil, "run_stop execute fixture missing")
    assert_equal(run_stop_execute.actual.result.executed, true, "run_stop execute flag mismatch")
    assert_equal(run_stop_execute.actual.calls.run[1][1], false, "run_stop execute argument mismatch")

    local run_stop_missing = find_entry(result.entries, "dispatcher_dispatch_execute_run_stop_missing_run_dep")
    assert_true(run_stop_missing ~= nil, "run_stop missing dep fixture missing")
    assert_equal(run_stop_missing.actual.result.reason, "missing_dep:run", "run_stop missing dep reason mismatch")

    local turn_validate = find_entry(result.entries, "dispatcher_validate_turn_ok")
    assert_true(turn_validate ~= nil, "turn validate fixture missing")
    assert_equal(turn_validate.actual.result[1], true, "turn validate ok mismatch")

    local turn_execute = find_entry(result.entries, "dispatcher_dispatch_execute_turn_calls_deps")
    assert_true(turn_execute ~= nil, "turn execute fixture missing")
    assert_equal(turn_execute.actual.calls.turn[1][1], 1.25, "turn execute argument mismatch")

    io.stdout:write("selftest_dispatcher_fixtures: OK\n")
end

main()
