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

local OVERLOAD_BUFF_ID = 299

-- Astral Conduit suppresses the normal Blood Pact recast, so Rage commands
-- cannot use recast consumption as their primary serialization barrier.
-- Wait briefly for the readying packet, then hold the pet lane through the
-- actual pact result. Failed launch attempts retry quickly without exponential
-- backoff so a transient "pet still acting" rejection does not waste Conduit.
local DEFAULT_CONDUIT_RAGE_START_TIMEOUT = 1.25
local DEFAULT_CONDUIT_RAGE_FINISH_TIMEOUT = 4.0
local DEFAULT_CONDUIT_RAGE_BACKOFF = 0.20

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
		if key == 'expected_effect_ids' then
			copy[key] = {}
			for i = 1, #value do
				copy[key][i] = value[i]
			end
		else
			copy[key] = value
		end
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
		reaction_key = pending.reaction_key,
		reaction_step_index = pending.reaction_step_index,
		at = now,
	}
	if outcome == 'complete' then
		state.failure_counts[pending.retry_key] = nil
		state.retry_until[pending.retry_key] = nil
		event.retry_delay = 0
	else
		local count = (state.failure_counts[pending.retry_key] or 0) + 1
		state.failure_counts[pending.retry_key] = count
		local conduit_rage = pending.kind == 'rage' and pending.astral_conduit == true
		local delay
		if conduit_rage then
			delay = state.conduit_rage_backoff
		else
			delay = state.backoff_base * (2 ^ (count - 1))
			if delay > state.backoff_max then
				delay = state.backoff_max
			end
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

local function player_has_all_effects(ctx, effect_ids)
	local buffs = require_table(ctx.player_buffs, 'pet command context player_buffs')
	for effect_index = 1, #effect_ids do
		local expected = effect_ids[effect_index]
		local found = false
		for buff_index = 1, #buffs do
			if tonumber(buffs[buff_index]) == expected then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
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
		ward_effect_timeout = require_positive_number(
			options.ward_effect_timeout,
			'pet command ward_effect_timeout'
		),
		backoff_base = require_positive_number(options.backoff_base, 'pet command backoff_base'),
		backoff_max = require_positive_number(options.backoff_max, 'pet command backoff_max'),
		conduit_rage_start_timeout = require_positive_number(
			options.conduit_rage_start_timeout or DEFAULT_CONDUIT_RAGE_START_TIMEOUT,
			'pet command conduit_rage_start_timeout'
		),
		conduit_rage_finish_timeout = require_positive_number(
			options.conduit_rage_finish_timeout or DEFAULT_CONDUIT_RAGE_FINISH_TIMEOUT,
			'pet command conduit_rage_finish_timeout'
		),
		conduit_rage_backoff = require_positive_number(
			options.conduit_rage_backoff or DEFAULT_CONDUIT_RAGE_BACKOFF,
			'pet command conduit_rage_backoff'
		),
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

function M.begin(state, command, now, owner_provider)
	state = require_table(state, 'pet command coordinator state')
	if owner_provider ~= nil
		and owner_provider ~= 'pet_combat'
		and owner_provider ~= 'maintenance_summoner' then
		error('pet command owner provider must be pet_combat or maintenance_summoner')
	end
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
	pending.owner_provider = owner_provider
	pending.dispatched_at = now
	pending.deadline = now + (
		pending.kind == 'rage' and pending.astral_conduit == true
			and state.conduit_rage_start_timeout
			or state.timeout
	)
	if pending.recast_id ~= nil then
		local before = tonumber(pending.recast_before)
		if before == nil or before < 0 then
			error('pet command recast_before must be a non-negative number')
		end
		pending.recast_before = before
	end
	if type(pending.reaction_key) == 'string' and pending.reaction_key ~= '' then
		local marked, mark_reason = require('uc_reaction_runtime').note_sequence_action_dispatched(
			pending.reaction_key,
			'pet',
			pending.action_name,
			'mob',
			pending.target_id,
			pending.pet_id,
			now
		)
		if marked ~= true then
			error('reaction pet command dispatch could not be correlated: ' .. tostring(mark_reason))
		end
	end
	state.pending = pending
	state.last_event = {
		outcome = 'pending',
		reason = 'dispatched',
		kind = pending.kind,
		action_name = pending.action_name,
		retry_key = pending.retry_key,
		reaction_key = pending.reaction_key,
		reaction_step_index = pending.reaction_step_index,
		at = now,
	}
	return pending
