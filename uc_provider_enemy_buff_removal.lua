local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_enemy_buff_removal %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_enemy_buff_removal deps.%s must be a function'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local log = require_function(deps, 'log')
	local build_friendly_claims = require_function(deps, 'build_friendly_claims')
	local list_targets = require_function(deps, 'list_targets')
	local get_effects = require_function(deps, 'get_effects')
	local claim_valid = require_function(deps, 'claim_valid')
	local is_dispellable = require_function(deps, 'is_dispellable')
	local dispel_priority = require_function(deps, 'dispel_priority')
	local diag = require_function(deps, 'diag')
	local choose_action = require_function(deps, 'choose_action')
	local effect_label = require_function(deps, 'effect_label')
	local can_attempt = require_function(deps, 'can_attempt')
	local action_ready = require_function(deps, 'action_ready')
	local build_action_command = require_function(deps, 'build_action_command')
	local clamp_urgency = require_function(deps, 'clamp_urgency')

	local provider = {}

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		local config = type(ctx.config) == 'table' and ctx.config or {}
		local defensive = type(config.defensive) == 'table' and config.defensive or {}
		local enemy_buffs = type(defensive.enemy_buffs) == 'table' and defensive.enemy_buffs or {}
		log(('ENEMY_DISPEL_TICK def_enabled=%s remove_enemy=%s provider=%s domain_defensive=true'):format(
			tostring(bool_setting(defensive.enabled, false)),
			tostring(bool_setting(enemy_buffs.remove, false)),
			tostring(defensive.provider or '')
		))
		if not bool_setting(defensive.enabled, false) then
			log('ENEMY_DISPEL_SKIP reason=DEFENSIVE_DISABLED')
			return
		end
		if not bool_setting(enemy_buffs.remove, false) then
			log('ENEMY_DISPEL_SKIP reason=TOGGLE_OFF')
			return
		end
		local _, claims_set = build_friendly_claims()
		local tracked_targets = list_targets()
		if #tracked_targets == 0 then
			log('ENEMY_DISPEL_SKIP reason=NO_TRACKED_TARGETS')
			return
		end
		local best = nil
		local best_effect_id = 0
		local best_effect_prio = -1
		for _, tracked_target in ipairs(tracked_targets) do
			local tid = tonumber(tracked_target and tracked_target.target_id) or 0
			if tid > 0 then
				local mob = ctx.mobs_by_id[tid]
				if mob and tonumber(mob.spawn_type) == 16 and (tonumber(mob.hpp) or 0) > 0 and claim_valid(mob.claim_id, claims_set) then
					local chosen_eid = 0
					local chosen_prio = -1
					for _, effect in ipairs(get_effects(tid)) do
						local eid = tonumber(effect and effect.effect_id) or 0
						if is_dispellable(eid) then
							local priority = tonumber(dispel_priority(eid))
							if priority == nil then
								error(('uc_provider_enemy_buff_removal fatal: dispellable effect %d has no priority'):format(eid))
							end
							if priority > chosen_prio then
								chosen_prio = priority
								chosen_eid = eid
							end
						end
					end
					if chosen_eid > 0 then
						local dist = mob.distance and mob.distance:sqrt() or 999
						local pick = {
							target_id = tid,
							target_name = tostring(mob.name or ''),
							effect_id = chosen_eid,
							effect_prio = chosen_prio,
							dist = tonumber(dist) or 999,
						}
						local is_better = false
						if not best then
							is_better = true
						elseif pick.effect_prio ~= best.effect_prio then
							is_better = pick.effect_prio > best.effect_prio
						elseif pick.dist ~= best.dist then
							is_better = pick.dist < best.dist
						else
							is_better = pick.target_id < best.target_id
						end
						if is_better then
							best = pick
							best_effect_id = chosen_eid
							best_effect_prio = chosen_prio
						end
					end
				end
			end
		end
		if not best then
			diag('[enemy_dispel]no_eligible_target')
			log('ENEMY_DISPEL_SKIP reason=NO_ELIGIBLE_TARGET')
			return
		end
		local action_name = choose_action(best.target_id)
		if action_name == '' then
			diag(('[enemy_dispel]not_ready target=%s effect=%d'):format(
				tostring(best.target_name or ''),
				tonumber(best_effect_id) or 0
			))
			log(('ENEMY_DISPEL_SKIP reason=NOT_READY target=\"%s\" effect=\"%s\"'):format(
				tostring(best.target_name or ''),
				effect_label(best_effect_id)
			))
			return
		end
		local attempt_ok, attempt_key = can_attempt(action_name, best.target_id, best_effect_id, ctx.now)
		if not attempt_ok then
			diag(('[enemy_dispel]attempt_gate action=%s target=%s effect=%d'):format(
				tostring(action_name),
				tostring(best.target_name or ''),
				tonumber(best_effect_id) or 0
			))
			log(('ENEMY_DISPEL_SKIP reason=ATTEMPT_GATE action=\"%s\" target=\"%s\" effect=\"%s\"'):format(
				tostring(action_name),
				tostring(best.target_name or ''),
				effect_label(best_effect_id)
			))
			return
		end
		local mob_target = { id = best.target_id, name = best.target_name, is_self = false, is_mob = true }
		local _, _, action_kind = action_ready(action_name, best.target_id)
		local legacy_command = build_action_command(action_name, action_kind, mob_target)
		diag(('[enemy_dispel]emit action=%s target=%s effect=%d prio=%d'):format(
			tostring(action_name),
			tostring(best.target_name or ''),
			tonumber(best_effect_id) or 0,
			tonumber(best_effect_prio) or 0
		))
		out[#out + 1] = {
			proposal_id = ('def.enemy_dispel.%s.%d.%d'):format(
				tostring(action_name),
				tonumber(best.target_id) or 0,
				math.floor(ctx.now * 1000)
			),
			family_id = 'def.enemy_dispel.primary',
			provider = 'defensive_internal',
			action_type = 'spell',
			action_name = tostring(action_name),
			target_kind = 'mob',
			target_id = tonumber(best.target_id) or 0,
			target_name = tostring(best.target_name or ''),
			priority_band = 106,
			urgency = clamp_urgency(0.65),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.40,
			commit_deadline = ctx.now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 21.0, los_required = true },
			recast_key = ('spell:%s'):format(action_name),
			duplicate_suppression_key = ('enemy_dispel:%s:%d:%d'):format(
				tostring(action_name),
				tonumber(best.target_id) or 0,
				tonumber(best_effect_id) or 0
			),
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'enemy_effect_removed',
			sticky = false,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = 'enemy_buff_remove',
			detail = {
				enemy_effect_id = tonumber(best_effect_id) or 0,
				enemy_effect_priority = tonumber(best_effect_prio) or 0,
				enemy_dispel_attempt_key = tostring(attempt_key or ''),
			},
			legacy_command = legacy_command,
		}
		log(('ENEMY_DISPEL_EMIT action=\"%s\" target=\"%s\" effect=\"%s\" prio=%d'):format(
			tostring(action_name),
			tostring(best.target_name or ''),
			effect_label(best_effect_id),
			tonumber(best_effect_prio) or 0
		))
	end

	return provider
end

return M
