local M = {}

local ORIGIN_CAPTURE_STABLE_S = 0.50
local ORIGIN_CAPTURE_TOLERANCE = 0.10

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(value, name)
	if type(value) ~= 'function' then
		error(name .. ' must be a function')
	end
	return value
end

local function require_nonempty_string(value, name)
	if type(value) ~= 'string' then
		error(name .. ' must be a string')
	end
	local normalized = value:match('^%s*(.-)%s*$')
	if normalized == '' then
		error(name .. ' must be a non-empty string')
	end
	return normalized
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

local function distance_2d(left, right)
	local dx = left.x - right.x
	local dy = left.y - right.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local function normalize_actor(actor, expected_name)
	if type(actor) ~= 'table' then
		return nil, 'FORMATION_MOCK_ACTOR_INCOMPLETE'
	end
	local normalized = {
		id = tonumber(actor.id),
		name = tostring(actor.name or ''),
		x = tonumber(actor.x),
		y = tonumber(actor.y),
		z = tonumber(actor.z),
		hpp = tonumber(actor.hpp),
		status = tonumber(actor.status),
	}
	if normalized.id == nil or normalized.id <= 0
		or normalized.name ~= expected_name
		or normalized.x == nil or normalized.y == nil
		or normalized.hpp == nil or normalized.status == nil then
		return nil, 'FORMATION_MOCK_ACTOR_INCOMPLETE'
	end
	return normalized, ''
end

