local structural_compare = require("tests.replay.harness.structural_compare")
local dispatcher = require("uc_scheduler_dispatcher")

local M = {}

local function make_deps(input_deps, calls)
    local deps = {
        execute = input_deps and input_deps.execute == true or false,
    }

    deps.send_command = function(command)
        calls.send_command = calls.send_command or {}
        calls.send_command[#calls.send_command + 1] = { command }
    end

    deps.run = function(x, y)
        calls.run = calls.run or {}
        calls.run[#calls.run + 1] = { x, y }
    end

    deps.turn = function(heading)
        calls.turn = calls.turn or {}
        calls.turn[#calls.turn + 1] = { heading }
    end

    deps.set_target = function(target_id)
        calls.set_target = calls.set_target or {}
        calls.set_target[#calls.set_target + 1] = { target_id }
    end

    if input_deps and input_deps.missing then
        deps[input_deps.missing] = nil
    end

    return deps
end

local function call_helper(fixture)
    local input = fixture.input or {}

    if fixture.helper == "normalize_intent" then
        return {
            result = dispatcher.normalize_intent(input.intent),
        }
    end

    if fixture.helper == "validate_intent" then
        local ok, reason = dispatcher.validate_intent(input.intent)
        return {
            result = { ok, reason },
        }
    end

    if fixture.helper == "dispatch_intent" then
        local calls = {}
        local deps = make_deps(input.deps, calls)
        local result = dispatcher.dispatch_intent(input.intent, deps)
        return {
            result = result,
            calls = calls,
        }
    end

    error("unknown helper: " .. tostring(fixture.helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("dispatcher_fixture_runner.run_fixture expects fixture table")
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
        error("dispatcher_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "dispatcher_suite"
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
