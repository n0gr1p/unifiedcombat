local M = {}

M.ORDINARY_WS_MIN_DELAY_S = 3.0
M.ORDINARY_WS_DISPATCH_BUFFER_S = 0.3
M.LATEST_WINDOW_GUARD_S = 0.6
M.CHAINBOUND_DELAY_S = 2.0
M.MAGIC_BURST_DURATION_S = 10.0
M.DIAMOND_ASPIS_DURATION_S = 10.0

M.CHAINBOUND_SOURCE_DURATION_S_BY_ACTION_ID = {
	[209] = 3.0,  -- Wild Flourish operational effective window
	[320] = 60.0, -- Konzen-ittai documented duration
}

local property_levels = {
	Compression = 1,
	Liquefaction = 1,
	Induration = 1,
	Reverberation = 1,
	Transfixion = 1,
	Scission = 1,
	Detonation = 1,
	Impaction = 1,
	Gravitation = 2,
	Fragmentation = 2,
	Distortion = 2,
	Fusion = 2,
	Light = 3,
	Darkness = 3,
	Radiance = 4,
	Umbra = 4,
}

local skillchain_target_properties = {
	auto = 'Auto',
	compression = 'Compression',
	liquefaction = 'Liquefaction',
	induration = 'Induration',
	reverberation = 'Reverberation',
	transfixion = 'Transfixion',
	scission = 'Scission',
	detonation = 'Detonation',
	impaction = 'Impaction',
	gravitation = 'Gravitation',
	fragmentation = 'Fragmentation',
	distortion = 'Distortion',
	fusion = 'Fusion',
	light = 'Light',
	darkness = 'Darkness',
	radiance = 'Radiance',
	umbra = 'Umbra',
}

function M.normalize_skillchain_target(value)
	local key = tostring(value or 'auto'):match('^%s*(.-)%s*$'):lower()
	local property = skillchain_target_properties[key]
	if property == nil then
		error('unsupported skillchain target: ' .. tostring(value))
	end
	if key == 'auto' then
		return key, nil
	end
	return key, property
end

local transitions = {
	Compression = {
		Transfixion = { level = 1, property = 'Transfixion' },
		Detonation = { level = 1, property = 'Detonation' },
	},
	Liquefaction = {
		Impaction = { level = 2, property = 'Fusion' },
		Scission = { level = 1, property = 'Scission' },
	},
	Induration = {
		Reverberation = { level = 2, property = 'Fragmentation' },
		Compression = { level = 1, property = 'Compression' },
		Impaction = { level = 1, property = 'Impaction' },
	},
	Reverberation = {
		Induration = { level = 1, property = 'Induration' },
		Impaction = { level = 1, property = 'Impaction' },
	},
	Transfixion = {
		Scission = { level = 2, property = 'Distortion' },
		Reverberation = { level = 1, property = 'Reverberation' },
		Compression = { level = 1, property = 'Compression' },
	},
	Scission = {
		Liquefaction = { level = 1, property = 'Liquefaction' },
		Reverberation = { level = 1, property = 'Reverberation' },
		Detonation = { level = 1, property = 'Detonation' },
	},
	Detonation = {
		Compression = { level = 2, property = 'Gravitation' },
		Scission = { level = 1, property = 'Scission' },
	},
	Impaction = {
		Liquefaction = { level = 1, property = 'Liquefaction' },
		Detonation = { level = 1, property = 'Detonation' },
	},
	Gravitation = {
		Distortion = { level = 3, property = 'Darkness' },
		Fragmentation = { level = 2, property = 'Fragmentation' },
	},
	Fragmentation = {
		Fusion = { level = 3, property = 'Light' },
		Distortion = { level = 2, property = 'Distortion' },
	},
	Distortion = {
		Gravitation = { level = 3, property = 'Darkness' },
		Fusion = { level = 2, property = 'Fusion' },
	},
	Fusion = {
		Fragmentation = { level = 3, property = 'Light' },
		Gravitation = { level = 2, property = 'Gravitation' },
	},
	Light = {
		Light = { level = 4, property = 'Light', aeonic_property = 'Radiance' },
	},
	Darkness = {
		Darkness = { level = 4, property = 'Darkness', aeonic_property = 'Umbra' },
	},
}

