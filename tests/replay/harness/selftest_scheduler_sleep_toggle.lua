local scheduler_path = "unified_scheduler.lua"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text present: " .. needle))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local function target_id_spell_dispatch_ready_mock(input)
    local p1_combat_helpers = {
        target_distance_to_id = function(target_id)
            return input.distances[target_id], input.mobs[target_id]
        end,
    }
    local selected = input.selected or {}
    local expected_tid = tonumber(input.expected_tid) or 0
    local tank_enmity = input.tank_enmity == true
    if (tank_enmity or (type(selected.detail) == "table" and selected.detail.allow_target_id_send == true)) and expected_tid > 0 then
        local max_range = math.max(0, tonumber(((selected.range_policy or {}).max)) or 0)
        local dist, mob = p1_combat_helpers.target_distance_to_id(expected_tid)
        if not mob or mob.valid_target ~= true or (tonumber(mob.hpp) or 0) <= 0 then
            return false
        end
        if max_range > 0 and dist and dist > max_range then
            return false
        end
        return true
    end
    return false
end

local function collect_sleep_mock(input)
    local sleep_max_target_distance = tonumber(input.sleep_max_target_range) or 6.0
    if input.engine_on ~= true then
        return nil
    end
    if input.domain_combat_enabled ~= true then
        return nil
    end
    if input.sleep ~= true then
        return nil
    end
    local list = input.sleep_spells or {}
    if #list == 0 and tostring(input.legacy_sleepspell or "") ~= "" then
        list = { tostring(input.legacy_sleepspell) }
    end
    if #list == 0 then
        return nil
    end
    local best = nil
    for _, candidate in ipairs(input.candidates or {}) do
        if candidate.eligible == true
            and candidate.suppressed ~= true
            and (tonumber(candidate.dist) or 999) <= sleep_max_target_distance
            and candidate.available_spell
            and candidate.available_spell ~= "" then
            if not best
                or candidate.dist < best.dist
                or (candidate.dist == best.dist and candidate.target_id < best.target_id) then
                best = candidate
            end
        end
    end
    if not best then
        return nil
    end
    return {
        provider = "combat",
        action_type = "spell",
        action_name = best.available_spell,
        target_id = best.target_id,
        priority_band = 142,
        detail = {
            allow_target_id_send = true,
        },
    }
end

local function pick_top_priority(proposals)
    table.sort(proposals, function(a, b)
        if a.priority_band ~= b.priority_band then
            return a.priority_band > b.priority_band
        end
        return tostring(a.action_name or "") < tostring(b.action_name or "")
    end)
    return proposals[1]
end

