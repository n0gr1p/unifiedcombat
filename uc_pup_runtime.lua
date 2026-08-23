local M = {
	RECAST_ACTIVATE = 205,
	RECAST_DEPLOY = 207,
	RECAST_MANEUVER = 210,
	BUFF_OVERLOAD = 299,
	PRIORITY_ACTIVATE = 149,
	PRIORITY_MANEUVER = 148,
	PRIORITY_DEPLOY = 147,
	DEFAULT_POST_ACTIVATE_QUIET_SECONDS = 120,
	DEFAULT_SAFE_BURDEN_CEILING = 30,
}

local MANEUVERS = {
	['Fire Maneuver'] = { action_id = 141, buff_id = 300, burden = 20 },
	['Ice Maneuver'] = { action_id = 142, buff_id = 301, burden = 20 },
	['Wind Maneuver'] = { action_id = 143, buff_id = 302, burden = 20 },
	['Earth Maneuver'] = { action_id = 144, buff_id = 303, burden = 20 },
	['Thunder Maneuver'] = { action_id = 145, buff_id = 304, burden = 20 },
	['Water Maneuver'] = { action_id = 146, buff_id = 305, burden = 20 },
	['Light Maneuver'] = { action_id = 147, buff_id = 306, burden = 20 },
	['Dark Maneuver'] = { action_id = 148, buff_id = 307, burden = 15 },
}

local ACTION_TO_MANEUVER = {}
for name, entry in pairs(MANEUVERS) do
	ACTION_TO_MANEUVER[entry.action_id] = name
end

local DEFAULT_CONFIG = {
	enabled = true,
	activate_if_missing = true,
	deploy_on_combat_start = true,
	maneuvers = {
		enabled = true,
		pattern = { 'Fire Maneuver', 'Fire Maneuver', 'Light Maneuver' },
		post_activate_quiet_seconds = M.DEFAULT_POST_ACTIVATE_QUIET_SECONDS,
		safe_burden_ceiling = M.DEFAULT_SAFE_BURDEN_CEILING,
	},
}

local file_config_cache = nil