local function copy_list(values)
	local out = {}
	for i = 1, #(values or {}) do
		out[i] = values[i]
	end
	return out
end

local function same_list(left, right)
	if #(left or {}) ~= #(right or {}) then
		return false
	end
	for i = 1, #(left or {}) do
		if left[i] ~= right[i] then
			return false
		end
	end
	return true
end

local function copy_map(values)
	local out = {}
	for key, value in pairs(values or {}) do
		out[key] = value
	end
	return out
end

local function copy_transition(value)
	if type(value) ~= 'table' then
		return nil
	end
	return {
		level = value.level,
		property = value.property,
		aeonic_property = value.aeonic_property,
	}
end

local function normal_transition(active_properties, closing_properties)
	for opener_index = 1, #(active_properties or {}) do
		local opener_property = active_properties[opener_index]
		local opener_transitions = transitions[opener_property]
		if opener_transitions then
			for closer_index = 1, #(closing_properties or {}) do
				local result = opener_transitions[closing_properties[closer_index]]
				if result then
					return copy_transition(result)
				end
			end
		end
	end
	return nil
end

local function chainbound_level_one_transition(active_properties, closing_properties)
	local first_level_one = nil
	for i = 1, #(closing_properties or {}) do
		local property = closing_properties[i]
		if property_levels[property] == 1 then
			first_level_one = property
			break
		end
	end
	if not first_level_one then
		return nil
	end
	for i = 1, #(active_properties or {}) do
		local opener_transitions = transitions[active_properties[i]]
		local result = opener_transitions and opener_transitions[first_level_one]
		if result then
			return copy_transition(result)
		end
	end
	return nil
end

function M.resolve_properties(active_properties, closing_properties, chainbound_level)
	if tonumber(chainbound_level) == 1 then
		return chainbound_level_one_transition(active_properties, closing_properties)
	end
	return normal_transition(active_properties, closing_properties)
end

function M.property_level(property)
	return property_levels[tostring(property or '')] or 0
end

function M.chainbound_expires_at(action_id, observed_at)
	local duration = tonumber(M.CHAINBOUND_SOURCE_DURATION_S_BY_ACTION_ID[tonumber(action_id) or 0])
	if not duration then
		return nil
	end
	return (tonumber(observed_at) or 0) + duration
end

function M.action_succeeded(event)
	if type(event) ~= 'table' then
		error('action_succeeded requires event')
	end
	return event.server_result == true
		or event.message_success == true
		or event.chain_affinity_success == true
		or (tonumber(event.chainbound_level) or 0) > 0
end

function M.should_observe_action(event)
	if type(event) ~= 'table' then
		error('should_observe_action requires event')
	end
	local resource = tostring(event.source_resource or '')
	if resource == 'weapon_skills' then
		return true
	end
	if event.server_result == true
		or event.chain_affinity_success == true
		or (tonumber(event.chainbound_level) or 0) > 0 then
		return true
	end
	return resource ~= 'spells' and event.has_properties == true
end

local function actor_expiry(state, actor_id)
	local actor_key = tonumber(actor_id) or 0
	local override = tonumber((state.actor_expiry_overrides or {})[actor_key])
	if override then
		return override
	end
	return tonumber(state.expires_at) or 0
end

local function aeonic_result_for(transition, actor_context, action_count)
	local aeonic_property = transition and transition.aeonic_property
	if not aeonic_property then
		return transition
	end
	if tostring(actor_context and actor_context.aeonic_weapon_name or '') == '' then
		return transition
	end
	local aftermath_level = tonumber(actor_context and actor_context.aftermath_level) or 0
	local minimum_prior_actions = 4 - aftermath_level
	if aftermath_level >= 1 and aftermath_level <= 3 and (tonumber(action_count) or 0) >= minimum_prior_actions then
		return {
			level = 4,
			property = aeonic_property,
			aeonic_property = aeonic_property,
		}
	end
	return transition
