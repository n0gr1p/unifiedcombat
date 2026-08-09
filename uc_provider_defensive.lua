local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_defensive %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_defensive deps.%s must be a function'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local active_value_or_flat = require_function(deps, 'active_value_or_flat')
	local build_defensive_candidates = require_function(deps, 'build_defensive_candidates')
	local choose_defensive_action = require_function(deps, 'choose_defensive_action')
	local action_ready = require_function(deps, 'action_ready')
	local build_action_command = require_function(deps, 'build_action_command')
	local cure_target_allowed = require_function(deps, 'cure_target_allowed')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local critical_cure_priority = tonumber(deps.critical_cure_priority)
	if critical_cure_priority == nil then
		error('uc_provider_defensive deps.critical_cure_priority must be numeric')
	end

	local provider = {}

	function provider.collect_internal(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(active_value_or_flat('config.defensive.enabled', ctx.settings.defensive_enabled), false) then
			return
		end
		if tostring(active_value_or_flat('config.defensive.provider', ctx.settings.defensive_provider) or 'internal') ~= 'internal' then
			return
		end
		local candidates = build_defensive_candidates(ctx)
		local action, reason = choose_defensive_action(candidates)
		if not action or not action.spell or not action.target or not action.target.name then
			return
		end
		local urgency = 0.35
		if action.type == 'overwrite' then
			urgency = 0.80
		elseif action.type == 'cure' then
			urgency = 0.70
		elseif action.type == 'debuff' then
			urgency = 0.60
		elseif action.type == 'buff' then
			urgency = 0.25
		end
		local target_kind = action.target.is_self and 'self' or 'ally'
		local target_id = tonumber(action.target.id) or 0
		local target_name = tostring(action.target.name or '')
		local action_name = tostring(action.spell or '')
		local target_hpp = tonumber(action.target.hpp) or -1
		local critical_hpp = tonumber(active_value_or_flat('config.defensive.thresholds.critical_hpp', ctx.settings.defensive_critical_hpp)) or 35
		local priority_band = 100
		if tostring(action.type or '') == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp then
			priority_band = critical_cure_priority
		end
		local _, _, action_kind = action_ready(action_name, target_id)
		local legacy_command = build_action_command(action_name, action_kind, action.target)
		out[#out + 1] = {
			proposal_id = ('def.internal.%s.%s.%d'):format(tostring(action.type or 'action'), action_name, math.floor(ctx.now * 1000)),
			family_id = ('def.internal.%s'):format(tostring(action.type or 'action')),
			provider = 'defensive_internal',
			action_type = action_kind,
			action_name = action_name,
			target_kind = target_kind,
			target_id = target_id,
			target_name = target_name,
			priority_band = priority_band,
			urgency = clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.40,
			commit_deadline = ctx.now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 21.0, los_required = true },
			recast_key = ('spell:%s'):format(action_name),
			duplicate_suppression_key = ('spell:%s:%d'):format(action_name, target_id),
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'buff_gain',
			sticky = false,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = tostring(reason or ''),
			detail = {
				def_action_type = tostring(action.type or ''),
				target_hpp = target_hpp,
			},
			legacy_command = legacy_command,
		}
	end

	function provider.collect_healbot(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(active_value_or_flat('config.defensive.enabled', ctx.settings.defensive_enabled), false) then
			return
		end
		if tostring(active_value_or_flat('config.defensive.provider', ctx.settings.defensive_provider) or 'internal') ~= 'healbot' then
			return
		end
		local ok_actions = type(rawget(_G, 'actions')) == 'table' and type(_G.actions.get_defensive_action) == 'function'
		local ok_healer = type(rawget(_G, 'healer')) == 'table' and type(_G.healer.take_action) == 'function'
		if not ok_actions or not ok_healer then
			return
		end
		local hb_action = _G.actions.get_defensive_action()
		if type(hb_action) ~= 'table' then
			return
		end
		local atype = tostring(hb_action.type or 'action')
		local aname = tostring((hb_action.action and hb_action.action.en) or atype or 'healbot_action')
		local target_obj = hb_action.target or {}
		local target_name = tostring(target_obj.name or target_obj.en or '')
		local target_id = tonumber(target_obj.id) or 0
		if target_name == '' then
			target_name = tostring(ctx.player_name or '')
		end
		local target_kind = (target_id ~= 0 and target_id ~= tonumber(ctx.player_id or 0)) and 'ally' or 'self'
		if atype == 'cure' and not cure_target_allowed(target_id, target_kind) then
			return
		end
		local target_hpp = tonumber(target_obj.hpp) or -1
		local critical_hpp = tonumber(active_value_or_flat('config.defensive.thresholds.critical_hpp', ctx.settings.defensive_critical_hpp)) or 35
		local priority_band = 100
		if atype == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp then
			priority_band = critical_cure_priority
		end
		local urgency = 0.45
		if atype == 'cure' then
			urgency = 0.70
		elseif atype == 'overwrite' then
			urgency = 0.80
		elseif atype == 'debuff' then
			urgency = 0.60
		elseif atype == 'buff' then
			urgency = 0.30
		end
		out[#out + 1] = {
			proposal_id = ('def.healbot.%s.%s.%d'):format(atype, aname, math.floor(ctx.now * 1000)),
			family_id = ('def.healbot.%s'):format(atype),
			provider = 'defensive_healbot',
			action_type = 'spell',
			action_name = aname,
			target_kind = target_kind,
			target_id = target_id,
			target_name = target_name,
			priority_band = priority_band,
			urgency = clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.40,
			commit_deadline = ctx.now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 21.0, los_required = true },
			recast_key = ('healbot:%s:%s'):format(atype, aname),
			duplicate_suppression_key = ('healbot:%s:%d'):format(aname, target_id),
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'buff_gain',
			sticky = false,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = ('healbot_%s'):format(atype),
			detail = {
				healbot_action = hb_action,
				def_action_type = atype,
				target_hpp = target_hpp,
			},
		}
	end

	return provider
end

return M
