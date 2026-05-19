local structural_compare = require("tests.replay.harness.structural_compare")
local defensive_utils = require("uc_scheduler_defensive_utils")

local M = {}

local function call_helper(helper, input)
    if helper == "debuff_spell_for_buff_id" then
        return defensive_utils.debuff_spell_for_buff_id(input and input.res_table, input and input.buff_id)
    end
    if helper == "has_buff" then
        return defensive_utils.has_buff(input and input.buff_list, input and input.buff_id)
    end
    if helper == "estimate_missing_hp" then
        return defensive_utils.estimate_missing_hp(input and input.member)
    end
    if helper == "resolve_doom_buff_id" then
        return defensive_utils.resolve_doom_buff_id(input and input.res_table, input and input.doom_buff_id)
    end
    if helper == "player_has_doom" then
        return defensive_utils.player_has_doom(input and input.resolve_fn, input and input.player)
    end
    if helper == "member_priority" then
        return defensive_utils.member_priority(input and input.member or {})
    end
    if helper == "pri_default" then
        return defensive_utils.pri_default(input and input.player_prio, input and input.action_prio)
    end
    if helper == "danger_level" then
        return defensive_utils.danger_level(input and input.hpp)
    end
    if helper == "cure_better" then
        return defensive_utils.cure_better(input and input.c1, input and input.c2)
    end
    if helper == "cure_tier_for_missing_hp" then
        return defensive_utils.cure_tier_for_missing_hp(input and input.hp_missing, input and input.max_tier, input and input.cure_by_tier or {})
    end
    if helper == "is_bard_song" then
        return defensive_utils.is_bard_song(input and input.spell_name, input and input.lookup)
    end
    error("unknown helper: " .. tostring(helper))
end

function M.run_fixture(fixture)
    if type(fixture) ~= "table" then
        error("defensive_utils_fixture_runner.run_fixture expects fixture table")
    end

    local actual_result = call_helper(fixture.helper, fixture.input or {})
    local actual_obj = { result = actual_result }
    local expected_obj = fixture.expected or {}
    local ok, mismatches = structural_compare.compare(actual_obj, expected_obj)

    return {
        fixture_id = fixture.fixture_id,
        helper = fixture.helper,
        ok = ok,
        actual = actual_obj,
        expected = expected_obj,
        mismatches = mismatches,
    }
end

function M.run_suite(fixtures, opts)
    if type(fixtures) ~= "table" then
        error("defensive_utils_fixture_runner.run_suite expects fixtures table")
    end

    opts = opts or {}
    local suite_id = opts.suite_id or "defensive_utils_suite"
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
