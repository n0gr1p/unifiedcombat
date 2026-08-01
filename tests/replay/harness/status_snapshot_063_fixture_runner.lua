local structural_compare = require("tests.replay.harness.structural_compare")
local parser_module = require("uc_scheduler_status_snapshot_parser")

local M = {}

local function ensure_string_unpack_compat()
    if type(string.unpack) == "function" then
        return
    end

    string.unpack = function(a, b, c)
        local data
        local fmt
        local pos

        if type(a) == "string" and (b == "H" or b == "I") then
            data = a
            fmt = b
            pos = c
        else
            fmt = a
            data = b
            pos = c
        end

        if type(data) ~= "string" then
            error("string.unpack compat expects string data")
        end
        if fmt ~= "H" and fmt ~= "I" then
            error("string.unpack compat only supports formats H and I")
        end

        local offset = pos or 1
        if fmt == "H" then
            local b1 = data:byte(offset) or 0
            local b2 = data:byte(offset + 1) or 0
            return b1 + b2 * 256
        end

        local b1 = data:byte(offset) or 0
        local b2 = data:byte(offset + 1) or 0
        local b3 = data:byte(offset + 2) or 0
        local b4 = data:byte(offset + 3) or 0
        return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("status_snapshot_063_fixture_runner.run_fixture expects fixture table")
    end

    ensure_string_unpack_compat()
    local actual = parser_module.parse_status_snapshot_063(fixture.data)
    local ok, mismatches = structural_compare.compare(actual, fixture.expected)

    return {
        fixture_id = fixture.fixture_id,
        ok = ok,
        actual = actual,
        expected = fixture.expected,
        mismatches = mismatches,
    }
end

function M.run_suite(fixtures, opts)
    if type(fixtures) ~= "table" then
        error("status_snapshot_063_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "status_snapshot_063_suite"
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
