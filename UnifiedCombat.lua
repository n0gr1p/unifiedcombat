local function uc_prefer_addon_local_libs()
	local ap = windower and windower.addon_path or nil
	if type(ap) ~= 'string' or ap == '' then
		return
	end
	ap = ap:gsub('\\', '/')
	if ap:sub(-1) ~= '/' then
		ap = ap .. '/'
	end
	local p1 = ap .. '?.lua'
	local p2 = ap .. '?/?.lua'
	if not package.path:find(p1, 1, true) then
		package.path = p1 .. ';' .. p2 .. ';' .. package.path
	end
end

uc_prefer_addon_local_libs()

-- Windower keeps Lua's package.loaded table alive across addon reloads. Force all
-- UnifiedCombat-owned modules to be required from the current files on disk.
package.loaded.uc_runtime_bootstrap = nil
local uc_runtime_bootstrap = require('uc_runtime_bootstrap')
local UC_RUNTIME_BOOT = uc_runtime_bootstrap.begin({ addon_path = windower.addon_path })

require('lor/lor_utils')
require('tables')
local uc_runtime_overrides = require('uc_runtime_overrides')
local uc_recovery_hold = require('uc_recovery_hold')
local uc_raise_accept = require('uc_raise_accept')
uc_raise_accept.register()
local uc_lifecycle_movement = require('uc_movement_dispatcher').build({
	dispatcher = require('uc_scheduler_dispatcher'),
	run = windower.ffxi.run,
	source_prefix = 'lifecycle',
})

local function uc_reset_reaction_runtime(reason)
	local lock = rawget(_G, 'UC_REACTION_LOCK')
	if require('uc_reaction_runtime').owns_movement(lock) then
		uc_lifecycle_movement.stop({
			reason = 'REACTION_MOVEMENT_LIFECYCLE_RESET',
			lifecycle_reason = reason,
		})
		_G.UC_MOVEMENT_OWNER = 'none'
		_G.UC_MOVEMENT_LOCK_UNTIL = 0
	end
	require('uc_reaction_runtime').reset(reason)
	_G.UC_REACTION_LOCK = nil
end

local function uc_now_s()
	return require('uc_time').now()
end

local function uc_update_recovery_hold()
	local player = windower.ffxi.get_player()
	return uc_recovery_hold.update(rawget(_G, 'UC_SETTINGS'), player, {
		on_enter = function()
			uc_lifecycle_movement.release({ reason = 'RECOVERY_HOLD_ENTER' })
			_G.UC_MOVEMENT_OWNER = 'none'
			_G.UC_MOVEMENT_LOCK_UNTIL = 0
			_G.UC_MOVEMENT_MODE = 'RECOVERY_HOLD'
			_G.UC_MOVEMENT_BLOCK_REASON = uc_recovery_hold.BLOCK_REASON
			_G.UC_PARTY_FOLLOW_RUN_ACTIVE = false
			_G.UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL = 0
			_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = false
			_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = 0
			_G.UC_PREENGAGE_APPROACH_ACTIVE = false
			_G.UC_PULL_APPROACH_UNTIL = 0
			local scheduler_enter = rawget(_G, 'UC_SCHED_OnRecoveryHoldEntered')
			if type(scheduler_enter) == 'function' then
				pcall(scheduler_enter)
			end
			windower.add_to_chat(207, 'UnifiedCombat: recovery hold active (Weakness); automation paused.')
		end,
		on_clear = function()
			_G.UC_MOVEMENT_MODE = 'OUT_OF_COMBAT'
			_G.UC_MOVEMENT_BLOCK_REASON = ''
			windower.add_to_chat(207, 'UnifiedCombat: recovery hold cleared; automation resumed.')
		end,
	})
end

require('luau')

_addon.name = 'unifiedcombat'
_addon.author = 'me'
_addon.version = '1.0'
_addon.commands = { 'uc', 'unifiedcombat' }

UC_ENGINE = 'UC'
_G.UC_REMOTE_HOST = _G.UC_REMOTE_HOST or '127.0.0.1'
_G.UC_REMOTE_PORT = _G.UC_REMOTE_PORT or 27182

Start_Engine = false

-- After zoning, suspend unified combat ticks (scheduler + offense) so mob data can settle and we
-- do not immediately autotarget with stale/cleared engine state (zone resets engagement; no /attack off).
local UC_ZONE_SUSPEND_SEC = 15

UC_JOB_DEFAULTS = {
	WAR = {
		ws1 = 'Savage Blade',
		ability1 = '',
		ability2 = '',
		ability3 = '',
		ability4 = '',
		ability5 = '',
		ability6 = '',
	},
	MNK = {
		ws1 = 'Shijin Spiral',
		ability1 = '',
		ability2 = '',
		ability3 = '',
		ability4 = '',
		ability5 = '',
		ability6 = '',
	},
	SAM = {
		ws1 = 'Tachi: Kasha',
		ability1 = 'Hasso',
		ability2 = 'Third Eye',
		ability3 = 'Berserk',
		ability4 = 'Aggressor',
		ability5 = 'Meditate',
		ability6 = '',
	},
	DRG = {
		ws1 = 'Stardiver',
		ability1 = 'Hasso',
		ability2 = '',
		ability3 = 'Berserk',
		ability4 = 'Aggressor',
		ability5 = 'Meditate',
		ability6 = '',
	},
	DRK = {
		ws1 = 'Entropy',
		ability1 = 'Hasso',
		ability2 = 'Third Eye',
		ability3 = 'Last Resort',
		ability4 = 'Diabolic Eye',
		ability5 = 'Meditate',
		ability6 = 'Consume Mana',
	},
}

local res = require('resources')
uc_recovery_hold.validate_resources(res.buffs)
local files = require('files')
require('actions')

local uc_partner_list = require('uc_partner_list')
local uc_add_priority = require('uc_add_priority')
local uc_camp_anchor = require('uc_camp_anchor')
local uc_camp_pull_registry = require('uc_camp_pull_registry')
local uc_config_status_export = require('uc_config_status_export')
local uc_active_config = require('uc_active_config')
local uc_encounter_runtime = require('uc_encounter_runtime')
local uc_profile_v2 = require('uc_profile_v2')
local uc_smn_config = require('uc_smn_config')
local UC_PROFILE_CONTRACT = nil
local UC_PROFILE_CONTRACT_LOAD_ERROR = nil
local UC_CONFIG_NORMALIZER = nil
local UC_CONFIG_NORMALIZER_LOAD_ERROR = nil
do
	local ok, contract = pcall(require, 'uc_profile_contract')
	if ok and type(contract) == 'table' then
		UC_PROFILE_CONTRACT = contract
	else
		UC_PROFILE_CONTRACT_LOAD_ERROR = tostring(contract)
	end
end
do
	local ok, normalizer = pcall(require, 'uc_config_normalizer')
	if ok and type(normalizer) == 'table' then
		UC_CONFIG_NORMALIZER = normalizer
	else
		UC_CONFIG_NORMALIZER_LOAD_ERROR = tostring(normalizer)
	end
end
_G.UC_PROFILE_CONTRACT_STATUS = {
	schema_version = 1,
	contract_loaded = UC_PROFILE_CONTRACT ~= nil,
	contract_load_error = UC_PROFILE_CONTRACT_LOAD_ERROR,
	validation_state = 'not_checked',
	load_state = 'idle',
	warnings = {},
	errors = {},
}
_G.UC_CONFIG_CONTRACT_STATUS = {
	schema_version = 1,
	ok = false,
	available = UC_CONFIG_NORMALIZER ~= nil,
	normalizer_version = nil,
	source = 'UC_SETTINGS',
	domains = {},
	warnings = UC_CONFIG_NORMALIZER_LOAD_ERROR and { 'config normalizer unavailable' } or {},
	errors = UC_CONFIG_NORMALIZER_LOAD_ERROR and { UC_CONFIG_NORMALIZER_LOAD_ERROR } or {},
	updated_at = uc_now_s(),
}

local function uc_new_settings_defaults()
	return {
		profiles = { UC = {} },
		engine_mode = 'UC',
		ability_active = false,
		abilities = {},
		weaponskill = '',
		ws1 = '',
		weaponskill_active = false,
		ws_mode = 'smart',
		weaponskill_min_tp = 1000,
		weaponskill_allow_aoe = true,
		fast_skillchain = false,
		recurring_spells_enabled = false,
		recurring_spells = '',
		weaponskill_no_skillchain_targets = {},
		aftermath_enabled = false,
		aftermath_ws = '',
		autotarget = false,
		spam = false,
		closer = false,
		manual = false,
		prime = false,
		static = false,
		spacing = false,
		camp_pulling = {
			enabled = false,
			mode = 'camp',
			action = {
				type = 'spell',
				name = nil,
			},
			targets = {},
			match_mode = 'exact',
			max_active_mobs = 1,
			replenish_below_hpp = 20,
			leash_yalms = 35.0,
			max_z_delta = 2.0,
			cast_range_ratio = 0.90,
			settle_seconds = 0.40,
			reaction_timeout_seconds = 4.0,
			retry_limit = 2,
			retry_window_seconds = 2.5,
			target_cooldown_seconds = 20.0,
			camp_arrival_yalms = 0.75,
		},
		spacing_band_min = -0.9,
		spacing_band_max = 0.4,
		spacing_model_size_floor = 0.9,
		spacing_use_prediction = true,
		spacing_lookahead_s = 0.25,
		spacing_repel_hold_ticks = 5,
		spacing_overlap_deadband = 0.10,
		spacing_repel_weight = 0.35,
		spacing_band_deadband = 0.20,
		encounter_enabled = false,
		encounter_id = 'sortie_ghatjot',
		encounter_water_damage = 'enforce',
		encounter_water_skillchain = 'enforce',
		encounter_repeat_action_wall = 'off',
		encounter_repeat_action_guard_s = 10.0,
		kei_elemental_dealer_name = '',
		kei_water_probe_spell = 'Water',
		kei_water_damage_spell = 'Water III',
		kei_ice_probe_spell = 'Blizzard',
		kei_ice_damage_spell = 'Blizzard III',
		kei_sustain_interval_s = 2.5,
		kei_probe_timeout_s = 3.0,
		kei_fullers_target_distance = 12.0,
		kei_fullers_prearm_hpp_margin = 1.0,
		named_formations_enabled = false,
		named_formation_entries = {},
		face = false,
		partner = false,
		partner2 = false,
		puller = false,
		puller_name = '',
		puller_leash_source = 'player',
		puller_engage_range = 6.0,
		puller_distance_only = false,
		partner_id = 0,
		partner_id2 = 0,
		partner_ids = {},
		puller_id = 0,
		fight_leader = false,
		fight_leader_id = 0,
		party_follow = false,
		party_follow_id = 0,
		party_follow_leader_name = '',
		party_follow_min = 0.5,
		party_follow_max = 50,
		fight_follow_min = 3.0,
		fight_follow_hold_s = 8.0,
		nyzul_coordinator_name = '',
		nyzul_anchor_name = '',
		nyzul_parking_order = {},
		add_control = false,
		add_priority_names = {},
		sub = false,
		sub2 = false,
		move = false,
		debug = false,
		log_combat_sched = false,
		log_ja_sched = false,
		log_ja_debug = false,
		log_def_sched = false,
		log_tank_sched = false,
		solo = false,
		aeonic = false,
		color = false,
		tank = false,
		tank_enmity_actions = {},
		sleep = false,
		sleepspells = { 'Horde Lullaby II' },
		sleep_max_target_range = 6.0,
		command = false,
		hunter = false,
		sleepspell = 'Horde Lullaby II',
		defensive_enabled = false,
		defensive_provider = 'internal',
		defensive_resurrection_enabled = false,
		defensive_resurrection_priority = 'Arise|Raise III|Raise II|Raise',
		defensive_cure_enabled = false,
		defensive_doom_water = false,
		def_charm_sleeper_enabled = false,
		def_sleep_waker_enabled = false,
		def_remove_enemy_buffs = false,
		def_maintain_enemy_debuffs = false,
		defensive_enemy_debuffs = '',
		def_heal_min_tier_cure = 3,
		def_heal_max_tier_cure = 4,
		def_heal_min_missing_hp = 250,
		def_heal_ignore_trusts = true,
		defensive_curaga_enabled = false,
		defensive_curaga_min_targets = 3,
		defensive_waltz_enabled = false,
		defensive_waltz_tp_reserve = 0,
		defensive_divine_waltz_min_targets = 3,
		defensive_na_enabled = false,
		defensive_na_limit_enabled = false,
		defensive_na_priority = '',
		defensive_buff_enabled = false,
		defensive_critical_hpp = 35,
		defensive_medium_hpp = 55,
		defensive_overwrite_enabled = false,
		defensive_overwrite_interval = 150,
		defensive_buff_self_only = true,
		defensive_buffs = '',
		defensive_targeted_buffs = '',
		engine_enabled = false,
		auto_accept_raise = false,
		pause_automation_while_weakened = false,
		domain_combat_enabled = true,
		domain_defensive_enabled = true,
		domain_movement_enabled = true,
		domain_maintenance_enabled = true,
		domain_follow_enabled = true,
		cor_roll_1 = '',
		cor_roll_2 = '',
		cor_crooked_roll_slot = 0,
		cor_elevens = false,
		cor_luzaf_range_override = false,
		cor_roll_range_selected = '',
		cor_roll_range_require_ids = {},
		maintenance_geo = {
			enabled = false,
			geo_spell = nil,
			geo_target = {
				kind = 'current_enemy',
				name = nil,
			},
			indi_spell = nil,
			ordering = 'geo_first',
			require_camp = true,
			camp_tolerance_yalms = 1.0,
			enemy_geo_requires_camp_radius = false,
			unknown_existing_policy = 'wait_for_clear',
			entrust = {
				enabled = false,
				spell = nil,
				target_name = nil,
			},
			luopan = {
				placement = 'target',
				use_blaze_of_glory = false,
				use_ecliptic_attrition = false,
				use_life_cycle = false,
				life_cycle_hpp = 50,
				replace_out_of_position = false,
				max_camp_distance_yalms = 6.0,
			},
		},
		summoner_enabled = false,
		summoner_avatar = '',
		summoner_avatar_favor = false,
		summoner_ward_enabled = false,
		summoner_ward_action = '',
		summoner_ward_actions = '',
		summoner_engage_on_combat_start = false,
		summoner_rage_enabled = false,
		summoner_rage_action = '',
		summoner_rage_usage = 'on_cooldown',
		summoner_rage_target_hpp_above_enabled = false,
		summoner_rage_target_hpp_above = 50,
		summoner_rage_pet_tp_above_enabled = false,
		summoner_rage_pet_tp_above = 2000,
		sch_enabled = false,
		sch_arts_minimum_commit_s = 12,
		sch_arts_emergency_off_art_casts = true,
		sch_regen_enabled = false,
		sch_accession_perpetuance_spells = 'Regen V',
		sch_regen_minimum_coverage = 4,
		sch_regen_refresh_before_s = 25,
		sch_storms_enabled = false,
		sch_storm_assignments = '',
		sch_storms_refresh_before_s = 30,
		sch_sublimation_enabled = false,
		sch_sublimation_release_when_mpp_at_most = 45,
		sch_sublimation_release_when_complete = false,
		sch_sublimation_minimum_hpp_to_activate = 75,
		sch_accession_cure_enabled = false,
		sch_accession_status_removal_enabled = false,
		sch_rapture_enabled = false,
		sch_penury_enabled = false,
		path_recording = false,
		path_follow_enabled = false,
		path_file_name = '',
		path_route_type = 'unknown',
		path_distance_to_start = 0,
		path_points = {},
		path_party_gate_yalms = 3.0,
		path_resume_index_window = 12,
		path_hunter_targets = {},
		path_hunter_max_z_delta = 2.0,
		path_hunter_max_target_range = 20.0,
		path_hunter_claim_timeout_s = 4.0,
		path_hunter_ignore_cooldown_s = 20.0,
		path_pull_action_type = 'ja',
		path_pull_action_name = '',
		path_pull_attack_fallback_enabled = false,
		wait_ignore_names = {},
		ignore = {},
		target_ignore_names = {},
		show_ingame_ui = false,
	}
end

_G.UC_SETTINGS = uc_new_settings_defaults()
uc_active_config.initialize_active_profile(_G.UC_SETTINGS, {
	source = 'UC_SETTINGS',
})

