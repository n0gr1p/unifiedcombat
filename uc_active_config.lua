local uc_config_normalizer = require('uc_config_normalizer')

local M = {}

local DURABLE_CONFIG_DOMAINS = {
	'ui',
	'command',
	'combat',
	'abilities',
	'defensive',
	'movement',
	'follow',
	'targeting',
	'reactions',
	'tank',
	'sleep',
	'spells',
	'maintenance',
	'debug',
	'ownership',
	'legacy',
}

local function trim_string(value)
	if type(value) ~= 'string' then
		return ''
	end
	return (value:match('^%s*(.-)%s*$') or '')
end

local function normalize_optional_string(value)
	local trimmed = trim_string(value)
	if trimmed == '' then
		return nil
	end
	return trimmed
end

local function normalize_string(value, default_value)
	local trimmed = trim_string(value)
	if trimmed == '' then
		return default_value
	end
	return trimmed
end

local function normalize_number(value, default_value, options)
	local number_value = tonumber(value)
	if number_value == nil then
		return default_value
	end
	if type(options) == 'table' and options.integer == true then
		number_value = math.floor(number_value)
	end
	return number_value
end

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		return {}
	end
	visited[value] = true
	local out = {}
	for key, inner_value in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner_value, visited)
	end
	visited[value] = nil
	return out
end

local function resolve_party_member_id_by_name(name)
	local trimmed = normalize_optional_string(name)
	if trimmed == nil then
		return 0
	end

	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	if type(ffxi) ~= 'table' then
		return 0
	end

	local get_party = ffxi.get_party
	if type(get_party) == 'function' then
		local ok_party, party = pcall(get_party)
		if ok_party and type(party) == 'table' then
			for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
				local entry = party[key]
				local mob = entry and entry.mob
				if mob and type(mob.name) == 'string' and mob.name == trimmed then
					local mob_id = tonumber(mob.id) or 0
					if mob_id > 0 then
						return mob_id
					end
				end
			end
		end
	end

	local get_mob_by_name = ffxi.get_mob_by_name
	if type(get_mob_by_name) == 'function' then
		local ok_mob, mob = pcall(get_mob_by_name, trimmed)
		if ok_mob and mob then
			local mob_id = tonumber(mob.id) or 0
			if mob_id > 0 then
				return mob_id
			end
		end
	end

	return 0
end

local function resolve_party_member_name_by_id(id)
	local member_id = normalize_number(id, 0, { integer = true }) or 0
	if member_id == 0 then
		return nil
	end

	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	if type(ffxi) ~= 'table' then
		return nil
	end

	local get_party = ffxi.get_party
	if type(get_party) == 'function' then
		local ok_party, party = pcall(get_party)
		if ok_party and type(party) == 'table' then
			for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
				local entry = party[key]
				local mob = entry and entry.mob
				if mob then
					local mob_id = tonumber(mob.id) or 0
					if mob_id == member_id then
						local name = normalize_optional_string(mob.name)
						if name ~= nil then
							return name
						end
					end
				end
			end
		end
	end

	return nil
end

local function resolve_party_member_ids_by_names(names)
	if type(names) ~= 'table' then
		return {}
	end
	local out = {}
	local seen = {}
	for i = 1, #names do
		local id = resolve_party_member_id_by_name(names[i])
		if id > 0 and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

local function resolve_party_member_names_by_ids(ids)
	if type(ids) ~= 'table' then
		return {}
	end
	local out = {}
	local seen = {}
	for i = 1, #ids do
		local name = resolve_party_member_name_by_id(ids[i])
		if type(name) == 'string' and name ~= '' then
			local key = name:lower()
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = name
			end
		end
	end
	return out
end

local function resolve_wait_ignore_names(settings)
	if type(settings) ~= 'table' then
		return {}
	end
	local wait_ignore_names = settings.wait_ignore_names
	if type(wait_ignore_names) == 'table' and #wait_ignore_names > 0 then
		return clone_value(wait_ignore_names)
	end
	local legacy_ids = settings.ignore
	if type(legacy_ids) == 'table' and #legacy_ids > 0 then
		return resolve_party_member_names_by_ids(legacy_ids)
	end
	return {}
end

