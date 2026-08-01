local structural_compare = require("tests.replay.harness.structural_compare")
local dryrun_publish = require("uc_scheduler_dryrun_publish")

local M = {}

local function run_publish_fixture(fixture)
    local input = fixture.input
    if type(input) ~= "table" then
        error("publish fixture input must be a table")
    end

    local scheduler = input.scheduler
    local globals = input.globals
    local ctx = input.ctx
    local ranked = input.ranked
    local reject_counts = input.reject_counts
    local rejected = input.rejected
    local proposals = input.proposals
    local locks = input.locks

    if type(scheduler) ~= "table" or type(scheduler.phase1) ~= "table" then
        error("publish fixture requires scheduler.phase1 table")
    end
    if type(globals) ~= "table" then
        error("publish fixture requires globals table")
    end
    if type(ctx) ~= "table" then
        error("publish fixture requires ctx table")
    end
    if type(ranked) ~= "table" then
        error("publish fixture requires ranked table")
    end
    if type(reject_counts) ~= "table" then
        error("publish fixture requires reject_counts table")
    end
    if type(rejected) ~= "table" then
        error("publish fixture requires rejected table")
    end
    if type(proposals) ~= "table" then
        error("publish fixture requires proposals table")
    end
    if type(locks) ~= "table" then
        error("publish fixture requires locks table")
    end

    local helper_returns = input.helper_returns or {}
    local calls = {
        p1_format_top3 = {},
        p1_format_top3_verbose = {},
        p1_format_topn_lines = {},
        p1_capture_topn_items = {},
        p1_push_recent_rejects = {},
        p1_reject_top = {},
        p1_set_pending_globals = 0,
        p1_build_lock_summary = {},
    }

    local function p1_format_top3(ranked_arg)
        calls.p1_format_top3[#calls.p1_format_top3 + 1] = ranked_arg
        return helper_returns.top3
    end

    local function p1_format_top3_verbose(ranked_arg)
        calls.p1_format_top3_verbose[#calls.p1_format_top3_verbose + 1] = ranked_arg
        return helper_returns.top3_verbose
    end

    local function p1_format_topn_lines(ranked_arg, n)
        calls.p1_format_topn_lines[#calls.p1_format_topn_lines + 1] = {
            ranked = ranked_arg,
            n = n,
        }
        return helper_returns.top5_lines
    end

    local function p1_capture_topn_items(ranked_arg, n)
        calls.p1_capture_topn_items[#calls.p1_capture_topn_items + 1] = {
            ranked = ranked_arg,
            n = n,
        }
        return helper_returns.top5_items
    end

    local function p1_push_recent_rejects(ctx_arg, rejected_arg)
        calls.p1_push_recent_rejects[#calls.p1_push_recent_rejects + 1] = {
            ctx = ctx_arg,
            rejected = rejected_arg,
        }
        if input.recent_rejects_after_push ~= nil then
            scheduler.phase1.recent_rejects = input.recent_rejects_after_push
        end
    end

    local function p1_reject_top(reject_counts_arg, proposal_count)
        calls.p1_reject_top[#calls.p1_reject_top + 1] = {
            reject_counts = reject_counts_arg,
            proposal_count = proposal_count,
        }
        return helper_returns.reject_top
    end

    local function p1_set_pending_globals()
        calls.p1_set_pending_globals = calls.p1_set_pending_globals + 1
    end

    local function p1_build_lock_summary(ctx_arg, locks_arg)
        calls.p1_build_lock_summary[#calls.p1_build_lock_summary + 1] = {
            ctx = ctx_arg,
            locks = locks_arg,
        }
        return helper_returns.lock_summary
    end

    local result = dryrun_publish.publish(
        scheduler,
        globals,
        ctx,
        input.selected,
        ranked,
        reject_counts,
        rejected,
        proposals,
        locks,
        input.plan,
        input.commit_reason,
        p1_format_top3,
        p1_format_top3_verbose,
        p1_format_topn_lines,
        p1_capture_topn_items,
        p1_push_recent_rejects,
        p1_reject_top,
        p1_set_pending_globals,
        p1_build_lock_summary
    )

    return {
        result = result,
        scheduler_phase1 = scheduler.phase1,
        globals = globals,
        calls = calls,
    }
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("dryrun_publish_fixture_runner.run_fixture expects fixture table")
    end
    if fixture.helper ~= "publish" then
        error("unknown helper: " .. tostring(fixture.helper))
    end

    local ok_call, actual = pcall(function()
        return run_publish_fixture(fixture)
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
        error("dryrun_publish_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "dryrun_publish_suite"
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
