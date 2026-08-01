local pet_combat_state = require('uc_pet_combat_state')

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

local function make_proposal(ctx, spec)
	return {
		proposal_id = ('pet.combat.%s.%d'):format(spec.kind, math.floor(ctx.now * 1000)),
		family_id = 'combat.pet.' .. spec.kind,
		provider = 'pet_combat',
		action_type = 'pet',
		action_name = spec.action_name,
		target_kind = 'mob',
		target_id = ctx.target_id,
		target_name = tostring(ctx.target.name or ''),
		priority_band = require_number(spec.priority_band, 'pet combat priority band'),
		urgency = require_number(spec.urgency, 'pet combat urgency'),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = 'none',
		range_policy = { min = 0.0, max = spec.range, los_required = false },
		recast_key = spec.retry_key,
		duplicate_suppression_key = spec.retry_key,
		lock_class = 'pet_command',
		expected_ack = 'pet_command',
		expected_effect = spec.expected_effect,
		sticky = false,
		can_preempt_movement = false,
		can_preempt_same_band = false,
		reason_code = spec.reason_code,
		detail = {
			pet_command = spec.command,
			pet_id = spec.command.pet_id,
			target_id = spec.command.target_id,
			combat_generation = spec.command.combat_generation,
			desired_avatar = spec.desired_avatar,
			range = spec.range,
			distance = spec.distance,
		},
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
	local state = require_table(deps.state, 'deps.state')

	local provider = {}

	local function engagement_observed(ctx, pet_id)
		local observed_target_id = pet_combat_state.observed_pet_target(state, pet_id)
		if observed_target_id > 0 then
			return observed_target_id == ctx.target_id, observed_target_id
		end
		return ctx.pet_status == 1, 0
	end

	function provider.observe_target(ctx)
		require_table(ctx, 'ctx')
		pet_combat_state.observe_pet_state(
			state,
			ctx.pet_present,
			ctx.pet_id,
			ctx.pet_status
		)
		local valid = ctx.combat_domain_enabled == true
			and ctx.target_present == true
			and target_is_actionable(ctx.target, ctx.now, true)
			and (tonumber(ctx.target.id) or 0) > 0
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
		if tonumber(act.category) ~= 1 or type(act.targets) ~= 'table' then
			return false
		end
		local pet_id = tonumber(act.actor_id)
		if pet_id == nil or pet_id <= 0 then
			return false
		end
		if pet_id ~= pet_combat_state.current_pet_id(state) then
			return false
		end
		for _, target in ipairs(act.targets) do
			local target_id = tonumber(target and target.id)
			if target_id ~= nil and target_id > 0 then
				pet_combat_state.observe_pet_melee_target(state, pet_id, target_id, observed_at)
				return true
			end
		end
		return false
	end

	function provider.observe_coordinator_event(event)
		if type(event) ~= 'table' or event.outcome ~= 'complete' or event.kind ~= 'assault' then
			return
		end
		pet_combat_state.mark_engaged(state, event.combat_generation, event.pet_id)
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if rawget(_G, 'Start_Engine') ~= true or ctx.target_valid ~= true then
			local state_name = 'engine_off'
			if rawget(_G, 'Start_Engine') == true then
				state_name = 'no_target'
			end
			_G.UC_SMN_PET_COMBAT_STATUS = {
				state = state_name,
				combat_generation = tonumber(ctx.combat_generation) or 0,
			}
			return
		end
		local snapshot = adapter.snapshot(ctx)
		if snapshot.enabled ~= true or snapshot.correct_pet ~= true then
			_G.UC_SMN_PET_COMBAT_STATUS = {
				state = snapshot.enabled == true and 'avatar_mismatch' or 'disabled',
				combat_generation = tonumber(ctx.combat_generation) or 0,
				pet_id = tonumber(ctx.pet_id) or 0,
			}
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
			local allowed = coordinator_can_attempt(engagement.retry_key, ctx.now)
			if allowed then
				out[#out + 1] = make_proposal(ctx, {
					kind = 'assault',
					action_name = engagement.action_name,
					priority_band = engagement.priority_band,
					urgency = engagement.urgency,
					range = 20.0,
					distance = 0,
					retry_key = engagement.retry_key,
					expected_effect = 'pet_engaged_observed',
					reason_code = 'pet_engagement_required',
					command = engagement.command,
					desired_avatar = snapshot.avatar.name,
				})
			end
		end

		local offensive = adapter.offensive_action(snapshot, ctx)
		if offensive ~= nil then
			local allowed = coordinator_can_attempt(offensive.retry_key, ctx.now)
			if allowed then
				out[#out + 1] = make_proposal(ctx, {
					kind = 'rage',
					action_name = offensive.action_name,
					priority_band = offensive.priority_band,
					urgency = offensive.urgency,
					range = offensive.range,
					distance = offensive.distance,
					retry_key = offensive.retry_key,
					expected_effect = 'rage_recast_consumed',
					reason_code = 'pet_offensive_action_ready',
					command = offensive.command,
					desired_avatar = snapshot.avatar.name,
				})
			end
		end
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

	function provider.revalidate(selected, ctx)
		local snapshot = adapter.snapshot(ctx)
		local detail = require_table(selected.detail, 'selected.detail')
		local command = require_table(detail.pet_command, 'selected.detail.pet_command')
		if command.kind == 'assault' and snapshot.correct_pet == true then
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