end

local function skillchain_target_distance(start_property, target_property, actor_context, action_count)
	local start = tostring(start_property or '')
	local target = tostring(target_property or '')
	if start == '' or target == '' then
		return nil
	end
	if start == target then
		return 0
	end
	local queue = {
		{
			property = start,
			action_count = tonumber(action_count) or 1,
			distance = 0,
		},
	}
	local head = 1
	local seen = {}
	seen[start .. ':' .. tostring(tonumber(action_count) or 1)] = true
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		if current.distance < 8 then
			local outgoing = transitions[current.property]
			if outgoing then
				for _, transition in pairs(outgoing) do
					local result = aeonic_result_for(copy_transition(transition), actor_context, current.action_count)
					local property = tostring(result and result.property or '')
					if property == target then
						return current.distance + 1
					end
					if property ~= '' then
						local next_count = current.action_count + 1
						local seen_key = property .. ':' .. tostring(next_count)
						if not seen[seen_key] then
							seen[seen_key] = true
							queue[#queue + 1] = {
								property = property,
								action_count = next_count,
								distance = current.distance + 1,
							}
						end
					end
				end
			end
		end
	end
	return nil
end

local State = {}
State.__index = State

function M.new(options)
	if type(options) ~= 'table' then
		error('uc_skillchain_state.new requires options')
	end
	if type(options.now) ~= 'function' then
		error('uc_skillchain_state.new requires a monotonic now function')
	end
	if options.telemetry ~= nil and type(options.telemetry) ~= 'function' then
		error('uc_skillchain_state.new telemetry must be a function')
	end
	return setmetatable({
		now = options.now,
		telemetry = options.telemetry,
		states = {},
		generation_by_target = {},
		dispatched_generation_by_target = {},
		dispatched_plan_by_target = {},
	}, State)
end

function State:_emit(event_code, fields)
	if self.telemetry then
		self.telemetry(event_code, fields or {})
	end
end

function State:_next_generation(target_id)
	local generation = (tonumber(self.generation_by_target[target_id]) or 0) + 1
	self.generation_by_target[target_id] = generation
	return generation
end

function State:_timing(event, observed_at, action_count)
	local delay = tonumber(event.delay)
	if not delay then
		error('skillchain property event requires action delay')
	end
	if tostring(event.source_resource or '') == 'weapon_skills' and delay < M.ORDINARY_WS_MIN_DELAY_S then
		delay = M.ORDINARY_WS_MIN_DELAY_S
	end
	local expires_at = tonumber(event.expires_at_override)
	if not expires_at then
		expires_at = observed_at + delay + 8 - action_count
	end
	local earliest_close_at = observed_at + delay
	return {
		landed_at = observed_at,
		earliest_close_at = earliest_close_at,
		preferred_execute_at = earliest_close_at + M.ORDINARY_WS_DISPATCH_BUFFER_S,
		expires_at = expires_at,
		latest_safe_at = expires_at - M.LATEST_WINDOW_GUARD_S,
	}
end

