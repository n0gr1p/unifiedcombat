local pet_combat_state = require('uc_pet_combat_state')
local combat_commitment = require('uc_combat_commitment')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_pet_combat_provider deps.%s must be a function'):format(name))
	end
	return value
end

local function require_number(value, name)
	local number = tonumber(value)
	if number == nil then
		error(name .. ' must be numeric')
	end
	return number
end

local function merge_detail(base, extra)
	local out = {}
	if type(base) == 'table' then
		for key, value in pairs(base) do
			out[key] = value
		end
	end
	if type(extra) == 'table' then
		for key, value in pairs(extra) do
			out[key] = value
		end
	end
	return out
end

local function make_proposal(ctx, spec)
	local action_type = tostring(spec.action_type or 'pet')
	local target_kind = tostring(spec.target_kind or 'mob')
	local target_id = tonumber(spec.target_id)
	if target_id == nil then
		target_id = tonumber(ctx.target_id) or 0
	end
	local target_name = spec.target_name
	if target_name == nil then
		target_name = tostring(ctx.target and ctx.target.name or '')
	end
	local range = tonumber(spec.range)
	if range == nil then
		range = 20.0
	end
	local command = spec.command
	local command_detail = {}
	if type(command) == 'table' then
		command_detail.pet_command = command
		command_detail.pet_id = command.pet_id
		command_detail.target_id = command.target_id
		command_detail.combat_generation = command.combat_generation
	end
	if spec.desired_avatar ~= nil then
		command_detail.desired_avatar = spec.desired_avatar
	end
	command_detail.range = range
	command_detail.distance = tonumber(spec.distance) or 0
	local detail = merge_detail(spec.detail, command_detail)
	return {
		proposal_id = ('pet.%s.%s.%d'):format(
			tostring(spec.kind or action_type),
			tostring(spec.action_name or ''):gsub('%s+', '_'),
			math.floor(ctx.now * 1000)
		),
		family_id = tostring(spec.family_id or ('combat.pet.' .. tostring(spec.kind or 'action'))),
		provider = 'pet_combat',
		action_type = action_type,
		action_name = spec.action_name,
		target_kind = target_kind,
		target_id = target_id,
		target_name = tostring(target_name or ''),
		priority_band = require_number(spec.priority_band, 'pet combat priority band'),
		urgency = require_number(spec.urgency, 'pet combat urgency'),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = tostring(spec.movement_policy or 'none'),
		range_policy = { min = 0.0, max = range, los_required = false },
		recast_key = spec.retry_key,
		duplicate_suppression_key = spec.retry_key,
		lock_class = tostring(spec.lock_class or (action_type == 'pet' and 'pet_command' or 'support_action')),
		expected_ack = tostring(spec.expected_ack or (action_type == 'pet' and 'pet_command' or 'action_start')),
		expected_effect = tostring(spec.expected_effect or ''),
		sticky = false,
		can_preempt_movement = false,
		can_preempt_same_band = false,
		reason_code = tostring(spec.reason_code or 'pet_action_required'),
		detail = detail,
		legacy_command = '',
	}
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local adapter = require_table(deps.adapter, 'deps.adapter')
	if type(adapter.snapshot) ~= 'function'
		or type(adapter.engagement) ~= 'function'
		or type(adapter.offensive_action) ~= 'function'
		or type(adapter.revalidate) ~= 'function' then
		error('uc_pet_combat_provider adapter contract is invalid')
	end
	local coordinator_can_attempt = require_function(deps, 'coordinator_can_attempt')
	local target_is_actionable = require_function(deps, 'target_is_actionable')
	local combat_commitment_evaluate = deps.combat_commitment_evaluate
	if combat_commitment_evaluate == nil then
		combat_commitment_evaluate = combat_commitment.evaluate_runtime
	elseif type(combat_commitment_evaluate) ~= 'function' then
		error('uc_pet_combat_provider deps.combat_commitment_evaluate must be a function')
	end
	local state = require_table(deps.state, 'deps.state')

	local provider = {}

	local function engagement_observed(ctx, pet_id)
		local observed_target_id = pet_combat_state.observed_pet_target(state, pet_id)
		if observed_target_id > 0 then
			return observed_target_id == ctx.target_id, observed_target_id
		end
		return ctx.pet_status == 1, 0
	end

	local function append_spec(ctx, out, spec)
		if type(spec) ~= 'table' then
			return false
		end
		if tostring(spec.action_type or 'pet') == 'pet' then
			local retry_key = tostring(spec.retry_key or '')
			if retry_key == '' then
				error('pet proposal requires retry_key')
			end
			local allowed = coordinator_can_attempt(retry_key, ctx.now)
			if not allowed then
				return false
			end
		end
		out[#out + 1] = make_proposal(ctx, spec)
		return true
	end

	function provider.observe_target(ctx)
		require_table(ctx, 'ctx')
		pet_combat_state.observe_pet_state(
			state,
			ctx.pet_present,
			ctx.pet_id,
			ctx.pet_status
		)
		local actionable = ctx.combat_domain_enabled == true
			and ctx.target_present == true
			and target_is_actionable(ctx.target, ctx.now, true)
			and (tonumber(ctx.target.id) or 0) > 0
		local commitment = { committed = false, reason = actionable and 'selection_only' or 'not_actionable' }
		if actionable then
			commitment = combat_commitment_evaluate(ctx, ctx.target, { allow_player_engaged = false })
			if type(commitment) ~= 'table' then
				error('pet combat commitment evaluator must return a table')
			end
		end
		local valid = actionable and commitment.committed == true
		ctx.target_combat_committed = valid
		ctx.target_commitment_reason = tostring(commitment.reason or '')
		ctx.target_valid = valid
		ctx.target_id = 0
		ctx.target_hpp = 0
		if valid then
			ctx.target_id = tonumber(ctx.target.id)
			ctx.target_hpp = tonumber(ctx.target.hpp)
		end
		ctx.combat_generation = pet_combat_state.observe_target(state, valid, ctx.target_id)
		return ctx.combat_generation
	end

	function provider.observe_pet_action(act, observed_at)
		require_table(act, 'pet action')
		local adapter_observed = false
		if type(adapter.observe_action) == 'function' then
			adapter_observed = adapter.observe_action(act, observed_at) == true
		end
		if tonumber(act.category) ~= 1 or type(act.targets) ~= 'table' then
			return adapter_observed
		end
		local pet_id = tonumber(act.actor_id)
		if pet_id == nil or pet_id <= 0 then
			return adapter_observed
		end
		if pet_id ~= pet_combat_state.current_pet_id(state) then
			return adapter_observed
		end
		for _, target in ipairs(act.targets) do
			local target_id = tonumber(target and target.id)
			if target_id ~= nil and target_id > 0 then
				pet_combat_state.observe_pet_melee_target(state, pet_id, target_id, observed_at)
				return true
			end
		end
		return adapter_observed
	end

	function provider.observe_coordinator_event(event)
		if type(event) ~= 'table' then
			return
		end
		if event.outcome == 'complete' and (event.kind == 'assault' or event.kind == 'deploy') then
			pet_combat_state.mark_engaged(state, event.combat_generation, event.pet_id)
		end
		if type(adapter.observe_coordinator_event) == 'function' then
			adapter.observe_coordinator_event(event)
		end
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if rawget(_G, 'Start_Engine') ~= true then
			_G.UC_PET_COMBAT_STATUS = {
				state = 'engine_off',
				combat_generation = tonumber(ctx.combat_generation) or 0,
			}
			_G.UC_SMN_PET_COMBAT_STATUS = _G.UC_PET_COMBAT_STATUS
			return
		end

		local snapshot = adapter.snapshot(ctx)
		if snapshot.enabled ~= true then
			_G.UC_PET_COMBAT_STATUS = {
				state = 'disabled',
				combat_generation = tonumber(ctx.combat_generation) or 0,
				pet_id = tonumber(ctx.pet_id) or 0,
			}
			_G.UC_SMN_PET_COMBAT_STATUS = _G.UC_PET_COMBAT_STATUS
			return
		end

		-- Job-specific persistent pet work is collected before combat-target work.
		-- This allows PUP Activate and Maneuver maintenance while no hostile target
		-- exists, without introducing a separate action loop.
		if type(adapter.maintenance) == 'function' then
			local maintenance = adapter.maintenance(snapshot, ctx)
			if type(maintenance) == 'table' then
				if maintenance.action_name ~= nil then
					append_spec(ctx, out, maintenance)
				else
					for i = 1, #maintenance do
						append_spec(ctx, out, maintenance[i])
					end
				end
			end
		end

		if ctx.target_valid ~= true then
			_G.UC_PET_COMBAT_STATUS = {
				state = 'no_target',
				combat_generation = tonumber(ctx.combat_generation) or 0,
				pet_id = tonumber(ctx.pet_id) or 0,
			}
			if snapshot._job_adapter == 'SMN' then
				_G.UC_SMN_PET_COMBAT_STATUS = _G.UC_PET_COMBAT_STATUS
			end
			return
		end

		if snapshot.correct_pet ~= true then
			_G.UC_PET_COMBAT_STATUS = {
				state = snapshot._job_adapter == 'SMN' and 'avatar_mismatch' or 'pet_missing',
				combat_generation = tonumber(ctx.combat_generation) or 0,
				pet_id = tonumber(ctx.pet_id) or 0,
			}
			if snapshot._job_adapter == 'SMN' then
				_G.UC_SMN_PET_COMBAT_STATUS = _G.UC_PET_COMBAT_STATUS
			end
			return
		end

		local generation = ctx.combat_generation
		local pet_id = snapshot.pet_id
		local already_engaged = pet_combat_state.is_engaged(state, generation, pet_id)
		local observed_engagement, inferred_target_id = engagement_observed(ctx, pet_id)
		local _, inferred_target_at = pet_combat_state.observed_pet_target(state, pet_id)
		if not already_engaged and observed_engagement then
			pet_combat_state.mark_engaged(state, generation, pet_id)
			already_engaged = true
		end

		local engagement = adapter.engagement(snapshot, ctx)
		if engagement ~= nil and not already_engaged then
			append_spec(ctx, out, {
				kind = engagement.kind or (engagement.command and engagement.command.kind) or 'assault',
				action_name = engagement.action_name,
				priority_band = engagement.priority_band,
				urgency = engagement.urgency,
				range = tonumber(engagement.range) or 20.0,
				distance = tonumber(engagement.distance) or 0,
				retry_key = engagement.retry_key,
				expected_effect = 'pet_engaged_observed',
				reason_code = 'pet_engagement_required',
				command = engagement.command,
				desired_avatar = snapshot.avatar and snapshot.avatar.name or nil,
			})
		end

		local offensive = adapter.offensive_action(snapshot, ctx)
		if offensive ~= nil then
			append_spec(ctx, out, {
				kind = offensive.kind or (offensive.command and offensive.command.kind) or 'rage',
				action_name = offensive.action_name,
				priority_band = offensive.priority_band,
				urgency = offensive.urgency,
				range = offensive.range,
				distance = offensive.distance,
				retry_key = offensive.retry_key,
				expected_effect = 'rage_recast_consumed',
				reason_code = 'pet_offensive_action_ready',
				command = offensive.command,
				desired_avatar = snapshot.avatar and snapshot.avatar.name or nil,
			})
		end

		_G.UC_PET_COMBAT_STATUS = {
			state = 'ready',
			job = tostring(snapshot._job_adapter or ''),
			combat_generation = generation,
			pet_id = pet_id,
			target_id = ctx.target_id,
			inferred_pet_target_id = inferred_target_id,
			inferred_pet_target_at = inferred_target_at,
			engagement_satisfied = already_engaged,
			engagement_eligible = engagement ~= nil and not already_engaged,
			offensive_eligible = offensive ~= nil,
		}
		if snapshot._job_adapter == 'SMN' then
			_G.UC_SMN_PET_COMBAT_STATUS = {
				state = 'ready',
				combat_generation = generation,
				pet_id = pet_id,
				target_id = ctx.target_id,
				inferred_pet_target_id = inferred_target_id,
				inferred_pet_target_at = inferred_target_at,
				engagement_satisfied = already_engaged,
				assault_eligible = engagement ~= nil and not already_engaged,
				rage_eligible = offensive ~= nil,
			}
		end
	end

	function provider.revalidate(selected, ctx)
		local snapshot = adapter.snapshot(ctx)
		local detail = require_table(selected.detail, 'selected.detail')
		local command = type(detail.pet_command) == 'table' and detail.pet_command or nil
		if command ~= nil
			and (command.kind == 'assault' or command.kind == 'deploy')
			and snapshot.correct_pet == true then
			local observed_engagement = engagement_observed(ctx, snapshot.pet_id)
			if observed_engagement then
				return false, 'engagement_satisfied'
			end
		end
		return adapter.revalidate(snapshot, selected, ctx)
	end

	return provider
end

return M
