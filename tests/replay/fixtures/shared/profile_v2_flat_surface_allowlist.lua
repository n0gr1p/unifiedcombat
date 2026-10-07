return {
	["files"] = {
		["UnifiedCombat.lua"] = {
			["sync_flat_settings"] = 3,
			["uc_settings"] = 71,
		},
		["UnifiedCombatWinForms/MainForm.ActivityProfiles.cs"] = {
			["build_profile_from_ui"] = 1,
		},
		["UnifiedCombatWinForms/MainForm.ParityLogic.cs"] = {
			["build_profile_from_ui"] = 1,
			["flat_live_set"] = 81,
		},
		["UnifiedCombatWinForms/MainForm.ProfileStore.cs"] = {
			["build_profile_from_ui"] = 2,
			["flat_profile_parameter"] = 1,
		},
		["UnifiedCombatWinForms/StructuredProfileV2Writer.cs"] = {
			["flat_profile_parameter"] = 51,
		},
		["build_dd2_module.py"] = {
			["uc_settings"] = 3,
		},
		["dd2_module.lua"] = {
			["uc_settings"] = 9,
		},
		["melee_engine.lua"] = {
			["uc_settings"] = 11,
		},
		["remote_bridge.lua"] = {
			["project_flat_settings"] = 1,
		},
		["uc_active_config.lua"] = {
			["project_flat_settings"] = 1,
			["sync_flat_settings"] = 1,
			["uc_settings"] = 4,
		},
		["uc_combat_commitment.lua"] = {
			["ctx_settings"] = 1,
		},
		["uc_combat_extension_config.lua"] = {
			["uc_settings"] = 1,
		},
		["uc_combat_extensions_base.lua"] = {
			["ctx_settings"] = 1,
		},
		["uc_config_normalizer_base.lua"] = {
			["uc_settings"] = 1,
		},
		["uc_config_runtime.lua"] = {
			["uc_settings"] = 2,
		},
		["uc_party_follow.lua"] = {
			["uc_settings"] = 5,
		},
		["uc_pathing.lua"] = {
			["uc_settings"] = 2,
		},
		["uc_profile_v2.lua"] = {
			["project_flat_settings"] = 1,
		},
		["uc_provider_combat.lua"] = {
			["ctx_settings"] = 11,
		},
		["uc_provider_run_tank.lua"] = {
			["ctx_settings"] = 1,
		},
		["uc_provider_tank_enmity.lua"] = {
			["ctx_settings"] = 2,
		},
		["uc_provider_target_control.lua"] = {
			["ctx_settings"] = 3,
		},
		["uc_runtime_overrides.lua"] = {
			["uc_settings"] = 1,
		},
		["uc_scheduler_config.lua"] = {
			["active_value_or_flat"] = 6,
			["uc_settings"] = 1,
		},
		["uc_scheduler_context_utils.lua"] = {
			["uc_settings"] = 1,
		},
		["uc_scheduler_dispatch_plan.lua"] = {
			["ctx_settings"] = 2,
		},
		["uc_scheduler_ranker.lua"] = {
			["ctx_settings"] = 2,
		},
		["unified_combat_core.lua"] = {
			["uc_settings"] = 1,
		},
		["unified_engine.lua"] = {
			["uc_settings"] = 1,
		},
		["unified_scheduler.lua"] = {
			["ctx_settings"] = 2,
		},
	},
	["patterns"] = {
		{
			["description"] = "legacy flat settings/global surface",
			["key"] = "uc_settings",
			["literal"] = "UC_SETTINGS",
		},
		{
			["description"] = "scheduler/provider flat context surface",
			["key"] = "ctx_settings",
			["literal"] = "ctx.settings",
		},
		{
			["description"] = "canonical-first reader with flat fallback",
			["key"] = "active_value_or_flat",
			["literal"] = "active_value_or_flat(",
		},
		{
			["description"] = "WinForms flat live set message",
			["key"] = "flat_live_set",
			["literal"] = "[\"op\"] = \"set\"",
		},
		{
			["description"] = "WinForms flat editor-to-v2 writer input",
			["key"] = "flat_profile_parameter",
			["literal"] = "JsonObject flatProfile",
		},
		{
			["description"] = "WinForms flat editor profile builder",
			["key"] = "build_profile_from_ui",
			["literal"] = "BuildProfileFromUi(",
		},
		{
			["description"] = "addon bridge flat settings mutation path",
			["key"] = "bridge_apply_set",
			["literal"] = "apply_set(",
		},
		{
			["description"] = "canonical-to-flat compatibility projection",
			["key"] = "project_flat_settings",
			["literal"] = "project_flat_settings(",
		},
		{
			["description"] = "in-place flat compatibility publication",
			["key"] = "sync_flat_settings",
			["literal"] = "sync_flat_settings_in_place(",
		},
	},
	["schema_version"] = 1,
}
