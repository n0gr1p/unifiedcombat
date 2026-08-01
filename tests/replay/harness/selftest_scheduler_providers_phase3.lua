local PROVIDER_PATHS = {
    "uc_provider_defensive.lua",
    "uc_provider_combat.lua",
    "uc_provider_tank_enmity.lua",
    "uc_provider_enemy_buff_removal.lua",
    "uc_provider_maintenance.lua",
    "uc_provider_target_control.lua",
}

local function read_file(path)
    local file, err = io.open(path, "rb")
    if not file then
        error("failed to open " .. tostring(path) .. ": " .. tostring(err))
    end
    local source = file:read("*a")
    file:close()
    return source
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then
        error(message or ("missing expected text: " .. tostring(needle)))
    end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then
        error(message or ("unexpected text: " .. tostring(needle)))
    end
end

local function assert_before(source, first, second, message)
    local first_pos = source:find(first, 1, true)
    local second_pos = source:find(second, 1, true)
    if not first_pos or not second_pos or first_pos >= second_pos then
        error(message or ("expected " .. tostring(first) .. " before " .. tostring(second)))
    end
end

local function assert_provider_purity()
    local forbidden = {
        "windower.send_command(",
        "windower.ffxi.run(",
        "windower.ffxi.turn(",
        "uc_settarget.select_by_id(",
        "uc_attack.engage_target(",
        "uc_attack.switch_target(",
        "uc_attack.disengage(",
        "uc_add_control.execute_add_retarget(",
        "dispatch_intent(",
        "apply_command_ownership(",
        "apply_run_ownership(",
        "apply_run_stop_ownership(",
        "apply_target_ownership(",
        "apply_turn_ownership(",
        "p1_get_locks(",
        "p1_hard_lock_reject(",
        "record_dispatch(",
        "pcall(require",
    }
    for _, path in ipairs(PROVIDER_PATHS) do
        local source = read_file(path)
        assert_contains(source, "function M.new(deps)", path .. " must expose a dependency-injected factory")
        for _, needle in ipairs(forbidden) do
            assert_not_contains(source, needle, path .. " must remain proposal-only: " .. needle)
        end
    end
end

local function assert_scheduler_wiring()
    local source = read_file("unified_scheduler.lua")
    local removed_collectors = {
        "local function p1_collect_defensive_internal",
        "local function p1_collect_defensive_healbot",
        "local function p1_collect_combat_offense",
        "function p1_combat_helpers.collect_combat_sleep",
        "local function p1_collect_combat_engage",
        "local function p1_collect_combat_ja",
        "local function p1_collect_combat_tank_enmity",
        "local function p1_collect_enemy_buff_removal",
        "local function p1_collect_maintenance",
        "local function p1_collect_target_control",
        "local function p1_collect_pull_control",
    }
    for _, needle in ipairs(removed_collectors) do
        assert_not_contains(source, needle, "proposal collection must live outside unified_scheduler.lua: " .. needle)
    end

    local calls = {
        "scheduler.providers.target_control.collect_target(ctx, out)",
        "scheduler.providers.combat.collect_engage(ctx, out)",
        "scheduler.providers.target_control.collect_pull(ctx, out)",
        "scheduler.providers.tank_enmity.collect(ctx, out)",
        "scheduler.providers.combat.collect_sleep(ctx, out)",
        "scheduler.providers.combat.collect_offense(ctx, out)",
        "scheduler.providers.combat.collect_ja(ctx, out)",
        "scheduler.providers.enemy_buff_removal.collect(ctx, out)",
        "scheduler.providers.defensive.collect_internal(ctx, out)",
        "scheduler.providers.defensive.collect_healbot(ctx, out)",
        "scheduler.providers.maintenance.collect(ctx, out)",
    }
    for _, call in ipairs(calls) do
        assert_contains(source, call, "scheduler must collect from extracted provider: " .. call)
    end
    for index = 1, #calls - 1 do
        assert_before(source, calls[index], calls[index + 1], "provider collection order changed")
    end

    for _, path in ipairs(PROVIDER_PATHS) do
        local module_name = path:gsub("%.lua$", "")
        assert_contains(source, "require('" .. module_name .. "').new({", "scheduler must initialize " .. module_name)
    end
end

local function assert_fail_fast_factories()
    for _, path in ipairs(PROVIDER_PATHS) do
        local module_name = path:gsub("%.lua$", "")
        package.loaded[module_name] = nil
        local module = require(module_name)
        local ok = pcall(module.new, {})
        assert_equal(ok, false, module_name .. " must reject missing dependencies")
    end
end