local function clone(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, inner in pairs(value) do
		out[key] = clone(inner)
	end
	return out
end

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function bool(value, default_value, name)
	if value == nil then
		return default_value
	end
	if type(value) ~= 'boolean' then
		error(name .. ' must be boolean')
	end
	return value
end

local function number_in_range(value, default_value, name, min_value, max_value)
	if value == nil then
		return default_value
	end
	local number = tonumber(value)
	if number == nil or number < min_value or number > max_value then
		error(('%s must be between %.1f and %.1f'):format(name, min_value, max_value))
	end
	return number
end

local function normalize_pattern(value)
	if value == nil then
		return clone(DEFAULT_CONFIG.maneuvers.pattern)
	end
	local raw = {}
	if type(value) == 'string' then
		for token in value:gmatch('[^|]+') do
			raw[#raw + 1] = token:match('^%s*(.-)%s*$')
		end
	elseif type(value) == 'table' then
		for i = 1, #value do
			raw[#raw + 1] = value[i]
		end
	else
		error('puppetmaster.maneuvers.pattern must be an array or pipe-delimited string')
	end
	if #raw < 1 or #raw > 3 then
		error('puppetmaster.maneuvers.pattern must contain one to three maneuvers')
	end
	local out = {}
	for i = 1, #raw do
		if type(raw[i]) ~= 'string' or MANEUVERS[raw[i]] == nil then
			error(('unsupported Puppetmaster maneuver at slot %d: %s'):format(i, tostring(raw[i])))
		end
		out[i] = raw[i]
	end
	return out
end

local function load_file_config()
	if file_config_cache ~= nil then
		return clone(file_config_cache)
	end
	local config = clone(DEFAULT_CONFIG)
	local windower_ref = rawget(_G, 'windower')
	local addon_path = type(windower_ref) == 'table' and tostring(windower_ref.addon_path or '') or ''
	if addon_path ~= '' then
		local ok, loaded = pcall(dofile, addon_path .. 'data/puppetmaster_config.lua')
		if ok and type(loaded) == 'table' then
			config = loaded
		end
	end
	file_config_cache = clone(config)
	return clone(file_config_cache)
end

function M.config_from_settings(settings)
	local source = nil
	if type(settings) == 'table' and type(settings.puppetmaster) == 'table' then
		source = settings.puppetmaster
	elseif type(settings) == 'table' and settings.puppetmaster_enabled ~= nil then
		source = {
			enabled = settings.puppetmaster_enabled,
			activate_if_missing = settings.puppetmaster_activate_if_missing,
			deploy_on_combat_start = settings.puppetmaster_deploy_on_combat_start,
			maneuvers = {
				enabled = settings.puppetmaster_maneuvers_enabled,
				pattern = settings.puppetmaster_maneuver_pattern,
				post_activate_quiet_seconds = settings.puppetmaster_post_activate_quiet_seconds,
				safe_burden_ceiling = settings.puppetmaster_safe_burden_ceiling,
			},
		}
	else
		source = load_file_config()
	end
	if type(source) ~= 'table' then
		source = {}
	end
	local maneuvers = type(source.maneuvers) == 'table' and source.maneuvers or {}
	return {
		enabled = bool(source.enabled, DEFAULT_CONFIG.enabled, 'puppetmaster.enabled'),
		activate_if_missing = bool(
			source.activate_if_missing,
			DEFAULT_CONFIG.activate_if_missing,
			'puppetmaster.activate_if_missing'
		),
		deploy_on_combat_start = bool(
			source.deploy_on_combat_start,
			DEFAULT_CONFIG.deploy_on_combat_start,
			'puppetmaster.deploy_on_combat_start'
		),
		maneuvers = {
			enabled = bool(maneuvers.enabled, DEFAULT_CONFIG.maneuvers.enabled, 'puppetmaster.maneuvers.enabled'),
			pattern = normalize_pattern(maneuvers.pattern),
			post_activate_quiet_seconds = number_in_range(
				maneuvers.post_activate_quiet_seconds,
				DEFAULT_CONFIG.maneuvers.post_activate_quiet_seconds,
				'puppetmaster.maneuvers.post_activate_quiet_seconds',
				0,
				300
			),
			safe_burden_ceiling = number_in_range(
				maneuvers.safe_burden_ceiling,
				DEFAULT_CONFIG.maneuvers.safe_burden_ceiling,
				'puppetmaster.maneuvers.safe_burden_ceiling',
				0,
				32
			),
		},
	}
end

function M.maneuver(name)
	local entry = MANEUVERS[tostring(name or '')]
	if entry == nil then
		return nil
	end
	local out = clone(entry)
	out.name = name
	return out
end

function M.maneuver_from_action_id(action_id)
	return ACTION_TO_MANEUVER[tonumber(action_id)]
end

function M.has_buff(player, buff_id)
	local buffs = type(player) == 'table' and player.buffs or nil
	if type(buffs) ~= 'table' then
		return false
	end
	for i = 1, #buffs do
		if tonumber(buffs[i]) == tonumber(buff_id) then
			return true
		end
	end
	return false
end

function M.maneuver_counts(player)
	local counts = {}
	for name in pairs(MANEUVERS) do
		counts[name] = 0
	end
	local buffs = type(player) == 'table' and player.buffs or nil
	if type(buffs) ~= 'table' then
		return counts
	end
	for i = 1, #buffs do
		local id = tonumber(buffs[i])
		for name, entry in pairs(MANEUVERS) do
			if id == entry.buff_id then
				counts[name] = counts[name] + 1
				break
			end
		end
	end
	return counts
end

function M.recast_ready(ctx, recast_id)
	require_table(ctx, 'Puppetmaster scheduler context')
	if ctx.ability_recasts_present ~= true then
		return false, 'ability_recasts_unavailable'
	end
	local recasts = require_table(ctx.ability_recasts, 'Puppetmaster ability recasts')
	local current = tonumber(recasts[recast_id])
	if current == nil then
		return false, 'recast_missing'
	end
	if current > 0 then
		return false, 'recast_unavailable'
	end
	return true, ''
end

function M.new_state()
	return {
		zone_id = nil,
		pet_id = 0,
		burden = {},
		burden_at = nil,
		quiet_until = 0,
		maneuver_counts = {},
		last_recorded_at = {},
		last_reason = 'init',
	}
end

local function current_zone_id()
	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	local get_info = type(ffxi) == 'table' and ffxi.get_info or nil
	if type(get_info) ~= 'function' then
		return 0
	end
	local ok, info = pcall(get_info)
	if not ok or type(info) ~= 'table' then
		return 0
	end
	return tonumber(info.zone) or 0
end

local function decay(state, now)
	local last = tonumber(state.burden_at)
	if last == nil then
		state.burden_at = now
		return
	end
	local elapsed = math.max(0, now - last)
	local amount = elapsed / 3.0
	for name in pairs(MANEUVERS) do
		state.burden[name] = math.max(0, (tonumber(state.burden[name]) or 0) - amount)
	end
	state.burden_at = now
end

local function reset_unknown_burden(state, now, quiet_seconds, reason)
	state.burden = {}
	for name in pairs(MANEUVERS) do
		-- Activation and zoning are documented to place every element near the
		-- overload threshold. Forty points with normal 1/3s decay reaches zero
		-- in two minutes, matching the deliberately conservative quiet window.
		state.burden[name] = 40
	end
	state.burden_at = now
	state.quiet_until = now + quiet_seconds
	state.last_reason = reason
end

function M.record_maneuver(state, name, now)
	require_table(state, 'Puppetmaster burden state')
	local maneuver = M.maneuver(name)
	if maneuver == nil then
		return false
	end
	now = tonumber(now) or 0
	decay(state, now)
	local last = tonumber(state.last_recorded_at[name]) or -math.huge
	if (now - last) < 1.25 then
		return false
	end
	state.burden[name] = (tonumber(state.burden[name]) or 0) + maneuver.burden
	state.last_recorded_at[name] = now
	state.last_reason = 'maneuver_observed:' .. name
	return true
end

function M.observe(state, ctx, now, config)
	require_table(state, 'Puppetmaster burden state')
	require_table(ctx, 'Puppetmaster scheduler context')
	config = config or M.config_from_settings(ctx.settings)
	now = tonumber(now) or tonumber(ctx.now) or 0
	decay(state, now)

	local zone_id = current_zone_id()
	if state.zone_id == nil then
		state.zone_id = zone_id
		if ctx.pet_present == true then
			reset_unknown_burden(state, now, config.maneuvers.post_activate_quiet_seconds, 'initial_pet_observation')
		end
	elseif zone_id > 0 and state.zone_id > 0 and zone_id ~= state.zone_id then
		state.zone_id = zone_id
		reset_unknown_burden(state, now, config.maneuvers.post_activate_quiet_seconds, 'zone_change')
	elseif zone_id > 0 then
		state.zone_id = zone_id
	end

	local pet_id = ctx.pet_present == true and (tonumber(ctx.pet_id) or 0) or 0
	if pet_id > 0 and pet_id ~= (tonumber(state.pet_id) or 0) then
		state.pet_id = pet_id
		reset_unknown_burden(state, now, config.maneuvers.post_activate_quiet_seconds, 'automaton_appeared')
	elseif pet_id == 0 and (tonumber(state.pet_id) or 0) > 0 then
		state.pet_id = 0
		state.burden = {}
		state.burden_at = now
		state.quiet_until = 0
		state.last_reason = 'automaton_absent'
	end

	local counts = M.maneuver_counts(ctx.player)
	for name in pairs(MANEUVERS) do
		local previous = tonumber(state.maneuver_counts[name]) or 0
		local current = tonumber(counts[name]) or 0
		if current > previous then
			for _ = 1, current - previous do
				M.record_maneuver(state, name, now)
			end
		end
	end
	state.maneuver_counts = counts
	return state
end

function M.next_missing_maneuver(config, player)
	config = require_table(config, 'Puppetmaster config')
	local counts = M.maneuver_counts(player)
	local wanted = {}
	for i = 1, #config.maneuvers.pattern do
		local name = config.maneuvers.pattern[i]
		wanted[name] = (wanted[name] or 0) + 1
		if counts[name] == nil then
			counts[name] = 0
		end
	end
	local seen = {}
	for i = 1, #config.maneuvers.pattern do
		local name = config.maneuvers.pattern[i]
		seen[name] = (seen[name] or 0) + 1
		if (counts[name] or 0) < seen[name] then
			return name, counts, wanted
		end
	end
	return nil, counts, wanted
end

function M.maneuver_safe(state, config, ctx, name, now)
	require_table(state, 'Puppetmaster burden state')
	config = require_table(config, 'Puppetmaster config')
	ctx = require_table(ctx, 'Puppetmaster scheduler context')
	now = tonumber(now) or tonumber(ctx.now) or 0
	local maneuver = M.maneuver(name)
	if maneuver == nil then
		return false, 'unknown_maneuver', 0, 0
	end
	if M.has_buff(ctx.player, M.BUFF_OVERLOAD) then
		return false, 'overload_active', tonumber(state.burden[name]) or 0, 0
	end
	if now < (tonumber(state.quiet_until) or 0) then
		return false, 'post_activate_or_zone_quiet', tonumber(state.burden[name]) or 0,
			(tonumber(state.quiet_until) or 0) - now
	end
	local ready, reason = M.recast_ready(ctx, M.RECAST_MANEUVER)
	if not ready then
		return false, reason, tonumber(state.burden[name]) or 0, 0
	end
	decay(state, now)
	local current = tonumber(state.burden[name]) or 0
	local projected = current + maneuver.burden
	if projected > config.maneuvers.safe_burden_ceiling then
		local required_decay = projected - config.maneuvers.safe_burden_ceiling
		return false, 'burden_guard', current, required_decay * 3.0
	end
	return true, '', current, 0
end

function M.status_snapshot(state, config, ctx, now)
	local next_name, active_counts = M.next_missing_maneuver(config, ctx.player)
	local burdens = {}
	for name in pairs(MANEUVERS) do
		burdens[name] = tonumber(state.burden[name]) or 0
	end
	return {
		enabled = config.enabled == true,
		pet_id = tonumber(ctx.pet_id) or 0,
		pet_present = ctx.pet_present == true,
		overload = M.has_buff(ctx.player, M.BUFF_OVERLOAD),
		next_maneuver = next_name or '',
		active_counts = active_counts,
		burden = burdens,
		quiet_remaining = math.max(0, (tonumber(state.quiet_until) or 0) - (tonumber(now) or 0)),
		safe_burden_ceiling = config.maneuvers.safe_burden_ceiling,
		last_reason = tostring(state.last_reason or ''),
	}
end

return M
