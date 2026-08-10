local registry = require('uc_encounter_registry')

local M = {}

local SHARED_ABILITY_NAMES = {
	['Nullifying Rain'] = true,
	['Noyade'] = true,
	['Cesspool'] = true,
	['Clobbering Wave'] = true,
	['Fetid Eddies'] = true,
}

local ORIGIN_CAPTURE_STABLE_S = 0.50
local ORIGIN_CAPTURE_TOLERANCE = 0.10
local DHARTOK_CESSPOOL_TELEMETRY_DURATION_S = 180.0

local state = {
	enabled = false,
	configured_id = '',
	resolved_id = '',
	family = '',
	phase = 'idle',
	error = '',
	boss = nil,
	origin = nil,
	origin_candidate = nil,
	origin_candidate_since = 0,
	last_ability = nil,
	status_context = {},
	recent_repeat_actions = {},
	cesspool = nil,
	hazard_candidates = {},
	unresolved_hazard_observations = 0,
	last_hazard_diagnostic = '',
	policy_modes = {},
	tuning = {},
	config_signature = '',
	last_policy_violation = nil,
	last_policy_rejection = nil,
	last_reset_reason = 'initial',
}

local POLICY_NAMES = {
	'water_damage',
	'water_skillchain',
	'repeat_action_wall',
}

local POLICY_MODES = {
	enforce = true,
	warn = true,
	off = true,
}

local function copy_point(point)
	if type(point) ~= 'table' then
		return nil
	end
	return {
		x = tonumber(point.x),
		y = tonumber(point.y),
		z = tonumber(point.z),
	}
end