function State:_install(event, properties, result, prior, observed_at)
	local is_result = type(result) == 'table'
	local action_count = is_result and ((tonumber(prior and prior.action_count) or 1) + 1) or 1
	local skillchain_stage = is_result and ((tonumber(prior and prior.skillchain_stage) or 0) + 1) or 0
	local result_level = is_result and (tonumber(result.level) or M.property_level(result.property)) or 0
	local timing = self:_timing(event, observed_at, action_count)
	local target_id = tonumber(event.target_id)
	local actor_id = tonumber(event.actor_id) or 0
	local state = {
		target_id = target_id,
		generation = self:_next_generation(target_id),
		source_action_id = tonumber(event.action_id) or 0,
		source_action_name = tostring(event.action_name or ''),
		source_actor_id = actor_id,
		source_resource = tostring(event.source_resource or ''),
		active_properties = is_result and { result.property } or copy_list(properties),
		landed_at = timing.landed_at,
		earliest_close_at = timing.earliest_close_at,
		preferred_execute_at = timing.preferred_execute_at,
		expires_at = timing.expires_at,
		latest_safe_at = timing.latest_safe_at,
		action_count = action_count,
		skillchain_stage = skillchain_stage,
		result_level = result_level,
		terminal = is_result and result_level == 4 or false,
		chainbound_level = is_result and 0 or (tonumber(event.chainbound_level) or 0),
		actor_expiry_overrides = {},
		magic_burst_expires_at = is_result and (observed_at + M.MAGIC_BURST_DURATION_S) or 0,
		last_confirmed_result = is_result and tostring(event.server_result or result.property or '') or '',
	}
	if is_result and event.actor_has_diamond_aspis == true and actor_id > 0 then
		state.actor_expiry_overrides[actor_id] = observed_at + M.DIAMOND_ASPIS_DURATION_S
	end
	self.states[target_id] = state
	self.dispatched_generation_by_target[target_id] = nil
	self.dispatched_plan_by_target[target_id] = nil
	return state
end

function State:observe_action_result(event)
	if type(event) ~= 'table' then
		error('observe_action_result requires event')
	end
	local target_id = tonumber(event.target_id) or 0
	if target_id <= 0 then
		return nil, 'SC_NO_TARGET'
	end
	local observed_at = tonumber(event.observed_at)
	if not observed_at then
		observed_at = self.now()
	end
	local prior = self.states[target_id]
	local prior_generation = tonumber(prior and prior.generation) or 0
	local telemetry = {
		observed_at = observed_at,
		actor_id = tonumber(event.actor_id) or 0,
		target_id = target_id,
		action_id = tonumber(event.action_id) or 0,
		action_name = tostring(event.action_name or ''),
		resource = tostring(event.source_resource or ''),
		message_id = tonumber(event.message_id) or 0,
		prior_generation = prior_generation,
		chainbound_level = tonumber(event.chainbound_level) or 0,
		chainbound_source_expiry_known = (tonumber(event.chainbound_level) or 0) == 0
			or tonumber(event.expires_at_override) ~= nil,
	}
	if event.success ~= true or event.interrupted == true then
		telemetry.success = false
		telemetry.interrupted = event.interrupted == true
		telemetry.result_generation = prior_generation
		self:_emit('SC_ACTION_IGNORED', telemetry)
		return prior, event.interrupted == true and 'SC_INTERRUPTED' or 'SC_ACTION_FAILED'
	end
	if (tonumber(event.chainbound_level) or 0) > 0 and tonumber(event.expires_at_override) == nil then
		telemetry.success = true
		telemetry.result_generation = prior_generation
		telemetry.reason = 'SC_CHAINBOUND_SOURCE_UNSUPPORTED'
		self:_emit('SC_ACTION_IGNORED', telemetry)
		return prior, 'SC_CHAINBOUND_SOURCE_UNSUPPORTED'
	end

	local properties = copy_list(event.effective_properties)
	local server_result = tostring(event.server_result or '')
	if #properties == 0 and server_result == '' then
		telemetry.success = true
		telemetry.result_generation = prior_generation
		self:_emit('SC_PROPERTYLESS_PRESERVED', telemetry)
		return prior, 'SC_PROPERTYLESS'
	end

	local eligible = prior ~= nil
		and prior.terminal ~= true
		and observed_at >= (tonumber(prior.earliest_close_at) or 0)
		and observed_at <= actor_expiry(prior, event.actor_id)
	local predicted = nil
	if eligible and #properties > 0 then
		predicted = M.resolve_properties(prior.active_properties, properties, prior.chainbound_level)
		predicted = aeonic_result_for(predicted, event.actor_context, prior.action_count)
	end
	local result = nil
	if server_result ~= '' then
		local server_level = tonumber(event.server_result_level) or M.property_level(server_result)
		if predicted and predicted.level == 4 and (server_result == 'Light' or server_result == 'Darkness') then
			server_level = 4
		end
		result = {
			property = server_result,
			level = server_level,
		}
	end
	local next_state = self:_install(event, properties, result, prior, observed_at)
	telemetry.success = true
	telemetry.source_properties = table.concat(properties, ',')
	telemetry.predicted_result = tostring(predicted and predicted.property or '')
	telemetry.server_result = server_result
	telemetry.result_generation = next_state.generation
	telemetry.action_count = next_state.action_count
	telemetry.skillchain_stage = next_state.skillchain_stage
	telemetry.terminal = next_state.terminal
	telemetry.landed_at = next_state.landed_at
	telemetry.earliest_close_at = next_state.earliest_close_at
	telemetry.preferred_execute_at = next_state.preferred_execute_at
	telemetry.latest_safe_at = next_state.latest_safe_at
	telemetry.expires_at = next_state.expires_at
	telemetry.magic_burst_expires_at = next_state.magic_burst_expires_at
	if result and (not predicted or predicted.property ~= result.property) then
		telemetry.disagreement = true
		self:_emit('SC_PREDICTION_DISAGREEMENT', telemetry)
	else
		self:_emit(result and 'SC_RESULT_CONFIRMED' or 'SC_OPENER_INSTALLED', telemetry)
	end
	return next_state, result and 'SC_RESULT_CONFIRMED' or 'SC_OPENER_INSTALLED'