local function uc_truthy(v)
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function uc_domain_enabled(s, key)
	local st = s or _G.UC_SETTINGS or {}
	if key == 'follow' then
		local active = require('uc_active_config').get_path('config.ownership.domain_follow_enabled')
		if type(active) == 'boolean' then
			return active
		end
		return uc_truthy(st.domain_follow_enabled)
	end
	if rawget(_G, 'Start_Engine') ~= true then
		return false
	end
	if key == 'combat' then
		return uc_truthy(st.domain_combat_enabled)
	elseif key == 'defensive' then
		return uc_truthy(st.domain_defensive_enabled)
	elseif key == 'movement' then
		return uc_truthy(st.domain_movement_enabled)
	elseif key == 'maintenance' then
		return uc_truthy(st.domain_maintenance_enabled)
	end
	return false
end

local function uc_is_combat_participant(_)
	if rawget(_G, 'Start_Engine') ~= true then
		return false
	end
	local active_config = require('uc_active_config').get_config()
	return require('uc_movement_config').combat_participant(active_config)
end

local function uc_is_defensive_participant(s)
	local st = s or _G.UC_SETTINGS or {}
	return uc_domain_enabled(st, 'defensive') and uc_truthy(st.defensive_enabled)
end

local function uc_is_movement_participant(_)
	if rawget(_G, 'Start_Engine') ~= true then
		return false
	end
	local active_config = require('uc_active_config').get_config()
	return require('uc_movement_config').movement_participant(active_config)
end

local function uc_is_follow_participant(s)
	local st = s or _G.UC_SETTINGS or {}
	local active_config = require('uc_active_config').get_config()
	if type(active_config) == 'table' then
		local follow_config = require('uc_follow_config')
		local party = follow_config.party(active_config)
		return uc_domain_enabled(st, 'follow')
			and follow_config.enabled(active_config)
			and type(party) == 'table'
			and party.enabled == true
	end
	return uc_domain_enabled(st, 'follow') and uc_truthy(st.party_follow)
end

_G.UC_DomainEnabled = uc_domain_enabled
_G.UC_IsCombatParticipant = uc_is_combat_participant
_G.UC_IsDefensiveParticipant = uc_is_defensive_participant
_G.UC_IsMovementParticipant = uc_is_movement_participant
_G.UC_IsFollowParticipant = uc_is_follow_participant

require('remote_bridge')
local UC_COMBAT_CORE = require('unified_combat_core')
local UC_UNIFIED_ENGINE = require('unified_engine')
local UC_UNIFIED_SCHEDULER = require('unified_scheduler')
local uc_party_follow = require('uc_party_follow')
local uc_nyzul_runtime = require('uc_nyzul_runtime')
local uc_pathing = require('uc_pathing')

local UC_RUNTIME_OK, UC_RUNTIME_STATUS = uc_runtime_bootstrap.finalize(UC_RUNTIME_BOOT, {
	scheduler = UC_UNIFIED_SCHEDULER,
	engine = UC_UNIFIED_ENGINE,
})
if not UC_RUNTIME_OK then
	error('UnifiedCombat runtime integrity check failed: ' .. tostring(UC_RUNTIME_STATUS.integrity_error or 'unknown mismatch'))
end
windower.add_to_chat(207, uc_runtime_bootstrap.summary_line(UC_RUNTIME_STATUS))
if type(_G.UC_ACTION_TIMELINE_LOG) == 'function' then
	_G.UC_ACTION_TIMELINE_LOG(
		'RUNTIME_FINGERPRINT',
		uc_runtime_bootstrap.timeline_fields(UC_RUNTIME_STATUS),
		'runtime_fingerprint',
		0
	)
end

local function uc_update_engine()
	UC_ENGINE = 'UC'
end

local function uc_start_active_engine_if_running()
	if not Start_Engine then
		return
	end
	require('uc_brd_maintenance').resume('engine_start')
	if UC_UNIFIED_ENGINE and type(UC_UNIFIED_ENGINE.start) == 'function' then
		UC_UNIFIED_ENGINE.start()
	end
end

_G.UC_StartUnifiedEngine = function()
	require('uc_brd_maintenance').resume('engine_start')
	if UC_UNIFIED_ENGINE and type(UC_UNIFIED_ENGINE.start) == 'function' then
		UC_UNIFIED_ENGINE.start()
	end
end

_G.UC_StopUnifiedEngine = function(reason)
	local stop_reason = tostring(reason or 'engine_stop')
	if stop_reason == 'engine_stop' then
		require('uc_brd_maintenance').suspend(stop_reason)
	else
		require('uc_brd_maintenance').reset(stop_reason)
	end
	if UC_COMBAT_CORE and type(UC_COMBAT_CORE.reset_skillchain_state) == 'function' then
		UC_COMBAT_CORE.reset_skillchain_state(stop_reason)
	end
	if UC_UNIFIED_ENGINE and type(UC_UNIFIED_ENGINE.stop) == 'function' then
		UC_UNIFIED_ENGINE.stop()
	end
end

_G.UC_ResetMovementLocksForFollow = function()
	_G.UC_MOVE_FREEZE_PREP_KEY = ''
	_G.UC_MOVE_FREEZE_PREP_UNTIL = 0
	_G.UC_MOVEMENT_MODE = 'OUT_OF_COMBAT'
	_G.UC_MOVEMENT_BLOCK_REASON = ''
	_G.UC_MOVEMENT_OWNER = 'none'
	_G.UC_MOVEMENT_LOCK_UNTIL = 0
	_G.UC_COMBAT_INTENT_UNTIL = 0
	_G.UC_PULL_SPELL_WAITING = false
	if type(_G.UC_ResetSchedulerRuntimeLocks) == 'function' then
		_G.UC_ResetSchedulerRuntimeLocks()
	end
	uc_lifecycle_movement.stop({ reason = 'reset_movement_locks_for_follow' })
end

local function uc_try_load_local_ownership_flags()
	local ok, mod_or_err = pcall(require, 'local_ownership_flags')
	if ok then
		return mod_or_err
	end
	local err = tostring(mod_or_err or '')
	if err:find("module 'local_ownership_flags' not found", 1, true) then
		return nil
	end
	if windower and windower.add_to_chat then
		windower.add_to_chat(167, 'UnifiedCombat: failed loading local_ownership_flags.lua: ' .. err)
	end
	return nil
end

uc_try_load_local_ownership_flags()

local function uc_apply_job_defaults(job)
	if not job or not _G.UC_SETTINGS then
		return
	end
	local j = job
	if type(j) ~= 'string' then
		j = res.jobs:with('id', j).english_short
	end
	j = j:upper()
	local d = UC_JOB_DEFAULTS[j]
	if not d then
		return
	end
	for k, v in pairs(d) do
		local cur = _G.UC_SETTINGS[k]
		if cur == nil or cur == '' then
			_G.UC_SETTINGS[k] = v
		end
	end
end

local PROFILE_KEYS = {
	'ability1', 'ability2', 'ability3', 'ability4', 'ability5', 'ability6',
	'ability_active', 'abilities', 'wsabilities',
	'ws1', 'weaponskill', 'weaponskill_active', 'ws_mode', 'weaponskill_min_tp', 'weaponskill_allow_aoe', 'fast_skillchain', 'weaponskill_no_skillchain_targets', 'recurring_spells_enabled', 'recurring_spells',
	'aftermath_enabled', 'aftermath_ws',
	'engine_mode',
	'show_ingame_ui',
	'defensive_enabled', 'defensive_provider', 'defensive_resurrection_enabled', 'defensive_resurrection_priority', 'defensive_cure_enabled', 'defensive_curaga_enabled', 'defensive_waltz_enabled', 'defensive_doom_water', 'def_charm_sleeper_enabled', 'def_sleep_waker_enabled', 'def_remove_enemy_buffs', 'def_maintain_enemy_debuffs', 'defensive_enemy_debuffs', 'defensive_na_enabled', 'defensive_na_limit_enabled', 'defensive_na_priority', 'defensive_buff_enabled',
	'defensive_critical_hpp', 'defensive_medium_hpp',
	'defensive_curaga_min_targets', 'defensive_waltz_tp_reserve', 'defensive_divine_waltz_min_targets',
	'defensive_overwrite_enabled', 'defensive_overwrite_interval', 'defensive_buff_self_only', 'defensive_buffs',
	'defensive_targeted_buffs',
	'engine_enabled', 'auto_accept_raise', 'pause_automation_while_weakened', 'domain_combat_enabled', 'domain_defensive_enabled', 'domain_movement_enabled', 'domain_maintenance_enabled', 'domain_follow_enabled',
	'cor_roll_1', 'cor_roll_2', 'cor_crooked_roll_slot', 'cor_elevens', 'cor_luzaf_range_override', 'cor_roll_range_selected', 'cor_roll_range_require_ids',
	'summoner_enabled', 'summoner_avatar', 'summoner_avatar_favor',
	'summoner_ward_enabled', 'summoner_ward_action', 'summoner_ward_actions',
	'summoner_engage_on_combat_start', 'summoner_rage_enabled',
	'summoner_rage_action', 'summoner_rage_usage',
	'summoner_rage_target_hpp_above_enabled', 'summoner_rage_target_hpp_above',
	'summoner_rage_pet_tp_above_enabled', 'summoner_rage_pet_tp_above',
	'sch_enabled', 'sch_arts_minimum_commit_s', 'sch_arts_emergency_off_art_casts',
	'sch_regen_enabled', 'sch_accession_perpetuance_spells',
	'sch_regen_minimum_coverage', 'sch_regen_refresh_before_s',
	'sch_storms_enabled', 'sch_storm_assignments', 'sch_storms_refresh_before_s',
	'sch_sublimation_enabled',
	'sch_sublimation_release_when_mpp_at_most', 'sch_sublimation_release_when_complete',
	'sch_sublimation_minimum_hpp_to_activate',
	'sch_accession_cure_enabled', 'sch_accession_status_removal_enabled',
	'sch_rapture_enabled', 'sch_penury_enabled',
	'path_recording', 'path_follow_enabled', 'path_file_name', 'path_route_type', 'path_distance_to_start', 'path_points', 'path_party_gate_yalms', 'path_resume_index_window', 'path_hunter_targets', 'path_hunter_max_z_delta', 'path_hunter_max_target_range', 'path_hunter_claim_timeout_s', 'path_hunter_ignore_cooldown_s', 'path_pull_action_type', 'path_pull_action_name', 'path_pull_attack_fallback_enabled',
	'autotarget', 'spam', 'closer', 'manual', 'prime', 'static', 'spacing', 'face',
	'spacing_band_min', 'spacing_band_max', 'spacing_use_prediction', 'spacing_lookahead_s',
	'spacing_model_size_floor',
	'spacing_repel_hold_ticks', 'spacing_overlap_deadband', 'spacing_repel_weight', 'spacing_band_deadband',
	'encounter_enabled', 'encounter_id', 'encounter_water_damage', 'encounter_water_skillchain', 'encounter_repeat_action_wall', 'encounter_repeat_action_guard_s',
	'kei_elemental_dealer_name', 'kei_water_probe_spell', 'kei_water_damage_spell', 'kei_ice_probe_spell', 'kei_ice_damage_spell',
	'kei_sustain_interval_s', 'kei_probe_timeout_s', 'kei_fullers_target_distance', 'kei_fullers_run_away_distance', 'kei_fullers_prearm_hpp_margin',
	'named_formations_enabled', 'named_formation_entries',
	'partner', 'partner2', 'puller', 'puller_name', 'puller_leash_source', 'puller_engage_range', 'puller_distance_only', 'partner_id', 'partner_id2', 'partner_ids', 'puller_id',
	'fight_leader', 'fight_leader_id', 'party_follow', 'party_follow_id', 'party_follow_leader_name', 'party_follow_min', 'party_follow_max', 'fight_follow_min', 'fight_follow_hold_s',
	'nyzul_coordinator_name', 'nyzul_anchor_name', 'nyzul_parking_order',
	'add_control', 'add_priority_names',
	'sub', 'sub2', 'move', 'debug', 'log_action_timeline', 'log_combat_sched', 'log_ja_sched', 'log_ja_debug', 'log_def_sched', 'log_tank_sched', 'solo', 'aeonic', 'color', 'tank', 'sleep', 'command', 'hunter',
	'tank_enmity_actions',
	'target1', 'target2', 'target3', 'targets',
	'targetability', 'targetability_active',
	'spell', 'spell_active', 'sleepspell', 'sleepspells', 'sleep_max_target_range',
	'dd2_spell_slots', 'wait_ignore_names', 'ignore', 'target_ignore_names',
}

local function uc_clone_value(v)
	if type(v) ~= 'table' then
		return v
	end
	local out = {}
	for k, vv in pairs(v) do
		out[k] = uc_clone_value(vv)
	end
	return out
end

local function uc_profile_contract_available()
	return type(UC_PROFILE_CONTRACT) == 'table'
end

local function uc_config_normalizer_available()
	return type(UC_CONFIG_NORMALIZER) == 'table'
		and type(UC_CONFIG_NORMALIZER.normalize) == 'function'
end

local function uc_config_normalizer_version()
	if type(UC_CONFIG_NORMALIZER) == 'table' and type(UC_CONFIG_NORMALIZER.version) == 'function' then
		local ok, version = pcall(UC_CONFIG_NORMALIZER.version)
		if ok then
			return version
		end
	end
	return nil
end

