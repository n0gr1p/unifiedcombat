local uc_config_normalizer = require('uc_config_normalizer')
local uc_sch_config = require('uc_sch_config')
local uc_pup_config = require('uc_pup_config')

local M = {}

local DURABLE_CONFIG_DOMAINS = {
	'ui',
	'command',
	'combat',
	'abilities',
	'defensive',
	'encounter',
	'movement',
	'follow',
	'targeting',
	'reactions',
	'tank',
	'sleep',
	'spells',
	'maintenance',
	'summoner',
	'puppetmaster',
	'sch',
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

local function serialize_brd_targeted_songs(entries)
	local out = {}
	for i = 1, #(entries or {}) do
		local entry = entries[i]
		if type(entry) == 'table' then
			out[#out + 1] = table.concat(entry.recipients or {}, ',') .. ':'
				.. table.concat(entry.priority_songs or {}, ',')
		end
	end
	return table.concat(out, '|')
end

local function summoner_ward_actions(ward)
	if ward.actions ~= nil and ward.action ~= nil then
		return nil, 'config.summoner.maintenance.ward must define actions or legacy action, not both'
	end
	if ward.actions == nil then
		if ward.action == nil or ward.action == '' then
			return {}, nil
		end
		if type(ward.action) ~= 'string' then
			return nil, 'config.summoner.maintenance.ward.action must be a string or nil'
		end
		return { ward.action }, nil
	end
	if type(ward.actions) ~= 'table' then
		return nil, 'config.summoner.maintenance.ward.actions must be an array of strings'
	end
	local count = 0
	for key in pairs(ward.actions) do
		count = count + 1
		if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then
			return nil, 'config.summoner.maintenance.ward.actions must be a contiguous array'
		end
	end
	if count ~= #ward.actions then
		return nil, 'config.summoner.maintenance.ward.actions must be a contiguous array'
	end
	local actions = {}
	local seen = {}
	for i = 1, #ward.actions do
		local action = ward.actions[i]
		if type(action) ~= 'string' or action == '' then
			return nil, 'config.summoner.maintenance.ward.actions entries must be non-empty strings'
		end
		if seen[action] then
			return nil, ('config.summoner.maintenance.ward.actions duplicates %q'):format(action)
		end
		seen[action] = true
		actions[#actions + 1] = action
	end
	return actions, nil
end

local function serialize_sch_storm_assignments(assignments)
	local out = {}
	for i = 1, #(assignments or {}) do
		local assignment = assignments[i]
		out[#out + 1] = tostring(assignment.spell) .. ':' .. table.concat(assignment.targets, ',')
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

local function pick_durable_config_domains(config, meta)
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
	if type(out.encounter) == 'table' and out.encounter.enabled ~= true then
		out.encounter = nil
	end
	if type(out.ownership) == 'table' then
		out.ownership.profile_v2_autoload = nil
		out.ownership.profile_v2_auto_reload_on_change = nil
	end
	local main_job = type(meta) == 'table' and meta.main_job or nil
	if main_job == nil and type(config.profile) == 'table' then
		main_job = config.profile.main_job
	end
	if type(main_job) ~= 'string' or main_job:upper() ~= 'PUP' then
		out.puppetmaster = nil
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

local function normalize_defensive_compatibility(config)
	if type(config.defensive) ~= 'table' then
		return true
	end
	local defensive = config.defensive

	local resurrection = defensive.resurrection
	if resurrection == nil then
		-- Profiles captured before resurrection support existed must remain valid.
		-- Treat the missing subdomain as the feature's safe default rather than
		-- inheriting a newer live session's resurrection settings.
		defensive.resurrection = {
			enabled = false,
			priority = { 'Arise', 'Raise III', 'Raise II', 'Raise' },
		}
	elseif type(resurrection) ~= 'table' then
		return false, 'config.defensive.resurrection must be a table'
	else
		if resurrection.enabled == nil then
			resurrection.enabled = false
		elseif type(resurrection.enabled) ~= 'boolean' then
			return false, 'config.defensive.resurrection.enabled must be a boolean'
		end
		if resurrection.priority == nil then
			resurrection.priority = { 'Arise', 'Raise III', 'Raise II', 'Raise' }
		elseif type(resurrection.priority) ~= 'table' then
			return false, 'config.defensive.resurrection.priority must be a table'
		else
			for i = 1, #resurrection.priority do
				if type(resurrection.priority[i]) ~= 'string' then
					return false, 'config.defensive.resurrection.priority entries must be strings'
				end
			end
		end
	end

	if type(defensive.cure) == 'table' then
		local curaga = defensive.cure.curaga
		if curaga == nil then
			defensive.cure.curaga = {
				enabled = false,
				min_targets = 3,
			}
		elseif type(curaga) ~= 'table' then
			return false, 'config.defensive.cure.curaga must be a table'
		else
			if curaga.enabled == nil then
				curaga.enabled = false
			elseif type(curaga.enabled) ~= 'boolean' then
				return false, 'config.defensive.cure.curaga.enabled must be a boolean'
			end
			if curaga.min_targets == nil then
				curaga.min_targets = 3
			elseif type(curaga.min_targets) ~= 'number'
				or curaga.min_targets % 1 ~= 0
				or curaga.min_targets < 2
				or curaga.min_targets > 6 then
				return false, 'config.defensive.cure.curaga.min_targets must be an integer from 2 to 6'
			end
		end
	end

	local waltz = defensive.waltz
	if waltz == nil then
		defensive.waltz = {
			enabled = false,
			tp_reserve = 0,
			divine_min_targets = 3,
		}
	elseif type(waltz) ~= 'table' then
		return false, 'config.defensive.waltz must be a table'
	else
		if waltz.enabled == nil then
			waltz.enabled = false
		elseif type(waltz.enabled) ~= 'boolean' then
			return false, 'config.defensive.waltz.enabled must be a boolean'
		end
		if waltz.tp_reserve == nil then
			waltz.tp_reserve = 0
		elseif type(waltz.tp_reserve) ~= 'number'
			or waltz.tp_reserve % 1 ~= 0
			or waltz.tp_reserve < 0
			or waltz.tp_reserve > 3000 then
			return false, 'config.defensive.waltz.tp_reserve must be an integer from 0 to 3000'
		end
		if waltz.divine_min_targets == nil then
			waltz.divine_min_targets = 3
		elseif type(waltz.divine_min_targets) ~= 'number'
			or waltz.divine_min_targets % 1 ~= 0
			or waltz.divine_min_targets < 2
			or waltz.divine_min_targets > 6 then
			return false, 'config.defensive.waltz.divine_min_targets must be an integer from 2 to 6'
		end
	end

	local enemy_debuffs = defensive.enemy_debuffs
	if enemy_debuffs == nil then
		defensive.enemy_debuffs = {
			enabled = false,
			list = '',
		}
		return true
	end
	if type(enemy_debuffs) ~= 'table' then
		return false, 'config.defensive.enemy_debuffs must be a table'
	end
	if enemy_debuffs.enabled == nil then
		enemy_debuffs.enabled = false
	elseif type(enemy_debuffs.enabled) ~= 'boolean' then
		return false, 'config.defensive.enemy_debuffs.enabled must be a boolean'
	end
	if enemy_debuffs.list == nil then
		enemy_debuffs.list = ''
	elseif type(enemy_debuffs.list) ~= 'string' then
		return false, 'config.defensive.enemy_debuffs.list must be a string'
	end
	return true
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

local function optional_summoner_gate(offensive, enabled_key, value_key, path, default_value, maximum)
	local enabled = offensive[enabled_key]
	local value = offensive[value_key]
	if enabled == nil and value == nil then
		return false, default_value
	end
	if type(enabled) ~= 'boolean' then
		return nil, nil, path .. '_enabled must be boolean'
	end
	if type(value) ~= 'number' or value % 1 ~= 0 or value < 0 or value > maximum then
		return nil, nil, ('%s must be an integer from 0 to %d'):format(path, maximum)
	end
	return enabled, value
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
		candidate.auto_engage = config.combat.auto_engage
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
			candidate.weaponskill_min_tp = config.combat.weaponskill.minimum_tp
			candidate.weaponskill_allow_aoe = config.combat.weaponskill.allow_aoe
			candidate.fast_skillchain = config.combat.weaponskill.fast_skillchain
			candidate.weaponskill_no_skillchain_targets = clone_value(config.combat.weaponskill.no_skillchain_targets)
			candidate.skillchain_target = config.combat.weaponskill.skillchain_target
			candidate.wait_ignore_names = clone_value(config.combat.weaponskill.wait_ignore_names)
			candidate.aftermath_enabled = config.combat.weaponskill.aftermath_enabled
			candidate.aftermath_ws = config.combat.weaponskill.aftermath_ws
			candidate.ignore = resolve_party_member_ids_by_names(config.combat.weaponskill.wait_ignore_names)
		end
		if type(config.combat.pulling) == 'table' then
			candidate.camp_pulling = clone_value(config.combat.pulling)
		end
	end

	if type(config.abilities) == 'table' then
		candidate.ability_active = config.abilities.enabled
		candidate.ability_allow_unengaged = config.abilities.allow_unengaged
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
		if type(config.defensive.resurrection) == 'table' then
			candidate.defensive_resurrection_enabled = config.defensive.resurrection.enabled
			candidate.defensive_resurrection_priority = clone_value(config.defensive.resurrection.priority)
		end
		if type(config.defensive.cure) == 'table' then
			candidate.defensive_cure_enabled = config.defensive.cure.enabled
			candidate.def_heal_min_tier_cure = config.defensive.cure.min_tier
			candidate.def_heal_max_tier_cure = config.defensive.cure.max_tier
			candidate.def_heal_min_missing_hp = config.defensive.cure.min_missing_hp
			candidate.def_heal_ignore_trusts = config.defensive.cure.ignore_trusts
			if type(config.defensive.cure.curaga) == 'table' then
				candidate.defensive_curaga_enabled = config.defensive.cure.curaga.enabled
				candidate.defensive_curaga_min_targets = config.defensive.cure.curaga.min_targets
			end
		end
		if type(config.defensive.waltz) == 'table' then
			candidate.defensive_waltz_enabled = config.defensive.waltz.enabled
			candidate.defensive_waltz_tp_reserve = config.defensive.waltz.tp_reserve
			candidate.defensive_divine_waltz_min_targets = config.defensive.waltz.divine_min_targets
		end
		if type(config.defensive.doom) == 'table' then
			candidate.defensive_doom_water = config.defensive.doom.holy_water_enabled
		end
		if type(config.defensive.charm_sleeper) == 'table' then
			candidate.def_charm_sleeper_enabled = config.defensive.charm_sleeper.enabled
		end
		if type(config.defensive.sleep_waker) == 'table' then
			candidate.def_sleep_waker_enabled = config.defensive.sleep_waker.enabled
		end
		if type(config.defensive.na) == 'table' then
			candidate.defensive_na_enabled = config.defensive.na.enabled
			candidate.defensive_na_limit_enabled = config.defensive.na.limit_enabled
			candidate.defensive_na_priority = config.defensive.na.priority
		end
		if type(config.defensive.enemy_buffs) == 'table' then
			candidate.def_remove_enemy_buffs = config.defensive.enemy_buffs.remove
		end
		if type(config.defensive.enemy_debuffs) == 'table' then
			candidate.def_maintain_enemy_debuffs = config.defensive.enemy_debuffs.enabled
			candidate.defensive_enemy_debuffs = config.defensive.enemy_debuffs.list
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

	if type(config.encounter) == 'table' then
		local encounter = config.encounter
		local definition = require('uc_encounter_registry').get(encounter.id)
		if encounter.enabled == true and definition == nil and encounter.id ~= 'kei' then
			error('enabled config.encounter has an unsupported id')
		end
		candidate.encounter_enabled = encounter.enabled == true
		candidate.encounter_id = encounter.id
		if encounter.id == 'kei' and encounter.enabled == true then
			candidate.encounter_water_damage = nil
			candidate.encounter_water_skillchain = nil
			candidate.encounter_repeat_action_wall = nil
			candidate.encounter_repeat_action_guard_s = nil
			if type(encounter.kei) ~= 'table' or type(encounter.kei.elemental_damage) ~= 'table' then
				error('enabled Kei encounter is missing elemental configuration')
			end
			local elemental = encounter.kei.elemental_damage
			if type(elemental.water) ~= 'table' or type(elemental.ice) ~= 'table' then
				error('enabled Kei encounter is missing water or ice configuration')
			end
			candidate.kei_elemental_dealer_name = elemental.dealer_name
			candidate.kei_water_probe_spell = elemental.water.probe_spell
			candidate.kei_water_damage_spell = elemental.water.damage_spell
			candidate.kei_ice_probe_spell = elemental.ice.probe_spell
			candidate.kei_ice_damage_spell = elemental.ice.damage_spell
			candidate.kei_sustain_interval_s = elemental.sustain_interval_s
			candidate.kei_probe_timeout_s = elemental.probe_timeout_s
			if type(encounter.kei.fullers) ~= 'table' then
				error('enabled Kei encounter is missing Fullers configuration')
			end
			candidate.kei_fullers_target_distance = encounter.kei.fullers.target_distance
			candidate.kei_fullers_prearm_hpp_margin = encounter.kei.fullers.prearm_hpp_margin
		elseif definition ~= nil then
			local policy = type(encounter.policy) == 'table' and encounter.policy or {}
			local tuning = type(encounter.tuning) == 'table' and encounter.tuning or {}
			candidate.encounter_water_damage = policy.water_damage or definition.policy.water_damage
			candidate.encounter_water_skillchain = policy.water_skillchain or definition.policy.water_skillchain
			candidate.encounter_repeat_action_wall = policy.repeat_action_wall or definition.policy.repeat_action_wall
			candidate.encounter_repeat_action_guard_s = tuning.repeat_action_guard_s or definition.tuning.repeat_action_guard_s
		end
	else
		candidate.encounter_enabled = false
		candidate.encounter_id = 'sortie_ghatjot'
		candidate.encounter_water_damage = 'enforce'
		candidate.encounter_water_skillchain = 'enforce'
		candidate.encounter_repeat_action_wall = 'off'
		candidate.encounter_repeat_action_guard_s = 10.0
		candidate.kei_elemental_dealer_name = ''
		candidate.kei_water_probe_spell = 'Water'
		candidate.kei_water_damage_spell = 'Water III'
		candidate.kei_ice_probe_spell = 'Blizzard'
		candidate.kei_ice_damage_spell = 'Blizzard III'
		candidate.kei_sustain_interval_s = 2.5
		candidate.kei_probe_timeout_s = 3.0
		candidate.kei_fullers_target_distance = 12.0
		candidate.kei_fullers_prearm_hpp_margin = 1.0
	end

	if type(config.movement) == 'table' then
		candidate.domain_movement_enabled = config.movement.enabled
		candidate.move = config.movement.move
		if type(config.movement.named_formations) == 'table' then
			local named_formations = config.movement.named_formations
			if type(named_formations.entries) ~= 'table' then
				error('config.movement.named_formations.entries must be a table')
			end
			candidate.named_formations_enabled = named_formations.enabled
			candidate.named_formation_entries = {}
			for i = 1, #named_formations.entries do
				local entry = named_formations.entries[i]
				local placement = entry.placement
				local constraints = entry.constraints
				local axis = placement.axis or {}
				candidate.named_formation_entries[#candidate.named_formation_entries + 1] = {
					mob_name = entry.mob_name,
					formation_placement_mode = placement.mode,
					formation_anchor = placement.anchor,
					formation_anchor_member = placement.anchor_member,
					formation_axis_type = axis.type,
					formation_axis_member = axis.member,
					formation_preferred_radius = placement.preferred_radius,
					formation_minimum_radius = placement.minimum_radius,
					formation_maximum_radius = placement.maximum_radius,
					formation_preferred_angle_deg = placement.preferred_angle_deg,
					formation_allowed_angle_half_width_deg = placement.allowed_angle_half_width_deg,
					formation_radius_step = placement.radius_step,
					formation_angle_step_deg = placement.angle_step_deg,
					formation_hysteresis_start_distance = entry.hysteresis.start_distance,
					formation_hysteresis_stop_distance = entry.hysteresis.stop_distance,
					formation_avoid_encounter_hazards = constraints.avoid_encounter_hazards,
					formation_hazard_margin = constraints.hazard_margin,
					formation_safe_origin_radius = constraints.safe_origin_radius or 0,
					formation_minimum_boss_distance = constraints.minimum_boss_distance or 0,
					formation_maximum_boss_distance = constraints.maximum_boss_distance or 0,
					formation_maximum_party_range = constraints.maximum_party_range or 0,
					formation_required_party_names = table.concat(constraints.required_party_names or {}, '|'),
				}
			end
		else
			candidate.named_formations_enabled = false
			candidate.named_formation_entries = {}
		end
		if type(config.movement.formation) == 'table' then
			local formation = config.movement.formation
			candidate.formation_enabled = formation.enabled
			candidate.formation_encounter = formation.encounter
			if type(formation.mock) == 'table' then
				candidate.formation_mock_enabled = formation.mock.enabled
				candidate.formation_mock_mob_name = formation.mock.mob_name
			else
				candidate.formation_mock_enabled = false
				candidate.formation_mock_mob_name = ''
			end
			candidate.formation_role = formation.role
			candidate.formation_tank_name = formation.tank_name
			candidate.formation_required_party_names = clone_value(formation.required_party_names)
			candidate.formation_capture_stable_s = formation.capture_stable_s
			candidate.formation_capture_tolerance = formation.capture_tolerance
			candidate.formation_safe_radius = formation.safe_radius
			if type(formation.tank) == 'table' then
				candidate.formation_tank_accept_radius = formation.tank.accept_radius
				candidate.formation_tank_return_radius = formation.tank.return_radius
			end
			if type(formation.dps) == 'table' then
				candidate.formation_dps_flank_angle_deg = formation.dps.flank_angle_deg
				candidate.formation_dps_melee_radius = formation.dps.melee_radius
				candidate.formation_dps_position_tolerance = formation.dps.position_tolerance
			end
			if type(formation.healer) == 'table' then
				candidate.formation_healer_preferred_radius = formation.healer.preferred_radius
				candidate.formation_healer_minimum_boss_distance = formation.healer.minimum_boss_distance
				candidate.formation_healer_maximum_party_range = formation.healer.maximum_party_range
				candidate.formation_healer_cone_half_angle_deg = formation.healer.cone_half_angle_deg
				candidate.formation_healer_cone_safety_margin_deg = formation.healer.cone_safety_margin_deg
				candidate.formation_healer_sample_step_deg = formation.healer.sample_step_deg
			end
			if type(formation.placement) == 'table' then
				local placement = formation.placement
				candidate.formation_placement_mode = placement.mode
				candidate.formation_anchor = placement.anchor
				candidate.formation_anchor_member = placement.anchor_member
				candidate.formation_preferred_radius = placement.preferred_radius
				candidate.formation_minimum_radius = placement.minimum_radius
				candidate.formation_maximum_radius = placement.maximum_radius
				candidate.formation_preferred_angle_deg = placement.preferred_angle_deg
				candidate.formation_allowed_angle_half_width_deg = placement.allowed_angle_half_width_deg
				candidate.formation_radius_step = placement.radius_step
				candidate.formation_angle_step_deg = placement.angle_step_deg
				if type(placement.axis) == 'table' then
					candidate.formation_axis_type = placement.axis.type
					candidate.formation_axis_member = placement.axis.member
				end
			end
			if type(formation.hysteresis) == 'table' then
				candidate.formation_hysteresis_start_distance = formation.hysteresis.start_distance
				candidate.formation_hysteresis_stop_distance = formation.hysteresis.stop_distance
			end
			if type(formation.constraints) == 'table' then
				local constraints = formation.constraints
				candidate.formation_avoid_encounter_hazards = constraints.avoid_encounter_hazards
				candidate.formation_hazard_margin = constraints.hazard_margin
				candidate.formation_safe_origin_radius = constraints.safe_origin_radius
				candidate.formation_minimum_boss_distance = constraints.minimum_boss_distance
				candidate.formation_maximum_boss_distance = constraints.maximum_boss_distance
				candidate.formation_maximum_party_range = constraints.maximum_party_range
				if type(constraints.required_party_names) == 'table' then
					candidate.formation_required_party_names = clone_value(constraints.required_party_names)
				end
			end
		else
			candidate.formation_enabled = false
			candidate.formation_mock_enabled = false
			candidate.formation_mock_mob_name = ''
		end
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
			local leash_source = config.follow.partner.leash_source
			if leash_source == nil then
				leash_source = 'player'
			elseif leash_source ~= 'player' and leash_source ~= 'camp' then
				error('follow.partner.leash_source must be player or camp')
			end
			candidate.partner = config.follow.partner.enabled
			candidate.partner2 = config.follow.partner.secondary_enabled
			local durable_partner_names = config.follow.partner.names
			if durable_partner_names == nil then
				durable_partner_names = {}
			elseif type(durable_partner_names) ~= 'table' then
				error('durable partner names must be a list')
			end
			candidate.partner_names = clone_value(durable_partner_names)
			if #candidate.partner_names > 0 then
				candidate.partner_ids = resolve_party_member_ids_by_names(candidate.partner_names)
			else
				local legacy_partner_ids = config.follow.partner.ids
				if legacy_partner_ids == nil then
					legacy_partner_ids = {}
				elseif type(legacy_partner_ids) ~= 'table' then
					error('legacy partner ids must be a list')
				end
				candidate.partner_ids = clone_value(legacy_partner_ids)
			end
			candidate.partner_id = candidate.partner_ids[1] or 0
			candidate.partner_id2 = candidate.partner_ids[2] or 0
			candidate.puller = config.follow.partner.puller
			candidate.puller_name = config.follow.partner.puller_name
			candidate.puller_leash_source = leash_source
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
				names = clone_value(config.follow.partner.names),
				ids = clone_value(candidate.partner_ids),
				puller = config.follow.partner.puller,
				puller_name = config.follow.partner.puller_name,
				leash_source = leash_source,
				engage_range = config.follow.partner.engage_range,
				puller_distance_only = config.follow.partner.puller_distance_only,
			}
			local puller_id = 0
			if leash_source == 'player' then
				puller_id = resolve_party_member_id_by_name(config.follow.partner.puller_name)
				if puller_id == 0 then
					puller_id = normalize_number(config.follow.partner.puller_id, 0, { integer = true }) or 0
				end
			end
			candidate.puller_id = puller_id
			candidate.follow.partner.puller_id = puller_id
			candidate.puller_engage_range = config.follow.partner.engage_range
			candidate.puller_distance_only = config.follow.partner.puller_distance_only
			candidate.follow.partner.puller_distance_only = config.follow.partner.puller_distance_only
		end
		if type(config.follow.nyzul) == 'table' then
			candidate.nyzul_coordinator_name = config.follow.nyzul.coordinator_name
			candidate.nyzul_anchor_name = config.follow.nyzul.anchor_name
			candidate.nyzul_parking_order = clone_value(config.follow.nyzul.parking_order)
			candidate.follow = candidate.follow or {}
			candidate.follow.nyzul = {
				coordinator_name = config.follow.nyzul.coordinator_name,
				anchor_name = config.follow.nyzul.anchor_name,
				parking_order = clone_value(config.follow.nyzul.parking_order),
			}
		else
			candidate.nyzul_coordinator_name = nil
			candidate.nyzul_anchor_name = nil
			candidate.nyzul_parking_order = nil
			if type(candidate.follow) == 'table' then
				candidate.follow.nyzul = nil
			end
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
			candidate.tank_enmity_include_pets = config.tank.enmity.include_pets == true
		end
		if type(config.tank.run) == 'table' then
			candidate.tank_run = clone_value(config.tank.run)
		end
	end

	if type(config.sleep) == 'table' then
		candidate.sleep = config.sleep.enabled
		candidate.sleepspells = clone_value(config.sleep.order)
		candidate.sleepspell = config.sleep.legacy_primary
		candidate.sleep_max_target_range = config.sleep.max_target_range
	end

	if type(config.spells) == 'table' then
		candidate.spell_active = config.spells.enabled
		candidate.spell = config.spells.configured
		candidate.magic_burst_enabled = config.spells.magic_burst
		candidate.magic_burst_mode = config.spells.magic_burst_mode
		candidate.magic_burst_family = config.spells.magic_burst_family
		candidate.magic_burst_max_tier = config.spells.magic_burst_max_tier
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
			candidate.cor_light_shot_dia = config.maintenance.cor.light_shot_dia
			candidate.cor_roll_range_selected = config.maintenance.cor.range_selected
			candidate.cor_roll_range_require_ids = clone_value(config.maintenance.cor.range_require_ids)
		end
		if type(config.maintenance.brd) == 'table' then
			candidate.maintenance_brd = clone_value(config.maintenance.brd)
			candidate.brd_maintenance_enabled = config.maintenance.brd.enabled
			candidate.brd_songs = clone_value(config.maintenance.brd.songs)
			candidate.brd_dummy_songs = clone_value(config.maintenance.brd.dummy_songs)
			candidate.brd_recovery_range_yalms = config.maintenance.brd.recovery_range_yalms
			candidate.brd_recovery_ignore_names = clone_value(config.maintenance.brd.recovery_ignore_names)
			candidate.brd_reposition_for_party_songs = config.maintenance.brd.reposition_for_party_songs
			candidate.brd_use_nitro = config.maintenance.brd.use_nitro
			candidate.brd_use_soul_voice = config.maintenance.brd.use_soul_voice
			candidate.brd_use_clarion_call = config.maintenance.brd.use_clarion_call
			candidate.brd_use_marcato = config.maintenance.brd.use_marcato
			candidate.brd_marcato_song = config.maintenance.brd.marcato_song
			candidate.brd_targeted_songs = serialize_brd_targeted_songs(config.maintenance.brd.targeted_songs)
		end
		candidate.maintenance_geo = clone_value(config.maintenance.geo)
	end

	if type(config.summoner) == 'table' then
		local summoner = config.summoner
		if type(summoner.enabled) ~= 'boolean' then
			return false, 'config.summoner.enabled must be boolean'
		end
		if summoner.avatar ~= nil and type(summoner.avatar) ~= 'string' then
			return false, 'config.summoner.avatar must be a string or nil'
		end
		if type(summoner.maintenance) ~= 'table' then
			return false, 'config.summoner.maintenance must be a table'
		end
		local maintenance = summoner.maintenance
		if type(maintenance.avatar_favor) ~= 'boolean' then
			return false, 'config.summoner.maintenance.avatar_favor must be boolean'
		end
		if type(maintenance.ward) ~= 'table' then
			return false, 'config.summoner.maintenance.ward must be a table'
		end
		local ward = maintenance.ward
		if type(ward.enabled) ~= 'boolean' then
			return false, 'config.summoner.maintenance.ward.enabled must be boolean'
		end
		local ward_actions, ward_actions_error = summoner_ward_actions(ward)
		if ward_actions_error ~= nil then
			return false, ward_actions_error
		end
		if type(summoner.pet_combat) ~= 'table' then
			return false, 'config.summoner.pet_combat must be a table'
		end
		local pet_combat = summoner.pet_combat
		if type(pet_combat.engage_on_combat_start) ~= 'boolean' then
			return false, 'config.summoner.pet_combat.engage_on_combat_start must be boolean'
		end
		if type(pet_combat.offensive_action) ~= 'table' then
			return false, 'config.summoner.pet_combat.offensive_action must be a table'
		end
		local offensive = pet_combat.offensive_action
		if type(offensive.enabled) ~= 'boolean' then
			return false, 'config.summoner.pet_combat.offensive_action.enabled must be boolean'
		end
		if offensive.action ~= nil and type(offensive.action) ~= 'string' then
			return false, 'config.summoner.pet_combat.offensive_action.action must be a string or nil'
		end
		if type(offensive.usage) ~= 'string' then
			return false, 'config.summoner.pet_combat.offensive_action.usage must be a string'
		end
		local target_hpp_enabled, target_hpp_above, target_hpp_error = optional_summoner_gate(
			offensive,
			'target_hpp_above_enabled',
			'target_hpp_above',
			'config.summoner.pet_combat.offensive_action.target_hpp_above',
			50,
			99
		)
		if target_hpp_error ~= nil then
			return false, target_hpp_error
		end
		local pet_tp_enabled, pet_tp_above, pet_tp_error = optional_summoner_gate(
			offensive,
			'pet_tp_above_enabled',
			'pet_tp_above',
			'config.summoner.pet_combat.offensive_action.pet_tp_above',
			2000,
			2999
		)
		if pet_tp_error ~= nil then
			return false, pet_tp_error
		end

		candidate.summoner_enabled = summoner.enabled
		candidate.summoner_avatar = summoner.avatar
		if candidate.summoner_avatar == nil then
			candidate.summoner_avatar = ''
		end
		candidate.summoner_avatar_favor = maintenance.avatar_favor
		candidate.summoner_ward_enabled = ward.enabled
		candidate.summoner_ward_actions = table.concat(ward_actions, '|')
		candidate.summoner_ward_action = ward_actions[1] or ''
		candidate.summoner_engage_on_combat_start = pet_combat.engage_on_combat_start
		candidate.summoner_rage_enabled = offensive.enabled
		candidate.summoner_rage_action = offensive.action
		if candidate.summoner_rage_action == nil then
			candidate.summoner_rage_action = ''
		end
		candidate.summoner_rage_usage = offensive.usage
		candidate.summoner_rage_target_hpp_above_enabled = target_hpp_enabled
		candidate.summoner_rage_target_hpp_above = target_hpp_above
		candidate.summoner_rage_pet_tp_above_enabled = pet_tp_enabled
		candidate.summoner_rage_pet_tp_above = pet_tp_above
	end

	if type(config.puppetmaster) == 'table' then
		local puppetmaster, validation = uc_pup_config.copy_validated(config.puppetmaster, config.profile)
		if puppetmaster == nil or validation.valid ~= true then
			local first = validation and validation.errors and validation.errors[1]
			return false, first and first.message or 'config.puppetmaster is invalid'
		end
		candidate.puppetmaster = clone_value(puppetmaster)
		candidate.puppetmaster_enabled = puppetmaster.enabled
		candidate.puppetmaster_activate_if_missing = puppetmaster.activate_if_missing
		candidate.puppetmaster_deploy_on_combat_start = puppetmaster.deploy_on_combat_start
		candidate.puppetmaster_maneuvers_enabled = puppetmaster.maneuvers.enabled
		candidate.puppetmaster_maneuver_pattern = table.concat(puppetmaster.maneuvers.pattern, '|')
		candidate.puppetmaster_post_activate_quiet_seconds = puppetmaster.maneuvers.post_activate_quiet_seconds
		candidate.puppetmaster_safe_burden_ceiling = puppetmaster.maneuvers.safe_burden_ceiling
	else
		candidate.puppetmaster = nil
		candidate.puppetmaster_enabled = false
	end

	if type(config.sch) == 'table' then
		local validation = uc_sch_config.validate(config.sch)
		if validation.valid ~= true then
			local first = validation.errors[1]
			return false, first and first.message or 'config.sch is invalid'
		end
		local sch = uc_sch_config.copy_validated(config.sch)
		candidate.sch = clone_value(sch)
		candidate.sch_enabled = sch.enabled
		candidate.sch_arts_minimum_commit_s = sch.arts.minimum_commit_s
		candidate.sch_arts_emergency_off_art_casts = sch.arts.emergency_off_art_casts
		candidate.sch_regen_enabled = sch.support.regen.enabled
		candidate.sch_accession_perpetuance_spells = table.concat(sch.support.regen.spells, '|')
		candidate.sch_regen_minimum_coverage = sch.support.regen.minimum_coverage
		candidate.sch_regen_refresh_before_s = sch.support.regen.refresh_before_s
		candidate.sch_storms_enabled = sch.support.storms.enabled
		candidate.sch_storm_assignments = serialize_sch_storm_assignments(sch.support.storms.assignments)
		candidate.sch_storms_refresh_before_s = sch.support.storms.refresh_before_s
		candidate.sch_sublimation_enabled = sch.sublimation.enabled
		candidate.sch_sublimation_release_when_mpp_at_most = sch.sublimation.release_when_mpp_at_most
		candidate.sch_sublimation_release_when_complete = sch.sublimation.release_when_complete
		candidate.sch_sublimation_minimum_hpp_to_activate = sch.sublimation.minimum_hpp_to_activate
		candidate.sch_accession_cure_enabled = sch.defensive.accession_cure.enabled
		candidate.sch_accession_status_removal_enabled = sch.defensive.accession_status_removal.enabled
		candidate.sch_rapture_enabled = sch.defensive.rapture.enabled
		candidate.sch_penury_enabled = sch.defensive.penury.enabled
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
        candidate.pause_automation_while_weakened = config.ownership.pause_automation_while_weakened == true
        candidate.profile_v2_auto_reload_on_change = nil
        candidate.profile_v2_autoload = nil
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
	local profile = build_profile_record(normalized.profile, meta, 'UC_SETTINGS')
	return {
		version = 2,
		profile = profile,
		config = pick_durable_config_domains(normalized, profile),
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
	local config = pick_durable_config_domains(payload.config, profile)
	local defensive_ok, defensive_err = normalize_defensive_compatibility(config)
	if defensive_ok ~= true then
		return nil, defensive_err
	end
	local pup_validation = uc_pup_config.validate(config.puppetmaster, profile)
	if pup_validation.valid ~= true then
		local first = pup_validation.errors[1]
		return nil, first and first.message or 'Puppetmaster configuration is invalid'
	end
	if type(config.puppetmaster) == 'table' then
		config.puppetmaster = uc_pup_config.copy_validated(config.puppetmaster, profile)
	end
	local sch_validation = uc_sch_config.validate(config.sch, profile)
	if sch_validation.valid ~= true then
		local first = sch_validation.errors[1]
		return nil, first and first.message or 'Scholar configuration is invalid'
	end
	if type(config.sch) == 'table' then
		config.sch = uc_sch_config.copy_validated(config.sch, profile)
	end
	local compatibility_source = {}
	if type(config.combat) == 'table' then
		compatibility_source.combat = {
			pulling = config.combat.pulling,
			weaponskill = config.combat.weaponskill,
		}
	end
	if type(config.maintenance) == 'table' then
		compatibility_source.maintenance = {
			geo = config.maintenance.geo,
		}
	end
	if next(compatibility_source) ~= nil then
		local ok_normalized, normalized_or_err = pcall(uc_config_normalizer.normalize, compatibility_source, meta)
		if ok_normalized ~= true then
			return nil, tostring(normalized_or_err)
		end
		if type(config.combat) == 'table' then
			config.combat.pulling = clone_value(normalized_or_err.combat.pulling)
			config.combat.weaponskill = clone_value(normalized_or_err.combat.weaponskill)
		end
		if type(config.maintenance) == 'table' then
			config.maintenance.geo = clone_value(normalized_or_err.maintenance.geo)
		end
	end
	if type(config.maintenance) == 'table' and type(config.maintenance.brd) == 'table' then
		local brd = config.maintenance.brd
		if brd.recovery_range_yalms == nil then
			brd.recovery_range_yalms = 9.9
		end
		if brd.recovery_ignore_names == nil then
			brd.recovery_ignore_names = {}
		end
	end
	local active_profile = {
		version = 2,
		profile = profile,
		config = config,
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
		config.ownership.profile_v2_autoload = nil
		config.ownership.profile_v2_auto_reload_on_change = nil
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
	-- The projected result is the legacy flat settings view. Canonical config
	-- sources left by a previous job would take precedence over these mirrors
	-- when the candidate is normalized, so they must not survive replacement.
	candidate.config = nil
	for i = 1, #DURABLE_CONFIG_DOMAINS do
		candidate[DURABLE_CONFIG_DOMAINS[i]] = nil
	end
	candidate.sch_sublimation_activate_when_mpp_at_least = nil
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
