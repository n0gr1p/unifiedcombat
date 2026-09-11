local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_tank_enmity %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_tank_enmity deps.%s must be a function'):format(name))
	end
	return value
end

local function valid_enemy_target(target)
	return type(target) == 'table'
		and target.valid_target == true
		and tonumber(target.spawn_type) == 16
		and (tonumber(target.hpp) or 0) > 0
		and (tonumber(target.id) or 0) > 0
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local select_tank_enmity = require_function(deps, 'select_tank_enmity')
	local action_ready = require_function(deps, 'action_ready')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local log_tank_sched = require_function(deps, 'log_tank_sched')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local run_provider = require('uc_provider_run_tank').new({
		action_ready = action_ready,
		action_effective_range = action_effective_range,
		log_tank_sched = log_tank_sched,
		clamp_urgency = clamp_urgency,
	})

	local provider = {}

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true then
			return
		end
		run_provider.collect(ctx, out)
		local engaged = tonumber(player.status) == 1
		local allow_unengaged = bool_setting(ctx.settings.ability_allow_unengaged, false)
		if not engaged and not allow_unengaged then
			return
		end
		local pick = select_tank_enmity(ctx.settings)
		if type(pick) ~= 'table' then
			return
		end
		local kind = tostring(pick.kind or ''):lower()
		if kind ~= 'ja' and kind ~= 'spell' then
			return
		end
		local action_name = tostring(pick.name or '')
		local target_id = tonumber(pick.target_id) or 0
		if action_name == '' or target_id <= 0 then
			return
		end
		-- The unengaged override is intentionally target-gated. Auto Target may
		-- establish this target without Auto Engage, or the user may select it
		-- manually. Never spend a hate action against a stale/dead/non-enemy ID.
		if not engaged then
			local mobs_by_id = type(ctx.mobs_by_id) == 'table' and ctx.mobs_by_id or {}
			if not valid_enemy_target(mobs_by_id[target_id]) then
				log_tank_sched(('collect_skip action="%s" kind=%s reason=UNENGAGED_TARGET_INVALID target_id=%d'):format(
					tostring(action_name),
					tostring(kind),
					target_id
				))
				return
			end
		end
		-- Hard gate at collect-time so unusable tank actions never starve the queue.
		-- If action is on cooldown / blocked now, do not emit an intent.
		local ready_ok, ready_reason, ready_kind = action_ready(action_name, target_id)
		if not ready_ok then
			log_tank_sched(('collect_skip action="%s" kind=%s reason=%s target_id=%d'):format(
				tostring(action_name),
				tostring(kind),
				tostring(ready_reason or 'NOT_READY'),
				target_id
			))
			return
		end
		-- Defensive consistency: ensure resolved action kind matches picked kind.
		if tostring(ready_kind or '') ~= kind then
			log_tank_sched(('collect_skip action="%s" kind=%s reason=KIND_MISMATCH resolved=%s target_id=%d'):format(
				tostring(action_name),
				tostring(kind),
				tostring(ready_kind or ''),
				target_id
			))
			return
		end
		-- Tank enmity recovery should stay high, but cures must outrank it so
		-- party sustain wins over threat correction when both are available.
		local prio = 96
		local urgency = 0.85
		local victim_hpp = tonumber(pick.victim_hpp) or 0
		if victim_hpp > 0 then
			urgency = clamp_urgency(1.0 - (math.min(victim_hpp, 100) / 100.0))
			if urgency < 0.60 then
				urgency = 0.60
			end
		end
		local action_range = tonumber(pick.action_range)
		if not action_range or action_range <= 0 then
			action_range = 20.0
		end
		out[#out + 1] = {
			proposal_id = ('combat.tank.%s.%s.%d.%d'):format(kind, action_name, target_id, math.floor(ctx.now * 1000)),
			family_id = 'combat.tank_enmity.primary',
			provider = 'combat',
			action_type = kind,
			action_name = action_name,
			target_kind = 'mob',
			target_id = target_id,
			target_name = tostring(pick.target_name or ''),
			priority_band = prio,
			urgency = clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.30,
			commit_deadline = ctx.now + 0.20,
			movement_policy = (kind == 'spell') and 'must_stop' or 'requires_range',
			range_policy = { min = 0.0, max = math.max(1.0, action_range), los_required = false },
			recast_key = ('tank:%s:%s'):format(kind, action_name),
			duplicate_suppression_key = ('tank:%s:%s:%d'):format(kind, action_name, target_id),
			lock_class = 'offense_action',
			expected_ack = 'action_start',
			expected_effect = (kind == 'spell') and 'spell_effect' or 'ja_effect',
			sticky = true,
			can_preempt_movement = true,
			can_preempt_same_band = true,
			reason_code = 'tank_enmity_violation',
			detail = {
				tank_enmity = true,
				victim_name = tostring(pick.victim_name or ''),
				victim_hpp = tonumber(pick.victim_hpp) or 0,
				mob_hpp = tonumber(pick.mob_hpp) or 0,
				dist = tonumber(pick.dist) or 0,
				action_range = tonumber(pick.action_range) or 0,
				selection_reason = tostring(pick.reason or ''),
			},
			legacy_command = (kind == 'spell')
				and ('input /ma "%s" %d'):format(action_name, target_id)
				or ('input /ja "%s" %d'):format(action_name, target_id),
		}
	end

	return provider
end

return M