end

-- A durable domain toggle retires only that domain's in-flight pet
-- reservation. Do not reset recast/retry history or pet packet observations.
-- Reaction-owned pet steps are forced safety work; their own reaction policy
-- controls their lifecycle, not a routine combat/maintenance toggle.
function M.cancel_disabled_owner(state, combat_enabled, maintenance_enabled, now)
	state = require_table(state, 'pet command coordinator state')
	local pending = state.pending
	if type(pending) ~= 'table'
		or (type(pending.reaction_key) == 'string' and pending.reaction_key ~= '') then
		return nil
	end
	local owner = tostring(pending.owner_provider or '')
	local disabled = (owner == 'pet_combat' and combat_enabled == false)
		or (owner == 'maintenance_summoner' and maintenance_enabled == false)
	if not disabled then return nil end
	now = require_now(now)
	local event = {
		outcome = 'cancelled',
		reason = 'owner_domain_disabled',
		kind = pending.kind,
		action_name = pending.action_name,
		retry_key = pending.retry_key,
		pet_id = pending.pet_id,
		target_id = pending.target_id,
		combat_generation = pending.combat_generation,
		owner_provider = owner,
		at = now,
		retry_delay = 0,
	}
	state.pending = nil
	state.last_event = event
	return event
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

	if pending.kind == 'activate' then
		if ctx.pet_present == true and current_pet_id > 0 then
			return finish(state, now, 'complete', 'automaton_appeared')
		end
		recast_consumed(pending, ctx)
	else
		local pet_matches = ctx.pet_present == true and current_pet_id == pending.pet_id
		if pending.kind == 'release' then
			if not pet_matches then
				return finish(state, now, 'complete', 'pet_disappeared')
			end
		elseif not pet_matches then
			return finish(state, now, 'failed', 'stale_pet')
		elseif pending.kind == 'assault' or pending.kind == 'deploy' then
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
			if player_has_all_effects(ctx, pending.expected_effect_ids) then
				return finish(state, now, 'complete', 'ward_effect_observed')
			end
			if recast_consumed(pending, ctx) then
				if pending.recast_consumed_at == nil then
					pending.recast_consumed_at = now
					pending.deadline = now + state.ward_effect_timeout
				end
			end
		elseif pending.kind == 'rage' then
			if not target_is_current_and_live(pending, ctx) then
				return finish(state, now, 'failed', 'stale_target')
			end
			if pending.astral_conduit ~= true and recast_consumed(pending, ctx) then
				return finish(state, now, 'complete', 'rage_recast_consumed')
			end
		elseif pending.kind == 'maneuver' then
			if player_has_effect(ctx, OVERLOAD_BUFF_ID) then
				return finish(state, now, 'failed', 'overload_observed')
			end
			if recast_consumed(pending, ctx) then
				return finish(state, now, 'complete', 'maneuver_recast_consumed')
			end
		end
	end

	if now >= pending.deadline then
		if pending.kind == 'rage' and pending.astral_conduit == true then
			return finish(
				state,
				now,
				'failed',
				pending.action_observed_at ~= nil
					and 'conduit_rage_finish_timeout'
					or 'conduit_rage_start_timeout'
			)
		end
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
	if pending.kind == 'activate' then
		return nil
	end
	if tonumber(act.actor_id) ~= pending.pet_id then
		return nil
	end
	if pending.kind == 'assault' or pending.kind == 'deploy' then
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
	if pending.kind == 'ward' then
		pending.action_observed_at = now
		pending.deadline = now + state.ward_effect_timeout
		return nil
	end
	if pending.kind == 'rage'
		and pending.astral_conduit == true
		and tonumber(act.category) == 7 then
		pending.action_observed_at = now
		pending.deadline = now + state.conduit_rage_finish_timeout
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
