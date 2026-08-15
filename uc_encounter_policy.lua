local action_classifier = require('uc_encounter_action_classifier')
local skillchain_elements = require('uc_skillchain_elements')

local M = {}

local POLICY_REASON = {
	water_damage = 'encounter_water_damage',
	water_skillchain = 'encounter_water_skillchain',
	repeat_action_wall = 'encounter_repeat_action_wall',
}

local POLICY_ID = {
	water_damage = 'plovid_water_damage',
	water_skillchain = 'plovid_water_skillchain',
	repeat_action_wall = 'dhartok_repeat_action_wall',
}

local function policy_mode(snapshot, name)
	local modes = snapshot.policy_modes
	if type(modes) ~= 'table' then
		error('resolved encounter snapshot requires policy_modes')
	end
	local mode = modes[name]
	if mode ~= 'enforce' and mode ~= 'warn' and mode ~= 'off' then
		error('resolved encounter snapshot has invalid policy mode: ' .. tostring(name))
	end
	return mode
end

local function decision(ctx, proposal, snapshot, policy_name, fields)
	local mode = policy_mode(snapshot, policy_name)
	if mode == 'off' then
		return true, '', nil
	end
	local record = {
		policy_id = POLICY_ID[policy_name],
		mode = mode,
		reason = POLICY_REASON[policy_name],
		encounter_id = snapshot.resolved_id,
		boss_id = tonumber(snapshot.boss.id),
		proposal_id = tostring(proposal.proposal_id or ''),
		action_type = tostring(proposal.action_type or ''),
		action_name = tostring(proposal.action_name or ''),
		target_id = tonumber(proposal.target_id),
		observed_at = tonumber(ctx.now),
	}
	for key, value in pairs(fields or {}) do
		record[key] = value
	end
	if mode == 'enforce' then
		return false, record.reason, record
	end
	return true, '', record
end

function M.validate(ctx, proposal, snapshot, deps)
	if type(ctx) ~= 'table' then
		error('uc_encounter_policy.validate requires ctx')
	end
	if type(proposal) ~= 'table' then
		error('uc_encounter_policy.validate requires proposal')
	end
	if type(snapshot) ~= 'table' then
		error('uc_encounter_policy.validate requires snapshot')
	end
	if snapshot.enabled ~= true or snapshot.resolved_id == '' or type(snapshot.boss) ~= 'table' then
		return true, '', nil
	end
	if tostring(proposal.target_kind or '') ~= 'mob' then
		return true, '', nil
	end
	local proposal_target_id = tonumber(proposal.target_id)
	local boss_id = tonumber(snapshot.boss.id)
	if proposal_target_id == nil or boss_id == nil or proposal_target_id ~= boss_id then
		return true, '', nil
	end
	local classify = action_classifier.classify
	if deps ~= nil then
		if type(deps) ~= 'table' or type(deps.classify) ~= 'function' then
			error('encounter policy deps.classify must be a function')
		end
		classify = deps.classify
	end
	local classification = classify(proposal)
	if type(classification) ~= 'table' then
		error('encounter action classifier must return a table')
	end

	if classification.direct_damage == true and classification.element == 'Water' then
		return decision(ctx, proposal, snapshot, 'water_damage', {
			element = classification.element,
			classification_proof = tostring(classification.proof or ''),
			resource_id = tonumber(classification.resource_id),
		})
	end

	if tostring(proposal.action_type or '') == 'ws' then
		local skillchain_plan = proposal.skillchain_plan
		local predicted_result = type(skillchain_plan) == 'table'
			and tostring(skillchain_plan.predicted_result or '') or ''
		if predicted_result ~= '' and skillchain_elements.contains(predicted_result, 'Water') then
			return decision(ctx, proposal, snapshot, 'water_skillchain', {
				predicted_result = predicted_result,
				resonance_generation = tonumber(skillchain_plan.resonance_generation),
			})
		end
	end

	if snapshot.resolved_id == 'sortie_dhartok'
		and classification.action_class ~= ''
		and classification.action_key ~= '' then
		local repeat_key = classification.action_class .. ':' .. classification.action_key
		local recent = type(snapshot.recent_repeat_actions) == 'table'
			and snapshot.recent_repeat_actions[repeat_key] or nil
		if type(recent) == 'table' then
			local now = tonumber(ctx.now)
			local succeeded_at = tonumber(recent.observed_at)
			local tuning = snapshot.tuning
			local guard_s = type(tuning) == 'table' and tuning.repeat_action_guard_s or nil
			if now == nil or succeeded_at == nil or type(guard_s) ~= 'number' or guard_s <= 0 then
				error('Dhartok repeat-action policy requires valid monotonic timestamps and guard tuning')
			end
			local elapsed = now - succeeded_at
			if elapsed < 0 then
				error('Dhartok repeat-action observation is newer than scheduler context')
			end
			if elapsed < guard_s then
				return decision(ctx, proposal, snapshot, 'repeat_action_wall', {
					action_class = classification.action_class,
					action_key = classification.action_key,
					last_success_at = succeeded_at,
					guard_s = guard_s,
					remaining_s = guard_s - elapsed,
				})
			end
		end
	end

	return true, '', nil
end

return M
