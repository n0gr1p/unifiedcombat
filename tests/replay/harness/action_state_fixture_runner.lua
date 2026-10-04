local structural_compare = require("tests.replay.harness.structural_compare")
local action_state = require("uc_scheduler_action_state")

local M = {}

local function run_with_diag_sink(fn)
    local prev = rawget(_G, "__diag_sink")
    local sink = {}
    _G.__diag_sink = sink
    local ok, a, b = pcall(fn)
    _G.__diag_sink = prev
    if not ok then
        error(a)
    end
    return a, b, sink
end

local function call_helper(fixture)
    local input = fixture.input or {}
    local scheduler = input.scheduler or {}

    if fixture.helper == "action_state" then
        local result = action_state.action_state(scheduler)
        return result, scheduler.action_state, {}
    end

    if fixture.helper == "action_mark_sent" then
        local result = action_state.action_mark_sent(scheduler, input.kind, input.now_s)
        return result, scheduler.action_state, {}
    end

    if fixture.helper == "action_mark_packet_pair" then
        action_state.action_mark_packet_start(scheduler, input.start_now_s)
        local result = action_state.action_mark_packet_end(scheduler, input.end_now_s)
        return result, scheduler.action_state, {}
    end

    if fixture.helper == "action_is_acting" then
        local result = action_state.action_is_acting(scheduler, input.now_s)
        return result, scheduler.action_state, {}
    end

    if fixture.helper == "action_dispatch_blocked" then
        local blocked, code, sink = run_with_diag_sink(function()
            return action_state.action_dispatch_blocked(scheduler, input.now_s, input.globals or {})
        end)
        return { blocked, code }, scheduler.action_state, sink
    end

    error("unknown helper: " .. tostring(fixture.helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("action_state_fixture_runner.run_fixture expects fixture table")
    end

    local ok_call, result, state_after, diag_calls = pcall(function()
        return call_helper(fixture)
    end)

    if not ok_call then
        error(result)
    end

    local actual = {
        result = result,
        scheduler_action_state = state_after,
        diag_calls = diag_calls,
    }

    local expected = fixture.expected or {}
    local compare_actual = {
        result = actual.result,
        scheduler_action_state = actual.scheduler_action_state,
    }
    local compare_expected = {
        result = expected.result,
        scheduler_action_state = expected.scheduler_action_state,
    }
    local ok, mismatches = structural_compare.compare(compare_actual, compare_expected)

    local expected_diag = expected.diag_calls or {}
    local actual_diag = actual.diag_calls or {}
    if #actual_diag ~= #expected_diag then
        ok = false
        mismatches[#mismatches + 1] = "$.diag_calls length mismatch (" .. tostring(#actual_diag) .. " vs " .. tostring(#expected_diag) .. ")"
    end
    for i, spec in ipairs(expected_diag) do
        local got = actual_diag[i]
        if not got then
            ok = false
            mismatches[#mismatches + 1] = "$.diag_calls[" .. tostring(i) .. "]: missing call"
        else
            if spec.topic ~= nil and tostring(got.topic or "") ~= tostring(spec.topic) then
                ok = false
                mismatches[#mismatches + 1] = "$.diag_calls[" .. tostring(i) .. "].topic mismatch"
            end
            if spec.contains ~= nil then
                local msg = tostring(got.msg or "")
                if not string.find(msg, spec.contains, 1, true) then
                    ok = false
                    mismatches[#mismatches + 1] = "$.diag_calls[" .. tostring(i) .. "].msg missing substring " .. tostring(spec.contains)
                end
            end
        end
    end

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
        error("action_state_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "action_state_suite"
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
