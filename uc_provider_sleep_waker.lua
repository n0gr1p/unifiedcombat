local M = {}

local OBSERVATION_GATE_S = 0.35
local ATTEMPT_GAP_S = 2.5

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_sleep_waker %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_sleep_waker deps.%s must be a function'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local active_value_or_flat = require_function(deps, 'active_value_or_flat')
	local get_party_members = require_function(deps, 'get_party_members')
	local get_mob_by_id = require_function(deps, 'get_mob_by_id')
	local in_party_cast_range = require_function(deps, 'in_party_cast_range')
	local action_ready = require_function(deps, 'action_ready')
	local build_action_command = require_function(deps, 'build_action_command')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local log = require_function(deps, 'log')
	local sleep_status = require_table(deps.sleep_status, 'deps.sleep_status')
	if type(sleep_status.has_sleep) ~= 'function' then
		error('uc_provider_sleep_waker deps.sleep_status.has_sleep must be a function')
	end
	local priority_band = tonumber(deps.priority_band)
	if priority_band == nil then
		error('uc_provider_sleep_waker deps.priority_band must be numeric')
	end

	local state = {
		observed = {},
		attempts = {},
		status = 'disabled',
	}
	local provider = {}

	local function publish_status(value)
		state.status = tostring(value)
		_G.UC_SLEEP_WAKER_STATUS = state.status
	end

	local function clear_target(target_id, reason)
		local tid = tonumber(target_id) or 0
		if tid <= 0 then
			return
		end
		if state.observed[tid] ~= nil or state.attempts[tid] ~= nil then
			log(('SLEEP_WAKE_CLEAR target_id=%d reason=%s'):format(tid, tostring(reason)))
		end
		state.observed[tid] = nil
		state.attempts[tid] = nil
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		local settings = require_table(ctx.settings, 'ctx.settings')
		local enabled = bool_setting(
			active_value_or_flat('config.defensive.enabled', settings.defensive_enabled),
			false
		) and bool_setting(
			active_value_or_flat('config.defensive.sleep_waker.enabled', settings.def_sleep_waker_enabled),
			false
		)
		if not enabled then
			provider.reset('DISABLED')
			publish_status('disabled')
			return
		end

		local active_ids = {}
		local saw_sleep = false
		local emitted = 0
		for _, member in ipairs(get_party_members(ctx)) do
			local tid = tonumber(member.id) or 0
			local sleeping = type(member.buffs) == 'table' and sleep_status.has_sleep(member.buffs)
			if sleeping and tid > 0 then
				saw_sleep = true
				active_ids[tid] = true
				log(('SLEEP_WAKE_CANDIDATE target="%s" target_id=%d self=%s hpp=%d charmed=%s buff_source=%s'):format(
					tostring(member.name),
					tid,
					tostring(member.is_self == true),
					tonumber(member.hpp) or 0,
					tostring(member.charmed),
					tostring(member.buff_source or 'missing')
				))
				local mob = get_mob_by_id(tid)
				if member.is_self == true then
					clear_target(tid, 'SELF_SLEEPING')
					log(('SLEEP_WAKE_REJECT target="%s" reason=SELF_SLEEPING'):format(tostring(member.name)))
				elseif (tonumber(member.hpp) or 0) <= 0 or member.is_npc == true or tonumber(member.spawn_type) == 14 then
					clear_target(tid, 'INVALID_TARGET')
					log(('SLEEP_WAKE_REJECT target="%s" reason=INVALID_TARGET'):format(tostring(member.name)))
				elseif type(mob) ~= 'table' then
					clear_target(tid, 'INVALID_TARGET')
					log(('SLEEP_WAKE_REJECT target="%s" reason=INVALID_TARGET'):format(tostring(member.name)))
				elseif mob.charmed == true then
					clear_target(tid, 'CHARMED_TARGET')
					log(('SLEEP_WAKE_REJECT target="%s" reason=CHARMED_TARGET'):format(tostring(member.name)))
				elseif mob.charmed ~= false then
					clear_target(tid, 'CHARM_STATE_UNKNOWN')
					log(('SLEEP_WAKE_REJECT target="%s" reason=CHARM_STATE_UNKNOWN'):format(tostring(member.name)))
				elseif not in_party_cast_range(member) then
					clear_target(tid, 'OUT_OF_RANGE')
					log(('SLEEP_WAKE_REJECT target="%s" reason=OUT_OF_RANGE'):format(tostring(member.name)))
				else
					local observed = state.observed[tid]
					if type(observed) ~= 'table' then
						state.observed[tid] = { first_seen_at = ctx.now }
						log(('SLEEP_WAKE_REJECT target="%s" reason=OBSERVATION_GATE'):format(tostring(member.name)))
					elseif (ctx.now - observed.first_seen_at) < OBSERVATION_GATE_S then
						log(('SLEEP_WAKE_REJECT target="%s" reason=OBSERVATION_GATE'):format(tostring(member.name)))
					else
						local attempt = state.attempts[tid]
						if type(attempt) == 'table' and (ctx.now - attempt.at) < ATTEMPT_GAP_S then
							log(('SLEEP_WAKE_REJECT target="%s" reason=ATTEMPT_GATE'):format(tostring(member.name)))
						else
							local ready, ready_reason, action_kind = action_ready('Cure', tid)
							if not ready or action_kind ~= 'spell' then
								log(('SLEEP_WAKE_REJECT target="%s" reason=%s'):format(
									tostring(member.name),
									tostring(ready_reason or 'CURE_NOT_READY')
								))
							else
								out[#out + 1] = {
									proposal_id = ('emergency.sleep_wake.%d.%d'):format(tid, math.floor(ctx.now * 1000)),
									family_id = 'emergency.sleep_wake.primary',
									provider = 'defensive_internal',
									action_type = 'spell',
									action_name = 'Cure',
									target_kind = 'ally',
									target_id = tid,
									target_name = tostring(member.name),
									priority_band = priority_band,
									urgency = clamp_urgency(1.0),
									starvation_eligible = false,
									created_at = ctx.now,
									expires_at = ctx.now + 0.30,
									commit_deadline = ctx.now + 0.20,
									movement_policy = 'must_stop',
									range_policy = { min = 0.0, max = 20.9, los_required = true },
									recast_key = 'spell:Cure',
									duplicate_suppression_key = ('sleep_wake:Cure:%d'):format(tid),
									lock_class = 'support_action',
									expected_ack = 'action_start',
									expected_effect = 'buff_loss',
									sticky = false,
									can_preempt_movement = true,
									can_preempt_same_band = false,
									reason_code = 'SLEEPING_TARGET_UNCHARMED',
									detail = {
										def_action_type = 'cure',
										cure_intent = 'sleep_wake',
										target_hpp = tonumber(member.hpp) or -1,
									},
									legacy_command = build_action_command('Cure', 'spell', member),
								}
								emitted = emitted + 1
								log(('SLEEP_WAKE_ACCEPT target="%s" spell="Cure"'):format(tostring(member.name)))
							end
						end
					end
				end
			end
		end
		for tid in pairs(state.observed) do
			if active_ids[tid] ~= true then
				clear_target(tid, 'SLEEP_CLEARED')
			end
		end
		for tid in pairs(state.attempts) do
			if active_ids[tid] ~= true then
				clear_target(tid, 'SLEEP_CLEARED')
			end
		end
		if emitted > 0 then
			publish_status(('ready proposals=%d'):format(emitted))
		elseif saw_sleep then
			publish_status('holding sleeping_target')
		else
			publish_status('idle no_sleeping_target')
		end
	end

	function provider.note_dispatch(selected, at)
		local detail = type(selected) == 'table' and selected.detail or nil
		if type(detail) ~= 'table' or detail.cure_intent ~= 'sleep_wake' then
			return false
		end
		local tid = tonumber(selected.target_id) or 0
		local dispatched_at = tonumber(at)
		if tid <= 0 or dispatched_at == nil then
			error('sleep waker dispatch requires target id and numeric time')
		end
		state.attempts[tid] = { at = dispatched_at }
		publish_status(('dispatched Cure -> %s'):format(tostring(selected.target_name)))
		return true
	end

	function provider.reset(reason)
		state.observed = {}
		state.attempts = {}
		publish_status(('reset %s'):format(tostring(reason)))
	end

	function provider.status()
		return state.status
	end

	provider._test = {
		state = state,
		observation_gate_s = OBSERVATION_GATE_S,
		attempt_gap_s = ATTEMPT_GAP_S,
	}

	return provider
end

return M
