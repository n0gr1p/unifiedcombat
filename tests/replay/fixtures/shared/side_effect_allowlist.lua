return {
    schema_version = 1,
    patterns = {
        { key = "direct_send_command", literal = "windower.send_command(" },
        { key = "direct_run", literal = "windower.ffxi.run(" },
        { key = "direct_turn", literal = "windower.ffxi.turn(" },
        { key = "direct_target_select", literal = "uc_settarget.select_by_id(" },
        { key = "direct_ipc_send", literal = "windower.send_ipc_message(" },
        { key = "injected_ipc_send", literal = "require_function(deps, 'send_ipc_message')(" },
        { key = "packet_inject", literal = "packets.inject(", case_insensitive = true },
        { key = "command_attack", literal = "input /attack", case_insensitive = true },
        { key = "command_magic", literal = "input /ma", case_insensitive = true },
        { key = "command_ability", literal = "input /ja", case_insensitive = true },
        { key = "command_weaponskill", literal = "input /ws", case_insensitive = true },
        { key = "wrapper_engage", literal = "uc_attack.engage_target(" },
        { key = "wrapper_switch_target", literal = "uc_attack.switch_target(" },
        { key = "wrapper_disengage", literal = "uc_attack.disengage(" },
        { key = "wrapper_add_retarget", literal = "uc_add_control.execute_add_retarget(" },
    },
    files = {
        ["dd2_engine.lua"] = {
            direct_send_command = 32,
            direct_run = 10,
            direct_turn = 2,
            command_attack = 7,
            command_ability = 3,
            command_weaponskill = 1,
            wrapper_add_retarget = 1,
        },
        ["dd2_module.lua"] = {
            direct_send_command = 32,
            direct_run = 10,
            direct_turn = 2,
            command_attack = 7,
            command_ability = 3,
            command_weaponskill = 1,
            wrapper_add_retarget = 1,
        },
        ["melee_engine.lua"] = {
            direct_send_command = 24,
            direct_run = 3,
            direct_turn = 2,
            command_attack = 15,
            command_magic = 3,
            command_ability = 2,
            command_weaponskill = 2,
            wrapper_add_retarget = 1,
        },
        ["remote_bridge.lua"] = {
            direct_send_command = 1,
        },
        ["uc_add_control.lua"] = {
            direct_send_command = 3,
            command_attack = 1,
        },
        ["uc_attack.lua"] = {
            packet_inject = 3,
        },
        ["uc_camp_anchor.lua"] = {
            direct_ipc_send = 8,
        },
        ["uc_combat_extensions.lua"] = {
            command_magic = 1,
        },
        ["uc_nyzul_runtime.lua"] = {
            direct_ipc_send = 2,
        },
        ["uc_party_follow.lua"] = {
            direct_ipc_send = 3,
            packet_inject = 1,
        },
        ["uc_provider_combat.lua"] = {
            command_magic = 1,
            command_ability = 2,
            command_weaponskill = 1,
        },
        ["uc_provider_kei.lua"] = {
            command_magic = 1,
        },
        ["uc_provider_saved_by_bell.lua"] = {
            command_magic = 1,
        },
        ["uc_provider_tank_enmity.lua"] = {
            command_magic = 1,
            command_ability = 1,
        },
        ["uc_pet_commands.lua"] = {
            command_ability = 1,
        },
        ["uc_scheduler_command_builder.lua"] = {
            command_magic = 1,
            command_ability = 1,
        },
        ["uc_scheduler_party_state.lua"] = {
            injected_ipc_send = 1,
        },
        ["uc_settarget.lua"] = {
            packet_inject = 1,
        },
        ["unified_combat_core.lua"] = {
            direct_ipc_send = 2,
            command_magic = 1,
            command_ability = 1,
            command_weaponskill = 1,
        },
        ["unified_scheduler.lua"] = {
            command_magic = 2,
            command_ability = 3,
        },
        ["lor/lor_actor.lua"] = {
            direct_send_command = 1,
            direct_run = 2,
        },
        ["lor/lor_chat.lua"] = {
            direct_send_command = 1,
        },
        ["TargetBar/TargetBar.lua"] = {
            packet_inject = 1,
        },
    },
}