local function resolve_profile_v2_auto_reload_on_change(settings)
	if type(settings) == 'table' and settings.profile_v2_auto_reload_on_change == true then
		return true
	end
	local ownership = type(settings) == 'table' and settings.ownership or nil
	if type(ownership) == 'table' and ownership.profile_v2_auto_reload_on_change == true then
		return true
	end
	return false
end

local function serialize_targeted_buffs(entries)
	local out = {}
	if type(entries) ~= 'table' then
		return ''
	end
	for i = 1, #entries do
		local entry = entries[i]
		if type(entry) == 'table' then
			local character = trim_string(entry.character or entry.target or entry.name)
			local buff = trim_string(entry.buff or entry.action)
			if character ~= '' and buff ~= '' then
				out[#out + 1] = character .. ':' .. buff
			end
		end
	end
	return table.concat(out, '|')
end

local function current_meta()
	local meta = {
		source = 'UC_SETTINGS',
	}
	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	local get_player = type(ffxi) == 'table' and ffxi.get_player or nil
	if type(get_player) ~= 'function' then
		return meta
	end
	local ok, player = pcall(get_player)
	if not ok or type(player) ~= 'table' then
		return meta
	end
	meta.character = player.name
	meta.main_job = player.main_job
	meta.sub_job = player.sub_job
	if player.name ~= nil then
		meta.profile_key = tostring(player.name)
		if player.main_job ~= nil or player.sub_job ~= nil then
			meta.profile_key = tostring(player.name) .. '|' .. tostring(player.main_job or '') .. '|' .. tostring(player.sub_job or '')
		end
	end
	return meta
end

local function resolve_meta(context, default_source)
	local meta = current_meta()
	local resolved_context = type(context) == 'table' and context or {}
	local fallback_source = normalize_string(default_source, 'UC_SETTINGS')
	meta.character = normalize_optional_string(resolved_context.character) or meta.character
	meta.main_job = normalize_optional_string(resolved_context.main_job) or meta.main_job
	meta.sub_job = normalize_optional_string(resolved_context.sub_job) or meta.sub_job
	meta.profile_key = normalize_optional_string(resolved_context.profile_key) or meta.profile_key
	meta.exported_at = normalize_optional_string(resolved_context.exported_at) or meta.exported_at
	meta.source = normalize_string(resolved_context.source, meta.source or fallback_source) or fallback_source
	return meta
end

local function pick_durable_config_domains(config)
	local out = {}
	if type(config) ~= 'table' then
		return out
	end
	for i = 1, #DURABLE_CONFIG_DOMAINS do
		local domain = DURABLE_CONFIG_DOMAINS[i]
		local value = config[domain]
		if type(value) == 'table' then
			out[domain] = clone_value(value)
		end
	end
	if type(out.targeting) == 'table' then
		out.targeting.ignore = nil
	end
	if type(out.reactions) == 'table'
		and out.reactions.enabled ~= true
		and type(out.reactions.rules) == 'table'
		and #out.reactions.rules == 0 then
		out.reactions = nil
	end
	if type(out.ownership) == 'table' and out.ownership.profile_v2_autoload ~= true then
		out.ownership.profile_v2_autoload = nil
	end
	if type(out.ownership) == 'table' and out.ownership.profile_v2_auto_reload_on_change ~= true then
		out.ownership.profile_v2_auto_reload_on_change = nil
	end
	return out
end

local function build_profile_record(profile_source, meta, default_source)
	local source_profile = type(profile_source) == 'table' and profile_source or {}
	local resolved_meta = resolve_meta(meta, default_source)
	local profile = clone_value(source_profile)
	profile.schema_version = 2
	profile.engine = normalize_string(profile.engine, 'UC')
	profile.character = normalize_optional_string(profile.character) or resolved_meta.character
	profile.main_job = normalize_optional_string(profile.main_job) or resolved_meta.main_job
	profile.sub_job = normalize_optional_string(profile.sub_job) or resolved_meta.sub_job
	profile.source = normalize_string(profile.source, resolved_meta.source)
	if resolved_meta.profile_key ~= nil and profile.profile_key == nil then
		profile.profile_key = resolved_meta.profile_key
	end
	if resolved_meta.exported_at ~= nil and profile.exported_at == nil then
		profile.exported_at = resolved_meta.exported_at
	end
	return profile
end

local function is_structured_profile(value)
	return type(value) == 'table' and value.version == 2 and type(value.profile) == 'table' and type(value.config) == 'table'
end

local function sync_table_in_place(target, source)
	if type(target) ~= 'table' or type(source) ~= 'table' then
		return false, 'tables required'
	end
	if target == source then
		return true
	end
	for key in pairs(target) do
		if source[key] == nil then
			target[key] = nil
		end
	end
	for key, value in pairs(source) do
		if type(value) == 'table' then
			if type(target[key]) ~= 'table' then
				target[key] = {}
			end
			local ok, err = sync_table_in_place(target[key], value)
			if ok ~= true then
				return false, err
			end
		else
			target[key] = value
		end
	end
	return true
end

local function apply_structured_config_to_candidate(candidate, config)
	if type(candidate) ~= 'table' or type(config) ~= 'table' then
		return false, 'candidate and config must be tables'
	end

	if type(config.ui) == 'table' then
		candidate.show_ingame_ui = config.ui.show_ingame_ui
	end

	if type(config.combat) == 'table' then
		candidate.domain_combat_enabled = config.combat.enabled
		candidate.autotarget = config.combat.autotarget
		candidate.spam = config.combat.spam
		candidate.closer = config.combat.closer
		candidate.manual = config.combat.manual
		candidate.prime = config.combat.prime
		candidate.static = config.combat.static
		candidate.face = config.combat.face
		if type(config.combat.weaponskill) == 'table' then
			candidate.weaponskill_active = config.combat.weaponskill.enabled
			candidate.weaponskill = config.combat.weaponskill.primary
			candidate.ws1 = config.combat.weaponskill.primary
			candidate.ws_mode = config.combat.weaponskill.mode
			candidate.wait_ignore_names = clone_value(config.combat.weaponskill.wait_ignore_names)
			candidate.aftermath_enabled = config.combat.weaponskill.aftermath_enabled
			candidate.aftermath_ws = config.combat.weaponskill.aftermath_ws
			candidate.ignore = resolve_party_member_ids_by_names(config.combat.weaponskill.wait_ignore_names)
		end
	end

	if type(config.abilities) == 'table' then
		candidate.ability_active = config.abilities.enabled
		candidate.abilities = clone_value(config.abilities.configured)
		candidate.wsabilities = clone_value(config.abilities.wsabilities)
		local legacy_slots = type(config.abilities.legacy_slots) == 'table' and config.abilities.legacy_slots or {}
		for i = 1, 6 do
			candidate['ability' .. tostring(i)] = legacy_slots[i]
		end
	end

	if type(config.defensive) == 'table' then
		candidate.defensive_enabled = config.defensive.enabled
		candidate.defensive_provider = config.defensive.provider
		if type(config.defensive.cure) == 'table' then
			candidate.defensive_cure_enabled = config.defensive.cure.enabled
			candidate.def_heal_min_tier_cure = config.defensive.cure.min_tier
			candidate.def_heal_max_tier_cure = config.defensive.cure.max_tier
			candidate.def_heal_min_missing_hp = config.defensive.cure.min_missing_hp
			candidate.def_heal_ignore_trusts = config.defensive.cure.ignore_trusts
		end
		if type(config.defensive.doom) == 'table' then
			candidate.defensive_doom_water = config.defensive.doom.holy_water_enabled
		end
		if type(config.defensive.na) == 'table' then
			candidate.defensive_na_enabled = config.defensive.na.enabled
		end
		if type(config.defensive.enemy_buffs) == 'table' then
			candidate.def_remove_enemy_buffs = config.defensive.enemy_buffs.remove
		end
		if type(config.defensive.buffs) == 'table' then
			candidate.defensive_buff_enabled = config.defensive.buffs.enabled
			candidate.defensive_buff_self_only = config.defensive.buffs.self_only
			candidate.defensive_buffs = config.defensive.buffs.list
			candidate.defensive_targeted_buffs = serialize_targeted_buffs(config.defensive.buffs.targeted)
			candidate.defensive_overwrite_enabled = config.defensive.buffs.overwrite_enabled
			candidate.defensive_overwrite_interval = config.defensive.buffs.overwrite_interval
		end
		if type(config.defensive.thresholds) == 'table' then
			candidate.defensive_critical_hpp = config.defensive.thresholds.critical_hpp
			candidate.defensive_medium_hpp = config.defensive.thresholds.medium_hpp
		end
	end

	if type(config.movement) == 'table' then
		candidate.domain_movement_enabled = config.movement.enabled
		candidate.move = config.movement.move
		if type(config.movement.spacing) == 'table' then
			candidate.spacing = config.movement.spacing.enabled
			candidate.spacing_band_min = config.movement.spacing.band_min
			candidate.spacing_band_max = config.movement.spacing.band_max
			candidate.spacing_model_size_floor = config.movement.spacing.model_size_floor
			candidate.spacing_use_prediction = config.movement.spacing.use_prediction
			candidate.spacing_lookahead_s = config.movement.spacing.lookahead_s
			candidate.spacing_repel_hold_ticks = config.movement.spacing.repel_hold_ticks
			candidate.spacing_overlap_deadband = config.movement.spacing.overlap_deadband
			candidate.spacing_repel_weight = config.movement.spacing.repel_weight
			candidate.spacing_band_deadband = config.movement.spacing.band_deadband
		end
		if type(config.movement.path) == 'table' then
			candidate.path_recording = config.movement.path.recording
			candidate.path_follow_enabled = config.movement.path.follow_enabled
			candidate.path_file_name = config.movement.path.file_name
			candidate.path_route_type = config.movement.path.route_type
			candidate.path_distance_to_start = config.movement.path.distance_to_start
			candidate.path_points = clone_value(config.movement.path.points)
			candidate.path_party_gate_yalms = config.movement.path.party_gate_yalms
			candidate.path_resume_index_window = config.movement.path.resume_index_window
			candidate.path_hunter_targets = clone_value(config.movement.path.hunter_targets)
			candidate.path_hunter_max_z_delta = config.movement.path.hunter_max_z_delta
			candidate.path_hunter_max_target_range = config.movement.path.hunter_max_target_range
			candidate.path_hunter_claim_timeout_s = config.movement.path.hunter_claim_timeout_s
			candidate.path_hunter_ignore_cooldown_s = config.movement.path.hunter_ignore_cooldown_s
			candidate.path_pull_action_type = config.movement.path.pull_action_type
			candidate.path_pull_action_name = config.movement.path.pull_action_name
		end
	end

	if type(config.follow) == 'table' then
		candidate.domain_follow_enabled = config.follow.enabled
		if type(config.follow.party) == 'table' then
			candidate.party_follow = config.follow.party.enabled
			candidate.party_follow_id = config.follow.party.leader_id
			candidate.party_follow_leader_name = config.follow.party.leader_name
			candidate.party_follow_min = config.follow.party.min
			candidate.party_follow_max = config.follow.party.max
		end
		if type(config.follow.fight) == 'table' then
			candidate.fight_leader = config.follow.fight.leader
			candidate.fight_leader_selected = config.follow.fight.leader_name
			candidate.fight_leader_name = config.follow.fight.leader_name
			local fight_leader_id = resolve_party_member_id_by_name(config.follow.fight.leader_name)
			if fight_leader_id == 0 then
				fight_leader_id = normalize_number(config.follow.fight.leader_id, 0, { integer = true }) or 0
			end
			candidate.fight_leader_id = fight_leader_id
			candidate.fight_follow_min = config.follow.fight.min
			candidate.fight_follow_hold_s = config.follow.fight.hold_s
		end
		if type(config.follow.partner) == 'table' then
			candidate.partner = config.follow.partner.enabled
			candidate.partner2 = config.follow.partner.secondary_enabled
			candidate.partner_ids = clone_value(config.follow.partner.ids)
			candidate.partner_id = candidate.partner_ids[1] or 0
			candidate.partner_id2 = candidate.partner_ids[2] or 0
			candidate.puller = config.follow.partner.puller
			candidate.puller_name = config.follow.partner.puller_name
			candidate.follow = candidate.follow or {}
			candidate.follow.enabled = config.follow.enabled
			candidate.follow.party = {
				enabled = config.follow.party and config.follow.party.enabled or nil,
				leader_id = config.follow.party and config.follow.party.leader_id or nil,
				leader_name = config.follow.party and config.follow.party.leader_name or nil,
				min = config.follow.party and config.follow.party.min or nil,
				max = config.follow.party and config.follow.party.max or nil,
			}
			candidate.follow.fight = {
				leader = config.follow.fight and config.follow.fight.leader or nil,
				leader_selected = config.follow.fight and config.follow.fight.leader_name or nil,
				leader_name = config.follow.fight and config.follow.fight.leader_name or nil,
				leader_id = config.follow.fight and config.follow.fight.leader_id or nil,
				min = config.follow.fight and config.follow.fight.min or nil,
				hold_s = config.follow.fight and config.follow.fight.hold_s or nil,
			}
			candidate.follow.fight.leader_name = config.follow.fight.leader_name
			local fight_leader_id = resolve_party_member_id_by_name(config.follow.fight.leader_name)
			if fight_leader_id == 0 then
				fight_leader_id = normalize_number(config.follow.fight.leader_id, 0, { integer = true }) or 0
			end
			candidate.follow.fight.leader_id = fight_leader_id
			candidate.fight_leader_name = config.follow.fight.leader_name
			candidate.fight_leader_id = fight_leader_id
			candidate.follow.partner = {
				enabled = config.follow.partner.enabled,
				secondary_enabled = config.follow.partner.secondary_enabled,
				ids = clone_value(config.follow.partner.ids),
				puller = config.follow.partner.puller,
				puller_name = config.follow.partner.puller_name,
				puller_distance_only = config.follow.partner.puller_distance_only,
			}
			local puller_id = resolve_party_member_id_by_name(config.follow.partner.puller_name)
			if puller_id == 0 then
				puller_id = normalize_number(config.follow.partner.puller_id, 0, { integer = true }) or 0
			end
			candidate.puller_id = puller_id
			candidate.follow.partner.puller_id = puller_id
			candidate.puller_distance_only = config.follow.partner.puller_distance_only
			candidate.follow.partner.puller_distance_only = config.follow.partner.puller_distance_only
		end
		if type(config.follow.fight) == 'table' then
			candidate.follow = candidate.follow or {}
			candidate.follow.enabled = config.follow.enabled
			candidate.follow.fight = {
				leader = config.follow.fight.leader,
				leader_selected = config.follow.fight.leader_name,
				leader_name = config.follow.fight.leader_name,
				leader_id = candidate.fight_leader_id,
				min = config.follow.fight.min,
				hold_s = config.follow.fight.hold_s,
			}
		end
	end

	if type(config.targeting) == 'table' then
		candidate.add_control = config.targeting.add_control
		local target_priority_names = config.targeting.targets
		if type(target_priority_names) == 'table' and #target_priority_names == 0 then
			target_priority_names = nil
		end
		if target_priority_names == nil then
			target_priority_names = config.targeting.add_priority_names
		end
		candidate.add_priority_names = clone_value(target_priority_names)
		candidate.targets = clone_value(target_priority_names)
		if type(config.targeting.targetability) == 'table' then
			candidate.targetability_active = config.targeting.targetability.enabled
			candidate.targetability = config.targeting.targetability.action
		end
		candidate.target_ignore_names = clone_value(config.targeting.target_ignore_names)
		local legacy_targets = type(config.targeting.legacy_slots) == 'table' and config.targeting.legacy_slots or {}
		for i = 1, 3 do
			candidate['target' .. tostring(i)] = legacy_targets[i]
		end
	end

	if type(config.reactions) == 'table' then
		candidate.reaction_enabled = config.reactions.enabled
		candidate.reaction_rules = clone_value(config.reactions.rules)
	else
		candidate.reaction_enabled = false
		candidate.reaction_rules = {}
	end

	if type(config.tank) == 'table' then
		candidate.tank = config.tank.enabled
		if type(config.tank.enmity) == 'table' then
			candidate.tank_enmity_actions = clone_value(config.tank.enmity.actions)
		end
	end

	if type(config.sleep) == 'table' then
		candidate.sleep = config.sleep.enabled
		candidate.sleepspells = clone_value(config.sleep.order)
		candidate.sleepspell = config.sleep.legacy_primary
	end

	if type(config.spells) == 'table' then
		candidate.spell_active = config.spells.enabled
		candidate.spell = config.spells.configured
		candidate.dd2_spell_slots = clone_value(config.spells.dd2_slots)
	end

	if type(config.maintenance) == 'table' then
		candidate.domain_maintenance_enabled = config.maintenance.enabled
		if type(config.maintenance.cor) == 'table' then
			candidate.cor_roll_1 = config.maintenance.cor.roll_1
			candidate.cor_roll_2 = config.maintenance.cor.roll_2
			candidate.cor_crooked_roll_slot = config.maintenance.cor.crooked_roll_slot
			candidate.cor_elevens = config.maintenance.cor.elevens
			candidate.cor_luzaf_range_override = config.maintenance.cor.luzaf_range_override
			candidate.cor_roll_range_selected = config.maintenance.cor.range_selected
			candidate.cor_roll_range_require_ids = clone_value(config.maintenance.cor.range_require_ids)
		end
		if type(config.maintenance.brd) == 'table' then
			candidate.maintenance_brd = clone_value(config.maintenance.brd)
			candidate.brd_maintenance_enabled = config.maintenance.brd.enabled
			candidate.brd_songs = clone_value(config.maintenance.brd.songs)
			candidate.brd_dummy_songs = clone_value(config.maintenance.brd.dummy_songs)
			candidate.brd_use_nitro = config.maintenance.brd.use_nitro
			candidate.brd_use_clarion_call = config.maintenance.brd.use_clarion_call
			candidate.brd_use_marcato = config.maintenance.brd.use_marcato
			candidate.brd_marcato_song = config.maintenance.brd.marcato_song
		end
		candidate.maintenance_geo = clone_value(config.maintenance.geo)
	end

	if type(config.debug) == 'table' then
		candidate.debug = config.debug.enabled
		candidate.log_combat_sched = config.debug.combat_sched
		candidate.log_ja_sched = config.debug.ja_sched
		candidate.log_ja_debug = config.debug.ja_debug
		candidate.log_def_sched = config.debug.def_sched
		candidate.log_tank_sched = config.debug.tank_sched
	end

	if type(config.ownership) == 'table' then
        candidate.domain_combat_enabled = config.ownership.domain_combat_enabled
        candidate.domain_defensive_enabled = config.ownership.domain_defensive_enabled
        candidate.domain_movement_enabled = config.ownership.domain_movement_enabled
        candidate.domain_maintenance_enabled = config.ownership.domain_maintenance_enabled
        candidate.domain_follow_enabled = config.ownership.domain_follow_enabled
        candidate.scheduler_dark_launch_combat = config.ownership.scheduler_dark_launch_combat
        candidate.scheduler_dark_launch_defensive = config.ownership.scheduler_dark_launch_defensive
        candidate.scheduler_dark_launch_movement = config.ownership.scheduler_dark_launch_movement
        candidate.scheduler_dark_launch_maintenance = config.ownership.scheduler_dark_launch_maintenance
        if config.ownership.profile_v2_auto_reload_on_change == true then
            candidate.profile_v2_auto_reload_on_change = true
        else
            candidate.profile_v2_auto_reload_on_change = nil
        end
        if config.ownership.profile_v2_autoload == true then
            candidate.profile_v2_autoload = true
        else
            candidate.profile_v2_autoload = nil
        end
    end

	if type(config.legacy) == 'table' then
		candidate.sub = config.legacy.sub
		candidate.sub2 = config.legacy.sub2
		candidate.solo = config.legacy.solo
		candidate.aeonic = config.legacy.aeonic
		candidate.color = config.legacy.color
		candidate.command = config.legacy.command
		candidate.hunter = config.legacy.hunter
		candidate.profiles = clone_value(config.legacy.profiles)
	end

	return true
end

function M.build_active_profile_from_settings(settings, context)
	local meta = resolve_meta(context, 'UC_SETTINGS')
	local normalized = uc_config_normalizer.normalize(settings, meta)
	if type(normalized.combat) == 'table' and type(normalized.combat.weaponskill) == 'table' then
		normalized.combat.weaponskill.wait_ignore_names = resolve_wait_ignore_names(settings)
	end
	if type(normalized.ownership) == 'table' then
		normalized.ownership.profile_v2_auto_reload_on_change = resolve_profile_v2_auto_reload_on_change(settings)
	end
	local profile = build_profile_record(normalized.profile, meta, 'UC_SETTINGS')
	return {
		version = 2,
		profile = profile,
		config = pick_durable_config_domains(normalized),
	}
end

function M.build_active_profile_from_v2_payload(payload, context)
	if type(payload) ~= 'table' then
		return nil, 'structured profile payload must be a table'
	end
	if payload.version ~= 2 then
		return nil, 'structured profile version must be 2'
	end
	if type(payload.profile) ~= 'table' then
		return nil, 'structured profile metadata missing'
	end
	if type(payload.config) ~= 'table' then
		return nil, 'structured profile config missing'
	end

	local meta = resolve_meta(context, 'UC_PROFILE_V2')
	local profile = build_profile_record(payload.profile, meta, 'UC_PROFILE_V2')
	local active_profile = {
		version = 2,
		profile = profile,
		config = pick_durable_config_domains(payload.config),
	}
	return active_profile
end

local function clean_active_profile_durable_config(active_profile)
	if type(active_profile) ~= 'table' then
		return
	end
	local config = active_profile.config
	if type(config) ~= 'table' then
		return
	end
	if type(config.ownership) == 'table' then
		if config.ownership.profile_v2_autoload ~= true then
			config.ownership.profile_v2_autoload = nil
		end
		if config.ownership.profile_v2_auto_reload_on_change ~= true then
			config.ownership.profile_v2_auto_reload_on_change = nil
		end
	end
end

function M.get_active_profile()
	local active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	if is_structured_profile(active_profile) then
		return active_profile
	end
	return nil
end

function M.set_active_profile(active_profile)
	if not is_structured_profile(active_profile) then
		return false, 'active profile must be a structured v2 table'
	end
	local current = rawget(_G, 'UC_ACTIVE_PROFILE')
	if not is_structured_profile(current) then
		_G.UC_ACTIVE_PROFILE = clone_value(active_profile)
		clean_active_profile_durable_config(_G.UC_ACTIVE_PROFILE)
		return true, _G.UC_ACTIVE_PROFILE
	end
	local ok, err = sync_table_in_place(current, active_profile)
	if ok ~= true then
		return false, err
	end
	clean_active_profile_durable_config(current)
	return true, current
end

function M.initialize_active_profile(settings, context)
	local active_profile = M.build_active_profile_from_settings(settings, context)
	return M.set_active_profile(active_profile)
end

function M.get_config()
	local active_profile = M.get_active_profile()
	if type(active_profile) ~= 'table' then
		return nil
	end
	return active_profile.config
end

function M.get_domain(domain_name)
	local config = M.get_config()
	if type(config) ~= 'table' then
		return nil
	end
	return config[domain_name]
end

local function normalize_path(path)
	if type(path) == 'table' then
		return path
	end
	if type(path) ~= 'string' then
		return nil
	end
	local segments = {}
	for segment in path:gmatch('[^%./]+') do
		if segment ~= '' then
			segments[#segments + 1] = segment
		end
	end
	if #segments == 0 then
		return nil
	end
	return segments
end

function M.get_path(path, default_value)
	local segments = normalize_path(path)
	if type(segments) ~= 'table' then
		return default_value
	end
	local current = M.get_active_profile()
	for i = 1, #segments do
		if type(current) ~= 'table' then
			return default_value
		end
		current = current[segments[i]]
		if current == nil then
			return default_value
		end
	end
	return current
end

function M.project_flat_settings(active_profile, base_settings)
	if not is_structured_profile(active_profile) then
		return nil, 'active profile must be a structured v2 table'
	end
	if type(base_settings) ~= 'table' then
		return nil, 'base settings must be a table'
	end
	local candidate = clone_value(base_settings)
	local ok, err = apply_structured_config_to_candidate(candidate, active_profile.config)
	if ok ~= true then
		return nil, err
	end
	return candidate
end

function M.sync_flat_settings_in_place(target_settings, projected_settings)
	if type(target_settings) ~= 'table' then
		return false, 'target settings must be a table'
	end
	if type(projected_settings) ~= 'table' then
		return false, 'projected settings must be a table'
	end
	local ok, err = sync_table_in_place(target_settings, projected_settings)
	if ok ~= true then
		return false, err
	end
	return true
end

return M
