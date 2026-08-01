local M = {}

local ATTEMPT_GAP_S = 1.0
local PRECLEAR_LEAD_S = 2.0

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_charm_sleeper %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_charm_sleeper deps.%s must be a function'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local active_value_or_flat = require_function(deps, 'active_value_or_flat')
	local get_party_members = require_function(deps, 'get_party_members')
	local get_mob_by_id = require_function(deps, 'get_mob_by_id')
	local action_ready = require_function(deps, 'action_ready')
	local get_spell_resource = require_function(deps, 'get_spell_resource')
	local get_player = require_function(deps, 'get_player')
	local get_mjob_data = require_function(deps, 'get_mjob_data')
	local get_sjob_data = require_function(deps, 'get_sjob_data')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local action_target_mode = require_function(deps, 'action_target_mode')
	local build_action_command = require_function(deps, 'build_action_command')
	local has_buff = require_function(deps, 'has_buff')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local log = require_function(deps, 'log')
	local policy = require_table(deps.policy, 'deps.policy')
	local spell_effect_gain_messages = require_table(deps.spell_effect_gain_messages, 'deps.spell_effect_gain_messages')
	local priority_band = tonumber(deps.priority_band)
	if priority_band == nil then
		error('uc_provider_charm_sleeper deps.priority_band must be numeric')
	end

	local state = {
		attempts = {},
		projections = {},
		status = 'disabled',
	}
	local spell_by_name = {}
	for _, spell in ipairs(policy.spells) do
		spell_by_name[tostring(spell.name):lower()] = spell
	end

	local provider = {}
	local function spell_is_set_if_blue_magic(resource)
		if tostring(resource.type or '') ~= 'BlueMagic' then
			return true
		end
		local player = get_player()
		if type(player) ~= 'table' then
			error('charm sleeper BLU spell validation requires player data')
		end
		local job_data
		if tonumber(player.main_job_id) == 16 then
			job_data = get_mjob_data()
		elseif tonumber(player.sub_job_id) == 16 then
			job_data = get_sjob_data()
		else
			return false
		end
		if type(job_data) ~= 'table' or type(job_data.spells) ~= 'table' then
			error('charm sleeper BLU spell validation requires active job spell data')
		end
		for _, spell_id in ipairs(job_data.spells) do
			if tonumber(spell_id) == tonumber(resource.id) then
				return true
			end
		end
		return false
	end

	local function publish_status(value)
		state.status = tostring(value)
		_G.UC_CHARM_SLEEPER_STATUS = state.status
	end

	local function clear_target(target_id, reason)
		local tid = tonumber(target_id) or 0
		if tid <= 0 then
			return
		end
		if state.attempts[tid] ~= nil or state.projections[tid] ~= nil then
			log(('CHARM_SLEEP_CLEAR target_id=%d reason=%s'):format(tid, tostring(reason)))
		end
		state.attempts[tid] = nil
		state.projections[tid] = nil
	end

	local function target_is_slept(member, now)
		local projection = state.projections[tonumber(member.id) or 0]
		if type(projection) == 'table'
			and projection.precleared ~= true
			and now >= projection.preclear_at then
			projection.precleared = true
			log(('CHARM_SLEEP_PRECLEAR target="%s" spell="%s" projected_end=%.3f'):format(
				tostring(member.name),
				tostring(projection.spell_name),
				tonumber(projection.projected_end_at)
			))
		end
		if type(member.buffs) == 'table' then
			for effect_id in pairs(policy.effect_ids) do
				if has_buff(member.buffs, effect_id) then
					return true, 'party_buffs'
				end
			end
			return false, 'party_buffs'
		end
		if type(projection) == 'table' then
			if projection.precleared ~= true and now < projection.projected_end_at then
				return true, 'projection'
			end
		end
		return false, 'missing_buff_snapshot'
	end

	local function select_spell(member, mob)
		local distance_sq = tonumber(mob.distance)
		local distance = distance_sq and math.sqrt(distance_sq) or nil
		if distance == nil then
			return nil, 'OUT_OF_RANGE'
		end
		local last_reason = 'NOT_READY'
		for _, policy_spell in ipairs(policy.spells) do
			local ready, ready_reason, action_kind = action_ready(policy_spell.name, member.id)
			if ready and action_kind == 'spell' then
				local resource = get_spell_resource(policy_spell.name)
				if type(resource) ~= 'table' then
					error('ready charm sleeper spell has no resource: ' .. tostring(policy_spell.name))
				end
				if spell_is_set_if_blue_magic(resource) then
					local target_mode = action_target_mode(policy_spell.name, action_kind)
					local max_range = policy_spell.range_yalms
					if target_mode ~= 'self_only' then
						local native_range = action_effective_range(resource.range)
						if native_range <= 0 then
							error('charm sleeper target spell has no effective range: ' .. tostring(policy_spell.name))
						end
						max_range = math.min(max_range, native_range)
					end
					if distance <= max_range then
						return {
							policy = policy_spell,
							action_kind = action_kind,
							target_mode = target_mode,
							distance = distance,
							max_range = max_range,
						}, ''
					end
					last_reason = 'OUT_OF_RANGE'
				else
					last_reason = 'BLU_SPELL_NOT_SET'
				end
			else
				last_reason = tostring(ready_reason or 'NOT_READY')
			end
		end
		return nil, last_reason
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		local settings = require_table(ctx.settings, 'ctx.settings')
		local enabled = bool_setting(
			active_value_or_flat('config.defensive.enabled', settings.defensive_enabled),
			false
		) and bool_setting(
			active_value_or_flat('config.defensive.charm_sleeper.enabled', settings.def_charm_sleeper_enabled),
			false
		)
		if not enabled then
			provider.reset('DISABLED')
			publish_status('disabled')
			return
		end

		local members = get_party_members(ctx)
		local charmed_ids = {}
		local emitted = 0
		local saw_charmed = false
		for _, member in ipairs(members) do
			local tid = tonumber(member.id) or 0
			if member.charmed == true and tid > 0 then
				saw_charmed = true
				charmed_ids[tid] = true
				log(('CHARM_SLEEP_CANDIDATE target="%s" target_id=%d self=%s hpp=%d buff_source=%s'):format(
					tostring(member.name),
					tid,
					tostring(member.is_self == true),
					tonumber(member.hpp) or 0,
					tostring(member.buff_source or 'missing')
				))
				if member.is_self then
					log(('CHARM_SLEEP_REJECT target="%s" reason=SELF_CHARMED'):format(tostring(member.name)))
				elseif (tonumber(member.hpp) or 0) <= 0 or member.is_npc == true or tonumber(member.spawn_type) == 14 then
					clear_target(tid, 'INVALID_TARGET')
					log(('CHARM_SLEEP_REJECT target="%s" reason=INVALID_TARGET'):format(tostring(member.name)))
				else
					local slept, slept_source = target_is_slept(member, ctx.now)
					if slept then
						log(('CHARM_SLEEP_REJECT target="%s" reason=TARGET_ALREADY_SLEPT source=%s'):format(
							tostring(member.name),
							tostring(slept_source)
						))
					else
						local mob = get_mob_by_id(tid)
						if type(mob) ~= 'table' or mob.charmed ~= true or mob.distance == nil then
							clear_target(tid, 'CHARM_SOURCE_CLEARED')
							log(('CHARM_SLEEP_REJECT target="%s" reason=NO_CHARMED_TARGET'):format(tostring(member.name)))
						else
							local selected, select_reason = select_spell(member, mob)
							if selected == nil then
								log(('CHARM_SLEEP_REJECT target="%s" reason=%s'):format(
									tostring(member.name),
									tostring(select_reason)
								))
							else
								local attempt = state.attempts[tid]
								if type(attempt) == 'table'
									and attempt.action_name == selected.policy.name
									and (ctx.now - attempt.at) < ATTEMPT_GAP_S then
									log(('CHARM_SLEEP_REJECT target="%s" spell="%s" reason=ATTEMPT_GATE'):format(
										tostring(member.name),
										tostring(selected.policy.name)
									))
								else
									local command_target = {
										id = tid,
										name = member.name,
										is_self = false,
										use_entity_id = selected.target_mode ~= 'self_only',
									}
									local action_name = selected.policy.name
									out[#out + 1] = {
										proposal_id = ('emergency.charm_sleep.%d.%d'):format(tid, math.floor(ctx.now * 1000)),
										family_id = 'emergency.charm_sleep.primary',
										provider = 'defensive_internal',
										action_type = selected.action_kind,
										action_name = action_name,
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
										range_policy = { min = 0.0, max = selected.max_range, los_required = true },
										recast_key = ('spell:%s'):format(action_name),
										duplicate_suppression_key = ('charm_sleep:%s:%d'):format(action_name, tid),
										lock_class = 'support_action',
										expected_ack = 'action_start',
										expected_effect = 'buff_gain',
										sticky = false,
										can_preempt_movement = true,
										can_preempt_same_band = true,
										reason_code = 'CHARMED_TARGET_UNSLEPT',
										detail = {
											def_action_type = 'charm_sleep',
											target_hpp = tonumber(member.hpp) or -1,
											projected_duration_s = selected.policy.duration_s,
											policy_id = selected.policy.id,
										},
										legacy_command = build_action_command(action_name, selected.action_kind, command_target),
									}
									emitted = emitted + 1
									log(('CHARM_SLEEP_ACCEPT target="%s" spell="%s" distance=%.2f max_range=%.2f'):format(
										tostring(member.name),
										tostring(action_name),
										selected.distance,
										selected.max_range
									))
								end
							end
						end
					end
				end
			end
		end
		for tid in pairs(state.attempts) do
			if charmed_ids[tid] ~= true then
				clear_target(tid, 'CHARM_CLEARED')
			end
		end
		for tid in pairs(state.projections) do
			if charmed_ids[tid] ~= true then
				clear_target(tid, 'CHARM_CLEARED')
			end
		end
		if emitted > 0 then
			publish_status(('ready proposals=%d'):format(emitted))
		elseif saw_charmed then
			publish_status('holding charmed_target')
		else
			publish_status('idle no_charmed_target')
			log('CHARM_SLEEP_SCAN reason=NO_CHARMED_TARGET')
		end
	end

	function provider.note_dispatch(selected, at)
		local detail = type(selected) == 'table' and selected.detail or nil
		if type(detail) ~= 'table' or detail.def_action_type ~= 'charm_sleep' then
			return false
		end
		local tid = tonumber(selected.target_id) or 0
		if tid <= 0 then
			error('charm sleeper dispatch requires a positive target id')
		end
		local dispatched_at = tonumber(at)
		if dispatched_at == nil then
			error('charm sleeper dispatch requires numeric time')
		end
		state.attempts[tid] = {
			action_name = tostring(selected.action_name),
			at = dispatched_at,
		}
		publish_status(('dispatched %s -> %s'):format(tostring(selected.action_name), tostring(selected.target_name)))
		return true
	end

	function provider.observe_action(act, player_id, at)
		if type(act) ~= 'table' or tonumber(act.actor_id) ~= tonumber(player_id) or tonumber(act.category) ~= 4 then
			return 0
		end
		local spell_id = tonumber(act.param) or 0
		local spell_name = ''
		for name, policy_spell in pairs(spell_by_name) do
			local resource = get_spell_resource(policy_spell.name)
			if tonumber(resource and resource.id) == spell_id then
				spell_name = name
				break
			end
		end
		local policy_spell = spell_by_name[spell_name]
		if type(policy_spell) ~= 'table' then
			return 0
		end
		local now = tonumber(at)
		if now == nil then
			error('charm sleeper action observation requires numeric time')
		end
		local marked = 0
		for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
			local tid = tonumber(target and target.id) or 0
			local successful = false
			for _, action in ipairs(type(target and target.actions) == 'table' and target.actions or {}) do
				local message_id = tonumber(action and (action.message or action.message_id)) or 0
				if spell_effect_gain_messages[message_id] == true then
					successful = true
					break
				end
			end
			if tid > 0 and successful and type(state.attempts[tid]) == 'table'
				and state.attempts[tid].action_name == policy_spell.name then
				local projected_end_at = now + policy_spell.duration_s
				state.projections[tid] = {
					spell_name = policy_spell.name,
					successful_at = now,
					projected_end_at = projected_end_at,
					preclear_at = projected_end_at - PRECLEAR_LEAD_S,
					precleared = false,
				}
				log(('CHARM_SLEEP_CONFIRMED target_id=%d spell="%s" projected_end=%.3f preclear_at=%.3f'):format(
					tid,
					policy_spell.name,
					projected_end_at,
					projected_end_at - PRECLEAR_LEAD_S
				))
				publish_status(('slept target_id=%d until=%.3f'):format(tid, projected_end_at))
				marked = marked + 1
			end
		end
		return marked
	end

	function provider.reset(reason)
		state.attempts = {}
		state.projections = {}
		publish_status(('reset %s'):format(tostring(reason)))
	end

	function provider.status()
		return state.status
	end

	provider._test = {
		state = state,
		target_is_slept = target_is_slept,
		select_spell = select_spell,
	}

	return provider
end

return M