end

function State:get_state(target_id)
	return self.states[tonumber(target_id) or 0]
end

function State:get_snapshot(target_id)
	local state = self:get_state(target_id)
	if not state then
		return nil
	end
	local out = copy_map(state)
	out.active_properties = copy_list(state.active_properties)
	out.actor_expiry_overrides = copy_map(state.actor_expiry_overrides)
	return out
end

function State:expiry_for_actor(target_id, actor_id)
	local state = self:get_state(target_id)
	if not state then
		return 0
	end
	return actor_expiry(state, actor_id)
end

function State:_reject_continuation(state, target_id, reason, now)
	self:_emit('SC_CONTINUATION_REJECTED', {
		observed_at = now,
		target_id = tonumber(target_id) or 0,
		resonance_generation = tonumber(state and state.generation) or 0,
		action_count = tonumber(state and state.action_count) or 0,
		skillchain_stage = tonumber(state and state.skillchain_stage) or 0,
		terminal = state and state.terminal == true or false,
		earliest_execute_at = tonumber(state and state.earliest_close_at) or 0,
		latest_safe_at = tonumber(state and state.latest_safe_at) or 0,
		expires_at = tonumber(state and state.expires_at) or 0,
		reason = reason,
	})
	return nil, reason
end

function State:plan_continuation(target_id, candidates, actor_context, now_value, skillchain_target)
	local target = tonumber(target_id) or 0
	if target <= 0 then
		return self:_reject_continuation(nil, target, 'SC_NO_TARGET', tonumber(now_value) or self.now())
	end
	local state = self.states[target]
	if not state or #(state.active_properties or {}) == 0 then
		return self:_reject_continuation(state, target, 'SC_NO_RESONANCE', tonumber(now_value) or self.now())
	end
	local now = tonumber(now_value)
	if not now then
		now = self.now()
	end
	if state.terminal == true then
		return self:_reject_continuation(state, target, 'SC_TERMINAL', now)
	end
	if tonumber(self.dispatched_generation_by_target[target]) == tonumber(state.generation) then
		local stored_plan = self.dispatched_plan_by_target[target]
		if type(stored_plan) ~= 'table' then
			error('dispatched skillchain generation is missing its reservation plan')
		end
		self:_reject_continuation(state, target, 'SC_DISPATCH_PENDING_RESULT', now)
		local pending_plan = copy_map(stored_plan)
		pending_plan.effective_properties = copy_list(stored_plan.effective_properties)
		pending_plan.requirements = copy_map(stored_plan.requirements)
		pending_plan.planned_at = now
		return pending_plan, 'SC_DISPATCH_PENDING_RESULT'
	end
	local expiry = actor_expiry(state, actor_context and actor_context.actor_id)
	if now > expiry then
		return self:_reject_continuation(state, target, 'SC_WINDOW_EXPIRED', now)
	end
	local latest_safe_at = expiry - M.LATEST_WINDOW_GUARD_S
	local target_key, target_property = M.normalize_skillchain_target(skillchain_target)
	local targeted = target_property ~= nil
	local chosen = nil
	local chosen_result = nil
	local chosen_distance = nil
	local saw_continuation = false
	for i = 1, #(candidates or {}) do
		local candidate = candidates[i]
		local result = M.resolve_properties(state.active_properties, candidate.effective_properties, state.chainbound_level)
		result = aeonic_result_for(result, actor_context, state.action_count)
		if result then
			saw_continuation = true
			if not targeted then
				-- Preserve legacy Auto behavior exactly, including later-candidate tie preference.
				if not chosen_result or result.level >= chosen_result.level then
					chosen = candidate
					chosen_result = result
				end
			else
				local distance = skillchain_target_distance(
					result.property,
					target_property,
					actor_context,
					(tonumber(state.action_count) or 1) + 1
				)
				-- Target mode is a hard gate. Equal routes preserve the existing candidate order.
				if distance ~= nil and (chosen_distance == nil or distance < chosen_distance) then
					chosen = candidate
					chosen_result = result
					chosen_distance = distance
				end
			end
		end
	end
	if not chosen then
		local reason = targeted and saw_continuation and 'SC_NO_PATH_TO_TARGET' or 'SC_NO_CONTINUATION'
		return self:_reject_continuation(state, target, reason, now)
	end
	local preferred_execute_at = tonumber(state.preferred_execute_at) or state.earliest_close_at
	local high_risk = preferred_execute_at > latest_safe_at
	if high_risk then
		preferred_execute_at = (tonumber(state.earliest_close_at) or now) + 0.1
	end
	local plan = {
		kind = 'skillchain_continuation',
		target_id = target,
		resonance_generation = state.generation,
		source_action_id = state.source_action_id,
		source_actor_id = state.source_actor_id,
		source_resource = state.source_resource,
		ws_id = tonumber(chosen.ws_id) or 0,
		ws_name = tostring(chosen.ws_name or ''),
		effective_properties = copy_list(chosen.effective_properties),
		predicted_result = tostring(chosen_result.property or ''),
		predicted_level = tonumber(chosen_result.level) or 0,
		skillchain_target = target_key,
		target_distance = chosen_distance,
		planned_at = now,
		earliest_execute_at = tonumber(state.earliest_close_at) or 0,
		preferred_execute_at = preferred_execute_at,
		latest_safe_at = latest_safe_at,
		high_risk = high_risk,
		selection_reason = high_risk and 'SC_WINDOW_HIGH_RISK' or 'SC_READY',
		requirements = {
			skillchain_target = target_key,
			weapon_signature = tostring(actor_context and actor_context.weapon_signature or ''),
			aftermath_level = tonumber(actor_context and actor_context.aftermath_level) or 0,
			diamond_aspis = actor_context and actor_context.diamond_aspis == true or false,
		},
	}
	self:_emit('SC_CONTINUATION_PLANNED', {
		observed_at = now,
		target_id = target,
		resonance_generation = state.generation,
		ws_id = plan.ws_id,
		ws_name = plan.ws_name,
		closer_properties = table.concat(plan.effective_properties, ','),
		predicted_result = plan.predicted_result,
		predicted_level = plan.predicted_level,
		skillchain_target = plan.skillchain_target,
		target_distance = plan.target_distance,
		earliest_execute_at = plan.earliest_execute_at,
		preferred_execute_at = plan.preferred_execute_at,
		latest_safe_at = plan.latest_safe_at,
		high_risk = plan.high_risk,
	})
	if now < plan.preferred_execute_at then
		return plan, 'SC_NOT_READY'
	end
	if now > plan.latest_safe_at then
		return self:_reject_continuation(state, target, 'SC_LATEST_SAFE_PASSED', now)
	end
	return plan, plan.selection_reason
