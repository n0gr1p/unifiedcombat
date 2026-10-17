local extension_config = require('uc_combat_extension_config')
local party_action_event = require('uc_party_action_event')

local M = {}

local party_lock = nil
local last_transition = 'none'

local function trim(value)
	if type(value) ~= 'string' then
		return ''
	end
	return value:match('^%s*(.-)%s*$') or ''
end

local function canonical(value)
	return trim(value):lower()
end

local function deep_copy(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		return nil
	end
	visited[value] = true
	local out = {}
	for key, inner in pairs(value) do
		out[deep_copy(key, visited)] = deep_copy(inner, visited)
	end
	visited[value] = nil
	return out
end

local function current_step(lock)
	if type(lock) ~= 'table' or type(lock.steps) ~= 'table' then
		return nil
	end
	return lock.steps[tonumber(lock.step_index) or 1]
end

local function public_lock(lock)
	if type(lock) ~= 'table' then
		return nil
	end
	local out = deep_copy(lock)
	local step = current_step(lock)
	if type(step) == 'table' then
		out.action_type = trim(step.action_type):lower()
		out.action_name = trim(step.action_name)
		out.action_target = trim(step.target):lower()
		out.action_optional = step.optional == true
		out.target_kind = out.action_target == 'self' and 'self' or 'mob'
	else
		out.action_type = nil
		out.action_name = nil
		out.action_target = nil
		out.action_optional = nil
		out.target_kind = nil
	end
	out.step_count = type(lock.steps) == 'table' and #lock.steps or 0
	return out
end

local function release(reason)
	if type(party_lock) ~= 'table' then
		return nil
	end
	local released = public_lock(party_lock)
	party_lock = nil
	last_transition = ('release:%s:%s'):format(tostring(reason or 'complete'), tostring(released.name or ''))
	return released
end

local function prune_unconfigured_party_sequence()
    if type(party_lock) == 'table'
        and not require('uc_reaction_sequence_policy').current(party_lock) then
        return release('config_changed')
    end
    return nil
end

local function advance_step(reason)
	if type(party_lock) ~= 'table' then
		return nil, nil
	end
	party_lock.step_index = (tonumber(party_lock.step_index) or 1) + 1
	party_lock.step_state = 'pending'
	party_lock.dispatched_actor_id = 0
	party_lock.dispatched_at = 0
	party_lock.dispatched_action_type = ''
	party_lock.dispatched_action_name = ''
	party_lock.last_step_reason = tostring(reason or 'complete')
	if party_lock.step_index > #party_lock.steps then
		return nil, release(reason or 'sequence_complete')
	end
	last_transition = ('step:%d:%s'):format(party_lock.step_index, tostring(party_lock.name or ''))
	return public_lock(party_lock), nil
end

local function matching_rule(event)
	local rules = extension_config.reaction_rules()
	for i = 1, #(rules or {}) do
		local rule = rules[i]
		if type(rule) == 'table'
			and rule.trigger == 'party_action_complete'
			and rule.response == 'use_sequence'
			and canonical(rule.action_type) == canonical(event.action_type)
			and canonical(rule.name) == canonical(event.action_name) then
			local source_id = party_action_event.party_member_actor_id(rule.source_name)
			if source_id > 0 and source_id == tonumber(event.actor_id) then
				return rule, i, source_id
			end
		end
	end
	return nil, nil, 0
end

local function local_sequence_completion(act)
	if type(party_lock) ~= 'table' or party_lock.step_state ~= 'dispatched' then
		return nil
	end
	local event = party_action_event.completed(act)
	if type(event) ~= 'table'
		or tonumber(event.actor_id) ~= (tonumber(party_lock.dispatched_actor_id) or 0) then
		return nil
	end
	local step = current_step(party_lock)
	if type(step) ~= 'table' then
		return nil
	end
	local action_type = trim(step.action_type):lower()
	if action_type == 'pet'
		or canonical(event.action_type) ~= canonical(action_type)
		or canonical(event.action_name) ~= canonical(step.action_name) then
		return nil
	end
	local activated, released = advance_step('step_complete')
	return {
		activated = activated,
		released = released,
		released_target_id = released and (tonumber(released.actor_id) or 0) or nil,
		sequence_step_completed = true,
		completed_action_type = action_type,
		completed_action_name = event.action_name,
	}
end

function M.extend(base)
	if type(base) ~= 'table' then
		error('uc_reaction_party_sequence_runtime requires base reaction runtime')
	end
	if base._party_sequence_extension_installed == true then
		return base
	end

	local base_on_action = base.on_action
	local base_evaluate = base.evaluate
	local base_prune = base.prune_invalid_ability_windows
	local base_get_action_lock = base.get_action_lock
	local base_skip_optional_step = base.skip_optional_step
	local base_note_sequence_action_dispatched = base.note_sequence_action_dispatched
	local base_note_sequence_pet_command_completed = base.note_sequence_pet_command_completed
	local base_note_sequence_pet_command_failed = base.note_sequence_pet_command_failed
	local base_blocks_proposal = base.blocks_proposal
	local base_blocks_movement = base.blocks_movement
	local base_owns_movement = base.owns_movement
	local base_requires_disengage = base.requires_disengage
	local base_cancel = base.cancel
	local base_reset = base.reset
	local base_status = base.status

	function base.on_action(act, current_target_id, now, actor_is_valid_enemy)
		prune_unconfigured_party_sequence()
		local completed = local_sequence_completion(act)
		if completed ~= nil then
			return completed
		end

		local event = party_action_event.completed(act)
		if type(event) == 'table' then
			local rule, rule_index, source_id = matching_rule(event)
			local instance_actor_id = tonumber(current_target_id) or 0
			if type(rule) == 'table'
				and instance_actor_id > 0
				and party_action_event.current_enemy_instance_valid(instance_actor_id) then
				local ok, err = extension_config.validate_action_rule(rule)
				if ok ~= true then
					error(('invalid party action reaction rule %d: %s'):format(rule_index, tostring(err or 'invalid')))
				end
				local key = table.concat({
					'party_action_complete',
					tostring(instance_actor_id),
					canonical(rule.source_name),
					canonical(rule.action_type),
					canonical(rule.name),
				}, ':')
				if type(party_lock) == 'table' and party_lock.key == key then
					return {}
				end
				local released = release('superseded')
				local status = base_status()
				for _, lock in ipairs(type(status) == 'table' and type(status.active) == 'table' and status.active or {}) do
					if tostring(lock.response or '') == 'use_sequence'
						and tonumber(lock.actor_id) == instance_actor_id then
						base_cancel(lock.key, 'party_action_complete_superseded')
					end
				end
				party_lock = {
					key = key,
					trigger = 'party_action_complete',
					name = trim(rule.name),
					response = 'use_sequence',
					actor_id = instance_actor_id,
					event_actor_id = source_id,
					event_actor_name = trim(rule.source_name),
					completed_action_type = trim(rule.action_type):lower(),
					completed_action_name = trim(rule.name),
					started_at = tonumber(now) or 0,
					rule_index = rule_index,
					steps = deep_copy(rule.steps),
					step_index = 1,
					step_state = 'pending',
					dispatched_actor_id = 0,
					dispatched_at = 0,
					dispatched_action_type = '',
					dispatched_action_name = '',
				}
				last_transition = 'party_complete:' .. tostring(event.action_name)
				return {
					activated = public_lock(party_lock),
					released = released,
				}
			end
		end
		return base_on_action(act, current_target_id, now, actor_is_valid_enemy)
	end

	function base.evaluate(current_target_id, effects, now)
		prune_unconfigured_party_sequence()
		if type(party_lock) == 'table' then
			return public_lock(party_lock), nil
		end
		return base_evaluate(current_target_id, effects, now)
	end

	function base.prune_invalid_ability_windows(actor_is_valid_enemy)
		local released = prune_unconfigured_party_sequence()
		if type(party_lock) == 'table'
			and actor_is_valid_enemy(tonumber(party_lock.actor_id) or 0) ~= true then
			released = release('actor_unavailable')
		end
		return released or base_prune(actor_is_valid_enemy)
	end

	function base.get_action_lock()
		prune_unconfigured_party_sequence()
		if type(party_lock) == 'table' then
			return public_lock(party_lock)
		end
		return base_get_action_lock()
	end

	function base.skip_optional_step(key_value, reason)
		if type(party_lock) ~= 'table' or tostring(key_value or '') ~= party_lock.key then
			return base_skip_optional_step(key_value, reason)
		end
		if party_lock.step_state ~= 'pending' then
			return public_lock(party_lock), 'step_already_dispatched'
		end
		local step = current_step(party_lock)
		if type(step) ~= 'table' or step.optional ~= true then
			return public_lock(party_lock), 'step_required'
		end
		local activated, released = advance_step(reason or 'optional_unavailable')
		return activated, released and 'sequence_complete' or 'skipped'
	end

	function base.note_sequence_action_dispatched(key_value, action_type, action_name, target_kind, target_id, action_actor_id, now)
		if type(party_lock) ~= 'table' or tostring(key_value or '') ~= party_lock.key then
			return base_note_sequence_action_dispatched(key_value, action_type, action_name, target_kind, target_id, action_actor_id, now)
		end
		if party_lock.step_state ~= 'pending' then
			return false, 'step_already_dispatched'
		end
		local step = current_step(party_lock)
		if type(step) ~= 'table' then
			return false, 'step_missing'
		end
		local expected_type = trim(step.action_type):lower()
		local expected_name = trim(step.action_name)
		local expected_target = trim(step.target):lower()
		local actual_kind = tostring(target_kind or '')
		if tostring(action_type or ''):lower() ~= expected_type
			or canonical(action_name) ~= canonical(expected_name)
			or (expected_target == 'self' and actual_kind ~= 'self')
			or (expected_target == 'actor' and actual_kind ~= 'mob')
			or (expected_target == 'actor' and (tonumber(target_id) or 0) ~= (tonumber(party_lock.actor_id) or 0)) then
			return false, 'dispatch_does_not_match_current_step'
		end
		local action_actor = tonumber(action_actor_id) or 0
		if action_actor <= 0 then
			return false, 'action_actor_unavailable'
		end
		party_lock.step_state = 'dispatched'
		party_lock.dispatched_actor_id = action_actor
		party_lock.dispatched_at = tonumber(now) or 0
		party_lock.dispatched_action_type = expected_type
		party_lock.dispatched_action_name = expected_name
		last_transition = ('dispatched:%d:%s'):format(tonumber(party_lock.step_index) or 1, tostring(party_lock.name or ''))
		return true, 'dispatched'
	end

	function base.note_sequence_pet_command_completed(key_value, action_name, target_id, pet_id, reason)
		if type(party_lock) ~= 'table' or tostring(key_value or '') ~= party_lock.key then
			return base_note_sequence_pet_command_completed(key_value, action_name, target_id, pet_id, reason)
		end
		local step = current_step(party_lock)
		if type(step) ~= 'table'
			or trim(step.action_type):lower() ~= 'pet'
			or party_lock.step_state ~= 'dispatched'
			or canonical(step.action_name) ~= canonical(action_name)
			or trim(step.target):lower() ~= 'actor'
			or (tonumber(target_id) or 0) ~= (tonumber(party_lock.actor_id) or 0)
			or (tonumber(pet_id) or 0) ~= (tonumber(party_lock.dispatched_actor_id) or 0) then
			return public_lock(party_lock), 'pet_completion_mismatch'
		end
		local activated, released = advance_step('pet_' .. tostring(reason or 'complete'))
		return activated or released, released and 'sequence_complete' or 'advanced'
	end

	function base.note_sequence_pet_command_failed(key_value, action_name, target_id, pet_id, reason)
		if type(party_lock) ~= 'table' or tostring(key_value or '') ~= party_lock.key then
			return base_note_sequence_pet_command_failed(key_value, action_name, target_id, pet_id, reason)
		end
		local step = current_step(party_lock)
		if type(step) ~= 'table'
			or trim(step.action_type):lower() ~= 'pet'
			or canonical(step.action_name) ~= canonical(action_name)
			or trim(step.target):lower() ~= 'actor'
			or (tonumber(target_id) or 0) ~= (tonumber(party_lock.actor_id) or 0)
			or (tonumber(pet_id) or 0) ~= (tonumber(party_lock.dispatched_actor_id) or 0) then
			return public_lock(party_lock), 'pet_failure_mismatch'
		end
		party_lock.step_state = 'pending'
		party_lock.dispatched_actor_id = 0
		party_lock.dispatched_at = 0
		party_lock.dispatched_action_type = ''
		party_lock.dispatched_action_name = ''
		party_lock.last_step_reason = 'pet_' .. tostring(reason or 'failed')
		last_transition = ('retry:%d:%s'):format(tonumber(party_lock.step_index) or 1, tostring(party_lock.name or ''))
		return public_lock(party_lock), 'retry'
	end

	function base.blocks_proposal(lock, proposal)
		if type(party_lock) == 'table'
			and type(lock) == 'table'
			and tostring(lock.key or '') == party_lock.key then
			if type(proposal) ~= 'table' then
				return false
			end
			local step = current_step(party_lock)
			if type(step) ~= 'table' or party_lock.step_state ~= 'pending' then
				return true
			end
			local expected_target = trim(step.target):lower()
			local target_matches = expected_target == 'self'
				and tostring(proposal.target_kind or '') == 'self'
				or expected_target == 'actor'
					and tostring(proposal.target_kind or '') == 'mob'
					and (tonumber(proposal.target_id) or 0) == (tonumber(party_lock.actor_id) or 0)
			local expected_type = trim(step.action_type):lower()
			local expected_provider = expected_type == 'pet' and 'pet_combat' or 'combat'
			if tostring(proposal.provider or '') == expected_provider
				and tostring(proposal.family_id or '') == 'combat.reaction.sequence'
				and tostring(proposal.action_type or '') == expected_type
				and canonical(proposal.action_name) == canonical(step.action_name)
				and target_matches then
				return false
			end
			return true
		end
		return base_blocks_proposal(lock, proposal)
	end

	function base.blocks_movement(lock)
		if type(party_lock) == 'table' and type(lock) == 'table' and tostring(lock.key or '') == party_lock.key then
			return true
		end
		return base_blocks_movement(lock)
	end

	function base.owns_movement(lock)
		if type(party_lock) == 'table' and type(lock) == 'table' and tostring(lock.key or '') == party_lock.key then
			return false
		end
		return base_owns_movement(lock)
	end

	function base.requires_disengage(lock, player_status)
		if type(party_lock) == 'table' and type(lock) == 'table' and tostring(lock.key or '') == party_lock.key then
			return false
		end
		return base_requires_disengage(lock, player_status)
	end

	function base.cancel(key_value, reason)
		if type(party_lock) == 'table' and tostring(key_value or '') == party_lock.key then
			local released = release(reason or 'manual')
			return released, nil
		end
		return base_cancel(key_value, reason)
	end

	function base.reset(reason)
		local released_actor_id = type(party_lock) == 'table' and (tonumber(party_lock.actor_id) or nil) or nil
		party_lock = nil
		last_transition = 'reset:' .. tostring(reason or 'manual')
		local base_released = base_reset(reason)
		return released_actor_id or base_released
	end

	function base.status()
		local status = base_status()
		if type(party_lock) == 'table' then
			status.active = type(status.active) == 'table' and status.active or {}
			status.active[#status.active + 1] = public_lock(party_lock)
			table.sort(status.active, function(left, right)
				return tostring(left.key or '') < tostring(right.key or '')
			end)
			status.last_transition = last_transition
		end
		return status
	end

	base._party_sequence_extension_installed = true
	return base
end

return M
