local function read_file(path)
    local fh, err = io.open(path, "r")
    if not fh then
        error("failed to open " .. tostring(path) .. ": " .. tostring(err))
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

local function slice_between(text, start_needle, end_needle)
    local start_pos = text:find(start_needle, 1, true)
    if not start_pos then
        error("missing slice start: " .. start_needle)
    end
    local end_pos = text:find(end_needle, start_pos, true)
    if not end_pos then
        error("missing slice end: " .. end_needle)
    end
    return text:sub(start_pos, end_pos + #end_needle - 1)
end

local function main()
    local party_follow = read_file("uc_party_follow.lua")
    local pathing = read_file("uc_pathing.lua")
    local scheduler = read_file("unified_scheduler.lua")
    local combat_provider = read_file("uc_provider_combat.lua")
    local defensive_provider = read_file("uc_provider_defensive.lua")
    local target_provider = read_file("uc_provider_target_control.lua")
    local scheduler_config = read_file("uc_scheduler_config.lua")
    local domain_ownership = read_file("uc_domain_ownership.lua")
    local runtime_overrides = read_file("uc_runtime_overrides.lua")
    local combat_core = read_file("unified_combat_core.lua")
    local hb_buff_maint = read_file("uc_hb_buff_maint.lua")
    local cor_maintenance = read_file("uc_cor_maintenance.lua")
    local add_control = read_file("uc_add_control.lua")
    local add_priority = read_file("uc_add_priority.lua")
    local fight_leader = read_file("uc_fight_leader.lua")
    local addon = read_file("UnifiedCombat.lua")

    assert_contains(party_follow, "local uc_active_config = require('uc_active_config')", "party follow must require active config")
    assert_contains(party_follow, "uc_active_config.get_path('config.debug.enabled')", "party follow debug gate must read active config")
    assert_contains(party_follow, "local uc_follow_config = require('uc_follow_config')", "party follow must use canonical follow adapter")
    assert_contains(party_follow, "uc_follow_config.party_leader_id(active_follow_config())", "party follow leader identity must resolve from canonical config")
    assert_contains(party_follow, "local party = uc_follow_config.party(active_follow_config())", "party follow distances and enablement must read canonical party config")
    assert_contains(party_follow, "local fight = uc_follow_config.fight(active_follow_config())", "fight-follow minimum must read canonical fight config")
    assert_not_contains(party_follow, "active_value_or_flat(", "party follow must not retain flat follow fallback")

    assert_contains(pathing, "local uc_active_config = require('uc_active_config')", "pathing must require active config")
    assert_contains(pathing, "uc_active_config.get_path('config.debug.enabled')", "pathing debug overlay gate must read active config")
    assert_contains(pathing, "local uc_path_config = require('uc_path_config')", "pathing must use canonical path adapter")
    assert_not_contains(pathing, "active_value_or_flat(", "pathing must not retain canonical-first flat path fallback")
    assert_contains(pathing, "uc_path_config.recording_enabled(active_path_config())", "path recording must use canonical path policy")
    assert_contains(pathing, "uc_path_config.follow_enabled(active_path_config())", "path follow must use canonical path policy")
    assert_contains(pathing, "uc_path_config.party_gate_yalms(active_path_config())", "path gate must use canonical path policy")
    assert_contains(pathing, "uc_path_config.resume_index_window(active_path_config())", "path resume window must use canonical path policy")
    assert_contains(pathing, "settings and settings.path_file_name", "path filename must remain runtime/session state")
    assert_contains(pathing, "settings and settings.path_route_type", "classified route must remain runtime/session state")
    assert_not_contains(pathing, "config.movement.path.file_name", "pathing must not read session filename from durable config")
    assert_not_contains(pathing, "config.movement.path.route_type", "pathing must not read classified route from durable config")
    assert_contains(pathing, "local uc_follow_config = require('uc_follow_config')", "pathing party-follow arbitration must use canonical follow adapter")
    assert_contains(pathing, "uc_follow_config.party_leader_id(config)", "pathing party-follow arbitration must resolve canonical leader identity")

    assert_contains(hb_buff_maint, "function mod.choose(config, members, helpers)", "hb buff maintenance must receive canonical config explicitly")
    assert_contains(hb_buff_maint, "type(config.defensive) == 'table'", "hb buff maintenance must read the canonical defensive domain")
    assert_not_contains(hb_buff_maint, "uc_active_config", "hb buff maintenance must not hide a global active-config dependency")
    assert_not_contains(hb_buff_maint, "active_value_or_flat", "hb buff maintenance must not retain flat fallback")

    assert_contains(cor_maintenance, "function mod.propose(config)", "cor maintenance must receive canonical config explicitly")
    assert_contains(cor_maintenance, "type(config.maintenance) == 'table'", "cor maintenance must read the canonical maintenance domain")
    assert_contains(cor_maintenance, "abilities.configured", "cor maintenance ability fallback must stay inside canonical config")
    assert_not_contains(cor_maintenance, "uc_active_config", "cor maintenance must not hide a global active-config dependency")
    assert_not_contains(cor_maintenance, "active_value_or_flat", "cor maintenance must not retain flat fallback")

    assert_contains(scheduler_config, "local uc_active_config = require('uc_active_config')", "scheduler config facade must require active config")
    assert_contains(scheduler_config, "config.debug.enabled", "scheduler config facade must cover debug enabled")
    assert_contains(scheduler_config, "config.debug.action_timeline", "scheduler config facade must cover action timeline logging")
    assert_contains(scheduler_config, "config.debug.def_sched", "scheduler config facade must cover defensive scheduler logging")
    assert_contains(scheduler_config, "config.debug.tank_sched", "scheduler config facade must cover tank scheduler logging")
    assert_contains(scheduler_config, "config.combat.autotarget", "scheduler config facade must cover combat autotarget")
    assert_contains(scheduler_config, "config.combat.prime", "scheduler config facade must cover combat prime")
    assert_not_contains(scheduler_config, "scheduler_dark_launch_", "scheduler config facade must not retain obsolete ownership markers")
    assert_contains(scheduler_config, "config.tank.enabled", "scheduler config facade must cover tank enabled")
    assert_contains(scheduler_config, "config.tank.enmity.actions", "scheduler config facade must cover tank enmity actions")
    assert_contains(scheduler_config, "config.defensive.enemy_buffs.remove", "scheduler config facade must cover enemy-buff removal diagnostics")
    assert_not_contains(scheduler_config, "config.follow.fight.leader", "fight_leader readers must remain deferred in the scheduler config facade")
    assert_not_contains(scheduler_config, "config.follow.fight.leader_id", "fight_leader_id readers must remain deferred in the scheduler config facade")
    assert_not_contains(scheduler_config, "config.targeting.add_priority_names", "add_priority readers must remain outside the scheduler config facade")
    assert_contains(scheduler_config, "function M.sleep_enabled_from_config(config)", "scheduler config facade must expose canonical Sleep enablement")
    assert_contains(scheduler_config, "function M.sleep_order_from_config(config)", "scheduler config facade must expose canonical Sleep spell order")
    assert_contains(scheduler_config, "function M.sleep_max_target_range_from_config(config)", "scheduler config facade must expose canonical Sleep range")

    assert_contains(runtime_overrides, "local uc_follow_config = require('uc_follow_config')", "runtime override facade must consume canonical follow adapter")
    assert_contains(runtime_overrides, "uc_follow_config.fight_leader_id(config)", "runtime override facade must resolve canonical fight leader identity")
    assert_contains(runtime_overrides, "config.targeting\')", "runtime override facade must read canonical targeting domain")
    assert_contains(runtime_overrides, "config.sleep.enabled", "runtime override facade must expose sleep enabled accessors")
    assert_contains(runtime_overrides, "sleep.order", "runtime override facade must expose canonical sleep spell order")
    assert_not_contains(runtime_overrides, "set_active_profile(", "runtime override facade must remain read-only")
    assert_not_contains(runtime_overrides, "sync_flat_settings_in_place(", "runtime override facade must not sync arbitrary command mutations")

    assert_contains(scheduler, "local uc_scheduler_config = require('uc_scheduler_config')", "scheduler must require the scheduler config facade")
    assert_contains(scheduler, "sleep_enabled = uc_scheduler_config.sleep_enabled_from_config", "scheduler must inject canonical Sleep enablement into the combat provider")
    assert_contains(combat_provider, "sleep_enabled(ctx.config)", "combat provider Sleep toggle must consume canonical scheduler config")
    assert_contains(scheduler, "sleep_spell_list = scheduler.sleep_spell_list_from_config", "scheduler Sleep spell order must come from canonical config")
    assert_contains(scheduler, "fight_leader_enabled = function(config)", "scheduler must inject canonical fight-leader enablement")
    assert_contains(scheduler, "fight_leader_id = function(config)", "scheduler must inject canonical fight-leader identity")
    assert_contains(combat_provider, "fight_leader_enabled(ctx.config)", "combat provider must consume canonical fight-leader enablement")
    assert_contains(combat_provider, "fight_leader_id(ctx.config)", "combat provider must consume canonical fight-leader identity")
    assert_contains(scheduler, "uc_scheduler_config.debug_enabled(", "scheduler debug gates must read through the scheduler config facade")
    assert_contains(scheduler, "uc_scheduler_config.debug_action_timeline(", "scheduler action timeline gate must read through the scheduler config facade")
    assert_contains(scheduler, "uc_scheduler_config.debug_log_def_sched(", "scheduler defensive log gates must read through the scheduler config facade")
    assert_contains(scheduler, "uc_scheduler_config.debug_log_tank_sched(", "scheduler tank log gates must read through the scheduler config facade")
    assert_contains(scheduler, "combat_autotarget = uc_scheduler_config.combat_autotarget_from_config", "scheduler must inject canonical-context autotarget into extracted providers")
    assert_contains(target_provider, "combat_autotarget(ctx.config)", "target provider must read autotarget from canonical scheduler config")
    assert_contains(combat_provider, "combat_autotarget(ctx.config)", "combat provider must read autotarget from canonical scheduler config")
    assert_contains(combat_provider, "combat_prime(ctx.config)", "combat provider engage claim policy must consume canonical Prime config")
    assert_contains(combat_provider, "tank_enabled(ctx.config)", "combat provider priority paths must consume canonical tank config")
    assert_contains(scheduler, "local domain_ownership = require('uc_domain_ownership')", "scheduler must require the Phase 5 domain ownership policy")
    assert_contains(scheduler, "return domain_ownership.is_enabled('combat')", "scheduler must inject active-config combat domain enablement into extracted providers")
    assert_contains(scheduler, "uc_scheduler_config.defensive_from_config(config)", "scheduler must obtain defensive policy from canonical config")
    assert_contains(defensive_provider, "type(ctx.config) == 'table'", "defensive provider must consume the canonical scheduler config snapshot")
    assert_contains(defensive_provider, "config.provider or 'internal'", "defensive provider must read provider selection from canonical defensive config")
    assert_not_contains(defensive_provider, "active_value_or_flat", "defensive provider must not retain canonical-first flat fallback")
    assert_not_contains(defensive_provider, "ctx.settings", "defensive provider must not read flat scheduler settings")
    assert_contains(scheduler, "local cure_enabled = cure.enabled == true", "scheduler must consume canonical defensive cure enablement")
    assert_contains(scheduler, "tonumber(cure.min_tier)", "scheduler must consume canonical defensive cure minimum tier")
    assert_contains(scheduler, "tonumber(cure.max_tier)", "scheduler must consume canonical defensive cure maximum tier")
    assert_contains(scheduler, "tonumber(cure.min_missing_hp)", "scheduler must consume canonical defensive cure missing-hp gate")
    assert_contains(scheduler, "local ignore_trusts = cure.ignore_trusts ~= false", "scheduler must consume canonical defensive trust handling")
    assert_contains(scheduler, "enabled = na.enabled == true", "scheduler must consume canonical defensive NA enablement")
    assert_contains(scheduler, "limit_enabled = na.limit_enabled == true", "scheduler must consume canonical status-removal limiting")
    assert_contains(scheduler, "priority = na.priority", "scheduler must consume canonical status-removal priority")
    assert_contains(scheduler, "uc_scheduler_config.defensive_critical_hpp_from_config(config)", "scheduler must consume canonical defensive critical threshold")
    assert_contains(domain_ownership, "config.ownership.domain_combat_enabled", "domain ownership policy must read combat enablement")
    assert_contains(domain_ownership, "config.ownership.domain_defensive_enabled", "domain ownership policy must read defensive enablement")
    assert_contains(domain_ownership, "config.ownership.domain_movement_enabled", "domain ownership policy must read movement enablement")
    assert_contains(domain_ownership, "config.ownership.domain_maintenance_enabled", "domain ownership policy must read maintenance enablement")
    assert_not_contains(scheduler, "config.ownership.scheduler_dark_launch_", "scheduler runtime must not branch on compatibility-only ownership markers")

    assert_contains(combat_core, "local function scheduler_settings_view(settings, config)", "combat core must build a scheduler-only config view with canonical context")
    assert_contains(combat_core, "scheduler_config.combat_autotarget_from_config(config)", "combat core scheduler target provider must prefer canonical context for autotarget")
    assert_contains(combat_core, "scheduler_config.combat_autotarget(base)", "combat core must retain autotarget fallback for unmigrated direct callers")
    assert_contains(combat_core, "scheduler_config.combat_prime(base)", "combat core scheduler target provider must consult active config for prime")
    assert_contains(combat_core, "scheduler_config.tank_enabled_from_config(config)", "combat core scheduler providers must prefer canonical tank mode")
    assert_contains(combat_core, "scheduler_config.tank_enmity_actions_from_config(config)", "combat core tank provider must prefer canonical tank enmity actions")
    assert_contains(combat_core, "scheduler_config.tank_enabled(base)", "combat core must retain tank fallback for unmigrated direct callers")
    assert_contains(combat_core, "scheduler_config.tank_enmity_actions(base)", "combat core must retain tank-enmity fallback for unmigrated direct callers")

    assert_contains(add_control, "local uc_runtime_overrides = require('uc_runtime_overrides')", "add control must require runtime overrides")
    assert_contains(add_control, "uc_runtime_overrides.fight_leader_enabled(s)", "add control must consult runtime override fight leader state")
    assert_contains(add_priority, "local uc_runtime_overrides = require('uc_runtime_overrides')", "add priority helper must require runtime overrides")
    assert_contains(add_priority, "uc_runtime_overrides.add_priority_names(s)", "add priority helper must consult runtime override names")
    assert_contains(fight_leader, "local uc_runtime_overrides = require('uc_runtime_overrides')", "fight leader helper must require runtime overrides")
    assert_contains(fight_leader, "uc_runtime_overrides.fight_leader_enabled(settings)", "fight leader helper must consult runtime override enablement")
    assert_contains(fight_leader, "uc_runtime_overrides.fight_leader_id(settings)", "fight leader helper must consult runtime override leader id")
    assert_contains(addon, "local uc_runtime_overrides = require('uc_runtime_overrides')", "addon command helpers must require runtime overrides")
    assert_contains(addon, "uc_profile_v2_command_edits.sleep('list')", "addon sleep command status must read canonical Profile V2")
    assert_contains(addon, "uc_runtime_overrides.sleep_spell_names(settings)", "addon sleep spell list helper must consult runtime override spell names")

    local addon_command_block = slice_between(
        addon,
        "windower.register_event('addon command', function(...)",
        "windower.add_to_chat(167, 'Unknown command.')"
    )
    local start_command_block = slice_between(
        addon,
        "if a == 'start' then",
        "elseif a == 'stop' then"
    )
    local load_block = slice_between(
        addon,
        "windower.register_event('load', function()",
        "windower.register_event('incoming chunk', function(id, data)"
    )
    local job_change_block = slice_between(
        addon,
        "windower.register_event('job change', function(job, lvl)",
        "windower.register_event('zone change', function()"
    )
    local login_start = addon:find("windower.register_event('login', function()", 1, true)
    if not login_start then
        error("missing login block start")
    end
    local login_block = addon:sub(login_start)
    assert_not_contains(
        addon_command_block,
        "uc_sync_active_profile_from_settings(",
        "addon command handlers must not introduce generic active-profile sync after arbitrary command mutation"
    )
    assert_not_contains(
        addon_command_block,
        "uc_active_config.set_active_profile(",
        "addon command handlers must not write active profile directly for arbitrary command mutations"
    )
    assert_not_contains(
        addon_command_block,
        "uc_active_config.sync_flat_settings_in_place(",
        "addon command handlers must not project command mutations through active-profile sync"
    )
    assert_contains(addon_command_block, "elseif a == 'fight_leader' or a == 'fightleader' then", "fight_leader command must remain available after canonical cutover")
    assert_contains(
        start_command_block,
        "_G.UC_ZONE_SUSPEND_UNTIL = nil",
        "explicit start command must clear the remaining zone action pause"
    )
    assert_not_contains(
        load_block,
        "_G.UC_ZONE_SUSPEND_UNTIL = nil",
        "addon load must not clear the zone action pause"
    )
    assert_not_contains(
        job_change_block,
        "_G.UC_ZONE_SUSPEND_UNTIL = nil",
        "job change autoload path must not clear the zone action pause"
    )
    assert_not_contains(
        login_block,
        "_G.UC_ZONE_SUSPEND_UNTIL = nil",
        "login autoload path must not clear the zone action pause"
    )

    io.stdout:write("selftest_active_config_consumer_migration: OK\n")
end

main()
