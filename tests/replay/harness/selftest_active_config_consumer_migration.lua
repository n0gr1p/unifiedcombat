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

    assert_contains(scheduler, "local uc_active_config = require('uc_active_config')", "scheduler must require active config")
    assert_contains(scheduler, "uc_active_config.get_path('config.debug.enabled')", "scheduler debug gate must read active config")
    assert_contains(scheduler, "uc_active_config.get_path('config.debug.def_sched')", "scheduler defensive log gate must read active config")
    assert_contains(scheduler, "uc_active_config.get_path('config.defensive.enemy_buffs.remove')", "scheduler enemy-buff diagnostic gate must read active config")

    local addon_command_block = slice_between(
        addon,
        "windower.register_event('addon command', function(...)",
        "windower.add_to_chat(167, 'Unknown command.')"
    )
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

    io.stdout:write("selftest_active_config_consumer_migration: OK\n")
end

main()
