local pet_commands = require('uc_pet_commands')

local M = {}

local FAILURE_MESSAGE_IDS = {
	[5] = true,
	[16] = true,
	[17] = true,
	[18] = true,
	[71] = true,
	[87] = true,
	[88] = true,
	[94] = true,
	[128] = true,
	[155] = true,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_positive_number(value, name)
	local number = tonumber(value)
	if number == nil or number <= 0 then
		error(name .. ' must be a positive number')
	end
	return number
end

local function require_now(value)
	local number = tonumber(value)
	if number == nil or number < 0 then
		error('pet command time must be a non-negative number')
	end
	return number
end

local function copy_command(command)
	local copy = {}
	for key, value in pairs(command) do
		copy[key] = value
	end
	return copy
end

local function finish(state, now, outcome, reason)
	local pending = state.pending
	if type(pending) ~= 'table' then
		return nil
	end
	local event = {
		outcome = outcome,
		reason = reason,
		kind = pending.kind,
		action_name = pending.action_name,
		retry_key = pending.retry_key,
		pet_id = pending.pet_id,
		target_id = pending.target_id,
		combat_generation = pending.combat_generation,
		at = now,
	}
	if outcome == 'complete' then
		state.failure_counts[pending.retry_key] = nil
		state.retry_until[pending.retry_key] = nil
		event.retry_delay = 0
	else
		local count = (state.failure_counts[pending.retry_key] or 0) + 1
		state.failure_counts[pending.retry_key] = count
		local delay = state.backoff_base * (2 ^ (count - 1))
		if delay > state.backoff_max then
			delay = state.backoff_max
		end
		state.retry_until[pending.retry_key] = now + delay
		event.retry_delay = delay
		event.retry_count = count
	end
	state.pending = nil
	state.last_event = event
	return event
end

local function recast_consumed(pending, ctx)
	if pending.recast_id == nil then
		return false
	end
	if ctx.ability_recasts_present ~= true then
		return false
	end
	local recasts = require_table(ctx.ability_recasts, 'pet command context ability_recasts')
	local current = tonumber(recasts[pending.recast_id])
	if current == nil then
		error(('pet command context is missing recast id %d'):format(pending.recast_id))
	end
	return current > pending.recast_before
end

local function player_has_effect(ctx, effect_id)
	local buffs = require_table(ctx.player_buffs, 'pet command context player_buffs')
	for i = 1, #buffs do
		if tonumber(buffs[i]) == effect_id then
			return true
		end
	end
	return false
end

local function target_is_current_and_live(pending, ctx)
	return tonumber(ctx.combat_generation) == pending.combat_generation
		and tonumber(ctx.target_id) == pending.target_id
		and ctx.target_valid == true
		and (tonumber(ctx.target_hpp) or 0) > 0
end

function M.new(options)
	options = require_table(options, 'pet command coordinator options')
	return {
		timeout = require_positive_number(options.timeout, 'pet command timeout'),
		backoff_base = require_positive_number(options.backoff_base, 'pet command backoff_base'),
		backoff_max = require_positive_number(options.backoff_max, 'pet command backoff_max'),
		pending = nil,
		retry_until = {},
		failure_counts = {},
		last_event = nil,
	}
end

function M.is_pending(state)
	state = require_table(state, 'pet command coordinator state')
	return type(state.pending) == 'table'
end

function M.reset(state, reason)
	state = require_table(state, 'pet command coordinator state')
	if type(reason) ~= 'string' or reason == '' then
		error('pet command reset reason must be a non-empty string')
	end
	state.pending = nil
	state.retry_until = {}
	state.failure_counts = {}
	state.last_event = {
		outcome = 'reset',
		reason = reason,
		at = 0,
	}
end

function M.can_attempt(state, retry_key, now)
	state = require_table(state, 'pet command coordinator state')
	if type(retry_key) ~= 'string' or retry_key == '' then
		error('pet command retry_key must be a non-empty string')
	end
	now = require_now(now)
	if type(state.pending) == 'table' then
		return false, 'pet_command_pending', 0
	end
	local retry_at = tonumber(state.retry_until[retry_key]) or 0
	if retry_at > now then
		return false, 'retry_backoff', retry_at - now
	end
	return true, '', 0
end

function M.begin(state, command, now)
	state = require_table(state, 'pet command coordinator state')
	pet_commands.validate(command)
	now = require_now(now)
	if type(state.pending) == 'table' then
		error('cannot begin a pet command while another pet command is pending')
	end
	if type(command.retry_key) ~= 'string' or command.retry_key == '' then
		error('pet command retry_key must be a non-empty string')
	end
	local allowed, reason = M.can_attempt(state, command.retry_key, now)
	if not allowed then
		error('cannot begin pet command: ' .. reason)
	end
	local pending = copy_command(command)
	pending.dispatched_at = now
	pending.deadline = now + state.timeout
	if pending.recast_id ~= nil then
		local before = tonumber(pending.recast_before)
		if before == nil or before < 0 then
			error('pet command recast_before must be a non-negative number')
		end
		pending.recast_before = before
	end
	state.pending = pending
	state.last_event = {
		outcome = 'pending',
		reason = 'dispatched',
		kind = pending.kind,
		action_name = pending.action_name,
		retry_key = pending.retry_key,
		at = now,
	}
	return pending
end

function M.complete(state, now, reason)
	state = require_table(state, 'pet command coordinator state')
	now = require_now(now)
	if type(reason) ~= 'string' or reason == '' then
		error('pet command completion reason must be a non-empty string')
	end
	return finish(state, now, 'complete', reason)
end

function M.fail(state, now, reason)
	state = require_table(state, 'pet command coordinator state')
	now = require_now(now)
	if type(reason) ~= 'string' or reason == '' then
		error('pet command failure reason must be a non-empty string')
	end
	return finish(state, now, 'failed', reason)
end

function M.observe(state, ctx)
	state = require_table(state, 'pet command coordinator state')
	ctx = require_table(ctx, 'pet command context')
	local pending = state.pending
	if type(pending) ~= 'table' then
		return nil
	end
	local now = require_now(ctx.now)
	local current_pet_id = tonumber(ctx.pet_id) or 0
	local pet_matches = ctx.pet_present == true and current_pet_id == pending.pet_id

	if pending.kind == 'release' then
		if not pet_matches then
			return finish(state, now, 'complete', 'pet_disappeared')
		end
	elseif not pet_matches then
		return finish(state, now, 'failed', 'stale_pet')
	elseif pending.kind == 'assault' then
		if not target_is_current_and_live(pending, ctx) then
			return finish(state, now, 'failed', 'stale_target')
		end
		local inferred_target_id = tonumber(ctx.pet_inferred_target_id)
		if inferred_target_id == nil then
			error('pet command context inferred target id must be numeric')
		end
		if inferred_target_id > 0 and inferred_target_id == pending.target_id then
			return finish(state, now, 'complete', 'pet_action_target_observed')
		end
		if inferred_target_id == 0 and ctx.pet_status == 1 then
			return finish(state, now, 'complete', 'pet_engaged_observed')
		end
	elseif pending.kind == 'ward' then
		if player_has_effect(ctx, pending.expected_effect_id) then
			return finish(state, now, 'complete', 'ward_effect_observed')
		end
		if recast_consumed(pending, ctx) then
			return finish(state, now, 'complete', 'ward_recast_consumed')
		end
	elseif pending.kind == 'rage' then
		if not target_is_current_and_live(pending, ctx) then
			return finish(state, now, 'failed', 'stale_target')
		end
		if recast_consumed(pending, ctx) then
			return finish(state, now, 'complete', 'rage_recast_consumed')
		end
	end

	if now >= pending.deadline then
		return finish(state, now, 'failed', 'timeout')
	end
	return nil
end

function M.observe_action(state, act, now)
	state = require_table(state, 'pet command coordinator state')
	act = require_table(act, 'pet action event')
	now = require_now(now)
	local pending = state.pending
	if type(pending) ~= 'table' then
		return nil
	end
	if tonumber(act.actor_id) ~= pending.pet_id then
		return nil
	end
	if pending.kind == 'assault' then
		if type(act.targets) ~= 'table' then
			return nil
		end
		for _, target in ipairs(act.targets) do
			if tonumber(target and target.id) == pending.target_id then
				return finish(state, now, 'complete', 'pet_action_on_target')
			end
		end
		return nil
	end
	if pending.kind ~= 'ward' and pending.kind ~= 'rage' then
		return nil
	end
	if tonumber(act.param) ~= pending.action_id then
		return nil
	end
	return finish(state, now, 'complete', 'pet_action_completed')
end

function M.observe_action_message(state, msg, player_id, now)
	state = require_table(state, 'pet command coordinator state')
	msg = require_table(msg, 'pet action message')
	now = require_now(now)
	local pending = state.pending
	if type(pending) ~= 'table' then
		return nil
	end
	local actor_id = tonumber(msg.actor_id) or 0
	if actor_id ~= tonumber(player_id) and actor_id ~= pending.pet_id then
		return nil
	end
	local message_id = tonumber(msg.message_id) or 0
	if FAILURE_MESSAGE_IDS[message_id] ~= true then
		return nil
	end
	local target_id = tonumber(msg.target_id) or 0
	if pending.target_id ~= nil
		and target_id > 0
		and target_id ~= pending.target_id
		and target_id ~= tonumber(player_id)
		and target_id ~= pending.pet_id then
		return nil
	end
	local reason = message_id == 16 and 'interrupted' or ('action_message_%d'):format(message_id)
	return finish(state, now, 'failed', reason)
end

function M.is_failure_message(message_id)
	return FAILURE_MESSAGE_IDS[tonumber(message_id) or 0] == true
end

return M