local function assert_defensive_proposal_shape()
    package.loaded.uc_provider_defensive = nil
    local provider = require("uc_provider_defensive").new({
        bool_setting = function(value) return value == true end,
        active_value_or_flat = function(_, flat_value) return flat_value end,
        build_defensive_candidates = function() return { "candidate" } end,
        choose_defensive_action = function()
            return {
                type = "cure",
                spell = "Cure IV",
                target = {
                    id = 77,
                    name = "Ally",
                    hpp = 20,
                    is_self = false,
                },
            }, "critical_cure"
        end,
        action_ready = function() return true, "READY", "spell" end,
        build_action_command = function() return "input /ma Cure IV 77" end,
        clamp_urgency = function(value) return value end,
        critical_cure_priority = 153,
    })
    local proposals = {}
    provider.collect_internal({
        now = 12.5,
        settings = {
            defensive_enabled = true,
            defensive_provider = "internal",
            defensive_critical_hpp = 35,
        },
    }, proposals)
    assert_equal(#proposals, 1, "defensive provider proposal count")
    local proposal = proposals[1]
    assert_equal(proposal.family_id, "def.internal.cure", "defensive family")
    assert_equal(proposal.provider, "defensive_internal", "defensive provider")
    assert_equal(proposal.action_type, "spell", "defensive action type")
    assert_equal(proposal.action_name, "Cure IV", "defensive action name")
    assert_equal(proposal.target_kind, "ally", "defensive target kind")
    assert_equal(proposal.target_id, 77, "defensive target id")
    assert_equal(proposal.priority_band, 153, "critical Cure priority")
    assert_equal(proposal.urgency, 0.70, "Cure urgency")
    assert_equal(proposal.lock_class, "support_action", "defensive lock class")
    assert_equal(proposal.reason_code, "critical_cure", "defensive reason")
    assert_equal(proposal.legacy_command, "input /ma Cure IV 77", "defensive compatibility command")
end

local function assert_tank_proposal_shape()
    package.loaded.uc_provider_tank_enmity = nil
    local provider = require("uc_provider_tank_enmity").new({
        bool_setting = function(value) return value == true end,
        select_tank_enmity = function()
            return {
                kind = "ja",
                name = "Provoke",
                target_id = 900,
                target_name = "Enemy",
                victim_name = "Ally",
                victim_hpp = 40,
                mob_hpp = 88,
                dist = 12,
                action_range = 20,
                reason = "victim_not_tank",
            }
        end,
        action_ready = function() return true, "READY", "ja" end,
        log_tank_sched = function() end,
        clamp_urgency = function(value) return value end,
    })
    local old_engine = rawget(_G, "Start_Engine")
    _G.Start_Engine = true
    local proposals = {}
    provider.collect({
        now = 20,
        player_present = true,
        player = { status = 1 },
        settings = {},
    }, proposals)
    _G.Start_Engine = old_engine
    assert_equal(#proposals, 1, "tank provider proposal count")
    local proposal = proposals[1]
    assert_equal(proposal.family_id, "combat.tank_enmity.primary", "tank family")
    assert_equal(proposal.provider, "combat", "tank provider compatibility value")
    assert_equal(proposal.action_type, "ja", "tank action type")
    assert_equal(proposal.action_name, "Provoke", "tank action name")
    assert_equal(proposal.target_id, 900, "tank target id")
    assert_equal(proposal.priority_band, 96, "tank priority")
    assert_equal(proposal.urgency, 0.60, "tank urgency floor")
    assert_equal(proposal.movement_policy, "requires_range", "tank movement policy")
    assert_equal(proposal.lock_class, "offense_action", "tank lock class")
    assert_equal(proposal.reason_code, "tank_enmity_violation", "tank reason")
    assert_equal(proposal.legacy_command, 'input /ja "Provoke" 900', "tank compatibility command")
end

local function assert_target_and_pull_proposal_shapes()
    package.loaded.uc_provider_target_control = nil
    local target_pick = {
        target_id = 501,
        target_name = "Target",
        hpp = 100,
    }
    local pull_pick = {
        target_id = 502,
        target_name = "Pull Target",
        action_name = "Flash",
        action_type = "spell",
        in_range = true,
        dist = 15,
        range_max = 20,
    }
    local provider = require("uc_provider_target_control").new({
        bool_setting = function(value) return value == true end,
        combat_autotarget = function() return true end,
        combat_domain_enabled = function() return true end,
        tank_enabled = function() return false end,
        select_target = function() return target_pick end,
        add_control_enabled = function() return false end,
        select_pull = function() return pull_pick end,
        action_timeline_log = function() end,
        clamp_urgency = function(value) return value end,
        tank_target_priority = 132,
        tank_target_urgency = 0.95,
    })
    local old_engine = rawget(_G, "Start_Engine")
    _G.Start_Engine = true
    local ctx = {
        now = 30,
        settings = {},
        player_present = true,
        player = { status = 0 },
        target_present = false,
    }
    local proposals = {}
    provider.collect_target(ctx, proposals)
    provider.collect_pull(ctx, proposals)
    _G.Start_Engine = old_engine
    assert_equal(#proposals, 2, "target and pull proposal count")
    assert_equal(proposals[1].family_id, "target.acquire.primary", "target family")
    assert_equal(proposals[1].provider, "target_control", "target provider")
    assert_equal(proposals[1].action_type, "target", "target action type")
    assert_equal(proposals[1].target_id, 501, "target id")
    assert_equal(proposals[1].priority_band, 84, "default target priority")
    assert_equal(proposals[1].lock_class, "target_control", "target lock class")
    assert_equal(proposals[2].family_id, "combat.pull.primary", "pull family")
    assert_equal(proposals[2].provider, "pull_control", "pull provider")
    assert_equal(proposals[2].action_type, "pull", "pull action type")
    assert_equal(proposals[2].action_name, "Flash", "pull action name")
    assert_equal(proposals[2].target_id, 502, "pull target id")
    assert_equal(proposals[2].priority_band, 82, "pull priority")
    assert_equal(proposals[2].lock_class, "offense_action", "pull lock class")
end

local function main()
    assert_provider_purity()
    assert_scheduler_wiring()
    assert_fail_fast_factories()
    assert_defensive_proposal_shape()
    assert_tank_proposal_shape()
    assert_target_and_pull_proposal_shapes()
    io.stdout:write("selftest_scheduler_providers_phase3: OK\n")
end

main()