local function copy_table(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copy_table(item)
	end
	return out
end

local function new_cesspool_state()
	return {
		active = false,
		observed_at = 0,
		expires_at = 0,
		pair_index = 0,
		last_tp_name = '',
		last_tp_target_id = 0,
		sequence_confidence = 'unverified_telemetry',
	}
end

local function clear_transient(reason)
	state.resolved_id = ''
	state.family = ''
	state.phase = state.enabled and 'awaiting_snapshot' or 'idle'
	state.error = ''
	state.boss = nil
	state.origin = nil
	state.origin_candidate = nil
	state.origin_candidate_since = 0
	state.last_ability = nil
	state.status_context = {}
	state.recent_repeat_actions = {}
	state.cesspool = new_cesspool_state()
	state.hazard_candidates = {}
	state.unresolved_hazard_observations = 0
	state.last_hazard_diagnostic = ''
	state.last_policy_violation = nil
	state.last_policy_rejection = nil
	state.last_reset_reason = tostring(reason)
end

local function set_error(reason)
	state.phase = 'error'
	state.error = tostring(reason)
	return false, state.error
end

local function invalidate_binding(error_reason, reset_reason)
	if state.resolved_id ~= '' or state.boss ~= nil then
		clear_transient(reset_reason)
	end
	return set_error(error_reason)
end

local function distance_2d(left, right)
	local dx = left.x - right.x
	local dy = left.y - right.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local function normalize_boss(actor)
	if type(actor) ~= 'table' then
		return nil, 'INCOMPLETE_BOSS_ACTOR'
	end
	local boss = {
		id = tonumber(actor.id),
		name = tostring(actor.name or ''),
		x = tonumber(actor.x),
		y = tonumber(actor.y),
		z = tonumber(actor.z),
		hpp = tonumber(actor.hpp),
		status = tonumber(actor.status),
	}
	if boss.id == nil or boss.id <= 0 or boss.name == '' or boss.x == nil or boss.y == nil
		or boss.hpp == nil or boss.status == nil then
		return nil, 'INCOMPLETE_BOSS_ACTOR'
	end
	return boss
end

local function update_origin(now, boss)
	if state.origin ~= nil then
		return 'ORIGIN_READY'
	end
	if boss.status ~= 0 then
		state.origin_candidate = nil
		state.origin_candidate_since = 0
		return 'ORIGIN_CAPTURE_MISSED'
	end
	local observed = copy_point(boss)
	if state.origin_candidate == nil
		or distance_2d(state.origin_candidate, observed) > ORIGIN_CAPTURE_TOLERANCE then
		state.origin_candidate = observed
		state.origin_candidate_since = now
		return 'ORIGIN_CAPTURE_STABILIZING'
	end
	if (now - state.origin_candidate_since) < ORIGIN_CAPTURE_STABLE_S then
		return 'ORIGIN_CAPTURE_STABILIZING'
	end
	state.origin = copy_point(state.origin_candidate)
	state.origin_candidate = nil
	state.origin_candidate_since = 0
	return 'ORIGIN_CAPTURED'
end

local function update_status_context(members)
	local context = {}
	for i = 1, #(members or {}) do
		local member = members[i]
		if type(member) == 'table' then
			local observed = {
				member_id = tonumber(member.id) or 0,
				member_name = tostring(member.name or ''),
				source = tostring(member.source or 'unavailable'),
				poison = false,
				taint = false,
			}
			for j = 1, #(member.buff_names or {}) do
				local buff_name = tostring(member.buff_names[j] or '')
				if buff_name == 'Poison' then
					observed.poison = true
				elseif buff_name == 'Taint' then
					observed.taint = true
				end
			end
			if observed.member_id > 0 or observed.member_name ~= '' then
				context[#context + 1] = observed
			end
		end
	end
	state.status_context = context
end

local function expire_cesspool(now)
	if state.cesspool.active == true and now >= state.cesspool.expires_at then
		state.cesspool.active = false
		state.cesspool.pair_index = 0
	end
end

local function resolve_policy_config(definition, config)
	local overrides = config.policy
	if overrides ~= nil and type(overrides) ~= 'table' then
		error('encounter policy configuration must be a table')
	end
	local modes = {}
	for i = 1, #POLICY_NAMES do
		local name = POLICY_NAMES[i]
		local mode = overrides and overrides[name] or nil
		if mode == nil then
			mode = definition.policy[name]
		end
		if type(mode) ~= 'string' or POLICY_MODES[mode] ~= true then
			error(('encounter policy %s must be enforce, warn, or off'):format(name))
		end
		modes[name] = mode
	end
	local tuning_overrides = config.tuning
	if tuning_overrides ~= nil and type(tuning_overrides) ~= 'table' then
		error('encounter tuning configuration must be a table')
	end
	local repeat_guard = tuning_overrides and tuning_overrides.repeat_action_guard_s or nil
	if repeat_guard == nil then
		repeat_guard = definition.tuning.repeat_action_guard_s
	end
	if type(repeat_guard) ~= 'number' or repeat_guard <= 0 then
		error('encounter repeat_action_guard_s must be a positive number')
	end
	return modes, {
		repeat_action_guard_s = repeat_guard,
	}
end

local function config_signature(configured_id, modes, tuning)
	return table.concat({
		configured_id,
		modes.water_damage,
		modes.water_skillchain,
		modes.repeat_action_wall,
		('%.6f'):format(tuning.repeat_action_guard_s),
	}, ':')
end

function M.configure(config, reason)
	if type(config) ~= 'table' then
		error('uc_encounter_state.configure requires config')
	end
	local enabled = config.enabled == true
	local configured_id = tostring(config.id or '')
	if not enabled then
		local changed = state.enabled == true or state.configured_id ~= ''
		state.enabled = false
		state.configured_id = ''
		state.policy_modes = {}
		state.tuning = {}
		state.config_signature = ''
		if changed then
			clear_transient(reason or 'configured_disabled')
		end
		return true, 'DISABLED'
	end
	local definition = registry.get(configured_id)
	if definition == nil then
		state.enabled = true
		state.configured_id = configured_id
		state.policy_modes = {}
		state.tuning = {}
		state.config_signature = configured_id
		clear_transient(reason or 'configured_invalid')
		return set_error('UNSUPPORTED_ENCOUNTER')
	end
	local modes, tuning = resolve_policy_config(definition, config)
	local signature = config_signature(configured_id, modes, tuning)
	local changed = state.enabled ~= true or state.config_signature ~= signature
	state.enabled = true
	state.configured_id = configured_id
	state.policy_modes = modes
	state.tuning = tuning
	state.config_signature = signature
	if changed then
		clear_transient(reason or 'configured_encounter_changed')
	end
	return true, changed and 'CONFIGURED' or 'UNCHANGED'
end

function M.reset(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('uc_encounter_state.reset requires a non-empty reason')
	end
	clear_transient(reason)
end

function M.observe_snapshot(snapshot)
	if type(snapshot) ~= 'table' then
		error('uc_encounter_state.observe_snapshot requires snapshot')
	end
	if state.enabled ~= true then
		return false, 'DISABLED'
	end
	local definition = registry.get(state.configured_id)
	if definition == nil then
		return set_error('UNSUPPORTED_ENCOUNTER')
	end
	local now = tonumber(snapshot.now)
	if now == nil then
		error('uc_encounter_state.observe_snapshot requires snapshot.now')
	end
	local zone_name = tostring(snapshot.zone_name or '')
	if zone_name ~= definition.zone_name then
		return invalidate_binding(
			zone_name == '' and 'ZONE_UNRESOLVED' or 'NOT_IN_SORTIE',
			'encounter_zone_unresolved'
		)
	end

	local matches = {}
	for i = 1, #(snapshot.actors or {}) do
		local actor = snapshot.actors[i]
		if type(actor) == 'table' and tostring(actor.name or '') == definition.actor_name then
			matches[#matches + 1] = actor
		end
	end
	if #matches > 1 then
		return invalidate_binding('MULTIPLE_BOSS_ACTORS', 'multiple_boss_actors')
	end
	if #matches == 0 then
		if state.resolved_id ~= '' or state.boss ~= nil then
			clear_transient('expected_boss_not_found')
		end
		state.phase = state.boss == nil and 'awaiting_boss' or 'boss_unresolved'
		state.error = 'EXPECTED_BOSS_NOT_FOUND'
		state.origin_candidate = nil
		state.origin_candidate_since = 0
		update_status_context(snapshot.members)
		expire_cesspool(now)
		return false, state.error
	end

	local boss, boss_error = normalize_boss(matches[1])
	if boss == nil then
		return invalidate_binding(boss_error, 'incomplete_boss_actor')
	end
	if state.boss ~= nil and tonumber(state.boss.id) ~= boss.id then
		clear_transient('boss_actor_replaced')
	end
	state.boss = boss
	state.resolved_id = definition.id
	state.family = definition.family
	state.error = ''
	if boss.hpp <= 0 then
		clear_transient('boss_defeated')
		return false, 'BOSS_DEFEATED'
	end
	local origin_reason = update_origin(now, boss)
	if boss.status == 0 then
		state.phase = state.origin ~= nil and 'origin_captured' or 'binding'
	else
		state.phase = 'active'
	end
	update_status_context(snapshot.members)
	expire_cesspool(now)
	return true, origin_reason
end

function M.observe_ability(event)
	if type(event) ~= 'table' then
		error('uc_encounter_state.observe_ability requires event')
	end
	if state.enabled ~= true or state.boss == nil then
		return false, 'ENCOUNTER_UNRESOLVED'
	end
	local actor_id = tonumber(event.actor_id) or 0
	if actor_id ~= tonumber(state.boss.id) then
		return false, 'UNRELATED_ACTOR'
	end
	local ability_name = tostring(event.ability_name or '')
	if ability_name == '' then
		error('uc_encounter_state.observe_ability requires event.ability_name')
	end
	local phase = tostring(event.phase or '')
	if phase ~= 'readied' and phase ~= 'completed' then
		error('uc_encounter_state.observe_ability requires readied or completed phase')
	end
	local observed_at = tonumber(event.observed_at)
	if observed_at == nil then
		error('uc_encounter_state.observe_ability requires event.observed_at')
	end
	expire_cesspool(observed_at)
	state.last_ability = {
		name = ability_name,
		phase = phase,
		actor_id = actor_id,
		target_id = tonumber(event.target_id) or 0,
		observed_at = observed_at,
		mechanic_tracked = SHARED_ABILITY_NAMES[ability_name] == true,
	}
	if state.resolved_id ~= 'sortie_dhartok' or phase ~= 'completed' then
		return true, 'ABILITY_OBSERVED'
	end
	if ability_name == 'Cesspool' then
		state.cesspool.active = true
		state.cesspool.observed_at = observed_at
		state.cesspool.expires_at = observed_at + DHARTOK_CESSPOOL_TELEMETRY_DURATION_S
		state.cesspool.pair_index = 0
		state.cesspool.last_tp_name = ability_name
		state.cesspool.last_tp_target_id = tonumber(event.target_id) or 0
		return true, 'CESSPOOL_TELEMETRY_STARTED'
	end
	if state.cesspool.active ~= true then
		return true, 'ABILITY_OBSERVED'
	end
	state.cesspool.pair_index = state.cesspool.pair_index + 1
	state.cesspool.last_tp_name = ability_name
	state.cesspool.last_tp_target_id = tonumber(event.target_id) or 0
	if state.cesspool.pair_index < 2 then
		return true, 'CESSPOOL_FIRST_TP_OBSERVED'
	end
	state.cesspool.pair_index = 0
	local point = copy_point(event.target_position)
	if point == nil or point.x == nil or point.y == nil then
		state.unresolved_hazard_observations = state.unresolved_hazard_observations + 1
		state.last_hazard_diagnostic = 'HAZARD_LOCATION_UNRESOLVED'
		return true, state.last_hazard_diagnostic
	end
	state.hazard_candidates[#state.hazard_candidates + 1] = {
		sequence = #state.hazard_candidates + 1,
		x = point.x,
		y = point.y,
		z = point.z,
		observed_at = observed_at,
		target_id = tonumber(event.target_id) or 0,
		source = 'unverified_second_tp_target_position',
	}
	state.last_hazard_diagnostic = 'HAZARD_CANDIDATE_OBSERVED'
	return true, state.last_hazard_diagnostic
end

function M.observe_successful_action(event)
	if type(event) ~= 'table' then
		error('uc_encounter_state.observe_successful_action requires event')
	end
	if state.enabled ~= true or state.resolved_id ~= 'sortie_dhartok' or state.boss == nil then
		return false, 'DHARTOK_UNRESOLVED'
	end
	if event.success ~= true then
		return false, 'ACTION_NOT_SUCCESSFUL'
	end
	if (tonumber(event.target_id) or 0) ~= tonumber(state.boss.id) then
		return false, 'UNRELATED_TARGET'
	end
	local action_class = tostring(event.action_class or '')
	if action_class ~= 'ws' and action_class ~= 'bp' then
		return false, 'ACTION_CLASS_NOT_TRACKED'
	end
	local action_key = tostring(event.action_key or '')
	local observed_at = tonumber(event.observed_at)
	if action_key == '' or observed_at == nil then
		error('successful encounter action requires action_key and observed_at')
	end
	state.recent_repeat_actions[action_class .. ':' .. action_key] = {
		action_class = action_class,
		action_key = action_key,
		action_name = tostring(event.action_name or ''),
		actor_id = tonumber(event.actor_id) or 0,
		target_id = tonumber(event.target_id) or 0,
		observed_at = observed_at,
	}
	return true, 'ACTION_SUCCESS_OBSERVED'
end

function M.observe_boss_defeat(target_id)
	if state.enabled ~= true or state.boss == nil then
		return false, 'ENCOUNTER_UNRESOLVED'
	end
	if (tonumber(target_id) or 0) ~= tonumber(state.boss.id) then
		return false, 'UNRELATED_TARGET'
	end
	clear_transient('boss_defeated_action_message')
	return true, 'BOSS_DEFEATED'
end

function M.record_policy_decision(decision)
	if type(decision) ~= 'table' then
		error('uc_encounter_state.record_policy_decision requires decision')
	end
	local mode = tostring(decision.mode or '')
	if mode ~= 'warn' and mode ~= 'enforce' then
		error('encounter policy decision mode must be warn or enforce')
	end
	local record = copy_table(decision)
	state.last_policy_violation = record
	if mode == 'enforce' then
		state.last_policy_rejection = copy_table(record)
	end
	return true
end

function M.snapshot()
	return copy_table(state)
end

M.ORIGIN_CAPTURE_STABLE_S = ORIGIN_CAPTURE_STABLE_S
M.ORIGIN_CAPTURE_TOLERANCE = ORIGIN_CAPTURE_TOLERANCE

return M