local function main()
    local source = read_file(scheduler_path)
    local combat_provider = read_file("uc_provider_combat.lua")

    assert_contains(combat_provider, "function provider.collect_sleep(ctx, out)", "combat provider must collect Sleep proposals explicitly")
    assert_contains(combat_provider, "if not bool_setting(sleep_enabled(ctx.settings), false) then", "Sleep collection must stay behind the existing Sleep toggle")
    assert_contains(combat_provider, "local configured_sleep_spells = sleep_spell_list(ctx.settings)", "Sleep collection must use UI-owned configured spell lists")
    assert_contains(combat_provider, "if #configured_sleep_spells == 0 then", "Sleep collection must no-op when no spell list is configured")
    assert_contains(source, "scheduler.SLEEP_MAX_TARGET_DISTANCE = 6.0", "Sleep collection must retain the 6-yalm compatibility default")
    assert_contains(source, "function scheduler.sleep_max_target_distance(settings)", "Sleep collection must read the configured target range")
    assert_contains(combat_provider, "if tonumber(mob.status) ~= 1 then", "Sleep target selection must stay scoped to active threat-style mobs")
    assert_contains(combat_provider, "if (tonumber(mob.hpp) or 0) <= 99 then", "Sleep target selection must preserve the legacy full-HP add filter")
    assert_contains(combat_provider, "if dist > sleep_max_target_distance(ctx.settings) then", "Sleep target eligibility must reject mobs beyond the configured range")
    assert_contains(combat_provider, "if target_sleep_suppressed(ctx.settings, tid, ctx.now) then", "Sleep target eligibility must reject already-slept targets")
    assert_contains(source, "scheduler.PRIORITY_BAND_SLEEP = 142", "Sleep priority band must remain globally pinned")
    assert_contains(source, "sleep_priority = scheduler.PRIORITY_BAND_SLEEP", "scheduler must inject the global Sleep priority band")
    assert_contains(combat_provider, "priority_band = sleep_priority", "Sleep proposals must use the global priority band")
    assert_contains(combat_provider, "provider = 'combat'", "Sleep proposals must dispatch through combat provider arbitration")
    assert_contains(combat_provider, "action_type = 'spell'", "Sleep proposals must remain spell actions")
    assert_contains(combat_provider, "required_setting = 'sleep'", "Sleep proposals must remain bound to the Sleep setting")
    assert_contains(combat_provider, "allow_target_id_send = true", "Sleep casts must send by target id without forcing a target hijack")
    assert_contains(source, "function p1_combat_helpers.target_distance_to_id(target_id)", "combat spell target-id sends must use the shared helper-table distance function")
    assert_contains(source, "function p1_combat_helpers.spell_target_dispatch_ready(selected, expected_tid, tank_enmity)", "combat spell dispatch must use a shared target-id spell revalidation helper")
    assert_contains(source, "local dist, mob = p1_combat_helpers.target_distance_to_id(expected_tid)", "target-id spell dispatch must call the scoped helper instead of a bare global")
    assert_contains(source, "type(selected.detail) == 'table' and selected.detail.allow_target_id_send == true", "combat spell dispatch helper must support non-current-target spell sends by id")
    assert_not_contains(source, "local dist, mob = p1_target_distance_to_id(expected_tid)", "no bare p1_target_distance_to_id call should remain in scheduler target-id spell paths")
    assert_contains(source, "require('uc_scheduler_command_ownership').apply_command_ownership({", "Sleep spell sends must keep using the command ownership seam")
    assert_contains(source, "send_command = windower.send_command", "Sleep command ownership must inject the dispatcher executor")
    assert_not_contains(source, "hb off", "scheduler Sleep ownership must not revive legacy hb-off toggling")
    assert_not_contains(source, "hb on", "scheduler Sleep ownership must not revive legacy hb-on toggling")

    local proposals_anchor = assert(source:find("local function p1_collect_proposals(ctx)", 1, true))
    local collect_pos = assert(source:find("scheduler.providers.combat.collect_sleep(ctx, out)", proposals_anchor, true))
    local offense_pos = assert(source:find("scheduler.providers.combat.collect_offense(ctx, out)", proposals_anchor, true))
    assert_true(collect_pos < offense_pos, "Sleep proposal collection must happen before standard offense proposal collection")

    local none = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = false,
        sleep = true,
        sleep_spells = { "Sleep II" },
        candidates = {
            { eligible = true, target_id = 9, dist = 6, available_spell = "Sleep II" },
        },
    })
    assert_equal(none, nil, "disabled combat domain must suppress Sleep proposals")

    none = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = false,
        sleep_spells = { "Sleep II" },
        candidates = {
            { eligible = true, target_id = 10, dist = 6, available_spell = "Sleep II" },
        },
    })
    assert_equal(none, nil, "Sleep off must produce no Sleep proposal")

    none = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = {},
        legacy_sleepspell = "",
        candidates = {
            { eligible = true, target_id = 10, dist = 6, available_spell = "Sleep II" },
        },
    })
    assert_equal(none, nil, "empty configured Sleep spell list must produce no Sleep proposal")

    local preengage = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II", "Sleep" },
        engaged = false,
        candidates = {
            { eligible = true, target_id = 20, dist = 6, available_spell = "Sleep" },
        },
    })
    assert_true(type(preengage) == "table", "Sleep should still produce a proposal while not engaged")
    assert_equal(preengage.action_name, "Sleep", "pre-engage Sleep must still choose the available configured spell")

    none = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II", "Sleep" },
        engaged = false,
        candidates = {
            { eligible = true, target_id = 21, dist = 6.01, available_spell = "Sleep" },
        },
    })
    assert_equal(none, nil, "pre-engage Sleep must reject targets beyond 6 yalms")

    local engaged_add = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II" },
        engaged = true,
        candidates = {
            { eligible = true, target_id = 22, dist = 5.5, available_spell = "Sleep II" },
        },
    })
    assert_true(type(engaged_add) == "table", "engaged add Sleep must still work inside 6 yalms")

    none = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II" },
        engaged = true,
        candidates = {
            { eligible = true, target_id = 23, dist = 8, available_spell = "Sleep II" },
        },
    })
    assert_equal(none, nil, "engaged add Sleep must reject targets beyond 6 yalms")

    local configured_range = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_max_target_range = 14.0,
        sleep_spells = { "Sleep II" },
        candidates = {
            { eligible = true, target_id = 24, dist = 12.0, available_spell = "Sleep II" },
        },
    })
    assert_true(type(configured_range) == "table", "configured Sleep range must admit candidates beyond the 6-yalm default")

    none = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_max_target_range = 14.0,
        sleep_spells = { "Sleep II" },
        candidates = {
            { eligible = true, target_id = 25, dist = 14.01, available_spell = "Sleep II" },
        },
    })
    assert_equal(none, nil, "configured Sleep range must reject candidates beyond its maximum")

    local send_ready = target_id_spell_dispatch_ready_mock({
        selected = {
            detail = { allow_target_id_send = true },
            range_policy = { max = 6.0 },
        },
        expected_tid = 24,
        distances = {
            [24] = 5.5,
        },
        mobs = {
            [24] = { valid_target = true, hpp = 100 },
        },
    })
    assert_equal(send_ready, true, "Sleep target-id spell send path must stay callable when only the scoped helper exists")

    send_ready = target_id_spell_dispatch_ready_mock({
        selected = {
            detail = { allow_target_id_send = true },
            range_policy = { max = 6.0 },
        },
        expected_tid = 25,
        distances = {
            [25] = 6.01,
        },
        mobs = {
            [25] = { valid_target = true, hpp = 100 },
        },
    })
    assert_equal(send_ready, false, "Sleep target-id spell send path must still reject targets beyond the 6-yalm boundary")

    local skip_slept = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II", "Sleep" },
        engaged = true,
        candidates = {
            { eligible = true, suppressed = true, target_id = 30, dist = 4.5, available_spell = "Sleep II" },
            { eligible = true, target_id = 31, dist = 5.0, available_spell = "Sleep" },
        },
    })
    assert_true(type(skip_slept) == "table", "Sleep must still produce a proposal when another unslept mob is eligible")
    assert_equal(skip_slept.target_id, 31, "already-slept targets must be skipped in favor of another eligible add")
    assert_equal(skip_slept.action_name, "Sleep", "first available spell selection must remain intact for the unslept add")

    local ranked = pick_top_priority({
        { action_name = "Cure IV", priority_band = 220 },
        { action_name = "Sleep II", priority_band = 142 },
        { action_name = "Protect", priority_band = 70 },
    })
    assert_equal(ranked.action_name, "Cure IV", "critical defensive cures must still outrank Sleep")

    ranked = pick_top_priority({
        { action_name = "Sleep II", priority_band = 142 },
        { action_name = "Protect", priority_band = 70 },
        { action_name = "Berserk", priority_band = 70 },
    })
    assert_equal(ranked.action_name, "Sleep II", "Sleep must outrank lower-priority maintenance/offense setup proposals")

    io.stdout:write("selftest_scheduler_sleep_toggle: OK\n")
end

main()
