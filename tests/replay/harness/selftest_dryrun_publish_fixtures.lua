local fixtures = require("tests.replay.fixtures.dryrun_publish.dryrun_publish_fixtures")
local runner = require("tests.replay.harness.dryrun_publish_fixture_runner")

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
    local scheduler_source = assert(io.open(scheduler_path or "unified_scheduler.lua", "r"))
    local scheduler_text = scheduler_source:read("*a")
    scheduler_source:close()
    assert_true(
        scheduler_text:find("scheduler%.p1_set_pending_globals", 1) ~= nil,
        "dryrun publish wiring must pass scheduler.p1_set_pending_globals"
    )
    assert_true(
        scheduler_text:find("scheduler%.p1_build_lock_summary", 1) ~= nil,
        "dryrun publish wiring must pass scheduler.p1_build_lock_summary"
    )

    local result = runner.run_suite(fixtures, {
        suite_id = "dryrun_publish",
    })

    assert_true(result.ok, "dryrun publish suite should fully pass")
    assert_equal(result.suite_id, "dryrun_publish", "suite id mismatch")
    assert_equal(result.total, 3, "fixture count mismatch")
    assert_equal(result.passed, 3, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local selected = find_entry(result.entries, "dryrun_publish_selected_sets_phase_and_globals")
    assert_true(selected ~= nil, "selected fixture missing")
    assert_equal(selected.actual.globals.UC_SCHED_P1_SELECTED_PROPOSAL, "proposal-7", "selected proposal id mismatch")
    assert_equal(selected.actual.globals.UC_SCHED_P1_REJECT5, "rr-2\nrr-3\nrr-4\nrr-5\nrr-6", "reject5 window mismatch")

    local invalidated = find_entry(result.entries, "dryrun_publish_no_selected_with_commit_reason")
    assert_true(invalidated ~= nil, "commit invalidated fixture missing")
    assert_equal(invalidated.actual.scheduler_phase1.last_noop_reason, "commit_invalidated:revalidate_failed", "commit invalidated noop mismatch")

    local none = find_entry(result.entries, "dryrun_publish_no_selected_no_proposals")
    assert_true(none ~= nil, "no proposals fixture missing")
    assert_equal(none.actual.scheduler_phase1.last_noop_reason, "no_proposals", "no proposals noop mismatch")

    io.stdout:write("selftest_dryrun_publish_fixtures: OK\n")
end

main()
