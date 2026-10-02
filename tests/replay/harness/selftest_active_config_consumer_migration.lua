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
    assert_contains(party_follow, "config.follow.party.enabled", "party follow readers must consult active config for party enablement")
    assert_contains(party_follow, "config.follow.party.leader_id", "party follow readers must consult active config for leader id")
    assert_contains(party_follow, "config.follow.party.leader_name", "party follow readers must consult active config for leader name")
    assert_contains(party_follow, "config.follow.party.min", "party follow readers must consult active config for follow minimum")
    assert_contains(party_follow, "config.follow.party.max", "party follow readers must consult active config for follow maximum")
    assert_contains(party_follow, "config.follow.fight.min", "party follow readers must consult active config for fight-follow minimum")

    assert_contains(pathing, "local uc_active_config = require('uc_active_config')", "pathing must require active config")
    assert_contains(pathing, "uc_active_config.get_path('config.debug.enabled')", "pathing debug overlay gate must read active config")
    assert_contains(pathing, "config.movement.path.recording", "pathing readers must consult active config for path recording")
    assert_contains(pathing, "config.movement.path.follow_enabled", "pathing readers must consult active config for path follow enablement")
    assert_contains(pathing, "config.movement.path.file_name", "pathing readers must consult active config for path file name")
    assert_contains(pathing, "config.movement.path.route_type", "pathing readers must consult active config for path route type")
    assert_contains(pathing, "config.movement.path.party_gate_yalms", "pathing readers must consult active config for path gate distance")
    assert_contains(pathing, "config.movement.path.resume_index_window", "pathing readers must consult active config for resume window")
    assert_contains(pathing, "config.follow.party.enabled", "pathing party-follow arbitration must consult active config for follow enablement")
    assert_contains(pathing, "config.follow.party.leader_id", "pathing party-follow arbitration must consult active config for follow leader id")

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
    assert_not_contains(scheduler_config, "config.sleep", "sleep readers must remain outside the scheduler config facade")

    assert_contains(runtime_overrides, "config.follow.fight.leader", "runtime override facade must expose fight leader accessors")
    assert_contains(runtime_overrides, "config.follow.fight.leader_id", "runtime override facade must expose fight leader id accessors")
    assert_contains(runtime_overrides, "config.targeting.add_priority_names", "runtime override facade must expose add priority accessors")
    assert_contains(runtime_overrides, "config.sleep.enabled", "runtime override facade must expose sleep enabled accessors")
    assert_contains(runtime_overrides, "config.sleep.order", "runtime override facade must expose sleep spell order accessors")
    assert_not_contains(runtime_overrides, "set_active_profile(", "runtime override facade must remain read-only")
    assert_not_contains(runtime_overrides, "sync_flat_settings_in_place(", "runtime override facade must not sync arbitrary command mutations")

    assert_contains(scheduler, "local uc_scheduler_config = require('uc_scheduler_config')", "scheduler must require the scheduler config facade")
    assert_contains(scheduler, "sleep_enabled = require('uc_runtime_overrides').sleep_enabled", "scheduler must inject the runtime sleep override into the combat provider")
    assert_contains(combat_provider, "sleep_enabled(ctx.settings)", "combat provider sleep toggle must read through the injected runtime override")
    assert_contains(scheduler, "return runtime_overrides.sleep_spell_names(settings)", "scheduler sleep spell list must read through runtime overrides")
    assert_contains(scheduler, "fight_leader_enabled = require('uc_runtime_overrides').fight_leader_enabled", "scheduler must inject fight leader enablement into the combat provider")
    assert_contains(scheduler, "fight_leader_id = require('uc_runtime_overrides').fight_leader_id", "scheduler must inject fight leader identity into the combat provider")
    assert_contains(combat_provider, "fight_leader_enabled(ctx.settings)", "combat provider must use the injected fight leader enablement reader")
    assert_contains(combat_provider, "fight_leader_id(ctx.settings)", "combat provider must use the injected fight leader identity reader")
    assert_contains(scheduler, "uc_scheduler_config.debug_enabled(", "scheduler debug gates must read through the scheduler config facade")
    assert_contains(scheduler, "uc_scheduler_config.debug_action_timeline(", "scheduler action timeline gate must read through the scheduler config facade")
    assert_contains(scheduler, "uc_scheduler_config.debug_log_def_sched(", "scheduler defensive log gates must read through the scheduler config facade")
    assert_contains(scheduler, "uc_scheduler_config.debug_log_tank_sched(", "scheduler tank log gates must read through the scheduler config facade")
    assert_contains(scheduler, "combat_autotarget = uc_scheduler_config.combat_autotarget", "scheduler must inject active-config autotarget into extracted providers")
    assert_contains(target_provider, "combat_autotarget(ctx.settings)", "target provider must consult active config for autotarget")
    assert_contains(combat_provider, "combat_autotarget(ctx.settings)", "combat provider must consult active config for autotarget")
    assert_contains(combat_provider, "combat_prime(ctx.settings)", "combat provider engage claim policy must consult active config for prime")
    assert_contains(combat_provider, "tank_enabled(ctx.settings)", "combat provider priority paths must consult active config for tank mode")
    assert_contains(scheduler, "local domain_ownership = require('uc_domain_ownership')", "scheduler must require the Phase 5 domain ownership policy")
    assert_contains(scheduler, "return domain_ownership.is_enabled('combat')", "scheduler must inject active-config combat domain enablement into extracted providers")
    assert_contains(scheduler, "config.defensive.enabled", "scheduler must consult active config for defensive enabled gating")
    assert_contains(defensive_provider, "config.defensive.provider", "defensive provider must consult active config for provider selection")
    assert_contains(scheduler, "config.defensive.cure.enabled", "scheduler must consult active config for defensive cure enablement")
    assert_contains(scheduler, "config.defensive.cure.min_tier", "scheduler must consult active config for defensive cure minimum tier")
    assert_contains(scheduler, "config.defensive.cure.max_tier", "scheduler must consult active config for defensive cure maximum tier")
    assert_contains(scheduler, "config.defensive.cure.min_missing_hp", "scheduler must consult active config for defensive cure missing-hp gate")
    assert_contains(scheduler, "config.defensive.cure.ignore_trusts", "scheduler must consult active config for defensive cure trust handling")
    assert_contains(scheduler, "config.defensive.na.enabled", "scheduler must consult active config for defensive NA enablement")
    assert_contains(scheduler, "config.defensive.na.limit_enabled", "scheduler must consult active config for status-removal limiting")
    assert_contains(scheduler, "config.defensive.na.priority", "scheduler must consult active config for status-removal priority")
    assert_contains(scheduler, "config.defensive.thresholds.critical_hpp", "scheduler must consult active config for defensive critical threshold")
    assert_contains(domain_ownership, "config.ownership.domain_combat_enabled", "domain ownership policy must read combat enablement")
    assert_contains(domain_ownership, "config.ownership.domain_defensive_enabled", "domain ownership policy must read defensive enablement")
    assert_contains(domain_ownership, "config.ownership.domain_movement_enabled", "domain ownership policy must read movement enablement")
    assert_contains(domain_ownership, "config.ownership.domain_maintenance_enabled", "domain ownership policy must read maintenance enablement")
    assert_not_contains(scheduler, "config.ownership.scheduler_dark_launch_", "scheduler runtime must not branch on compatibility-only ownership markers")

    assert_contains(combat_core, "local function scheduler_settings_view(settings)", "combat core must build a scheduler-only config view")
    assert_contains(combat_core, "scheduler_config.combat_autotarget(base)", "combat core scheduler target provider must consult active config for autotarget")
    assert_contains(combat_core, "scheduler_config.combat_prime(base)", "combat core scheduler target provider must consult active config for prime")
    assert_contains(combat_core, "scheduler_config.tank_enabled(base)", "combat core scheduler providers must consult active config for tank mode")
    assert_contains(combat_core, "scheduler_config.tank_enmity_actions(base)", "combat core tank provider must consult active config for tank enmity actions")

    assert_contains(add_control, "local uc_runtime_overrides = require('uc_runtime_overrides')", "add control must require runtime overrides")
    assert_contains(add_control, "uc_runtime_overrides.fight_leader_enabled(s)", "add control must consult runtime override fight leader state")
    assert_contains(add_priority, "local uc_runtime_overrides = require('uc_runtime_overrides')", "add priority helper must require runtime overrides")
    assert_contains(add_priority, "uc_runtime_overrides.add_priority_names(s)", "add priority helper must consult runtime override names")
    assert_contains(fight_leader, "local uc_runtime_overrides = require('uc_runtime_overrides')", "fight leader helper must require runtime overrides")
    assert_contains(fight_leader, "uc_runtime_overrides.fight_leader_enabled(settings)", "fight leader helper must consult runtime override enablement")
    assert_contains(fight_leader, "uc_runtime_overrides.fight_leader_id(settings)", "fight leader helper must consult runtime override leader id")
    assert_contains(addon, "local uc_runtime_overrides = require('uc_runtime_overrides')", "addon command helpers must require runtime overrides")
    assert_contains(addon, "uc_runtime_overrides.sleep_enabled(s)", "addon sleep command status must consult runtime override enablement")
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
    assert_contains(addon_command_block, "elseif a == 'fight_leader' or a == 'fightleader' then", "fight_leader command block must remain deferred rather than migrated through generic sync")
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
