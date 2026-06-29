local RUNTIME_LUA_FILES = {
    "dd2_engine.lua",
    "dd2_module.lua",
    "melee_engine.lua",
    "remote_bridge.lua",
    "skills.lua",
    "uc_ability_pipeline.lua",
    "uc_add_control.lua",
    "uc_add_priority.lua",
    "uc_attack.lua",
    "uc_cor_maintenance.lua",
    "uc_enemy_effect_tracker.lua",
    "uc_fight_leader.lua",
    "uc_hb_buff_maint.lua",
    "uc_ignore.lua",
    "uc_partner_list.lua",
    "uc_party_follow.lua",
    "uc_path_hunter.lua",
    "uc_pathing.lua",
    "uc_config_normalizer.lua",
    "uc_config_runtime.lua",
    "uc_config_status_export.lua",
    "uc_profile_v2_export.lua",
    "uc_profile_contract.lua",
    "uc_scheduler_action_metadata.lua",
    "uc_scheduler_action_predicates.lua",
    "uc_scheduler_action_state.lua",
    "uc_scheduler_command_builder.lua",
    "uc_scheduler_context_utils.lua",
    "uc_scheduler_defensive_utils.lua",
    "uc_scheduler_dispatch_plan.lua",
    "uc_scheduler_dispatcher.lua",
    "uc_scheduler_dryrun_publish.lua",
    "uc_scheduler_enemy_effect_utils.lua",
    "uc_scheduler_geometry.lua",
    "uc_scheduler_locks.lua",
    "uc_scheduler_maintenance_utils.lua",
    "uc_scheduler_numeric_utils.lua",
    "uc_scheduler_pending_record.lua",
    "uc_scheduler_pending.lua",
    "uc_scheduler_proposal_keys.lua",
    "uc_scheduler_rank_output.lua",
    "uc_scheduler_reject_history.lua",
    "uc_scheduler_status_snapshot_parser.lua",
    "uc_scheduler_target_utils.lua",
    "uc_scheduler_text_utils.lua",
    "uc_settarget.lua",
    "uc_target_ignore.lua",
    "uc_targeting_common.lua",
    "uc_tb_effect_table.lua",
    "uc_ws_gate.lua",
    "uc_ws_memory.lua",
    "unified_combat_core.lua",
    "unified_engine.lua",
    "unified_scheduler.lua",
    "UnifiedCombat.lua",
}

local function assert_compiles(path)
    local chunk, err = loadfile(path)
    if not chunk then
        error("parse failed for " .. path .. ": " .. tostring(err))
    end
end

local function main()
    io.stdout:write("selftest_runtime_parse: compile-checking " .. tostring(#RUNTIME_LUA_FILES) .. " runtime files\n")

    for i, path in ipairs(RUNTIME_LUA_FILES) do
        io.stdout:write(string.format("[%02d/%02d] %s\n", i, #RUNTIME_LUA_FILES, path))
        assert_compiles(path)
    end

    io.stdout:write("selftest_runtime_parse: OK\n")
end

main()