local function uc_config_domain_names(config)
	local out = {}
	if type(config) ~= 'table' then
		return out
	end
	for _, domain in ipairs({
		'profile',
		'ui',
		'command',
		'combat',
		'abilities',
		'defensive',
		'movement',
		'follow',
		'targeting',
		'tank',
		'sleep',
		'spells',
		'maintenance',
		'summoner',
		'debug',
		'ownership',
		'legacy',
	}) do
		if type(config[domain]) == 'table' then
			out[#out + 1] = domain
		end
	end
	return out
end

local function uc_profile_v2_contract_validator(payload)
	if not uc_profile_contract_available() or type(UC_PROFILE_CONTRACT.validate_structured_profile_config) ~= 'function' then
		return nil
	end
	return UC_PROFILE_CONTRACT.validate_structured_profile_config(payload)
end

local function uc_current_profile_v2_config(context, meta)
	context = type(context) == 'table' and context or {}
	if type(context.config) == 'table' then
		return context.config
	end
	local active_config = uc_active_config.get_config()
	if type(active_config) == 'table' then
		return active_config
	end
	local settings = context.settings or _G.UC_SETTINGS
	if type(settings) == 'table' then
		local ok, config = pcall(uc_profile_v2.build_durable_config, settings, meta)
		if ok and type(config) == 'table' then
			return config
		end
	end
	return nil
end

local function uc_update_profile_v2_contract_status(context)
	context = type(context) == 'table' and context or {}
	local meta = {
		character = context.character,
		main_job = context.main_job,
		sub_job = context.sub_job,
		source = context.source or 'UC_ACTIVE_PROFILE',
		addon_path = context.addon_path,
	}
	local current_config = uc_current_profile_v2_config(context, meta)
	if type(current_config) ~= 'table' or meta.character == nil or meta.character == '' or meta.main_job == nil or meta.main_job == '' or meta.sub_job == nil or meta.sub_job == '' then
		return {
			path = uc_profile_v2.default_export_path(meta),
			state = 'error',
			valid = false,
			diff_count = 0,
			reason = 'missing canonical config or profile identity',
			source = meta.source,
			character = meta.character,
			main_job = meta.main_job,
			sub_job = meta.sub_job,
		}
	end
	local status = uc_profile_v2.inspect_structured_profile_status_against_config(
		current_config,
		meta,
		uc_profile_v2_contract_validator
	)
	if type(status) ~= 'table' then
		return {
			path = uc_profile_v2.default_export_path(meta),
			state = 'error',
			valid = false,
			diff_count = 0,
			reason = 'profile v2 status helper returned invalid result',
			source = meta.source,
			character = meta.character,
			main_job = meta.main_job,
			sub_job = meta.sub_job,
		}
	end
	return status
end

local function uc_update_config_contract_status(context)
	context = type(context) == 'table' and context or {}
	local status = {
		schema_version = 1,
		ok = false,
		available = uc_config_normalizer_available(),
		normalizer_version = uc_config_normalizer_version(),
		source = context.source or 'UC_SETTINGS',
		character = context.character,
		main_job = context.main_job,
		sub_job = context.sub_job,
		profile_key = context.profile_key,
		profile_v2 = uc_update_profile_v2_contract_status(context),
		domains = {},
		warnings = uc_clone_value(context.warnings or {}),
		errors = {},
		updated_at = context.updated_at or uc_now_s(),
	}
	if not status.available then
		status.warnings[#status.warnings + 1] = 'config normalizer unavailable'
		status.errors[#status.errors + 1] = UC_CONFIG_NORMALIZER_LOAD_ERROR or 'config normalizer unavailable'
		_G.UC_CONFIG_CONTRACT_STATUS = status
		return status
	end

	local meta = {
		character = context.character,
		main_job = context.main_job,
		sub_job = context.sub_job,
		source = status.source,
	}
	local config = uc_current_profile_v2_config(context, meta)
	local ok = type(config) == 'table'
	if ok then
		local summoner = uc_smn_config.validate(config.summoner)
		status.ok = summoner.valid
		status.summoner = {
			enabled = summoner.enabled,
			valid = summoner.valid,
			avatar_valid = summoner.avatar_valid,
			ward_valid = summoner.ward_valid,
			rage_valid = summoner.rage_valid,
		}
		for _, issue in ipairs(summoner.errors) do
			status.errors[#status.errors + 1] = issue.message
		end
		for _, issue in ipairs(summoner.warnings) do
			status.warnings[#status.warnings + 1] = issue.message
		end
		status.domains = uc_config_domain_names(config)
		if type(config.profile) == 'table' then
			status.character = status.character or config.profile.character
			status.main_job = status.main_job or config.profile.main_job
			status.sub_job = status.sub_job or config.profile.sub_job
			status.source = config.profile.source or status.source
		end
	else
		status.errors[#status.errors + 1] = tostring(config)
	end
	_G.UC_CONFIG_CONTRACT_STATUS = status
	return status
end

local function uc_validate_profile_tree(profile_tree)
	if not uc_profile_contract_available() or type(UC_PROFILE_CONTRACT.validate_profile_tree) ~= 'function' then
		return nil
	end
	return UC_PROFILE_CONTRACT.validate_profile_tree(profile_tree)
end

local function uc_validate_structured_profile_export(profile)
	if not uc_profile_contract_available() or type(UC_PROFILE_CONTRACT.validate_structured_profile_config) ~= 'function' then
		return nil
	end
	return UC_PROFILE_CONTRACT.validate_structured_profile_config(profile)
end

local function uc_update_profile_contract_status(context)
	context = type(context) == 'table' and context or {}
	local status
	if uc_profile_contract_available() and type(UC_PROFILE_CONTRACT.build_status_contract_snapshot) == 'function' then
		status = UC_PROFILE_CONTRACT.build_status_contract_snapshot(context)
	else
		status = {
			schema_version = 1,
			character = context.character,
			main_job = context.main_job,
			sub_job = context.sub_job,
			profile_key = context.profile_key,
			engine_state = uc_clone_value(context.engine_state or {}),
			zone_suspended = context.zone_suspended == true,
			scheduler_summary = uc_clone_value(context.scheduler_summary or {}),
			current_action = uc_clone_value(context.current_action or {}),
			warnings = uc_clone_value(context.warnings or {}),
			errors = uc_clone_value(context.errors or {}),
			updated_at = context.updated_at,
		}
	end
	status.contract_loaded = uc_profile_contract_available()
	status.contract_load_error = UC_PROFILE_CONTRACT_LOAD_ERROR
	status.validation_state = context.validation_state or status.validation_state
	status.load_state = context.load_state or status.load_state
	status.validation_source = context.validation_source
	status.file_present = context.file_present == true
	status.profile_tree_valid = context.profile_tree_valid
	_G.UC_PROFILE_CONTRACT_STATUS = status
	return status
end

local function uc_safe_filename(name)
	local n = tostring(name or 'unknown'):lower()
	n = n:gsub('[^%w%-_]+', '_')
	if n == '' then
		n = 'unknown'
	end
	return n
end

local function uc_profiles_file_path(char_name)
	return 'data/profiles/' .. uc_safe_filename(char_name) .. '.lua'
end

local function uc_config_status_file_path(char_name)
	return 'data/status/' .. uc_safe_filename(char_name) .. '_config_contract_status.lua'
end

local function uc_profile_v2_file_path(meta)
	return uc_profile_v2.default_export_path(meta)
end

local function uc_addon_path()
	if type(windower) == 'table' and type(windower.addon_path) == 'string' and windower.addon_path ~= '' then
		return windower.addon_path
	end
	return nil
end

local function uc_profile_v2_meta(player, exported_at)
	return {
		character = player and player.name or nil,
		main_job = player and player.main_job or nil,
		sub_job = player and player.sub_job or nil,
		profile_key = player and (tostring(player.name or '') .. '|' .. tostring(player.main_job or '') .. '|' .. tostring(player.sub_job or '')) or nil,
		exported_at = exported_at,
		addon_path = uc_addon_path(),
	}
end

local function uc_profile_v2_export_failure(reason)
	if type(reason) ~= 'string' or reason == '' then
		reason = 'export failed without reason'
	end
	windower.add_to_chat(167, 'UC profile v2 export failed: ' .. reason)
end

local uc_normalize_profiles_tree

local function uc_serialize_lua(v, indent)
	indent = indent or 0
	local t = type(v)
	if t == 'nil' then
		return 'nil'
	elseif t == 'number' or t == 'boolean' then
		return tostring(v)
	elseif t == 'string' then
		return string.format('%q', v)
	elseif t ~= 'table' then
		return string.format('%q', tostring(v))
	end
	local next_indent = indent + 2
	local pad = string.rep(' ', indent)
	local npad = string.rep(' ', next_indent)
	local parts = { '{' }
	for k, vv in pairs(v) do
		local key
		if type(k) == 'string' and k:match('^[_%a][_%w]*$') then
			key = k
		else
			key = '[' .. uc_serialize_lua(k, next_indent) .. ']'
		end
		parts[#parts + 1] = '\n' .. npad .. key .. ' = ' .. uc_serialize_lua(vv, next_indent) .. ','
	end
	if #parts > 1 then
		parts[#parts + 1] = '\n' .. pad .. '}'
	else
		parts[#parts + 1] = '}'
	end
	return table.concat(parts, '')
end

local function uc_write_profiles_file(char_name, profiles_tbl)
	local path = uc_profiles_file_path(char_name)
	local payload = {
		version = 1,
		profiles = uc_normalize_profiles_tree(uc_clone_value(profiles_tbl or {})),
	}
	local content = 'return ' .. uc_serialize_lua(payload, 0) .. '\n'
	local fobj = files.new(path, true)
	local ok = files.write(fobj, content)
	return ok ~= nil
end

local function uc_write_config_status_export(status, meta)
	meta = type(meta) == 'table' and meta or {}
	local char_name = meta.character
	if char_name == nil or char_name == '' then
		char_name = type(status) == 'table' and status.character or nil
	end
	if char_name == nil or char_name == '' then
		return false, nil, 'missing character for config status export'
	end
	local path = uc_config_status_file_path(char_name)
	local ok_render, content = pcall(uc_config_status_export.render_config_status_export, status, {
		exported_at = meta.exported_at,
	})
	if not ok_render then
		return false, path, tostring(content)
	end
	local ok_write, result = pcall(function()
		local fobj = files.new(path, true)
		return files.write(fobj, content)
	end)
	if not ok_write then
		return false, path, tostring(result)
	end
	if result == nil then
		return false, path, 'files.write returned nil'
	end
	return true, path, nil
end

local function uc_write_profile_v2_export(profile, meta)
	local result = uc_profile_v2.write_structured_profile_export(profile, meta)
	if type(result) ~= 'table' then
		return false, uc_profile_v2_file_path(meta), 'profile v2 export writer returned invalid result', nil
	end
	return result.ok == true, result.path, result.reason, result.detail or result.error
end

local function uc_validate_profile_v2_file(meta)
	local result = uc_profile_v2.validate_structured_profile_file(meta, function(payload)
		return uc_validate_structured_profile_export(payload)
	end)
	if type(result) ~= 'table' then
		return false, uc_profile_v2_file_path(meta), 'profile v2 validator returned invalid result'
	end
	return result.ok == true, result.path, result.error
end

local function uc_diff_profile_v2_file(meta, settings)
	local current_config = uc_current_profile_v2_config({ settings = settings }, meta)
	local result = uc_profile_v2.diff_structured_profile_file_against_config(current_config, meta, function(payload)
		return uc_validate_structured_profile_export(payload)
	end)
	if type(result) ~= 'table' then
		return false, uc_profile_v2_file_path(meta), 'profile v2 diff returned invalid result', nil
	end
	return result.ok == true, result.path, result.error, result.count
end

local function uc_diff_profile_v2_detail_file(meta, settings)
	local current_config = uc_current_profile_v2_config({ settings = settings }, meta)
	local result = uc_profile_v2.diff_structured_profile_file_against_config(current_config, meta, function(payload)
		return uc_validate_structured_profile_export(payload)
	end)
	if type(result) ~= 'table' then
		return false, uc_profile_v2_file_path(meta), 'profile v2 diff detail returned invalid result', nil
	end
	return result.ok == true, result.path, result.error, result
end

local function uc_status_profile_v2_file(meta, settings)
	local current_config = uc_current_profile_v2_config({ settings = settings }, meta)
	local result = uc_profile_v2.inspect_structured_profile_file_against_config(current_config, meta, function(payload)
		return uc_validate_structured_profile_export(payload)
	end)
	if type(result) ~= 'table' then
		return {
			ok = false,
			path = uc_profile_v2_file_path(meta),
			stage = 'inspect',
			error = 'profile v2 status returned invalid result',
		}
	end
	return result
end

local uc_sync_table_in_place
local uc_normalize_settings_table
local uc_profile_v2_autoload_pending_key = nil
local uc_profile_v2_autoload_completed_key = nil
local uc_profile_v2_autoload_expected_main_job = nil
local uc_profile_v2_autoload_resume_engine = false
local uc_profile_v2_auto_reload_pending_path = nil
local uc_profile_v2_auto_reload_pending_hash = nil
local uc_profile_v2_auto_reload_pending_seen_at = nil
local uc_profile_v2_auto_reload_session_key = nil
local uc_profile_v2_auto_reload_last_applied_session_key = nil
local uc_profile_v2_auto_reload_last_applied_hash = nil
local uc_profile_v2_auto_reload_last_reported_hash = nil
local uc_profile_v2_auto_reload_last_checked_at = 0
local uc_profile_v2_auto_reload_last_error = nil
local UC_PROFILE_V2_AUTO_RELOAD_POLL_SEC = 1
local UC_PROFILE_V2_AUTO_RELOAD_STABLE_SEC = 1

local function uc_profile_v2_session_key(player)
	if not player or not player.name or not player.main_job or not player.sub_job then
		return nil
	end
	return tostring(player.name) .. '|' .. tostring(player.main_job) .. '|' .. tostring(player.sub_job)
end

local function uc_profile_v2_meta_key(meta)
	if type(meta) ~= 'table' or not meta.character or not meta.main_job or not meta.sub_job then
		return nil
	end
	return tostring(meta.character) .. '|' .. tostring(meta.main_job) .. '|' .. tostring(meta.sub_job)
end

local function uc_profile_v2_content_hash(content)
	local hash = 5381
	if type(content) ~= 'string' or content == '' then
		return nil
	end
	for i = 1, #content do
		hash = (hash * 33 + content:byte(i)) % 4294967296
	end
	return hash
end

local function uc_profile_v2_read_file_content(path)
	if type(path) ~= 'string' or path == '' then
		return nil, 'missing path'
	end
	local fh, err = io.open(path, 'rb')
	if not fh then
		return nil, err
	end
	local ok_read, content_or_err = pcall(function()
		return fh:read('*a')
	end)
	pcall(function()
		fh:close()
	end)
	if not ok_read then
		return nil, content_or_err
	end
	if type(content_or_err) ~= 'string' or content_or_err == '' then
		return nil, 'empty file'
	end
	return content_or_err
end

local function uc_profile_v2_auto_reload_reset()
	uc_profile_v2_auto_reload_pending_path = nil
	uc_profile_v2_auto_reload_pending_hash = nil
	uc_profile_v2_auto_reload_pending_seen_at = nil
	uc_profile_v2_auto_reload_session_key = nil
	uc_profile_v2_auto_reload_last_applied_session_key = nil
	uc_profile_v2_auto_reload_last_applied_hash = nil
	uc_profile_v2_auto_reload_last_reported_hash = nil
	uc_profile_v2_auto_reload_last_checked_at = 0
	uc_profile_v2_auto_reload_last_error = nil
end

local function uc_profile_v2_auto_reload_note_applied(meta, session_key, path, known_hash)
	local effective_path = path or uc_profile_v2_file_path(meta)
	if type(effective_path) ~= 'string' or effective_path == '' then
		return
	end
	local current_hash = known_hash
	if not current_hash then
		local content, read_err = uc_profile_v2_read_file_content(effective_path)
		if type(content) ~= 'string' then
			uc_profile_v2_auto_reload_last_error = tostring(read_err or 'read failed')
			return
		end
		current_hash = uc_profile_v2_content_hash(content)
	end
	if not current_hash then
		return
	end
	local effective_key = session_key
	if not effective_key and type(meta) == 'table' then
		effective_key = normalize_optional_string(meta.character)
		if effective_key ~= nil and (meta.main_job ~= nil or meta.sub_job ~= nil) then
			effective_key = tostring(meta.character or '') .. '|' .. tostring(meta.main_job or '') .. '|' .. tostring(meta.sub_job or '')
		end
	end
	uc_profile_v2_auto_reload_session_key = effective_key
	uc_profile_v2_auto_reload_last_applied_session_key = effective_key
	uc_profile_v2_auto_reload_last_applied_hash = current_hash
	uc_profile_v2_auto_reload_last_reported_hash = current_hash
	uc_profile_v2_auto_reload_last_error = nil
	uc_profile_v2_auto_reload_pending_path = nil
	uc_profile_v2_auto_reload_pending_hash = nil
	uc_profile_v2_auto_reload_pending_seen_at = nil
end

local function uc_profile_v2_auto_reload_note_rejected(meta, session_key, path, reason)
	local effective_path = path or uc_profile_v2_file_path(meta)
	local content = uc_profile_v2_read_file_content(effective_path)
	local rejected_hash = uc_profile_v2_content_hash(content)
	uc_profile_v2_auto_reload_session_key = session_key
	uc_profile_v2_auto_reload_last_reported_hash = rejected_hash
	uc_profile_v2_auto_reload_last_error = tostring(reason or 'invalid profile v2')
	uc_profile_v2_auto_reload_pending_path = nil
	uc_profile_v2_auto_reload_pending_hash = nil
	uc_profile_v2_auto_reload_pending_seen_at = nil
end

local function uc_profile_v2_auto_reload_status(meta, settings)
	local inspector = uc_profile_v2.inspect_structured_profile_file_against_settings
	if type(inspector) ~= 'function' then
		return {
			ok = false,
			valid = false,
			path = uc_profile_v2_file_path(meta),
			error = 'profile v2 status unavailable',
		}
	end
	local result = inspector(settings, meta, function(payload)
		return uc_validate_structured_profile_export(payload)
	end)
	if type(result) ~= 'table' then
		return {
			ok = false,
			valid = false,
			path = uc_profile_v2_file_path(meta),
			error = 'profile v2 status returned invalid result',
		}
	end
	result.automatic = true
	result.pending_path = uc_profile_v2_auto_reload_pending_path
	result.pending_hash = uc_profile_v2_auto_reload_pending_hash
	result.pending_since = uc_profile_v2_auto_reload_pending_seen_at
	result.last_applied_hash = uc_profile_v2_auto_reload_last_applied_hash
	result.last_reported_hash = uc_profile_v2_auto_reload_last_reported_hash
	result.last_checked_at = uc_profile_v2_auto_reload_last_checked_at
	result.last_error = uc_profile_v2_auto_reload_last_error
	result.session_key = uc_profile_v2_auto_reload_session_key
	return result
end

local function uc_queue_profile_v2_autoload(expected_main_job, resume_engine)
	local p = windower.ffxi.get_player()
	if not p or not p.name or not _G.UC_SETTINGS then
		return nil
	end

	local key = uc_profile_v2_session_key(p)
	if not key then
		return key
	end

	uc_profile_v2_autoload_pending_key = key
	uc_profile_v2_autoload_expected_main_job = expected_main_job and tostring(expected_main_job):upper() or nil
	uc_profile_v2_autoload_resume_engine = resume_engine == true
	return key
end

local function uc_apply_profile_v2_file(meta, settings)
	local current_config = uc_current_profile_v2_config({ settings = settings }, meta)
	local result = uc_profile_v2.apply_structured_profile_file_to_active_config(current_config, meta, function(payload)
		return uc_validate_structured_profile_export(payload)
	end)
	if type(result) ~= 'table' then
		return false, uc_profile_v2_file_path(meta), 'profile v2 apply returned invalid result', nil
	end
	if result.ok ~= true or type(result.active_profile) ~= 'table' then
		local failure_error = result.error
		if result.stage == 'convert' and type(result.detail) == 'string' and result.detail ~= '' then
			failure_error = tostring(failure_error or 'unknown error') .. ': ' .. result.detail
		end
		return false, result.path or uc_profile_v2_file_path(meta), failure_error, nil
	end
	local active_ok, active_err = uc_active_config.set_active_profile(result.active_profile)
	if active_ok ~= true then
		return false, result.path or uc_profile_v2_file_path(meta), active_err, nil
	end
	uc_profile_v2_auto_reload_note_applied(meta, uc_profile_v2_meta_key(meta), result.path)
	return true, result.path, nil, result.count
end

local function uc_initialize_safe_profile_v2_identity(player, job_for_defaults)
	if type(player) ~= 'table' or not player.name or not player.main_job or not player.sub_job or not _G.UC_SETTINGS then
		return false, 'missing exact player identity or settings'
	end
	local defaults = uc_new_settings_defaults()
	defaults.engine_enabled = Start_Engine == true
	local sync_ok, sync_err = uc_active_config.sync_flat_settings_in_place(_G.UC_SETTINGS, defaults)
	if sync_ok ~= true then
		return false, sync_err
	end
	uc_apply_job_defaults(job_for_defaults or player.main_job)
	uc_normalize_settings_table(_G.UC_SETTINGS)
	local active_profile = uc_active_config.build_active_profile_from_settings(_G.UC_SETTINGS, {
		character = player.name,
		main_job = player.main_job,
		sub_job = player.sub_job,
		profile_key = uc_profile_v2_session_key(player),
		source = 'UC_DEFAULTS',
	})
	local active_ok, active_err = uc_active_config.set_active_profile(active_profile)
	if active_ok ~= true then
		return false, active_err
	end
	return true
end

local function uc_establish_profile_v2_identity(player, job_for_defaults)
	local key = uc_profile_v2_session_key(player)
	if not key then
		return nil
	end
	uc_profile_v2_auto_reload_reset()
	uc_profile_v2_auto_reload_session_key = key
	local safe_ok, safe_err = uc_initialize_safe_profile_v2_identity(player, job_for_defaults)
	if safe_ok ~= true then
		return {
			ok = false,
			state = 'error',
			stage = 'initialize',
			error = safe_err,
		}
	end

	local meta = {
		character = player.name,
		main_job = player.main_job,
		sub_job = player.sub_job,
		profile_key = key,
		addon_path = uc_addon_path(),
	}
	local inspection = uc_profile_v2.inspect_structured_profile_status_against_config(
		uc_active_config.get_config(),
		meta,
		function(payload)
			return uc_validate_structured_profile_export(payload)
		end
	)
	if type(inspection) ~= 'table' then
		return {
			ok = false,
			state = 'error',
			stage = 'inspect',
			path = uc_profile_v2_file_path(meta),
			error = 'profile v2 inspection returned invalid result',
		}
	end
	if inspection.state == 'missing' then
		uc_update_config_contract_status({
			settings = _G.UC_SETTINGS,
			source = 'UC_DEFAULTS',
			character = player.name,
			main_job = player.main_job,
			sub_job = player.sub_job,
			addon_path = meta.addon_path,
			profile_key = key,
			updated_at = uc_now_s(),
		})
		return {
			ok = true,
			state = 'missing',
			stage = 'done',
			path = inspection.path,
			count = 0,
			diff_count = 0,
		}
	end
	if inspection.valid ~= true then
		local reason = inspection.reason or inspection.error or 'invalid profile v2'
		uc_profile_v2_auto_reload_note_rejected(meta, key, inspection.path, reason)
		uc_update_config_contract_status({
			settings = _G.UC_SETTINGS,
			source = 'UC_DEFAULTS',
			character = player.name,
			main_job = player.main_job,
			sub_job = player.sub_job,
			addon_path = meta.addon_path,
			profile_key = key,
			warnings = { tostring(reason) },
			updated_at = uc_now_s(),
		})
		return {
			ok = false,
			state = 'invalid',
			stage = inspection.state or 'validate',
			path = inspection.path,
			error = tostring(reason),
		}
	end

	local ok_apply, path, apply_err, apply_count = uc_apply_profile_v2_file(meta, _G.UC_SETTINGS)
	if ok_apply ~= true then
		uc_profile_v2_auto_reload_note_rejected(meta, key, path, apply_err)
		return {
			ok = false,
			state = 'invalid',
			stage = 'apply',
			path = path,
			error = apply_err,
			count = tonumber(apply_count) or 0,
			diff_count = tonumber(apply_count) or 0,
		}
	end
	return {
		ok = true,
		state = 'active',
		path = path,
		count = tonumber(apply_count) or 0,
		diff_count = tonumber(apply_count) or 0,
		stage = 'done',
	}
end

local function uc_autoload_profile_v2_file()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not p.main_job or not p.sub_job or not _G.UC_SETTINGS then
		return nil
	end
	return uc_establish_profile_v2_identity(p, p.main_job)
end

local function uc_reload_profile_v2_for_current_identity()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not p.main_job or not p.sub_job then
		return {
			ok = false,
			error = 'missing player identity',
			diff_count = -1,
		}
	end
	if not _G.UC_SETTINGS then
		return {
			ok = false,
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			error = 'missing settings',
			diff_count = -1,
		}
	end

	local meta = {
		character = p.name,
		main_job = p.main_job,
		sub_job = p.sub_job,
		addon_path = uc_addon_path(),
	}
	local ok_reload, path, reload_err, reload_count = uc_apply_profile_v2_file(meta, _G.UC_SETTINGS)
	if not ok_reload then
		return {
			ok = false,
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			path = path,
			error = tostring(reload_err or 'unknown error'),
			diff_count = tonumber(reload_count) or -1,
		}
	end

	uc_profile_v2_auto_reload_note_applied(meta, uc_profile_v2_session_key(p), path)
	local status = uc_update_profile_v2_contract_status({
		settings = _G.UC_SETTINGS,
		source = 'UC_SETTINGS',
		character = p.name,
		main_job = p.main_job,
		sub_job = p.sub_job,
		addon_path = meta.addon_path,
		profile_key = uc_profile_v2_session_key(p),
		updated_at = uc_now_s(),
	})
	local diff_count = tonumber(status and (status.diff_count or status.count)) or -1
	if type(status) ~= 'table' then
		return {
			ok = false,
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			path = path,
			error = 'post-reload verification returned an invalid status result',
			diff_count = diff_count,
		}
	end
	if status.valid ~= true then
		return {
			ok = false,
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			path = path,
			error = 'post-reload profile status is invalid: ' .. tostring(status.reason or status.error or 'reason missing'),
			diff_count = diff_count,
		}
	end
	if diff_count ~= 0 then
		local first_difference = status.first_difference
		local verification_error
		if type(first_difference) == 'table' then
			verification_error = 'post-reload mismatch: '
				.. uc_profile_v2.format_structured_profile_diff_detail(first_difference)
		else
			verification_error = 'post-reload verification reported '
				.. tostring(diff_count)
				.. ' differences but omitted first-difference detail'
		end
		return {
			ok = false,
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			path = path,
			error = verification_error,
			diff_count = diff_count,
		}
	end

	return {
		ok = true,
		character = p.name,
		main_job = p.main_job,
		sub_job = p.sub_job,
		path = path,
		error = '',
		diff_count = 0,
	}
end

_G.UC_ReloadProfileV2ForCurrentIdentity = uc_reload_profile_v2_for_current_identity

local function uc_run_queued_profile_v2_autoload()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not _G.UC_SETTINGS then
		return nil
	end

	local key = uc_profile_v2_session_key(p)
	if not key or uc_profile_v2_autoload_pending_key == nil then
		return nil
	end
	if uc_profile_v2_autoload_expected_main_job ~= nil
		and tostring(p.main_job):upper() ~= uc_profile_v2_autoload_expected_main_job then
		return nil
	end

	local result = uc_autoload_profile_v2_file()
	if type(result) ~= 'table' then
		return nil
	end

	uc_profile_v2_autoload_completed_key = key
	uc_profile_v2_autoload_pending_key = nil
	uc_profile_v2_autoload_expected_main_job = nil
	local resume_engine = uc_profile_v2_autoload_resume_engine
	uc_profile_v2_autoload_resume_engine = false

	if result.ok == true and result.state == 'active' then
		local status = uc_update_profile_v2_contract_status({
			settings = _G.UC_SETTINGS,
			source = 'UC_SETTINGS',
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			addon_path = uc_addon_path(),
			profile_key = tostring(p.name or '') .. '|' .. tostring(p.main_job or '') .. '|' .. tostring(p.sub_job or ''),
			updated_at = uc_now_s(),
		})
		local diff_count = tonumber(status and (status.diff_count or status.count)) or 0
		if status and status.valid == true and diff_count == 0 then
			if tonumber(result.count) == 0 then
				windower.add_to_chat(207, 'UC profile v2 autoload: no config differences')
			else
				windower.add_to_chat(207, 'UC profile v2 autoload: applied')
			end
		else
			local first_difference = type(status) == 'table' and status.first_difference or nil
			if type(first_difference) ~= 'table' then
				first_difference = type(result.first_difference) == 'table' and result.first_difference or nil
			end
			local diff_path = first_difference and first_difference.path or 'unknown diff'
			windower.add_to_chat(167, 'UC profile v2 autoload warning: ' .. tostring(diff_path))
		end
	elseif result.state == 'missing' then
		windower.add_to_chat(207, 'UC profile v2: no exact profile; using safe defaults')
	else
		local reason = result.error or result.reason or 'unknown error'
		windower.add_to_chat(167, 'UC profile v2 identity load failed; using safe defaults: ' .. tostring(reason))
	end

	if resume_engine and Start_Engine then
		uc_start_active_engine_if_running()
	end

	return result
end

local function uc_begin_profile_v2_identity_transition(expected_main_job)
	local p = windower.ffxi.get_player()
	if not p or not p.name or not p.main_job or not p.sub_job or not _G.UC_SETTINGS then
		return nil
	end
	local resume_engine = Start_Engine == true
	if resume_engine and type(_G.UC_StopUnifiedEngine) == 'function' then
		_G.UC_StopUnifiedEngine('profile_identity_change')
	end
	local safe_player = {
		name = p.name,
		main_job = expected_main_job or p.main_job,
		sub_job = p.sub_job,
	}
	local safe_ok, safe_err = uc_initialize_safe_profile_v2_identity(safe_player, expected_main_job or p.main_job)
	if safe_ok ~= true then
		error('failed to initialize safe profile identity state: ' .. tostring(safe_err))
	end
	uc_queue_profile_v2_autoload(expected_main_job, resume_engine)
	return p
end

local function uc_run_profile_v2_auto_reload()
	local now = uc_now_s()
	if (now - uc_profile_v2_auto_reload_last_checked_at) < UC_PROFILE_V2_AUTO_RELOAD_POLL_SEC then
		return nil
	end
	uc_profile_v2_auto_reload_last_checked_at = now

	local p = windower.ffxi.get_player()
	if not p or not p.name or not p.main_job or not p.sub_job or not _G.UC_SETTINGS then
		return nil
	end
	local session_key = uc_profile_v2_session_key(p)
	if session_key ~= uc_profile_v2_auto_reload_session_key then
		uc_profile_v2_auto_reload_reset()
		uc_profile_v2_auto_reload_session_key = session_key
	end

	local meta = {
		character = p.name,
		main_job = p.main_job,
		sub_job = p.sub_job,
		profile_key = tostring(p.name or '') .. '|' .. tostring(p.main_job or '') .. '|' .. tostring(p.sub_job or ''),
		addon_path = uc_addon_path(),
	}
	local path = uc_profile_v2_file_path(meta)
	local content, read_err = uc_profile_v2_read_file_content(path)
	if type(content) ~= 'string' then
		uc_profile_v2_auto_reload_last_error = tostring(read_err or 'missing file')
		return nil
	end

	local current_hash = uc_profile_v2_content_hash(content)
	if not current_hash then
		uc_profile_v2_auto_reload_last_error = 'unable to hash structured profile file'
		return nil
	end

	if uc_profile_v2_auto_reload_last_applied_hash == current_hash and uc_profile_v2_auto_reload_last_applied_session_key == session_key then
		uc_profile_v2_auto_reload_pending_path = nil
		uc_profile_v2_auto_reload_pending_hash = nil
		uc_profile_v2_auto_reload_pending_seen_at = nil
		uc_profile_v2_auto_reload_last_error = nil
		return nil
	end
	if uc_profile_v2_auto_reload_last_reported_hash == current_hash then
		return nil
	end

	if uc_profile_v2_auto_reload_pending_path ~= path or uc_profile_v2_auto_reload_pending_hash ~= current_hash then
		uc_profile_v2_auto_reload_pending_path = path
		uc_profile_v2_auto_reload_pending_hash = current_hash
		uc_profile_v2_auto_reload_pending_seen_at = now
		uc_profile_v2_auto_reload_last_error = nil
		return nil
	end

	if (now - (uc_profile_v2_auto_reload_pending_seen_at or now)) < UC_PROFILE_V2_AUTO_RELOAD_STABLE_SEC then
		uc_profile_v2_auto_reload_last_error = nil
		return nil
	end

	local ok_apply, apply_path, apply_err = uc_apply_profile_v2_file({
		character = p.name,
		main_job = p.main_job,
		sub_job = p.sub_job,
		addon_path = uc_addon_path(),
	}, _G.UC_SETTINGS)
	if ok_apply ~= true then
		uc_profile_v2_auto_reload_last_reported_hash = current_hash
		uc_profile_v2_auto_reload_pending_seen_at = now
		uc_profile_v2_auto_reload_last_error = tostring(apply_err or 'unknown error')
		windower.add_to_chat(167, 'UC profile v2 auto-reload failed: ' .. tostring(apply_err or 'unknown error'))
		return {
			ok = false,
			path = apply_path or path,
			error = apply_err,
			reason = apply_err,
		}
	end

	local inspector = uc_profile_v2.inspect_structured_profile_file_against_config
	local status = nil
	if type(inspector) == 'function' then
		status = inspector(uc_active_config.get_config(), {
			character = p.name,
			main_job = p.main_job,
			sub_job = p.sub_job,
			addon_path = uc_addon_path(),
		}, function(payload)
			return uc_validate_structured_profile_export(payload)
		end)
	end
	local diff_count = tonumber(status and (status.diff_count or status.count)) or 0
	uc_profile_v2_auto_reload_last_reported_hash = current_hash
	uc_profile_v2_auto_reload_last_applied_session_key = session_key
	uc_profile_v2_auto_reload_last_applied_hash = current_hash
	uc_profile_v2_auto_reload_last_error = nil
	uc_profile_v2_auto_reload_pending_path = nil
	uc_profile_v2_auto_reload_pending_hash = nil
	uc_profile_v2_auto_reload_pending_seen_at = nil

	if status and status.valid == true and diff_count == 0 then
		windower.add_to_chat(207, 'UC profile v2 auto-reload: applied')
	else
		local first_difference = type(status) == 'table' and status.first_difference or nil
		local diff_path = first_difference and first_difference.path or 'unknown diff'
		windower.add_to_chat(167, 'UC profile v2 auto-reload warning: ' .. tostring(diff_path))
	end

	return {
		ok = true,
		path = status and status.path or apply_path or path,
		count = tonumber(status and (status.count or status.diff_count)) or 0,
		diff_count = diff_count,
		status = status,
	}
end

uc_sync_table_in_place = function(dst, src)
	return uc_active_config.sync_flat_settings_in_place(dst, src)
end

local function uc_read_profiles_file(char_name)
	local path = uc_profiles_file_path(char_name)
	if not files.exists(path) then
		return nil
	end
	local content = files.read(path)
	if type(content) ~= 'string' or content == '' then
		return nil
	end
	local loader = loadstring or load
	local chunk = loader and loader(content) or nil
	if type(chunk) ~= 'function' then
		return nil
	end
	local ok, payload = pcall(chunk)
	if not ok or type(payload) ~= 'table' then
		return nil
	end
	if type(payload.profiles) == 'table' then
		return payload.profiles
	end
	if type(payload.melee) == 'table' or type(payload.dd2) == 'table' then
		return payload
	end
	return nil
end

local uc_get_active_profile_coords

local function uc_normalize_abilities(s)
	local out = {}
	if type(s.abilities) == 'table' then
		for _, a in ipairs(s.abilities) do
			if a and a ~= '' then
				out[#out + 1] = a
			end
		end
	end
	if #out == 0 then
		for i = 1, 6 do
			local a = s['ability' .. tostring(i)]
			if a and a ~= '' then
				out[#out + 1] = a
			end
		end
	end
	s.abilities = out
	for i = 1, 6 do
		s['ability' .. tostring(i)] = out[i] or ''
	end
end

local function uc_normalize_targets(s)
	if type(s.targets) ~= 'table' then
		s.targets = {}
	end
	if #s.targets == 0 then
		local arr = {}
		for i = 1, 3 do
			local t = s['target' .. tostring(i)]
			if t and t ~= '' then
				arr[#arr + 1] = t
			end
		end
		s.targets = arr
	else
		for i = 1, 3 do
			s['target' .. tostring(i)] = s.targets[i] or ''
		end
	end
end

local function uc_normalize_ws_for_engine(s, eng)
	local ws = s.weaponskill or s.ws1 or ''
	s.weaponskill = ws
	s.ws1 = ws
	if s.weaponskill_min_tp == nil then
		s.weaponskill_min_tp = 1000
	elseif type(s.weaponskill_min_tp) ~= 'number'
		or s.weaponskill_min_tp % 1 ~= 0
		or s.weaponskill_min_tp < 1000
		or s.weaponskill_min_tp > 3000 then
		error('weaponskill_min_tp must be an integer from 1000 to 3000')
	end
	if s.weaponskill_allow_aoe == nil then
		s.weaponskill_allow_aoe = true
	elseif type(s.weaponskill_allow_aoe) ~= 'boolean' then
		error('weaponskill_allow_aoe must be a boolean')
	end
	if s.fast_skillchain == nil then
		s.fast_skillchain = false
	elseif type(s.fast_skillchain) ~= 'boolean' then
		error('fast_skillchain must be a boolean')
	end
	s.engine_mode = eng
end

local function uc_trim_string(v)
	if type(v) ~= 'string' then
		return ''
	end
	return (v:match('^%s*(.-)%s*$') or '')
end

local function uc_normalize_sleep_spell_entry(v)
	local raw = uc_trim_string(v)
	if raw == '' then
		return ''
	end
	local spell = res.spells:with('en', raw)
	if spell and spell.en then
		return tostring(spell.en)
	end
	return raw
end

local function uc_normalize_sleep_spell_list(s)
	if type(s) ~= 'table' then
		return
	end
	local out = {}
	local seen = {}
	local function append_spell(raw)
		local spell_name = uc_normalize_sleep_spell_entry(raw)
		if spell_name == '' then
			return
		end
		local key = spell_name:lower()
		if seen[key] == true then
			return
		end
		seen[key] = true
		out[#out + 1] = spell_name
	end
	if type(s.sleepspells) == 'table' then
		for _, entry in ipairs(s.sleepspells) do
			append_spell(entry)
		end
	elseif type(s.sleepspells) == 'string' then
		append_spell(s.sleepspells)
	end
	local legacy_sleep = uc_normalize_sleep_spell_entry(s.sleepspell)
	if #out == 0 and legacy_sleep ~= '' then
		append_spell(legacy_sleep)
	end
	s.sleepspells = out
	s.sleepspell = out[1] or ''
end

local function uc_normalize_domain_settings(s)
	if type(s) ~= 'table' then
		return
	end
	-- Canonical domain settings migration:
	-- - legacy behavior implied combat/defensive/movement/maintenance/follow domains enabled.
	-- - preserve existing runtime engine flag when available.
	if s.engine_enabled == nil then
		s.engine_enabled = Start_Engine == true
	end
	if s.domain_combat_enabled == nil then
		s.domain_combat_enabled = true
	end
	if s.domain_defensive_enabled == nil then
		s.domain_defensive_enabled = true
	end
	if s.domain_movement_enabled == nil then
		s.domain_movement_enabled = true
	end
	if s.domain_maintenance_enabled == nil then
		s.domain_maintenance_enabled = true
	end
	if s.domain_follow_enabled == nil then
		s.domain_follow_enabled = true
	end
	if s.auto_accept_raise == nil then
		s.auto_accept_raise = false
	end
	if s.pause_automation_while_weakened == nil then
		s.pause_automation_while_weakened = false
	end
	if type(s.wait_ignore_names) ~= 'table' then
		s.wait_ignore_names = {}
	end
end

uc_normalize_settings_table = function(s)
	if type(s) ~= 'table' then
		return
	end
	local eng = nil
	if type(s.main_job) == 'string' and s.main_job ~= '' then
		eng = tostring(s.main_job):upper()
	else
		local p = windower.ffxi.get_player()
		local job = p and p.main_job or 'UNKNOWN'
		if type(job) ~= 'string' then
			local rj = res.jobs:with('id', job)
			job = (rj and rj.english_short) or tostring(job)
		end
		eng = tostring(job):upper()
	end
	uc_normalize_abilities(s)
	uc_normalize_targets(s)
	uc_normalize_ws_for_engine(s, eng)
	uc_normalize_sleep_spell_list(s)
	uc_normalize_domain_settings(s)
	uc_partner_list.migrate_from_legacy(s)
	uc_partner_list.sync_legacy_partner_fields(s)
end

local function uc_normalize_active_settings()
	local s = _G.UC_SETTINGS
	if not s then
		return
	end
	uc_normalize_settings_table(s)
end

uc_get_active_profile_coords = function()
	local p = windower.ffxi.get_player()
	local eng = 'UC'
	local job = p and p.main_job or 'UNKNOWN'
	if type(job) ~= 'string' then
		local rj = res.jobs:with('id', job)
		job = (rj and rj.english_short) or tostring(job)
	end
	job = tostring(job):upper()
	return eng, job
end

local function uc_get_profiles_root()
	local s = _G.UC_SETTINGS
	if not s then
		return nil
	end
	if type(s.profiles) ~= 'table' then
		s.profiles = {}
	end
	if type(s.profiles.UC) ~= 'table' then
		s.profiles.UC = {}
	end
	return s.profiles
end

local function uc_table_has_any(t)
	if type(t) ~= 'table' then
		return false
	end
	for _ in pairs(t) do
		return true
	end
	return false
end

uc_normalize_profiles_tree = function(profiles)
	if type(profiles) ~= 'table' then
		return { UC = {} }
	end
	local uc_branch = profiles.UC
	if type(uc_branch) ~= 'table' then
		uc_branch = {}
		local candidates = { profiles.melee, profiles.dd2, profiles.DD2 }
		for _, branch in ipairs(candidates) do
			if type(branch) == 'table' then
				for job, pdata in pairs(branch) do
					local j = tostring(job):upper()
					if type(uc_branch[j]) ~= 'table' then
						uc_branch[j] = uc_clone_value(pdata)
					end
				end
			end
		end
		for key, val in pairs(profiles) do
			if key ~= 'UC' and key ~= 'melee' and key ~= 'dd2' and key ~= 'DD2' and type(val) == 'table' then
				local j = tostring(key):upper()
				if type(uc_branch[j]) ~= 'table' then
					uc_branch[j] = uc_clone_value(val)
				end
			end
		end
	end
	local out = { UC = {} }
	for job, pdata in pairs(uc_branch) do
		local j = tostring(job):upper()
		out.UC[j] = uc_clone_value(pdata)
	end
	return out
end

local function uc_load_profiles_for_character(char_name)
	if not _G.UC_SETTINGS or not char_name or char_name == '' then
		uc_update_profile_contract_status({
			validation_state = 'skipped',
			load_state = 'missing_settings_or_character',
			validation_source = 'load_path',
			file_present = false,
			warnings = { 'profile load skipped: missing settings or character' },
			errors = { 'profile load skipped: missing settings or character' },
			updated_at = uc_now_s(),
		})
		uc_update_config_contract_status({
			source = 'UC_SETTINGS',
			warnings = { 'config status skipped: missing settings or character' },
			updated_at = uc_now_s(),
		})
		return false
	end
	local file_profiles = uc_read_profiles_file(char_name)
	if type(file_profiles) ~= 'table' then
		uc_update_profile_contract_status({
			character = char_name,
			main_job = nil,
			sub_job = nil,
			profile_key = nil,
			validation_state = 'missing_or_invalid',
			load_state = 'missing_or_invalid',
			validation_source = 'load_path',
			file_present = false,
			warnings = { 'profile file missing or invalid' },
			errors = { 'profile file missing or invalid' },
			updated_at = uc_now_s(),
		})
		return false
	end
	local validation_result = uc_validate_profile_tree(file_profiles)
	local validation_state = 'unavailable'
	local load_state = 'loaded_without_validation'
	local validation_warnings = { 'profile validation module unavailable' }
	local validation_errors = {}
	local profile_tree_valid = nil
	if validation_result ~= nil then
		profile_tree_valid = validation_result.ok == true
		validation_state = validation_result.ok and 'valid' or 'invalid'
		load_state = validation_result.ok and 'loaded' or 'validation_failed'
		validation_warnings = validation_result.warnings or {}
		validation_errors = validation_result.errors or {}
		if not validation_result.ok then
			uc_update_profile_contract_status({
				character = char_name,
				main_job = nil,
				sub_job = nil,
				profile_key = nil,
				validation_state = validation_state,
				load_state = load_state,
				validation_source = 'load_path',
				file_present = true,
				warnings = validation_warnings,
				errors = validation_errors,
				updated_at = uc_now_s(),
			})
			return false
		end
	end
	_G.UC_SETTINGS.profiles = uc_normalize_profiles_tree(uc_clone_value(file_profiles))
	local p = windower.ffxi.get_player()
	local profile_character = p and p.name or char_name
	local profile_main_job = p and p.main_job or nil
	local profile_sub_job = p and p.sub_job or nil
	local profile_key = profile_character
	if profile_main_job ~= nil or profile_sub_job ~= nil then
		profile_key = tostring(profile_character or '') .. '|' .. tostring(profile_main_job or '') .. '|' .. tostring(profile_sub_job or '')
	end
	uc_update_profile_contract_status({
		character = profile_character,
		main_job = profile_main_job,
		sub_job = profile_sub_job,
		profile_key = profile_key,
		validation_state = validation_state,
		load_state = load_state,
		validation_source = 'load_path',
		file_present = true,
		profile_tree_valid = profile_tree_valid,
		warnings = validation_warnings,
		errors = validation_errors,
		engine_state = {
			engine_enabled = Start_Engine == true,
		},
		scheduler_summary = {
			profile_character = profile_character,
			profile_main_job = profile_main_job,
		},
		current_action = {
			kind = 'profile_load',
			name = 'reload_active_profile',
		},
		updated_at = uc_now_s(),
	})
	uc_update_config_contract_status({
		settings = _G.UC_SETTINGS,
		source = 'UC_SETTINGS',
		character = profile_character,
		main_job = profile_main_job,
		sub_job = profile_sub_job,
		addon_path = uc_addon_path(),
		profile_key = profile_key,
		updated_at = uc_now_s(),
	})
	uc_get_profiles_root()
	return true
end

local function uc_capture_active_profile()
	local s = _G.UC_SETTINGS
	local profiles = uc_get_profiles_root()
	if not s or not profiles then
		return false
	end
	uc_normalize_active_settings()
	local eng, job = uc_get_active_profile_coords()
	profiles[eng][job] = profiles[eng][job] or {}
	local dst = profiles[eng][job]
	for _, key in ipairs(PROFILE_KEYS) do
		if s[key] ~= nil then
			dst[key] = uc_clone_value(s[key])
		else
			dst[key] = nil
		end
	end
	return true
end

local function uc_apply_active_profile()
	local s = _G.UC_SETTINGS
	local profiles = uc_get_profiles_root()
	if not s or not profiles then
		return false
	end
	local eng, job = uc_get_active_profile_coords()
	local src = profiles[eng] and profiles[eng][job] or nil
	if type(src) ~= 'table' or not uc_table_has_any(src) then
		return false
	end
	for _, key in ipairs(PROFILE_KEYS) do
		s[key] = uc_clone_value(src[key])
	end
	uc_normalize_active_settings()
	return true
end

local function uc_sync_active_profile_from_settings(source)
	local s = _G.UC_SETTINGS
	if type(s) ~= 'table' then
		return false
	end
	local active_profile = uc_active_config.build_active_profile_from_settings(s, {
		source = source or 'UC_SETTINGS',
	})
	local ok, err = uc_active_config.set_active_profile(active_profile)
	if ok ~= true then
		return false, err
	end
	return true
end

local function uc_save_active_profile()
	local p = windower.ffxi.get_player()
	local active_profile = uc_active_config.get_active_profile()
	if not p or not p.name or not p.main_job or not p.sub_job or type(active_profile) ~= 'table' then
		return false, nil, 'missing exact player identity or active Profile V2'
	end
	local meta = uc_profile_v2_meta(p, os.date('!%Y-%m-%dT%H:%M:%SZ'))
	meta.source = 'exported_from_active_profile'
	local ok_build, profile = pcall(uc_profile_v2.build_structured_profile_from_active_profile, active_profile, meta)
	if not ok_build or type(profile) ~= 'table' then
		return false, uc_profile_v2_file_path(meta), tostring(profile or 'profile build failed')
	end
	local validation = uc_validate_structured_profile_export(profile)
	if type(validation) ~= 'table' or validation.ok ~= true then
		return false, uc_profile_v2_file_path(meta), 'profile contract validation failed'
	end
	meta.profile_key = profile.profile and profile.profile.profile_key or nil
	meta.exported_at = profile.profile and profile.profile.exported_at or meta.exported_at
	local ok_write, path, write_reason = uc_write_profile_v2_export(profile, meta)
	if ok_write then
		uc_profile_v2_auto_reload_note_applied(meta, uc_profile_v2_session_key(p), path)
	end
	return ok_write, path, write_reason
end

local function uc_reload_character_settings()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not _G.UC_SETTINGS then
		return nil
	end
	return p
end

local function uc_reload_active_profile(job_for_defaults)
	local p = uc_reload_character_settings()
	if not p then
		return nil
	end
	local result = uc_reload_profile_v2_for_current_identity()
	if type(result) ~= 'table' or result.ok ~= true then
		return nil, type(result) == 'table' and result.error or 'profile v2 reload failed'
	end
	return p
end

local function uc_sleep_spell_list_lines(settings)
	local arr = uc_runtime_overrides.sleep_spell_names(settings)
	if #arr == 0 then
		return { 'Sleep spell list: (empty)' }
	end
	local lines = { 'Sleep spell list:' }
	for i, spell_name in ipairs(arr) do
		lines[#lines + 1] = ('  %d. %s'):format(i, tostring(spell_name))
	end
	return lines
end

local uc_sleep_spell = {}

function uc_sleep_spell.as_ordered_names(settings)
	local arr = type(settings and settings.sleepspells) == 'table' and settings.sleepspells or {}
	local out = {}
	for i = 1, #arr do
		out[#out + 1] = tostring(arr[i])
	end
	return out
end

local function uc_sleep_spell_validate_names(names)
	local out = {}
	local seen = {}
	for _, raw in ipairs(names or {}) do
		local spell_name = uc_normalize_sleep_spell_entry(raw)
		if spell_name == '' then
			return nil, 'SLEEP_SPELL_EMPTY'
		end
		if not res.spells:with('en', spell_name) then
			return nil, 'SLEEP_SPELL_UNKNOWN'
		end
		local key = spell_name:lower()
		if seen[key] ~= true then
			seen[key] = true
			out[#out + 1] = spell_name
		end
	end
	return out, ''
end

function uc_sleep_spell.validate_names(names)
	return uc_sleep_spell_validate_names(names or {})
end

function uc_sleep_spell.replace_names(settings, names)
	if type(settings) ~= 'table' then
		return false, 'SLEEP_NO_SETTINGS'
	end
	local validated, why = uc_sleep_spell_validate_names(names or {})
	if not validated then
		return false, why
	end
	settings.sleepspells = validated
	uc_normalize_sleep_spell_list(settings)
	return true, ''
end

function uc_sleep_spell.append_name(settings, name)
	if type(settings) ~= 'table' then
		return false, 'SLEEP_NO_SETTINGS'
	end
	local spell_name = uc_normalize_sleep_spell_entry(name)
	if spell_name == '' then
		return false, 'SLEEP_SPELL_EMPTY'
	end
	if not res.spells:with('en', spell_name) then
		return false, 'SLEEP_SPELL_UNKNOWN'
	end
	local arr = uc_sleep_spell.as_ordered_names(settings)
	for i = 1, #arr do
		if arr[i]:lower() == spell_name:lower() then
			return false, 'SLEEP_SPELL_ALREADY'
		end
	end
	arr[#arr + 1] = spell_name
	return uc_sleep_spell.replace_names(settings, arr)
end

function uc_sleep_spell.remove_index(settings, idx)
	if type(settings) ~= 'table' then
		return false, 'SLEEP_NO_SETTINGS'
	end
	idx = tonumber(idx)
	local arr = uc_sleep_spell.as_ordered_names(settings)
	if not idx or idx < 1 or idx > #arr then
		return false, 'SLEEP_SPELL_BAD_INDEX'
	end
	table.remove(arr, idx)
	return uc_sleep_spell.replace_names(settings, arr)
end

function uc_sleep_spell.move_index(settings, idx, delta)
	if type(settings) ~= 'table' then
		return false, 'SLEEP_NO_SETTINGS'
	end
	idx = tonumber(idx)
	delta = tonumber(delta)
	local arr = uc_sleep_spell.as_ordered_names(settings)
	if not idx or idx < 1 or idx > #arr or not delta or (delta ~= -1 and delta ~= 1) then
		return false, 'SLEEP_SPELL_MOVE_BAD_ARGS'
	end
	local swap_idx = idx + delta
	if swap_idx < 1 or swap_idx > #arr then
		return false, 'SLEEP_SPELL_MOVE_OOB'
	end
	arr[idx], arr[swap_idx] = arr[swap_idx], arr[idx]
	return uc_sleep_spell.replace_names(settings, arr)
end

_G.UC_SleepSpell = uc_sleep_spell

_G.UC_SaveActiveProfile = uc_save_active_profile
_G.UC_ReloadActiveProfile = uc_reload_active_profile

local ap_listener_id

local function uc_register_action_listener()
	if ap_listener_id then
		ActionPacket.close_listener(ap_listener_id)
		ap_listener_id = nil
	end
	ap_listener_id = ActionPacket.open_listener(function(act_org, act_mod)
		local act = act_org
		local observed_at = uc_now_s()

		-- Safety reactions are the first UnifiedCombat consumer of an action packet.
		-- Keep this ahead of encounter/core/scheduler bookkeeping so spell-start
		-- reactions can turn/disengage with the minimum addon-side latency.
		if type(_G.UC_SCHED_OnReactionAction) == 'function' then
			_G.UC_SCHED_OnReactionAction(act, observed_at)
		end

		uc_encounter_runtime.observe(observed_at)
		uc_encounter_runtime.on_action(act, observed_at)
		if UC_COMBAT_CORE and type(UC_COMBAT_CORE.on_action) == 'function' then
			UC_COMBAT_CORE.on_action(act)
		end
		if type(_G.UC_SCHED_OnAction) == 'function' then
			_G.UC_SCHED_OnAction(act)
		end
	end)
end

windower.register_event('load', function()
	uc_register_action_listener()
	if windower.ffxi.get_info().logged_in then
		UC_UNIFIED_ENGINE.seed_cached_status_snapshot()
		uc_update_engine()
		uc_begin_profile_v2_identity_transition()
		uc_camp_anchor.request_current_state()
	end
end)

windower.register_event('incoming chunk', function(id, data)
	if type(_G.UC_SCHED_OnIncomingChunk) == 'function' then
		pcall(function()
			_G.UC_SCHED_OnIncomingChunk(id, data)
		end)
	end
	if type(_G.UC_COR_MAINT_OnIncomingChunk) == 'function' then
		pcall(function()
			_G.UC_COR_MAINT_OnIncomingChunk(id, data)
		end)
	end
	if id == 0x029 and type(data) == 'string' then
		local ok = pcall(function()
			local msg = {
				actor_id = data:unpack('I', 0x05),
				target_id = data:unpack('I', 0x09),
				param_1 = data:unpack('I', 0x0D),
				effect_id = data:unpack('I', 0x0D),
				message_id = data:unpack('H', 0x19) % 32768,
			}
			if UC_COMBAT_CORE and type(UC_COMBAT_CORE.on_action_message) == 'function' then
				UC_COMBAT_CORE.on_action_message(msg)
			end
			if type(_G.UC_SCHED_OnActionMessage) == 'function' then
				_G.UC_SCHED_OnActionMessage(msg)
			end
		end)
		if not ok then
			-- Ignore malformed packet data. The scheduler continues on the next
			-- engine tick with no alternate execution path.
		end
	end
end)

windower.register_event('incoming text', function(original, modified, mode, blocked)
	if type(_G.UC_SCHED_OnIncomingText) == 'function' then
		pcall(function()
			_G.UC_SCHED_OnIncomingText(original, modified, mode, blocked)
		end)
	end
end)

windower.register_event('add item', function(bag, index, item_id, count)
	if type(_G.UC_SCHED_OnAddItem) == 'function' then
		pcall(function()
			_G.UC_SCHED_OnAddItem(bag, index, item_id, count)
		end)
	end
end)

windower.register_event('ipc message', function(msg)
	uc_camp_anchor.on_ipc_message(msg)
	local info = windower.ffxi.get_info()
	uc_camp_pull_registry.on_ipc_message(msg, info and info.zone)
	if UC_COMBAT_CORE and type(UC_COMBAT_CORE.on_ipc_message) == 'function' then
		pcall(function()
			UC_COMBAT_CORE.on_ipc_message(msg)
		end)
	end
	if type(_G.UC_SCHED_OnIpcMessage) == 'function' then
		pcall(function()
			_G.UC_SCHED_OnIpcMessage(msg)
		end)
	end
end)

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
	local buf = modified or data
	if uc_party_follow.outgoing_chunk(id, buf, blocked, injected) then
		return true
	end
end)

windower.register_event('prerender', function()
	uc_camp_anchor.observe_runtime()
	uc_run_queued_profile_v2_autoload()
	uc_update_recovery_hold()
	pcall(function()
		uc_pathing.tick()
	end)
	uc_party_follow.broadcast_self_ipc()
	uc_remote_tick()
	uc_party_follow.prerender()
	uc_run_profile_v2_auto_reload()
end)

windower.register_event('job change', function(job, lvl)
	local jname = res.jobs:with('id', job).english_short
	uc_begin_profile_v2_identity_transition(jname)
	uc_nyzul_runtime.reset('job_change')
	require('uc_brd_maintenance').reset('job_change')
	require('uc_sch_runtime').reset('job_change', uc_now_s())
	uc_reset_reaction_runtime('job_change')
	uc_encounter_runtime.reset('job_change')
	require('uc_lilith_easy_encounter').reset('job_change')
	require('uc_formation_runtime').reset('job_change')
	uc_update_engine()
	uc_register_action_listener()
end)

windower.register_event('zone change', function()
	uc_camp_anchor.clear()
	uc_camp_anchor.schedule_state_request()
	uc_camp_pull_registry.reset('zone_change')
	uc_nyzul_runtime.reset('zone_change')
	require('uc_brd_maintenance').reset('zone_change')
	require('uc_sch_runtime').reset('zone_change', uc_now_s())
	uc_reset_reaction_runtime('zone_change')
	uc_encounter_runtime.reset('zone_change')
	require('uc_lilith_easy_encounter').reset('zone_change')
	require('uc_formation_runtime').reset('zone_change')
	UC_COMBAT_CORE.reset_skillchain_state('zone_change')
	_G.UC_LAST_ZONE_CHANGE_AT = uc_now_s()
	_G.UC_ZONE_SUSPEND_UNTIL = uc_now_s() + UC_ZONE_SUSPEND_SEC
	_G.UC_LAST_BLOCK_REASON = 'ZONE_SUSPEND'
end)

windower.register_event('unload', function()
	local sch_capture_status = require('unified_scheduler').sch_maintenance_capture_status()
	if sch_capture_status.active == true then
		require('unified_scheduler').sch_maintenance_capture_stop('unload')
	end
	uc_recovery_hold.reset_runtime()
	uc_camp_anchor.clear()
	uc_camp_pull_registry.reset('unload')
	uc_nyzul_runtime.reset('unload')
	require('uc_brd_maintenance').reset('unload')
	require('uc_sch_runtime').reset('unload', uc_now_s())
	uc_reset_reaction_runtime('unload')
	uc_encounter_runtime.reset('unload')
	require('uc_lilith_easy_encounter').reset('unload')
	require('uc_formation_runtime').reset('unload')
	uc_profile_v2_autoload_pending_key = nil
	uc_profile_v2_autoload_completed_key = nil
	uc_profile_v2_autoload_expected_main_job = nil
	uc_profile_v2_autoload_resume_engine = false
	uc_profile_v2_auto_reload_reset()
	uc_remote_unload()
	if type(_G.UC_StopUnifiedEngine) == 'function' then
		_G.UC_StopUnifiedEngine('unload')
	end
	if ap_listener_id then
		ActionPacket.close_listener(ap_listener_id)
		ap_listener_id = nil
	end
end)

windower.register_event('logout', function()
	local sch_capture_status = require('unified_scheduler').sch_maintenance_capture_status()
	if sch_capture_status.active == true then
		require('unified_scheduler').sch_maintenance_capture_stop('logout')
	end
	uc_recovery_hold.reset_runtime()
	uc_camp_anchor.clear()
	uc_camp_pull_registry.reset('logout')
	uc_nyzul_runtime.reset('logout')
	require('uc_sch_runtime').reset('logout', uc_now_s())
	uc_reset_reaction_runtime('logout')
	uc_encounter_runtime.reset('logout')
	require('uc_lilith_easy_encounter').reset('logout')
	require('uc_formation_runtime').reset('logout')
	_G.UC_ZONE_SUSPEND_UNTIL = nil
	uc_profile_v2_autoload_pending_key = nil
	uc_profile_v2_autoload_completed_key = nil
	uc_profile_v2_autoload_expected_main_job = nil
	uc_profile_v2_autoload_resume_engine = false
	uc_profile_v2_auto_reload_reset()
	uc_remote_unload()
	if type(_G.UC_StopUnifiedEngine) == 'function' then
		_G.UC_StopUnifiedEngine('logout')
	end
end)

local function uc_fight_leader_party_id_by_name(name)
	if not name or name == '' then
		return 0
	end
	local want = tostring(name):lower()
	local party = windower.ffxi.get_party()
	if not party then
		return 0
	end
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, key in ipairs(keys) do
		local e = party[key]
		local mob = e and e.mob
		if mob and mob.name and mob.name:lower() == want and mob.id and mob.id ~= 0 then
			return mob.id
		end
	end
	return 0
end

windower.register_event('addon command', function(...)
	local args = { ... }
	local a = args[1] and tostring(args[1]):lower() or ''
	if a == 'start' then
		if not Start_Engine then
			Start_Engine = true
			_G.UC_ZONE_SUSPEND_UNTIL = nil
			uc_start_active_engine_if_running()
			windower.add_to_chat(207, 'UnifiedCombat: engine started')
		end
		return
	elseif a == 'stop' then
		Start_Engine = false
		local sch_capture_status = require('unified_scheduler').sch_maintenance_capture_status()
		if sch_capture_status.active == true then
			require('unified_scheduler').sch_maintenance_capture_stop('engine_stop')
		end
		require('uc_sch_runtime').reset('engine_stop', uc_now_s())
		uc_encounter_runtime.reset('engine_stop')
		require('uc_lilith_easy_encounter').reset('engine_stop')
		require('uc_formation_runtime').reset('engine_stop')
		if type(_G.UC_ResetMovementLocksForFollow) == 'function' then
			_G.UC_ResetMovementLocksForFollow()
		end
		if type(_G.UC_StopUnifiedEngine) == 'function' then
			_G.UC_StopUnifiedEngine('engine_stop')
		end
		windower.add_to_chat(207, 'UnifiedCombat: engine stopped')
		return
	elseif a == 'activity' then
		local name = table.concat(args, ' ', 2)
		if name == '' then
			windower.add_to_chat(207, '//uc activity <name> | //uc activity list | //uc activity apply <name>')
			return
		end
		local action = 'apply'
		if name:lower() == 'list' then
			action = 'list'
			name = ''
		elseif tostring(args[2]):lower() == 'apply' then
			name = table.concat(args, ' ', 3)
		end
		if action == 'apply' and name == '' then
			windower.add_to_chat(167, 'UnifiedCombat: activity name is required')
			return
		end
		uc_remote_activity_request(action, name)
		return
	elseif a == 'encounter' then
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'status' then
			uc_encounter_runtime.observe(uc_now_s())
			local lines = uc_encounter_runtime.status_lines()
			for i = 1, #lines do
				windower.add_to_chat(207, 'UC ' .. tostring(lines[i]))
			end
			return
		end
		windower.add_to_chat(207, '//uc encounter status')
		return
	elseif a == 'save' then
		local ok_save, path, save_err = _G.UC_SaveActiveProfile()
		if ok_save == true then
			windower.add_to_chat(207, 'UnifiedCombat: Profile V2 saved: ' .. tostring(path))
		else
			windower.add_to_chat(167, 'UnifiedCombat: Profile V2 save failed: ' .. tostring(save_err or 'unknown error'))
		end
		return
	elseif a == 'reload' then
		local reloaded, reload_err = _G.UC_ReloadActiveProfile()
		if reloaded ~= nil then
			windower.add_to_chat(207, 'UnifiedCombat: Profile V2 reloaded')
		else
			windower.add_to_chat(167, 'UnifiedCombat: Profile V2 reload failed: ' .. tostring(reload_err or 'unknown error'))
		end
		return
	elseif a == 'configstatus' then
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'export' then
			local p = windower.ffxi.get_player()
			local status = _G.UC_CONFIG_CONTRACT_STATUS
			if p and _G.UC_SETTINGS then
				local profile_key = tostring(p.name or '')
				if p.main_job ~= nil or p.sub_job ~= nil then
					profile_key = tostring(p.name or '') .. '|' .. tostring(p.main_job or '') .. '|' .. tostring(p.sub_job or '')
				end
				status = uc_update_config_contract_status({
					settings = _G.UC_SETTINGS,
					source = 'UC_SETTINGS',
					character = p.name,
					main_job = p.main_job,
					sub_job = p.sub_job,
					addon_path = uc_addon_path(),
					profile_key = profile_key,
					updated_at = uc_now_s(),
				})
			end
			local ok, path = uc_write_config_status_export(status, {
				character = p and p.name or nil,
				exported_at = uc_now_s(),
			})
			if ok then
				windower.add_to_chat(207, 'UC config status exported: ' .. tostring(path))
			else
				windower.add_to_chat(167, 'UC config status export failed')
			end
			return
		end
		windower.add_to_chat(207, '//uc configstatus export')
		return
	elseif a == 'smn' then
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'pettarget' then
			local op = args[3] and tostring(args[3]):lower() or 'status'
			local context = require('uc_scheduler_context')
			local status
			if op == 'start' then
				status = context.start_pet_target_diagnostic()
				windower.add_to_chat(207, 'UC SMN pet-target diagnostic started; fight normally, then use status or stop.')
			elseif op == 'stop' then
				status = context.stop_pet_target_diagnostic()
				windower.add_to_chat(207, 'UC SMN pet-target diagnostic stopped.')
			elseif op == 'status' then
				status = context.pet_target_diagnostic_status()
			else
				windower.add_to_chat(207, '//uc smn pettarget start|status|stop')
				return
			end
			windower.add_to_chat(207, ('UC SMN pet-target samples: active=%s total=%d pet=%d engaged=%d transitions=%d'):format(
				tostring(status.active == true),
				status.samples,
				status.pet_present_samples,
				status.pet_engaged_samples,
				status.transitions
			))
			windower.add_to_chat(207, ('UC SMN pet-target evidence: raw_index=%d resolved_id=%d same_current_target=%d engaged_no_index=%d engaged_no_id=%d'):format(
				status.nonzero_target_index_samples,
				status.resolved_target_id_samples,
				status.matching_current_target_samples,
				status.engaged_without_target_index_samples,
				status.engaged_without_target_id_samples
			))
			windower.add_to_chat(207, ('UC SMN pet-target current: pet=%s/%d status=%d raw_index=%d resolved_id=%d target_index=%d target_id=%d match=%s'):format(
				status.current_pet_name,
				status.current_pet_id,
				status.current_pet_status,
				status.current_pet_target_index,
				status.current_pet_target_id,
				status.current_target_index,
				status.current_target_id,
				tostring(status.current_matches_target == true)
			))
			local combat_status = rawget(_G, 'UC_SMN_PET_COMBAT_STATUS')
			if type(combat_status) == 'table' then
				if combat_status.state == 'ready' then
					local inferred_target_id = tonumber(combat_status.inferred_pet_target_id)
					local inferred_target_at = tonumber(combat_status.inferred_pet_target_at)
					local current_target_id = tonumber(combat_status.target_id)
					if inferred_target_id == nil or inferred_target_at == nil or current_target_id == nil then
						error('UC SMN ready combat status has invalid pet-action inference fields')
					end
					windower.add_to_chat(207, ('UC SMN pet-action inference: target_id=%d observed_at=%s current_target_id=%d match=%s'):format(
						inferred_target_id,
						tostring(inferred_target_at),
						current_target_id,
						tostring(inferred_target_id > 0 and inferred_target_id == current_target_id)
					))
				else
					windower.add_to_chat(207, 'UC SMN pet-action inference unavailable: combat state='
						.. tostring(combat_status.state))
				end
			end
			return
		end
		windower.add_to_chat(207, '//uc smn pettarget start|status|stop')
		return
	elseif a == 'brd' then
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'options' then
			local names, stats = require('uc_brd_song_options').collect(res, windower.ffxi.get_spells(), windower.ffxi.get_player())
			windower.add_to_chat(207, ('UC BRD options: %d eligible, %d learned, %d resources (BRD level %d)'):format(
				#names,
				stats.learned_song_count,
				stats.resource_song_count,
				stats.bard_level
			))
			if #names > 0 then
				windower.add_to_chat(207, table.concat(names, ' | '))
			end
			return
		end
		if sub == 'status' then
			for _, line in ipairs(require('uc_brd_maintenance').status_lines()) do
				windower.add_to_chat(207, line)
			end
			return
		end
		if sub == 'trace' and args[3] and tostring(args[3]):lower() == 'once' then
			require('uc_brd_maintenance').arm_trace_once()
			windower.add_to_chat(207, 'UC BRD trace armed for the next song transaction')
			return
		end
		if sub == 'capture' and args[3] and tostring(args[3]):lower() == 'once' then
			require('uc_brd_maintenance').arm_manual_capture_once()
			windower.add_to_chat(207, 'UC BRD passive capture armed for the next local general song')
			return
		end
		if sub == 'log' then
			local op = args[3] and tostring(args[3]):lower() or ''
			local brd = require('uc_brd_maintenance')
			if op == 'start' then
				local ok, path_or_error = brd.start_diagnostic_log()
				windower.add_to_chat(ok and 207 or 167, ok and ('UC BRD diagnostic log started: ' .. path_or_error)
					or ('UC BRD diagnostic log failed: ' .. path_or_error))
				return
			elseif op == 'stop' then
				windower.add_to_chat(207, 'UC BRD diagnostic log stopped: ' .. tostring(brd.stop_diagnostic_log()))
				return
			elseif op == 'status' then
				local enabled, path, log_error = brd.diagnostic_log_status()
				windower.add_to_chat(207, ('UC BRD diagnostic log: enabled=%s path=%s error=%s'):format(
					tostring(enabled), tostring(path), tostring(log_error)))
				return
			end
		end
		windower.add_to_chat(207, '//uc brd status | //uc brd options | //uc brd trace once | //uc brd capture once | //uc brd log start|stop|status')
		return
	elseif a == 'nyzul' then
		local sub = args[2] and tostring(args[2]):lower() or 'status'
		local ok, message
		if sub == 'begin' then
			ok, message = uc_nyzul_runtime.begin()
		elseif sub == 'park' then
			ok, message = uc_nyzul_runtime.park_next()
		elseif sub == 'regroup' then
			ok, message = uc_nyzul_runtime.regroup()
		elseif sub == 'undo' then
			ok, message = uc_nyzul_runtime.undo()
		elseif sub == 'end' or sub == 'finish' then
			ok, message = uc_nyzul_runtime.finish()
		elseif sub == 'status' then
			local status = uc_nyzul_runtime.status()
			local parked = #status.parked_order > 0 and table.concat(status.parked_order, ',') or 'none'
			local next_name = status.parking_order[status.next_index] or 'none'
			windower.add_to_chat(207, ('UC Nyzul: active=%s role=%s coordinator=%s anchor=%s parked=%s pending=%s next=%s'):format(
				tostring(status.active == true),
				tostring(status.role),
				tostring(status.coordinator_name ~= '' and status.coordinator_name or 'none'),
				tostring(status.anchor_name ~= '' and status.anchor_name or 'none'),
				parked,
				tostring(status.pending_park or 'none'),
				next_name
			))
			return
		else
			windower.add_to_chat(207, '//uc nyzul begin|park|regroup|undo|status|end')
			return
		end
		windower.add_to_chat(ok and 207 or 167, 'UC Nyzul: ' .. tostring(message))
		return
	elseif a == 'sch' then
		local scheduler = require('unified_scheduler')
		local sub = args[2] and tostring(args[2]):lower() or 'status'
		if sub == 'status' then
			local lines = scheduler.sch_maintenance_status_lines()
			for i = 1, #lines do
				windower.add_to_chat(207, lines[i])
			end
			return
		elseif sub == 'trace' and tostring(args[3] or ''):lower() == 'once' then
			local ok, message = scheduler.sch_maintenance_trace_once()
			windower.add_to_chat(ok and 207 or 167, 'UC SCH: ' .. tostring(message))
			return
		elseif sub == 'trace' and tostring(args[3] or ''):lower() == 'show' then
			local lines = scheduler.sch_maintenance_trace_lines()
			if type(lines) ~= 'table' then
				windower.add_to_chat(207, 'UC SCH: no transaction trace is available.')
				return
			end
			for i = 1, #lines do
				windower.add_to_chat(207, lines[i])
			end
			return
		elseif sub == 'capture' then
			if args[3] == nil then
				windower.add_to_chat(167, '//uc sch capture start <label>|mark <label>|status|stop')
				return
			end
			local capture_command = tostring(args[3]):lower()
			if capture_command == 'start' then
				if args[4] == nil or tostring(args[4]) == '' then
					windower.add_to_chat(167, 'UC SCH: capture start requires a label.')
					return
				end
				local ok, message, path = scheduler.sch_maintenance_capture_start(tostring(args[4]))
				windower.add_to_chat(ok and 207 or 167, 'UC SCH: ' .. tostring(message))
				if ok then
					windower.add_to_chat(207, 'UC SCH capture file: ' .. tostring(path))
				end
				return
			elseif capture_command == 'mark' then
				if args[4] == nil or tostring(args[4]) == '' then
					windower.add_to_chat(167, 'UC SCH: capture mark requires a label.')
					return
				end
				local ok, message = scheduler.sch_maintenance_capture_mark(tostring(args[4]))
				windower.add_to_chat(ok and 207 or 167, 'UC SCH: ' .. tostring(message))
				return
			elseif capture_command == 'status' then
				local capture_status = scheduler.sch_maintenance_capture_status()
				if capture_status.active == true then
					windower.add_to_chat(207, ('UC SCH capture active label=%s mark=%s traces=%d path=%s'):format(
						tostring(capture_status.label),
						tostring(capture_status.mark),
						tonumber(capture_status.trace_count),
						tostring(capture_status.path)
					))
				elseif type(capture_status.last) == 'table' then
					windower.add_to_chat(207, ('UC SCH capture inactive last=%s traces=%d'):format(
						tostring(capture_status.last.path),
						tonumber(capture_status.last.trace_count)
					))
				else
					windower.add_to_chat(207, 'UC SCH capture inactive; no completed session.')
				end
				return
			elseif capture_command == 'stop' then
				local ok, message, path = scheduler.sch_maintenance_capture_stop('operator_stop')
				windower.add_to_chat(ok and 207 or 167, 'UC SCH: ' .. tostring(message))
				if ok then
					windower.add_to_chat(207, 'UC SCH capture file: ' .. tostring(path))
				end
				return
			end
			windower.add_to_chat(167, '//uc sch capture start <label>|mark <label>|status|stop')
			return
		end
		windower.add_to_chat(207, '//uc sch status|trace once|trace show|capture start <label>|mark <label>|status|stop')
		return
	elseif a == 'geo' then
		local scheduler = require('unified_scheduler')
		local sub = args[2] and tostring(args[2]):lower() or 'status'
		if sub == 'status' then
			local status = scheduler.geo_maintenance_status()
			local sequence = status.sequence
			windower.add_to_chat(207, ('UC GEO: state=%s reason=%s detail=%s geo=%s indi=%s entrust=%s target=%d sequence=%s/%s atomic=%s bolster_armed=%s'):format(
				tostring(status.state or ''),
				tostring(status.reason or ''),
				tostring(status.detail or ''),
				tostring(status.owned_geo_spell or ''),
				tostring(status.owned_indi_spell or ''),
				tostring(status.owned_entrust_spell or ''),
				tonumber(status.owned_entrust_target_id) or 0,
				tostring(sequence and sequence.kind or 'none'),
				tostring(sequence and sequence.step or 'none'),
				tostring(sequence and sequence.atomic == true),
				tostring(status.bolster_armed == true)
			))
			return
		elseif sub == 'reseed' then
			local ok, message = scheduler.geo_maintenance_reseed()
			windower.add_to_chat(ok and 207 or 167, 'UC GEO: ' .. tostring(message))
			return
		elseif sub == 'bolster' then
			local operation = args[3] and tostring(args[3]):lower() or ''
			if operation == 'arm' then
				local ok, message = scheduler.geo_maintenance_arm_bolster(true)
				windower.add_to_chat(ok and 207 or 167, 'UC GEO: ' .. tostring(message))
				return
			elseif operation == 'disarm' then
				local ok, message = scheduler.geo_maintenance_arm_bolster(false)
				windower.add_to_chat(ok and 207 or 167, 'UC GEO: ' .. tostring(message))
				return
			end
		end
		windower.add_to_chat(207, '//uc geo status|reseed|bolster arm|bolster disarm')
		return
	elseif a == 'camp' then
		local sub = args[2] and tostring(args[2]):lower() or 'status'
		if sub == 'set' then
			local ok, message = uc_camp_anchor.set_current_position()
			windower.add_to_chat(ok and 207 or 167, 'UC camp: ' .. tostring(message))
			return
		elseif sub == 'clear' then
			local ok, message = uc_camp_anchor.clear_shared()
			windower.add_to_chat(ok and 207 or 167, 'UC camp: ' .. tostring(message))
			return
		elseif sub == 'status' then
			local status = uc_camp_anchor.status()
			if status.active then
				if status.coordinate_mode == 'xyz' then
					windower.add_to_chat(207, ('UC camp: state=active geometry=xyz zone=%d x=%.2f y=%.2f z=%.2f set_by=%s revision=%s source=%s'):format(
						status.zone_id,
						status.x,
						status.y,
						status.z,
						status.set_by,
						tostring(status.revision),
						status.source
					))
				elseif status.coordinate_mode == 'xy' then
					windower.add_to_chat(207, ('UC camp: state=active geometry=xy zone=%d x=%.2f y=%.2f z=unavailable set_by=%s revision=%s source=%s'):format(
						status.zone_id,
						status.x,
						status.y,
						status.set_by,
						tostring(status.revision),
						status.source
					))
				else
					error('active camp status has an invalid coordinate mode')
				end
			elseif status.known then
				windower.add_to_chat(207, ('UC camp: state=cleared zone=%d cleared_by=%s revision=%s source=%s'):format(
					status.zone_id,
					status.cleared_by,
					tostring(status.revision),
					status.source
				))
			else
				windower.add_to_chat(207, 'UC camp: state=unknown')
			end
			return
		elseif sub == 'pullstatus' then
			local status = require('unified_scheduler').camp_puller_status()
			windower.add_to_chat(207, ('UC camp puller: state=%s target=%d:%s reason=%s detail=%s intent=%s active=%d/%d tracked=%d foreign=%d orphaned=%d forfeited=%d camp=%.2f target_camp=%.2f cast/action=%.2f/%.2f crumbs=%d recovery=%d retry=%d cooldown=%.2f'):format(
				tostring(status.state or ''),
				tonumber(status.target_id) or 0,
				tostring(status.target_name or ''),
				tostring(status.reason or ''),
				tostring(status.detail or ''),
				tostring(status.last_intent or ''),
				tonumber(status.active_count) or 0,
				tonumber(status.quota) or 0,
				tonumber(status.tracked_count) or 0,
				tonumber(status.foreign_claimed_count) or 0,
				tonumber(status.orphaned_hostile_count) or 0,
				tonumber(status.forfeited_idle_count) or 0,
				tonumber(status.camp_distance) or -1,
				tonumber(status.target_camp_distance) or -1,
				tonumber(status.cast_range) or -1,
				tonumber(status.action_range) or -1,
				tonumber(status.breadcrumb_count) or 0,
				tonumber(status.recovery_count) or 0,
				tonumber(status.retry_count) or 0,
				tonumber(status.cooldown_until) or 0
			))
			return
		end
		windower.add_to_chat(207, '//uc camp set|clear|status|pullstatus')
		return
	elseif a == 'reaction' or a == 'reactions' then
		local sub = args[2] and tostring(args[2]):lower() or 'status'
		if sub == 'status' then
			local status = require('uc_reaction_runtime').status()
			windower.add_to_chat(207, ('UC reactions: enabled=%s rules=%d active=%d transition=%s'):format(
				tostring(status.enabled == true),
				tonumber(status.rule_count) or 0,
				type(status.active) == 'table' and #status.active or 0,
				tostring(status.last_transition or 'none')
			))
			for i = 1, #(status.active or {}) do
				local lock = status.active[i]
				local movement_detail = ''
				if require('uc_reaction_runtime').owns_movement(lock) then
					local current_distance = type(lock.current_distance) == 'number'
						and ('%.2f'):format(lock.current_distance) or 'unavailable'
					movement_detail = (' target_distance=%.2f current_distance=%s phase=%s'):format(
						lock.distance,
						current_distance,
						tostring(lock.run_away_phase or lock.move_to_range_phase or 'pending')
					)
				end
				windower.add_to_chat(207, ('  %s %s actor=%d response=%s%s'):format(
					tostring(lock.trigger or ''),
					tostring(lock.name or ''),
					tonumber(lock.actor_id) or 0,
					tostring(lock.response or ''),
					movement_detail
				))
			end
			if #(status.unresolved_enemy_buffs or {}) > 0 then
				windower.add_to_chat(167, 'UC reactions unresolved enemy buffs: ' .. table.concat(status.unresolved_enemy_buffs, ', '))
			end
			return
		end
		windower.add_to_chat(207, '//uc reactions status')
		return
	elseif a == 'formation' then
		local sub = args[2] and tostring(args[2]):lower() or 'status'
		if sub == 'status' then
			local runtime = rawget(_G, 'UC_FORMATION_STATUS')
			local encounter = require('uc_lilith_easy_encounter').status()
			local runtime_enabled = type(runtime) == 'table' and runtime.enabled == true
			local role = type(runtime) == 'table' and tostring(runtime.role or 'disabled') or 'disabled'
			local reason = type(runtime) == 'table' and tostring(runtime.reason or '') or ''
			local center_text = 'none'
			if type(encounter.center) == 'table' then
				center_text = ('%.3f,%.3f'):format(tonumber(encounter.center.x), tonumber(encounter.center.y))
			end
			windower.add_to_chat(207, ('UC formation: enabled=%s role=%s phase=%s reason=%s center=%s'):format(
				tostring(runtime_enabled), role, tostring(encounter.phase), reason, center_text
			))
			if type(runtime) == 'table' and tostring(runtime.error or '') ~= '' then
				windower.add_to_chat(167, 'UC formation error: ' .. tostring(runtime.error))
			end
			return
		end
		windower.add_to_chat(207, '//uc formation status')
		return
	elseif a == 'profilev2' then
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'export' then
			local p = windower.ffxi.get_player()
			local active_profile = uc_active_config.get_active_profile()
			if not p or not p.name or type(active_profile) ~= 'table' then
				uc_profile_v2_export_failure('missing player or active Profile V2')
				return
			end
			local meta = uc_profile_v2_meta(p, os.date('!%Y-%m-%dT%H:%M:%SZ'))
			meta.source = 'exported_from_active_profile'
			local ok_build, profile = pcall(uc_profile_v2.build_structured_profile_from_active_profile, active_profile, meta)
			if not ok_build or type(profile) ~= 'table' then
				uc_profile_v2_export_failure('profile build failed')
				return
			end
			local validation = uc_validate_structured_profile_export(profile)
			if validation == nil then
				uc_profile_v2_export_failure('contract unavailable')
				return
			end
			if validation.ok ~= true then
				uc_profile_v2_export_failure('contract validation failed')
				return
			end
			meta.profile_key = profile.profile and profile.profile.profile_key or nil
			meta.exported_at = profile.profile and profile.profile.exported_at or meta.exported_at
			local ok_write, path, write_reason = uc_write_profile_v2_export(profile, meta)
			if ok_write then
				windower.add_to_chat(207, 'UC profile v2 exported: ' .. tostring(path))
			else
				uc_profile_v2_export_failure(write_reason)
			end
			return
		elseif sub == 'validate' then
			local p = windower.ffxi.get_player()
			if not p or not p.name then
				windower.add_to_chat(167, 'UC profile v2 validation failed: missing player')
				return
			end
			local ok_validate, _, validate_err = uc_validate_profile_v2_file({
				character = p.name,
				main_job = p.main_job,
				sub_job = p.sub_job,
				addon_path = uc_addon_path(),
			})
			if ok_validate then
				windower.add_to_chat(207, 'UC profile v2 valid')
			else
				windower.add_to_chat(167, 'UC profile v2 validation failed: ' .. tostring(validate_err or 'unknown error'))
			end
			return
		elseif sub == 'diff' then
			local detail_mode = args[3] and tostring(args[3]):lower() == 'detail'
			local p = windower.ffxi.get_player()
			if not p or not p.name or not _G.UC_SETTINGS then
				windower.add_to_chat(167, 'UC profile v2 diff failed: missing player')
				return
			end
			if detail_mode then
				local ok_diff, _, diff_err, diff_result = uc_diff_profile_v2_detail_file({
					character = p.name,
					main_job = p.main_job,
					sub_job = p.sub_job,
					addon_path = uc_addon_path(),
				}, _G.UC_SETTINGS)
				if not ok_diff then
					windower.add_to_chat(167, 'UC profile v2 diff detail failed: ' .. tostring(diff_err or 'unknown error'))
				else
					local lines, lines_err = uc_profile_v2.format_structured_profile_diff_detail_lines(diff_result, 5)
					if type(lines) ~= 'table' then
						windower.add_to_chat(167, 'UC profile v2 diff detail failed: ' .. tostring(lines_err or 'unknown error'))
					else
						for i = 1, #lines do
							windower.add_to_chat(207, tostring(lines[i]))
						end
					end
				end
			else
				local ok_diff, _, diff_err, diff_count = uc_diff_profile_v2_file({
					character = p.name,
					main_job = p.main_job,
					sub_job = p.sub_job,
					addon_path = uc_addon_path(),
				}, _G.UC_SETTINGS)
				if not ok_diff then
					windower.add_to_chat(167, 'UC profile v2 diff failed: ' .. tostring(diff_err or 'unknown error'))
				elseif diff_count == 0 then
					windower.add_to_chat(207, 'UC profile v2 diff: no config differences')
				else
					windower.add_to_chat(207, 'UC profile v2 diff: ' .. tostring(diff_count) .. ' config differences')
				end
			end
			return
		elseif sub == 'status' then
			local p = windower.ffxi.get_player()
			if not p or not p.name then
				windower.add_to_chat(167, 'UC profile v2 status: missing player')
				return
			end
			if not _G.UC_SETTINGS then
				windower.add_to_chat(167, 'UC profile v2 status: missing settings')
				return
			end
			local status_result = uc_status_profile_v2_file({
				character = p.name,
				main_job = p.main_job,
				sub_job = p.sub_job,
				addon_path = uc_addon_path(),
			}, _G.UC_SETTINGS)
			if type(status_result) ~= 'table' or status_result.ok ~= true then
				if type(status_result) == 'table' and status_result.stage == 'read' then
					windower.add_to_chat(167, 'UC profile v2 status: ' .. tostring(status_result.error or 'read failed'))
				else
					local status_reason = type(status_result) == 'table' and (status_result.error or status_result.reason) or 'unknown error'
					windower.add_to_chat(167, 'UC profile v2 status: invalid: ' .. tostring(status_reason))
				end
			elseif status_result.count == 0 then
				windower.add_to_chat(207, 'UC profile v2 status: valid, runtime matches file')
			else
				windower.add_to_chat(207, 'UC profile v2 status: valid, ' .. tostring(status_result.count) .. ' config differences')
			end
			return
		elseif sub == 'autoreload' and args[3] and tostring(args[3]):lower() == 'status' then
			local p = windower.ffxi.get_player()
			if not p or not p.name then
				windower.add_to_chat(167, 'UC profile v2 autoreload status: missing player')
				return
			end
			if not _G.UC_SETTINGS then
				windower.add_to_chat(167, 'UC profile v2 autoreload status: missing settings')
				return
			end
			local status_result = uc_profile_v2_auto_reload_status({
				character = p.name,
				main_job = p.main_job,
				sub_job = p.sub_job,
				addon_path = uc_addon_path(),
			}, _G.UC_SETTINGS)
			if type(status_result) ~= 'table' then
				windower.add_to_chat(167, 'UC profile v2 autoreload status: invalid')
				return
			end
			local pending_since = status_result.pending_since and tostring(status_result.pending_since) or 'nil'
			local last_checked = status_result.last_checked_at and tostring(status_result.last_checked_at) or 'nil'
			local pending_hash = status_result.pending_hash and tostring(status_result.pending_hash) or 'nil'
			local last_hash = status_result.last_reported_hash and tostring(status_result.last_reported_hash) or 'nil'
			local last_error = status_result.last_error and tostring(status_result.last_error) or 'nil'
			windower.add_to_chat(
				207,
				'UC profile v2 autoreload status: automatic=true path=' .. tostring(status_result.path or 'unknown')
				.. ' pending=' .. tostring(status_result.pending_path or 'nil')
				.. ' pending_hash=' .. pending_hash
				.. ' pending_since=' .. pending_since
				.. ' last_hash=' .. last_hash
				.. ' last_checked=' .. last_checked
				.. ' last_error=' .. last_error
			)
			return
		elseif sub == 'apply' then
			local p = windower.ffxi.get_player()
			if not p or not p.name or not _G.UC_SETTINGS then
				windower.add_to_chat(167, 'UC profile v2 apply failed: missing player')
				return
			end
			local ok_apply, _, apply_err, apply_count = uc_apply_profile_v2_file({
				character = p.name,
				main_job = p.main_job,
				sub_job = p.sub_job,
				addon_path = uc_addon_path(),
			}, _G.UC_SETTINGS)
			if ok_apply then
				uc_profile_v2_auto_reload_note_applied({
					character = p.name,
					main_job = p.main_job,
					sub_job = p.sub_job,
					addon_path = uc_addon_path(),
				}, uc_profile_v2_session_key(p))
			end
			if not ok_apply then
				windower.add_to_chat(167, 'UC profile v2 apply failed: ' .. tostring(apply_err or 'unknown error'))
			elseif apply_count == 0 then
				windower.add_to_chat(207, 'UC profile v2 apply: no config differences')
			else
				windower.add_to_chat(207, 'UC profile v2 apply: ' .. tostring(apply_count) .. ' config differences applied')
			end
			return
		elseif sub == 'reload' then
			local p = windower.ffxi.get_player()
			if not p or not p.name then
				windower.add_to_chat(167, 'UC profile v2 reload failed: missing player')
				return
			end
			if not _G.UC_SETTINGS then
				windower.add_to_chat(167, 'UC profile v2 reload failed: missing settings')
				return
			end
			local ok_reload, _, reload_err, reload_count = uc_apply_profile_v2_file({
				character = p.name,
				main_job = p.main_job,
				sub_job = p.sub_job,
				addon_path = uc_addon_path(),
			}, _G.UC_SETTINGS)
			if ok_reload then
				uc_profile_v2_auto_reload_note_applied({
					character = p.name,
					main_job = p.main_job,
					sub_job = p.sub_job,
					addon_path = uc_addon_path(),
				}, uc_profile_v2_session_key(p))
			end
			if not ok_reload then
				windower.add_to_chat(167, 'UC profile v2 reload failed: ' .. tostring(reload_err or 'unknown error'))
			elseif reload_count == 0 then
				windower.add_to_chat(207, 'UC profile v2 reload: no config differences')
			else
				windower.add_to_chat(207, 'UC profile v2 reload: ' .. tostring(reload_count) .. ' config differences applied')
			end
			return
		end
		windower.add_to_chat(207, '//uc configstatus export | //uc profilev2 export | //uc profilev2 validate | //uc profilev2 diff | //uc profilev2 diff detail | //uc profilev2 status | //uc profilev2 autoreload status | //uc profilev2 apply | //uc profilev2 reload')
		return
	elseif a == 'host' and args[2] then
		_G.UC_REMOTE_HOST = tostring(args[2])
		windower.add_to_chat(207, 'UnifiedCombat remote host: ' .. _G.UC_REMOTE_HOST)
		return
	elseif a == 'port' and args[2] then
		_G.UC_REMOTE_PORT = tonumber(args[2]) or 27182
		windower.add_to_chat(207, 'UnifiedCombat remote port: ' .. tostring(_G.UC_REMOTE_PORT))
		return
	elseif a == 'runtime' or a == 'fingerprint' then
		local runtime_status = rawget(_G, 'UC_RUNTIME_FINGERPRINT')
		for _, line in ipairs(uc_runtime_bootstrap.status_lines(runtime_status)) do
			windower.add_to_chat(runtime_status and runtime_status.integrity_ok == false and 167 or 207, line)
		end
		return
	elseif a == 'engine' then
		windower.add_to_chat(207, 'UnifiedCombat engine: ' .. UC_ENGINE)
		return
	elseif a == 'fight_leader' or a == 'fightleader' then
		local s = _G.UC_SETTINGS
		if not s then
			return
		end
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'on' then
			s.fight_leader = true
			windower.add_to_chat(207, 'Fight leader: on')
			return
		elseif sub == 'off' then
			s.fight_leader = false
			windower.add_to_chat(207, 'Fight leader: off')
			return
		elseif sub == 'clear' then
			s.fight_leader_id = 0
			windower.add_to_chat(207, 'Fight leader: id cleared')
			return
		elseif args[2] then
			local nm = tostring(args[2])
			local pid = uc_fight_leader_party_id_by_name(nm)
			if pid == 0 then
				windower.add_to_chat(167, 'Fight leader: not in party: ' .. nm)
				return
			end
			s.fight_leader = true
			s.fight_leader_id = pid
			windower.add_to_chat(207, 'Fight leader set: ' .. nm)
			return
		end
		windower.add_to_chat(207, '//uc fight_leader on|off|clear|<party name>')
		return
	elseif a == 'add_priority' or a == 'addpriority' then
		local s = _G.UC_SETTINGS
		if not s then
			return
		end
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'clear' then
			s.add_priority_names = {}
			_G.UC_LAST_ADD_PRIORITY_OP = 'clear'
			windower.add_to_chat(207, 'Add priority list cleared (add control will stay on the fight leader target).')
			return
		elseif sub == 'list' then
			local arr = uc_add_priority.as_ordered_names(s)
			if #arr == 0 then
				windower.add_to_chat(207, 'Add priority list: (empty)')
			else
				for i, nm in ipairs(arr) do
					windower.add_to_chat(207, ('  %d. %s'):format(i, nm))
				end
			end
			return
		elseif sub == 'add' then
			local raw = table.concat(args, ' ', 3)
			local nm = type(raw) == 'string' and (raw:match('^%s*(.-)%s*$') or '') or ''
			if nm == '' then
				windower.add_to_chat(167, 'Add priority: need name after add')
				return
			end
			local ok, why = uc_add_priority.append_name(s, nm)
			if not ok then
				if why == 'ADD_PRIORITY_ALREADY' then
					windower.add_to_chat(167, 'Add priority: already listed: ' .. nm)
				else
					windower.add_to_chat(167, 'Add priority: could not add: ' .. tostring(why))
				end
				return
			end
			_G.UC_LAST_ADD_PRIORITY_OP = 'add:' .. nm
			windower.add_to_chat(207, 'Add priority appended: ' .. nm)
			return
		elseif sub == 'remove' and args[3] then
			local idx = tonumber(args[3])
			local ok, why = uc_add_priority.remove_index(s, idx)
			if not ok then
				windower.add_to_chat(167, 'Add priority remove failed: ' .. tostring(why) .. ' (use //uc add_priority list)')
				return
			end
			_G.UC_LAST_ADD_PRIORITY_OP = 'remove:' .. tostring(idx)
			windower.add_to_chat(207, 'Add priority removed index ' .. tostring(idx))
			return
		end
		windower.add_to_chat(207, '//uc add_priority add <mob name>|remove <n>|list|clear')
		return
	elseif a == 'sleep' then
		local s = _G.UC_SETTINGS
		if not s then
			return
		end
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'on' then
			s.sleep = true
			windower.add_to_chat(207, 'Sleep: on')
			return
		elseif sub == 'off' then
			s.sleep = false
			windower.add_to_chat(207, 'Sleep: off')
			return
		elseif sub == 'list' or sub == '' then
			windower.add_to_chat(207, 'Sleep: ' .. (uc_runtime_overrides.sleep_enabled(s) and 'on' or 'off'))
			for _, line in ipairs(uc_sleep_spell_list_lines(s)) do
				windower.add_to_chat(207, line)
			end
			return
		elseif sub == 'clear' then
			uc_sleep_spell.replace_names(s, {})
			windower.add_to_chat(207, 'Sleep spell list cleared')
			return
		elseif sub == 'set' or sub == 'spell' then
			local ok, why = uc_sleep_spell.replace_names(s, { table.concat(args, ' ', 3) })
			if not ok then
				if why == 'SLEEP_SPELL_UNKNOWN' then
					windower.add_to_chat(167, 'Sleep spell set failed: unknown spell')
				else
					windower.add_to_chat(167, 'Sleep spell set failed: ' .. tostring(why))
				end
				return
			end
			windower.add_to_chat(207, 'Sleep spell list set: ' .. tostring(s.sleepspell or ''))
			return
		elseif sub == 'add' then
			local raw = table.concat(args, ' ', 3)
			local spell_name = uc_normalize_sleep_spell_entry(raw)
			local ok, why = uc_sleep_spell.append_name(s, raw)
			if not ok then
				if why == 'SLEEP_SPELL_UNKNOWN' then
					windower.add_to_chat(167, 'Sleep spell add failed: unknown spell')
				elseif why == 'SLEEP_SPELL_ALREADY' then
					windower.add_to_chat(167, 'Sleep spell add failed: already listed')
				else
					windower.add_to_chat(167, 'Sleep spell add failed: ' .. tostring(why))
				end
				return
			end
			windower.add_to_chat(207, 'Sleep spell appended: ' .. spell_name)
			return
		elseif sub == 'remove' then
			local ok, why = uc_sleep_spell.remove_index(s, args[3])
			if not ok then
				windower.add_to_chat(167, 'Sleep spell remove failed: use //uc sleep list')
				return
			end
			windower.add_to_chat(207, 'Sleep spell removed index ' .. tostring(args[3]))
			return
		elseif sub == 'move' then
			local idx = tonumber(args[3])
			local dir = args[4] and tostring(args[4]):lower() or ''
			local delta = (dir == 'up') and -1 or ((dir == 'down') and 1 or nil)
			local ok, why = uc_sleep_spell.move_index(s, idx, delta)
			if not ok then
				windower.add_to_chat(167, 'Sleep spell move failed: ' .. tostring(why))
				return
			end
			windower.add_to_chat(207, 'Sleep spell moved index ' .. tostring(idx) .. ' ' .. dir)
			return
		end
		windower.add_to_chat(207, '//uc sleep on|off|list|clear|set <spell>|add <spell>|remove <n>|move <n> up|down')
		return
	end
	windower.add_to_chat(167, 'Unknown command.')
end)

windower.register_event('login', function()
	uc_update_engine()
	uc_begin_profile_v2_identity_transition()
	uc_register_action_listener()
	uc_camp_anchor.request_current_state()
end)
