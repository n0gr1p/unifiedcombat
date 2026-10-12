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

local function normalize_maintenance_compatibility(config)
	if type(config.maintenance) ~= 'table' then
		return
	end
	-- Profiles written before food maintenance existed already own the
	-- maintenance domain, but have no food subtree. Treat the missing leaf as
	-- the canonical disabled default so projection replaces stale live food
	-- settings instead of inheriting them from the current session.
	if config.maintenance.food == nil then
		config.maintenance.food = {
			enabled = false,
			item = '',
		}
	end
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

local function compact_job_default_abilities(defaults)
	local out = {}
	if type(defaults) ~= 'table' then
		return out
	end
	for i = 1, 6 do
		local value = normalize_optional_string(defaults['ability' .. tostring(i)])
		if value ~= nil then
			out[#out + 1] = value
		end
	end
	return out
end

function M.build_default_active_profile(context, job_defaults)
	local resolved_context = type(context) == 'table' and context or {}
	local meta = resolve_meta(resolved_context, 'UC_DEFAULTS')
	meta.source = normalize_string(resolved_context.source, 'UC_DEFAULTS')
	local config = uc_config_normalizer.default_config(meta)
	if type(config) ~= 'table' then
		return nil, 'canonical default config builder returned invalid result'
	end

	if type(config.command) == 'table' then
		config.command.engine_enabled_default = resolved_context.engine_enabled == true
	end

	local job_key = normalize_optional_string(resolved_context.job_for_defaults) or meta.main_job
	if type(job_key) == 'string' then
		job_key = job_key:upper()
	end
	local defaults = type(job_defaults) == 'table' and job_defaults[job_key] or nil
	if type(defaults) == 'table' then
		local primary_ws = normalize_optional_string(defaults.ws1 or defaults.weaponskill)
		if primary_ws ~= nil
			and type(config.combat) == 'table'
			and type(config.combat.weaponskill) == 'table' then
			config.combat.weaponskill.primary = primary_ws
		end
		if type(config.abilities) == 'table' then
			local abilities = compact_job_default_abilities(defaults)
			config.abilities.configured = clone_value(abilities)
			config.abilities.legacy_slots = clone_value(abilities)
		end
	end

	local payload = {
		version = 2,
		profile = clone_value(config.profile or {}),
		config = config,
	}
	return M.build_active_profile_from_v2_payload(payload, meta)
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
	normalize_maintenance_compatibility(config)
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
			recurring_spells = config.combat.recurring_spells,
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
			config.combat.recurring_spells = clone_value(normalized_or_err.combat.recurring_spells)
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

function M.replace_name(path, value)
	local segments = normalize_path(path)
	if type(segments) ~= 'table' or #segments < 2 then
		return false, 'active config name path missing'
	end
	local parent = M.get_active_profile()
	for i = 1, #segments - 1 do
		if type(parent) ~= 'table' then
			return false, 'active config name parent missing'
		end
		parent = parent[segments[i]]
	end
	if type(parent) ~= 'table' then
		return false, 'active config name parent missing'
	end
	parent[segments[#segments]] = trim_string(value)
	if #segments == 4 and segments[1] == 'config' and segments[2] == 'follow' then
		if segments[3] == 'party' and segments[4] == 'leader_name' then
			parent.leader_id = 0
		elseif segments[3] == 'fight' and segments[4] == 'leader_name' then
			parent.leader_id = 0
		elseif segments[3] == 'partner' and segments[4] == 'puller_name' then
			parent.puller_id = 0
		end
	end
	return true, 'REPLACED'
end

local function normalized_string_list(values)
	if type(values) ~= 'table' then
		return nil, 'string list values must be a table'
	end
	local out = {}
	local seen = {}
	for i = 1, #values do
		local value = normalize_optional_string(values[i])
		if value ~= nil then
			local key = value:lower()
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = value
			end
		end
	end
	return out
end

function M.replace_pipe_string_list(path, values)
	local segments = normalize_path(path)
	if type(segments) ~= 'table' or #segments < 2 then
		return false, 'active config pipe-list path missing'
	end
	local normalized, err = normalized_string_list(values)
	if type(normalized) ~= 'table' then
		return false, err
	end
	local parent = M.get_active_profile()
	for i = 1, #segments - 1 do
		if type(parent) ~= 'table' then
			return false, 'active config pipe-list parent missing'
		end
		parent = parent[segments[i]]
	end
	if type(parent) ~= 'table' then
		return false, 'active config pipe-list parent missing'
	end
	parent[segments[#segments]] = table.concat(normalized, '|')
	if #segments == 4
		and segments[1] == 'config'
		and segments[2] == 'maintenance'
		and segments[3] == 'cor'
		and segments[4] == 'range_selected' then
		parent.range_require_ids = {}
	end
	return true, 'REPLACED'
end

local function sync_string_list_dependents(path, target)
	local segments = normalize_path(path)
	if type(segments) ~= 'table' then
		return
	end
	if #segments == 3
		and segments[1] == 'config'
		and segments[2] == 'sleep'
		and segments[3] == 'order' then
		local sleep = M.get_path('config.sleep')
		if type(sleep) == 'table' then
			sleep.legacy_primary = tostring(target[1] or '')
		end
	elseif #segments == 4
		and segments[1] == 'config'
		and segments[2] == 'follow'
		and segments[3] == 'partner'
		and segments[4] == 'names' then
		local partner = M.get_path('config.follow.partner')
		if type(partner) == 'table' then
			partner.ids = {}
		end
	end
end

function M.replace_string_list(path, values)
	local target = M.get_path(path)
	if type(target) ~= 'table' then
		return false, 'active config string list missing'
	end
	local normalized, err = normalized_string_list(values)
	if type(normalized) ~= 'table' then
		return false, err
	end
	local ok, sync_err = sync_table_in_place(target, normalized)
	if ok ~= true then
		return false, sync_err
	end
	sync_string_list_dependents(path, target)
	return true, 'REPLACED'
end

function M.append_string_list(path, value)
	local target = M.get_path(path)
	if type(target) ~= 'table' then
		return false, 'active config string list missing'
	end
	local normalized = normalize_optional_string(value)
	if normalized == nil then
		return false, 'string list value required'
	end
	local key = normalized:lower()
	for i = 1, #target do
		if tostring(target[i] or ''):lower() == key then
			sync_string_list_dependents(path, target)
			return true, 'ALREADY'
		end
	end
	target[#target + 1] = normalized
	sync_string_list_dependents(path, target)
	return true, 'ADDED'
end

function M.remove_string_list_index(path, index)
	local target = M.get_path(path)
	if type(target) ~= 'table' then
		return false, 'active config string list missing'
	end
	local resolved = tonumber(index)
	if resolved == nil or resolved % 1 ~= 0 or resolved < 1 or resolved > #target then
		return false, 'BAD_INDEX'
	end
	table.remove(target, resolved)
	sync_string_list_dependents(path, target)
	return true, 'REMOVED'
end

function M.remove_string_list_value(path, value)
	local target = M.get_path(path)
	if type(target) ~= 'table' then
		return false, 'active config string list missing'
	end
	local normalized = normalize_optional_string(value)
	if normalized == nil then
		return false, 'string list value required'
	end
	local key = normalized:lower()
	for i = 1, #target do
		if tostring(target[i] or ''):lower() == key then
			table.remove(target, i)
			sync_string_list_dependents(path, target)
			return true, 'REMOVED'
		end
	end
	return false, 'NOT_FOUND'
end

function M.move_string_list_index(path, index, delta)
	local target = M.get_path(path)
	if type(target) ~= 'table' then
		return false, 'active config string list missing'
	end
	local resolved_index = tonumber(index)
	local resolved_delta = tonumber(delta)
	if resolved_index == nil or resolved_index % 1 ~= 0
		or resolved_delta == nil or resolved_delta % 1 ~= 0
		or resolved_index < 1 or resolved_index > #target then
		return false, 'BAD_INDEX'
	end
	local destination = resolved_index + resolved_delta
	if destination < 1 or destination > #target then
		return false, 'EDGE'
	end
	target[resolved_index], target[destination] = target[destination], target[resolved_index]
	sync_string_list_dependents(path, target)
	return true, 'MOVED'
end

return M
