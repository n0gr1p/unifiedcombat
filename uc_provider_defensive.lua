local M = {}

local RESURRECTION_OBSERVATION_GATE_S = 0.35
local RESURRECTION_ATTEMPT_GAP_S = 30.0
local DEFAULT_RESURRECTION_PRIORITY = { 'Arise', 'Raise III', 'Raise II', 'Raise' }
local RESURRECTION_NAMES = {
	['Arise'] = true,
	['Raise III'] = true,
	['Raise II'] = true,
	['Raise'] = true,
}

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
	local action_range = require_function(deps, 'action_range')
	local build_action_command = require_function(deps, 'build_action_command')
	local cure_target_allowed = require_function(deps, 'cure_target_allowed')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local get_party_members = deps.get_party_members
	if get_party_members ~= nil and type(get_party_members) ~= 'function' then
		error('uc_provider_defensive deps.get_party_members must be a function')
	end
	local in_party_cast_range = deps.in_party_cast_range
	if in_party_cast_range ~= nil and type(in_party_cast_range) ~= 'function' then
		error('uc_provider_defensive deps.in_party_cast_range must be a function')
	end
	local log = type(deps.log) == 'function' and deps.log or function() end
	local critical_cure_priority = tonumber(deps.critical_cure_priority)
	if critical_cure_priority == nil then
		error('uc_provider_defensive deps.critical_cure_priority must be numeric')
	end

	local resurrection_state = {
		observed = {},
		attempts = {},
	}
	local provider = {}

	local function parse_resurrection_priority(value)
		local out = {}
		local seen = {}
		local function add(name)
			name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+
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
		local action_name = type(action) == 'table' and tostring(action.action_name or action.spell or '') or ''
		if not action or action_name == '' or not action.target or not action.target.name then
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
		local target_hpp = tonumber(action.lowest_covered_hpp) or tonumber(action.target.hpp) or -1
		local critical_hpp = tonumber(active_value_or_flat('config.defensive.thresholds.critical_hpp', ctx.settings.defensive_critical_hpp)) or 35
		local priority_band = 100
		if tostring(action.type or '') == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp then
			priority_band = critical_cure_priority
		end
		local ready, _, action_kind = action_ready(action_name, target_id)
		if not ready or action_kind == 'none' then
			return
		end
		if action.action_kind ~= nil and tostring(action.action_kind) ~= action_kind then
			error(('defensive action kind mismatch for %s: candidate=%s resolved=%s'):format(action_name, tostring(action.action_kind), tostring(action_kind)))
		end
		local legacy_command = build_action_command(action_name, action_kind, action.target)
		local target_range = tonumber(action.target_range)
		if target_range == nil and type(action.action_detail) == 'table' then
			target_range = tonumber(action.action_detail.target_range)
		end
		if target_range == nil then
			target_range = action_range(action_name, action_kind)
		end
		if type(target_range) ~= 'number' or target_range < 0 then
			error(('defensive action range is invalid for %s'):format(action_name))
		end
		local recast_key = ('spell:%s'):format(action_name)
		local duplicate_key = ('spell:%s:%d'):format(action_name, target_id)
		if action_kind == 'ja' then
			recast_key = ('ja:%s'):format(action_name)
			duplicate_key = ('ja:%s:%d'):format(action_name, target_id)
		end
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
			movement_policy = action_kind == 'spell' and 'must_stop' or 'requires_range',
			range_policy = { min = 0.0, max = target_range, los_required = true },
			recast_key = recast_key,
			duplicate_suppression_key = duplicate_key,
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = action_kind == 'ja' and 'ja_effect' or 'buff_gain',
			sticky = false,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = tostring(reason or ''),
			detail = {
				def_action_type = tostring(action.type or ''),
				target_hpp = target_hpp,
				aoe = action.aoe == true,
				coverage_count = tonumber(action.coverage_count) or 0,
				covered_ids = action.covered_ids,
				covered_names = action.covered_names,
				aggregate_missing_hp = tonumber(action.aggregate_missing_hp) or 0,
				lowest_covered_hpp = tonumber(action.lowest_covered_hpp) or -1,
				aoe_radius = tonumber(action.aoe_radius) or 0,
				target_range = target_range,
				tp_cost = type(action.action_detail) == 'table' and tonumber(action.action_detail.tp_cost) or nil,
				tp_reserve = type(action.action_detail) == 'table' and tonumber(action.action_detail.tp_reserve) or nil,
				waltz_action = action_kind == 'ja' and action_name:find('Waltz', 1, true) ~= nil,
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
, '')
			if RESURRECTION_NAMES[name] == true and not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
		if type(value) == 'table' then
			for i = 1, #value do
				add(value[i])
			end
		elseif type(value) == 'string' then
			for name in value:gmatch('[^|,]+') do
				add(name)
			end
		end
		if #out == 0 then
			for _, name in ipairs(DEFAULT_RESURRECTION_PRIORITY) do
				add(name)
			end
		end
		return out
	end

	local function clear_resurrection_target(target_id)
		local tid = tonumber(target_id) or 0
		if tid > 0 then
			resurrection_state.observed[tid] = nil
			resurrection_state.attempts[tid] = nil
		end
	end

	function provider.collect_resurrection(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if type(get_party_members) ~= 'function' or type(in_party_cast_range) ~= 'function' then
			return
		end
		local settings = require_table(ctx.settings, 'ctx.settings')
		local enabled = bool_setting(
			active_value_or_flat('config.defensive.enabled', settings.defensive_enabled),
			false
		) and bool_setting(
			active_value_or_flat('config.defensive.resurrection.enabled', settings.defensive_resurrection_enabled),
			false
		)
		if not enabled then
			resurrection_state.observed = {}
			resurrection_state.attempts = {}
			return
		end

		local priority = parse_resurrection_priority(active_value_or_flat(
			'config.defensive.resurrection.priority',
			settings.defensive_resurrection_priority
		))
		local active_dead_ids = {}
		for _, member in ipairs(get_party_members(ctx)) do
			local tid = tonumber(member.id) or 0
			local hpp = tonumber(member.hpp) or 100
			local is_human_ally = tid > 0
				and member.is_self ~= true
				and member.is_npc ~= true
				and tonumber(member.spawn_type) ~= 14
			if is_human_ally and hpp <= 0 then
				active_dead_ids[tid] = true
				if not in_party_cast_range(member) then
					log(('RESURRECTION_REJECT target="%s" reason=OUT_OF_RANGE'):format(tostring(member.name or '?')))
				else
					local observed = resurrection_state.observed[tid]
					if type(observed) ~= 'table' then
						resurrection_state.observed[tid] = { first_seen_at = ctx.now }
						log(('RESURRECTION_REJECT target="%s" reason=OBSERVATION_GATE'):format(tostring(member.name or '?')))
					elseif (ctx.now - (tonumber(observed.first_seen_at) or ctx.now)) >= RESURRECTION_OBSERVATION_GATE_S then
						local attempt = resurrection_state.attempts[tid]
						if type(attempt) == 'table' and (ctx.now - (tonumber(attempt.at) or 0)) < RESURRECTION_ATTEMPT_GAP_S then
							log(('RESURRECTION_REJECT target="%s" reason=ATTEMPT_GATE'):format(tostring(member.name or '?')))
						else
							for index, action_name in ipairs(priority) do
								local ready, ready_reason, action_kind = action_ready(action_name, tid)
								if ready and action_kind == 'spell' then
									local target_range = action_range(action_name, 'spell')
									if type(target_range) ~= 'number' or target_range < 0 then
										error(('resurrection action range is invalid for %s'):format(action_name))
									end
									out[#out + 1] = {
										proposal_id = ('def.internal.resurrection.%s.%d.%d'):format(action_name, tid, math.floor(ctx.now * 1000)),
										family_id = 'def.internal.resurrection',
										provider = 'defensive_internal',
										action_type = 'spell',
										action_name = action_name,
										target_kind = 'ally',
										target_id = tid,
										target_name = tostring(member.name or ''),
										priority_band = critical_cure_priority,
										urgency = clamp_urgency(1.0),
										starvation_eligible = false,
										created_at = ctx.now,
										expires_at = ctx.now + 0.40,
										commit_deadline = ctx.now + 0.25,
										movement_policy = 'must_stop',
										range_policy = { min = 0.0, max = target_range, los_required = true },
										recast_key = ('spell:%s'):format(action_name),
										duplicate_suppression_key = ('resurrection:%d'):format(tid),
										lock_class = 'support_action',
										expected_ack = 'action_start',
										expected_effect = 'spell_effect',
										sticky = false,
										can_preempt_movement = true,
										can_preempt_same_band = false,
										reason_code = 'downed_party_member',
										detail = {
											def_action_type = 'resurrection',
											target_hpp = 0,
											resurrection_priority_index = index,
										},
										legacy_command = build_action_command(action_name, 'spell', member),
									}
									log(('RESURRECTION_ACCEPT target="%s" action="%s" priority=%d'):format(
										tostring(member.name or '?'), action_name, index
									))
									break
								else
									log(('RESURRECTION_SKIP target="%s" action="%s" reason=%s'):format(
										tostring(member.name or '?'), action_name, tostring(ready_reason or 'NOT_READY')
									))
								end
							end
						end
					end
				end
			else
				clear_resurrection_target(tid)
			end
		end
		for tid in pairs(resurrection_state.observed) do
			if active_dead_ids[tid] ~= true then
				clear_resurrection_target(tid)
			end
		end
		for tid in pairs(resurrection_state.attempts) do
			if active_dead_ids[tid] ~= true then
				clear_resurrection_target(tid)
			end
		end
	end

	function provider.note_dispatch(selected, at)
		local detail = type(selected) == 'table' and selected.detail or nil
		if type(detail) ~= 'table' or detail.def_action_type ~= 'resurrection' then
			return false
		end
		local tid = tonumber(selected.target_id) or 0
		local dispatched_at = tonumber(at)
		if tid <= 0 or dispatched_at == nil then
			error('resurrection dispatch requires target id and numeric time')
		end
		resurrection_state.attempts[tid] = {
			at = dispatched_at,
			action_name = tostring(selected.action_name or ''),
		}
		return true
	end

	provider._resurrection_test = {
		state = resurrection_state,
		observation_gate_s = RESURRECTION_OBSERVATION_GATE_S,
		attempt_gap_s = RESURRECTION_ATTEMPT_GAP_S,
	}

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
		local action_name = type(action) == 'table' and tostring(action.action_name or action.spell or '') or ''
		if not action or action_name == '' or not action.target or not action.target.name then
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
		local target_hpp = tonumber(action.lowest_covered_hpp) or tonumber(action.target.hpp) or -1
		local critical_hpp = tonumber(active_value_or_flat('config.defensive.thresholds.critical_hpp', ctx.settings.defensive_critical_hpp)) or 35
		local priority_band = 100
		if tostring(action.type or '') == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp then
			priority_band = critical_cure_priority
		end
		local ready, _, action_kind = action_ready(action_name, target_id)
		if not ready or action_kind == 'none' then
			return
		end
		if action.action_kind ~= nil and tostring(action.action_kind) ~= action_kind then
			error(('defensive action kind mismatch for %s: candidate=%s resolved=%s'):format(action_name, tostring(action.action_kind), tostring(action_kind)))
		end
		local legacy_command = build_action_command(action_name, action_kind, action.target)
		local target_range = tonumber(action.target_range)
		if target_range == nil and type(action.action_detail) == 'table' then
			target_range = tonumber(action.action_detail.target_range)
		end
		if target_range == nil then
			target_range = action_range(action_name, action_kind)
		end
		if type(target_range) ~= 'number' or target_range < 0 then
			error(('defensive action range is invalid for %s'):format(action_name))
		end
		local recast_key = ('spell:%s'):format(action_name)
		local duplicate_key = ('spell:%s:%d'):format(action_name, target_id)
		if action_kind == 'ja' then
			recast_key = ('ja:%s'):format(action_name)
			duplicate_key = ('ja:%s:%d'):format(action_name, target_id)
		end
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
			movement_policy = action_kind == 'spell' and 'must_stop' or 'requires_range',
			range_policy = { min = 0.0, max = target_range, los_required = true },
			recast_key = recast_key,
			duplicate_suppression_key = duplicate_key,
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = action_kind == 'ja' and 'ja_effect' or 'buff_gain',
			sticky = false,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = tostring(reason or ''),
			detail = {
				def_action_type = tostring(action.type or ''),
				target_hpp = target_hpp,
				aoe = action.aoe == true,
				coverage_count = tonumber(action.coverage_count) or 0,
				covered_ids = action.covered_ids,
				covered_names = action.covered_names,
				aggregate_missing_hp = tonumber(action.aggregate_missing_hp) or 0,
				lowest_covered_hpp = tonumber(action.lowest_covered_hpp) or -1,
				aoe_radius = tonumber(action.aoe_radius) or 0,
				target_range = target_range,
				tp_cost = type(action.action_detail) == 'table' and tonumber(action.action_detail.tp_cost) or nil,
				tp_reserve = type(action.action_detail) == 'table' and tonumber(action.action_detail.tp_reserve) or nil,
				waltz_action = action_kind == 'ja' and action_name:find('Waltz', 1, true) ~= nil,
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