end

function State:revalidate_plan(plan, context)
	local function reject(reason)
		self:_emit('SC_COMMIT_RESULT', {
			observed_at = type(context) == 'table' and tonumber(context.now) or self.now(),
			target_id = type(plan) == 'table' and tonumber(plan.target_id) or 0,
			resonance_generation = type(plan) == 'table' and tonumber(plan.resonance_generation) or 0,
			ws_id = type(plan) == 'table' and tonumber(plan.ws_id) or 0,
			ws_name = type(plan) == 'table' and tostring(plan.ws_name or '') or '',
			predicted_result = type(plan) == 'table' and tostring(plan.predicted_result or '') or '',
			commit_stage = type(context) == 'table' and tostring(context.commit_stage or 'unspecified') or 'unspecified',
			commit_result = reason,
		})
		return false, reason
	end
	if type(plan) ~= 'table' or plan.kind ~= 'skillchain_continuation' then
		return reject('SC_INTENT_LOST')
	end
	if type(context) ~= 'table' then
		error('revalidate_plan requires context')
	end
	if context.engine_enabled ~= true then
		return reject('SC_ENGINE_DISABLED')
	end
	if (tonumber(context.current_target_id) or 0) ~= (tonumber(plan.target_id) or 0) then
		return reject('SC_TARGET_CHANGED')
	end
	if context.target_valid ~= true then
		return reject('SC_TARGET_INVALID')
	end
	local state = self.states[tonumber(plan.target_id) or 0]
	if not state then
		return reject('SC_NO_RESONANCE')
	end
	if tonumber(state.generation) ~= tonumber(plan.resonance_generation) then
		return reject('SC_RESONANCE_CHANGED')
	end
	if tonumber(self.dispatched_generation_by_target[tonumber(plan.target_id) or 0]) == tonumber(state.generation) then
		return reject('SC_DISPATCH_PENDING_RESULT')
	end
	if state.terminal == true then
		return reject('SC_TERMINAL')
	end
	local now = tonumber(context.now)
	if not now then
		now = self.now()
	end
	if now < (tonumber(plan.earliest_execute_at) or 0) then
		return reject('SC_NOT_READY')
	end
	if now < (tonumber(plan.preferred_execute_at) or tonumber(plan.earliest_execute_at) or 0) then
		return reject('SC_NOT_READY')
	end
	if now > (tonumber(plan.latest_safe_at) or 0) then
		return reject('SC_LATEST_SAFE_PASSED')
	end
	if context.ws_available ~= true then
		return reject('SC_WS_UNAVAILABLE')
	end
	if (tonumber(context.tp) or 0) < 1000 then
		return reject('SC_TP_LOST')
	end
	if context.actor_blocked == true then
		return reject('SC_ACTOR_BLOCKED')
	end
	if context.range_valid ~= true then
		return reject('SC_OUT_OF_RANGE')
	end
	if context.reaction_hold == true then
		return reject('SC_REACTION_HOLD')
	end
	if context.intent_valid ~= true then
		return reject('SC_INTENT_LOST')
	end
	local actor_context = context.actor_context or {}
	local requirements = plan.requirements or {}
	local current_target_key = select(1, M.normalize_skillchain_target(context.skillchain_target))
	local planned_target_key = tostring(requirements.skillchain_target or plan.skillchain_target or 'auto')
	if current_target_key ~= planned_target_key then
		return reject('SC_TARGET_POLICY_CHANGED')
	end
	if tostring(actor_context.weapon_signature or '') ~= tostring(requirements.weapon_signature or '')
		or (tonumber(actor_context.aftermath_level) or 0) ~= (tonumber(requirements.aftermath_level) or 0)
		or (actor_context.diamond_aspis == true) ~= (requirements.diamond_aspis == true) then
		return reject('SC_PROPERTIES_CHANGED')
	end
	if not same_list(context.effective_properties, plan.effective_properties) then
		return reject('SC_PROPERTIES_CHANGED')
	end
	local result = M.resolve_properties(state.active_properties, context.effective_properties, state.chainbound_level)
	result = aeonic_result_for(result, actor_context, state.action_count)
	if not result or tostring(result.property or '') ~= tostring(plan.predicted_result or '') then
		return reject('SC_PROPERTIES_CHANGED')
	end
	self:_emit('SC_COMMIT_RESULT', {
		observed_at = now,
		target_id = plan.target_id,
		resonance_generation = plan.resonance_generation,
		ws_id = plan.ws_id,
		ws_name = plan.ws_name,
		predicted_result = plan.predicted_result,
		commit_stage = tostring(context.commit_stage or 'unspecified'),
		commit_result = 'SC_DISPATCHED',
	})
	return true, 'SC_DISPATCHED'
