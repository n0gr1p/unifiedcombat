local structural_compare = require("tests.replay.harness.structural_compare")
local locks = require("uc_scheduler_locks")

local M = {}

local function call_helper(fixture)
    local input = fixture.input or {}

    if fixture.helper == "p1_pending_is_live_state" then
        return {
            result = locks.p1_pending_is_live_state(input.state_name),
        }
    end

    if fixture.helper == "p1_duplicate_suppressed" then
        return {
            result = locks.p1_duplicate_suppressed(input.scheduler, input.ctx, input.proposal, input.p1_number),
        }
    end

    if fixture.helper == "p1_get_locks" then
        return {
            result = locks.p1_get_locks(input.scheduler, input.ctx, input.p1_number, input.globals or {}),
        }
    end

    if fixture.helper == "p1_hard_lock_reject" then
        local out = {}
        for _, c in ipairs(input.calls or {}) do
            out[#out + 1] = locks.p1_hard_lock_reject(c.locks or {}, c.proposal or {})
        end
        return {
            result = out,
        }
    end

    if fixture.helper == "p1_build_lock_summary" then
        return {
            result = locks.p1_build_lock_summary(input.ctx, input.locks, input.p1_get_locks),
        }
    end

    if fixture.helper == "reset_runtime_locks" then
        local st = input.state or {}
        local function action_state()
            return st
        end
        local result = locks.reset_runtime_locks(input.globals or {}, action_state)
        return {
            result = result,
            globals = input.globals,
            state = st,
        }
    end

    error("unknown helper: " .. tostring(fixture.helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("locks_fixture_runner.run_fixture expects fixture table")
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
        error("locks_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "locks_suite"
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