function M.build(opts)
	opts = require_table(opts, 'uc_formation_mock_state opts')
	local get_mob_array = require_function(opts.get_mob_array, 'opts.get_mob_array')
	local get_target = require_function(opts.get_target, 'opts.get_target')
	local state = {
		enabled = false,
		configured_id = '',
		resolved_id = '',
		mock = true,
		mock_mob_name = '',
		bound_actor_id = 0,
		phase = 'disabled',
		error = '',
		boss = nil,
		origin = nil,
		origin_candidate = nil,
		origin_candidate_since = 0,
		last_reset_reason = 'initial',
	}
	local config_signature = ''
	local runtime = {}

	local function clear_transient(reason)
		state.resolved_id = ''
		state.phase = state.enabled and 'awaiting_mock_mob' or 'disabled'
		state.error = ''
		state.boss = nil
		state.bound_actor_id = 0
		state.origin = nil
		state.origin_candidate = nil
		state.origin_candidate_since = 0
		state.last_reset_reason = reason
	end

	local function set_error(reason)
		clear_transient(reason)
		state.resolved_id = ''
		state.phase = 'error'
		state.error = reason
		return copy_table(state), reason
	end

	local function update_origin(now, boss)
		if state.origin ~= nil then
			return 'FORMATION_MOCK_ORIGIN_READY'
		end
		if boss.status ~= 0 then
			state.origin_candidate = nil
			state.origin_candidate_since = 0
			return 'FORMATION_MOCK_ORIGIN_CAPTURE_MISSED'
		end
		local observed = copy_point(boss)
		if state.origin_candidate == nil
			or distance_2d(state.origin_candidate, observed) > ORIGIN_CAPTURE_TOLERANCE then
			state.origin_candidate = observed
			state.origin_candidate_since = now
			return 'FORMATION_MOCK_ORIGIN_CAPTURE_STABILIZING'
		end
		if (now - state.origin_candidate_since) < ORIGIN_CAPTURE_STABLE_S then
			return 'FORMATION_MOCK_ORIGIN_CAPTURE_STABILIZING'
		end
		state.origin = copy_point(state.origin_candidate)
		state.origin_candidate = nil
		state.origin_candidate_since = 0
		return 'FORMATION_MOCK_ORIGIN_CAPTURED'
	end

	function runtime.observe(now, config)
		local observed_at = tonumber(now)
		if observed_at == nil then
			error('uc_formation_mock_state.observe requires now')
		end
		config = require_table(config, 'uc_formation_mock_state config')
		if type(config.enabled) ~= 'boolean' then
			error('config.movement.formation.mock.enabled must be boolean')
		end
		if config.enabled ~= true then
			if state.enabled then
				state.enabled = false
				state.configured_id = ''
				state.mock_mob_name = ''
				config_signature = ''
				clear_transient('mock_disabled')
			end
			return copy_table(state), 'FORMATION_MOCK_DISABLED'
		end

		local encounter_id = require_nonempty_string(config.encounter, 'config.movement.formation.encounter')
		local mob_name = require_nonempty_string(config.mob_name, 'config.movement.formation.mock.mob_name')
		local signature = encounter_id .. '\0' .. mob_name
		if signature ~= config_signature then
			state.enabled = true
			state.configured_id = encounter_id
			state.mock_mob_name = mob_name
			config_signature = signature
			clear_transient('mock_config_changed')
		end

		local mob_array = get_mob_array()
		if type(mob_array) ~= 'table' then
			return set_error('FORMATION_MOCK_MOB_ARRAY_UNAVAILABLE')
		end
		if state.bound_actor_id <= 0 then
			local target = get_target()
			if type(target) ~= 'table' or tostring(target.name or '') ~= mob_name then
				return set_error('FORMATION_MOCK_TARGET_REQUIRED')
			end
			local target_actor, target_error = normalize_actor(target, mob_name)
			if target_actor == nil then
				return set_error(target_error)
			end
			state.bound_actor_id = target_actor.id
		end

		local matched_actor = nil
		for _, actor in pairs(mob_array) do
			if type(actor) == 'table' and tonumber(actor.id) == state.bound_actor_id then
				if matched_actor ~= nil then
					return set_error('FORMATION_MOCK_DUPLICATE_ACTOR_ID')
				end
				matched_actor = actor
			end
		end
		if matched_actor == nil then
			return set_error('FORMATION_MOCK_BOUND_MOB_NOT_FOUND')
		end

		local boss, actor_error = normalize_actor(matched_actor, mob_name)
		if boss == nil then
			return set_error(actor_error)
		end
		state.boss = boss
		state.resolved_id = encounter_id
		state.error = ''
		if boss.hpp <= 0 then
			state.phase = 'complete'
			return copy_table(state), 'FORMATION_MOCK_ENCOUNTER_COMPLETE'
		end
		local origin_reason = update_origin(observed_at, boss)
		if boss.status == 0 then
			state.phase = state.origin ~= nil and 'origin_captured' or 'binding'
		else
			state.phase = 'active'
		end
		return copy_table(state), origin_reason
	end

	function runtime.reset(reason)
		reason = require_nonempty_string(reason, 'uc_formation_mock_state.reset reason')
		state.enabled = false
		state.configured_id = ''
		state.mock_mob_name = ''
		config_signature = ''
		clear_transient(reason)
		return true, reason
	end

	function runtime.snapshot()
		return copy_table(state)
	end

	return runtime
end

local default_runtime = nil

local function get_default_runtime()
	if default_runtime == nil then
		if type(rawget(_G, 'windower')) ~= 'table'
			or type(windower.ffxi) ~= 'table'
			or type(windower.ffxi.get_mob_array) ~= 'function'
			or type(windower.ffxi.get_mob_by_target) ~= 'function' then
			error('default formation mock state requires Windower mob APIs')
		end
		default_runtime = M.build({
			get_mob_array = function()
				return windower.ffxi.get_mob_array()
			end,
			get_target = function()
				return windower.ffxi.get_mob_by_target('t')
			end,
		})
	end
	return default_runtime
end

function M.observe(now, config)
	return get_default_runtime().observe(now, config)
end

function M.reset(reason)
	return get_default_runtime().reset(reason)
end

function M.snapshot()
	return get_default_runtime().snapshot()
end

M.ORIGIN_CAPTURE_STABLE_S = ORIGIN_CAPTURE_STABLE_S
M.ORIGIN_CAPTURE_TOLERANCE = ORIGIN_CAPTURE_TOLERANCE

return M
