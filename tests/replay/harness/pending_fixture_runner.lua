local structural_compare = require("tests.replay.harness.structural_compare")
local pending = require("uc_scheduler_pending")

local M = {}

local function call_helper(fixture)
    local input = fixture.input or {}

    if fixture.helper == "p1_update_pending_state" then
        local scheduler = input.scheduler or { phase1 = { recent_duplicate_until = {} } }
        local result = pending.p1_update_pending_state(
            scheduler,
            input.ctx or {},
            input.p1_pending_is_live_state,
            input.p1_number
        )
        return {
            result = result,
            pending = scheduler.phase1.pending,
            recent_duplicate_until = scheduler.phase1.recent_duplicate_until,
        }
    end

    if fixture.helper == "p1_set_pending_globals" then
        local scheduler = input.scheduler or { phase1 = {} }
        local globals = input.globals or {}
        local result = pending.p1_set_pending_globals(scheduler, globals)
        return {
            result = result,
            global_state = globals.UC_SCHED_P1_PENDING_STATE,
        }
    end

    if fixture.helper == "p1_pending_mark_complete" then
        local scheduler = input.scheduler or { phase1 = { recent_duplicate_until = {} } }
        local result = pending.p1_pending_mark_complete(scheduler, input.now, input.result_code)
        return {
            result = result,
            pending = scheduler.phase1.pending,
            recent_duplicate_until = scheduler.phase1.recent_duplicate_until,
        }
    end

    error("unknown helper: " .. tostring(fixture.helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("pending_fixture_runner.run_fixture expects fixture table")
    end

    local ok_call, actual = pcall(function()
        return call_helper(fixture)
    end)
    if not ok_call then
        error(actual)
    end

    local expected = fixture.expected or {}
    local ok, mismatches = structural_compare.compare(actual, expected)

    return {
        fixture_id = fixture.fixture_id,
        helper = fixture.helper,
        ok = ok,
        actual = actual,
        expected = expected,
        mismatches = mismatches,
    }
end

function M.run_suite(fixtures, opts)
    if type(fixtures) ~= "table" then
        error("pending_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "pending_suite"
    local entries = {}
    local total = 0
    local passed = 0
    local failed = 0

    for i, fixture in ipairs(fixtures) do
        total = total + 1
        local entry = M.run_fixture(fixture)
        entry.index = i
        entries[#entries + 1] = entry
        if entry.ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    return {
        ok = failed == 0,
        suite_id = suite_id,
        total = total,
        passed = passed,
        failed = failed,
        entries = entries,
    }
end

return M