end

function State:mark_plan_dispatched(plan, observed_at)
	if type(plan) ~= 'table' or plan.kind ~= 'skillchain_continuation' then
		error('mark_plan_dispatched requires a skillchain continuation plan')
	end
	local target_id = tonumber(plan.target_id) or 0
	local generation = tonumber(plan.resonance_generation) or 0
	local state = self.states[target_id]
	if not state or tonumber(state.generation) ~= generation then
		return false, 'SC_RESONANCE_CHANGED'
	end
	self.dispatched_generation_by_target[target_id] = generation
	local stored_plan = copy_map(plan)
	stored_plan.effective_properties = copy_list(plan.effective_properties)
	stored_plan.requirements = copy_map(plan.requirements)
	self.dispatched_plan_by_target[target_id] = stored_plan
	self:_emit('SC_DISPATCH_PENDING_RESULT', {
		observed_at = tonumber(observed_at) or self.now(),
		target_id = target_id,
		resonance_generation = generation,
		ws_id = tonumber(plan.ws_id) or 0,
		ws_name = tostring(plan.ws_name or ''),
		predicted_result = tostring(plan.predicted_result or ''),
	})
	return true, 'SC_DISPATCH_PENDING_RESULT'
end

function State:clear_target(target_id, reason)
	local target = tonumber(target_id) or 0
	if target <= 0 then
		return false
	end
	local prior = self.states[target]
	self.states[target] = nil
	self.dispatched_generation_by_target[target] = nil
	self.dispatched_plan_by_target[target] = nil
	if prior then
		self:_emit('SC_TARGET_CLEARED', {
			target_id = target,
			prior_generation = prior.generation,
			reason = tostring(reason or ''),
			observed_at = self.now(),
		})
		return true
	end
	return false
end

function State:reset(reason)
	for target_id in pairs(self.states) do
		self.states[target_id] = nil
	end
	for target_id in pairs(self.generation_by_target) do
		self.generation_by_target[target_id] = nil
	end
	for target_id in pairs(self.dispatched_generation_by_target) do
		self.dispatched_generation_by_target[target_id] = nil
	end
	for target_id in pairs(self.dispatched_plan_by_target) do
		self.dispatched_plan_by_target[target_id] = nil
	end
	self:_emit('SC_STATE_RESET', {
		reason = tostring(reason or ''),
		observed_at = self.now(),
	})
end

return M
