local policy = require('uc_camp_puller_policy')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

function M.movement_reserved(config)
	config = require_table(config, 'config')
	if type(config.enabled) ~= 'boolean' then
		error('normalized combat.pulling configuration is required for movement ownership')
	end
	return config.enabled == true
		and rawget(_G, 'Start_Engine') == true
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_camp_puller deps.%s must be a function'):format(name))
	end
	return value
end

local function finite_number(value)
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	return number
end

local function proposal(ctx, spec)
	local target_id = tonumber(spec.target_id) or 0
	local action_type = tostring(spec.action_type or '')
	if target_id <= 0
		and action_type ~= 'camp_return'
		and action_type ~= 'camp_stop'
		and action_type ~= 'camp_recover' then
		error('camp pull proposal requires a positive target id')
	end
	return {
		proposal_id = ('camp.pull.%s.%d'):format(action_type, math.floor(ctx.now * 1000)),
		family_id = 'combat.camp_pulling.' .. action_type,
		provider = 'camp_puller',
		action_type = action_type,
		action_name = tostring(spec.action_name or action_type),
		target_kind = spec.target_kind or 'none',
		target_id = target_id,
		target_name = tostring(spec.target_name or ''),
		priority_band = tonumber(spec.priority_band) or 210,
		urgency = tonumber(spec.urgency) or 0.90,
		starvation_eligible = false,
		created_at = ctx.now,
		expires_at = ctx.now + 0.40,
		commit_deadline = ctx.now + 0.25,
		movement_policy = spec.movement_policy or 'none',
		range_policy = {
			min = 0.0,
			max = tonumber(spec.max_range) or 100.0,
			los_required = false,
		},
		recast_key = 'camp_puller:' .. action_type,
		duplicate_suppression_key = ('camp_puller:%s:%d'):format(action_type, target_id),
		lock_class = (action_type == 'spell' or action_type == 'ja') and 'combat_action' or 'movement',
		expected_ack = tostring(spec.expected_ack or ''),
		expected_effect = tostring(spec.expected_effect or ''),
		sticky = true,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = tostring(spec.reason_code or 'camp_pull_' .. action_type),
		detail = spec.detail or {},
		legacy_command = '',
	}
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local resolve_camp_anchor = require_function(deps, 'resolve_camp_anchor')
	local get_friendly_claims = require_function(deps, 'get_friendly_claims')
	local ignored = require_function(deps, 'ignored')
	local get_spell_resource = require_function(deps, 'get_spell_resource')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local action_ready = require_function(deps, 'action_ready')
	local log = require_function(deps, 'log')
	local action_timeline_log = require_function(deps, 'action_timeline_log')
	local pull_action_in_flight = require_function(deps, 'pull_action_in_flight')
	local can_start_journey = require_function(deps, 'can_start_journey')

	local provider = {
		state = {
			name = 'IDLE',
			target_id = 0,
			target_name = '',
			settle_until = 0,
			action_sent_at = 0,
			reaction_deadline = 0,
			cooldowns = {},
			breadcrumbs = {},
			last_breadcrumb = nil,
			last_progress_at = 0,
			last_progress_distance = nil,
			recovery_count = 0,
			retry_count = 0,
			retry_window_started_at = 0,
			last_reason = '',
			last_detail = '',
			last_intent = '',
			active_count = 0,
			quota = 0,
			camp_distance = nil,
			target_camp_distance = nil,
			action_range = nil,
			cast_range = nil,
			target_distance = nil,
			target_hpp = nil,
			target_status = nil,
			target_claim_id = nil,
			action_in_flight = false,
			cooldown_until = 0,
			last_log_signature = '',
			last_timeline_state = '',
		},
	}

	local function canonical_reason(detail)
		local reason = tostring(detail or '')
		if reason == 'CAMP_UNSET' or reason == 'CAMP_ZONE_UNAVAILABLE' then
			return 'PULL_CAMP_UNSET'
		elseif reason == 'CAMP_ZONE_MISMATCH' then
			return 'PULL_CAMP_ZONE_MISMATCH'
		elseif reason == 'PULL_QUOTA_SATISFIED' then
			return 'PULL_NO_DEMAND'
		elseif reason == 'PULL_TARGET_STATE_INVALID' then
			return 'PULL_SKIP_INVALID'
		elseif reason == 'PULL_TARGET_OUT_OF_LEASH' then
			return 'PULL_SKIP_OUT_OF_LEASH'
		elseif reason == 'PULL_TARGET_Z_DELTA' then
			return 'PULL_SKIP_Z_DELTA'
		elseif reason == 'PULL_TARGET_COOLDOWN' then
			return 'PULL_SKIP_COOLDOWN'
		elseif reason:find('PULL_ACTION_NOT_READY:', 1, true) == 1 then
			local lowered = reason:lower()
			if lowered:find('mp', 1, true) then
				return 'PULL_WAIT_MP'
			elseif lowered:find('silence', 1, true) or lowered:find('status', 1, true) then
				return 'PULL_WAIT_STATUS'
			end
			return 'PULL_WAIT_RECAST'
		elseif reason == 'PULL_PRECAST_SETTLE' then
			return 'PULL_SETTLE'
		elseif reason == 'PULL_ACTION_FAILED' then
			return 'PULL_ACTION_REJECTED'
		elseif reason == 'PULL_WAIT_TARGET_REACTION' then
			return 'PULL_WAIT_REACTION'
		elseif reason == 'PULL_RETURN_TO_CAMP' then
			return 'PULL_RETURN'
		elseif reason == 'PULL_CAMP_ARRIVED' then
			return 'PULL_ARRIVED_CAMP'
		end
		return reason
	end

	local function publish(detail, demand)
		if detail ~= nil then
			provider.state.last_reason = canonical_reason(detail)
			provider.state.last_detail = tostring(detail)
		end
		if demand ~= nil then
			provider.state.active_count = demand.active_count
			provider.state.quota = demand.quota
		end
		_G.UC_CAMP_PULLER_STATUS = {
			state = provider.state.name,
			target_id = provider.state.target_id,
			target_name = provider.state.target_name,
			reason = provider.state.last_reason,
			detail = provider.state.last_detail,
			last_intent = provider.state.last_intent,
			active_count = provider.state.active_count,
			quota = provider.state.quota,
			camp_distance = provider.state.camp_distance,
			target_camp_distance = provider.state.target_camp_distance,
			target_distance = provider.state.target_distance,
			target_hpp = provider.state.target_hpp,
			target_status = provider.state.target_status,
			target_claim_id = provider.state.target_claim_id,
			action_in_flight = provider.state.action_in_flight,
			action_range = provider.state.action_range,
			cast_range = provider.state.cast_range,
			cooldown_until = provider.state.cooldown_until,
			breadcrumb_count = #provider.state.breadcrumbs,
			recovery_count = provider.state.recovery_count,
			retry_count = provider.state.retry_count,
		}
		local signature = table.concat({
			provider.state.name,
			provider.state.last_reason,
			tostring(provider.state.target_id),
			provider.state.last_intent,
			tostring(provider.state.recovery_count),
			tostring(provider.state.retry_count),
		}, '|')
		if signature ~= provider.state.last_log_signature then
			provider.state.last_log_signature = signature
			action_timeline_log('CAMP_PULL_STATE', {
				from = provider.state.last_timeline_state,
				to = provider.state.name,
				reason = provider.state.last_reason,
				detail = provider.state.last_detail,
				target = provider.state.target_name,
				target_id = provider.state.target_id,
				active_count = provider.state.active_count,
				quota = provider.state.quota,
				camp_distance = provider.state.camp_distance,
				target_camp_distance = provider.state.target_camp_distance,
				target_distance = provider.state.target_distance,
				target_hpp = provider.state.target_hpp,
				target_status = provider.state.target_status,
				target_claim_id = provider.state.target_claim_id,
				action_in_flight = provider.state.action_in_flight,
				cast_range = provider.state.cast_range,
				action_range = provider.state.action_range,
				last_intent = provider.state.last_intent,
				breadcrumb_count = #provider.state.breadcrumbs,
				recovery_count = provider.state.recovery_count,
				retry_count = provider.state.retry_count,
			}, 'camp_pull_state:' .. signature, 0)
			provider.state.last_timeline_state = provider.state.name
			log(('CAMP_PULL state=%s reason=%s detail=%s target=%d:"%s" intent=%s active=%d/%d camp=%s target_camp=%s cast=%s action=%s breadcrumbs=%d recovery=%d retry=%d cooldown=%s'):format(
				provider.state.name,
				provider.state.last_reason,
				provider.state.last_detail,
				provider.state.target_id,
				provider.state.target_name,
				provider.state.last_intent,
				provider.state.active_count,
				provider.state.quota,
				tostring(provider.state.camp_distance),
				tostring(provider.state.target_camp_distance),
				tostring(provider.state.cast_range),
				tostring(provider.state.action_range),
				#provider.state.breadcrumbs,
				provider.state.recovery_count,
				provider.state.retry_count,
				tostring(provider.state.cooldown_until)
			))
		end
	end

	local function reset(reason)
		provider.state.name = 'IDLE'
		provider.state.target_id = 0
		provider.state.target_name = ''
		provider.state.settle_until = 0
		provider.state.action_sent_at = 0
		provider.state.reaction_deadline = 0
		provider.state.breadcrumbs = {}
		provider.state.last_breadcrumb = nil
		provider.state.last_progress_at = 0
		provider.state.last_progress_distance = nil
		provider.state.recovery_count = 0
		provider.state.retry_count = 0
		provider.state.retry_window_started_at = 0
		provider.state.last_detail = ''
		provider.state.last_intent = ''
		provider.state.active_count = 0
		provider.state.quota = 0
		provider.state.camp_distance = nil
		provider.state.target_camp_distance = nil
		provider.state.action_range = nil
		provider.state.cast_range = nil
		provider.state.target_distance = nil
		provider.state.target_hpp = nil
		provider.state.target_status = nil
		provider.state.target_claim_id = nil
		provider.state.action_in_flight = false
		provider.state.cooldown_until = 0
		publish(reason or 'PULL_IDLE')
	end

	local function config_from_context(ctx)
		local settings = require_table(ctx.settings, 'ctx.settings')
		local config = settings.camp_pulling
		if type(config) ~= 'table' then
			error('normalized combat.pulling configuration is required')
		end
		return config
	end

	local function action_contract(config)
		local action_type = tostring(config.action.type or '')
		local resource
		if action_type == 'spell' then
			resource = get_spell_resource(config.action.name)
		elseif action_type == 'ja' then
			resource = get_ja_resource(config.action.name)
		else
			return nil, 'PULL_ACTION_TYPE_INVALID'
		end
		if type(resource) ~= 'table' or tonumber(resource.id) == nil then
			return nil, 'PULL_ACTION_RESOURCE_MISSING'
		end
		if tostring(resource.en or '') ~= config.action.name then
			return nil, 'PULL_ACTION_RESOURCE_NAME_MISMATCH'
		end
		local max_range = action_effective_range(resource.range)
		if finite_number(max_range) == nil or max_range <= 0 then
			return nil, 'PULL_ACTION_RANGE_INVALID'
		end
		return {
			action_type = action_type,
			action_name = config.action.name,
			resource = resource,
			max_range = max_range,
			cast_range = max_range * config.cast_range_ratio,
		}, nil
	end

	local function cooldown_target(config, now, reason)
		if provider.state.target_id > 0 then
			provider.state.cooldowns[provider.state.target_id] = now + config.target_cooldown_seconds
			provider.state.cooldown_until = provider.state.cooldowns[provider.state.target_id]
		end
		provider.state.name = 'RETURN_TO_CAMP'
		provider.state.last_reason = canonical_reason(reason)
		provider.state.last_detail = tostring(reason or '')
	end

	local function current_target(ctx)
		if type(ctx.mobs_by_id) ~= 'table' then
			return nil
		end
		return ctx.mobs_by_id[provider.state.target_id]
	end

	local function target_distance(mob)
		local squared = finite_number(mob and mob.distance)
		if squared == nil or squared < 0 then
			return nil
		end
		return math.sqrt(squared)
	end

	local function update_target_observation(ctx)
		local mob = current_target(ctx)
		provider.state.target_distance = target_distance(mob)
		provider.state.target_hpp = finite_number(mob and mob.hpp)
		provider.state.target_status = finite_number(mob and mob.status)
		provider.state.target_claim_id = finite_number(mob and mob.claim_id)
	end

	local function action_not_dispatched()
		local name = provider.state.name
		return name == 'APPROACH'
			or name == 'SETTLE'
			or name == 'SEND_ACTION'
	end

	local function heading_to(from, destination)
		local fx = finite_number(from and from.x)
		local fy = finite_number(from and from.y)
		local tx = finite_number(destination and destination.x)
		local ty = finite_number(destination and destination.y)
		if fx == nil or fy == nil or tx == nil or ty == nil then
			return nil
		end
		return math.atan2(tx - fx, ty - fy) - 1.5708
	end

	local function copy_point(source)
		local x = finite_number(source and source.x)
		local y = finite_number(source and source.y)
		if x == nil or y == nil then
			return nil
		end
		return {
			x = x,
			y = y,
		}
	end

	local function record_breadcrumb(me)
		local point = copy_point(me)
		if point == nil then
			return
		end
		local last = provider.state.last_breadcrumb
		if last == nil or policy.distance_2d(last, point) >= 2.0 then
			provider.state.breadcrumbs[#provider.state.breadcrumbs + 1] = point
			provider.state.last_breadcrumb = point
		end
	end

	local function reset_progress(now, distance)
		provider.state.last_progress_at = now
		provider.state.last_progress_distance = distance
		provider.state.recovery_count = 0
	end

	local function movement_stalled(now, distance)
		if provider.state.last_progress_distance == nil then
			reset_progress(now, distance)
			return false
		end
		if distance <= provider.state.last_progress_distance - 0.25 then
			provider.state.last_progress_at = now
			provider.state.last_progress_distance = distance
			provider.state.recovery_count = 0
			return false
		end
		return now - provider.state.last_progress_at >= 2.0
	end

	local function begin_journey(ctx, config, anchor, friendly_claims, demand)
		local lane_available, lane_reason = can_start_journey()
		if type(lane_available) ~= 'boolean' then
			error('camp pull start-lane contract must return a boolean')
		end
		if lane_available ~= true then
			if type(lane_reason) ~= 'string' or lane_reason == '' then
				error('camp pull blocked start-lane contract requires a reason')
			end
			publish('PULL_WAIT_ACTION_LANE:' .. lane_reason, demand)
			return false
		end
		local candidate, selection_reason = policy.select_candidate(
			config,
			ctx,
			anchor,
			friendly_claims,
			provider.state.cooldowns,
			function(mob)
				return ignored(ctx.settings, mob)
			end
		)
		if candidate == nil then
			publish(selection_reason, demand)
			return false
		end
		provider.state.target_id = candidate.id
		provider.state.target_name = candidate.name
		provider.state.target_camp_distance = candidate.camp_distance
		provider.state.name = 'APPROACH'
		provider.state.last_reason = selection_reason
		update_target_observation(ctx)
		provider.state.breadcrumbs = {}
		provider.state.last_breadcrumb = nil
		record_breadcrumb(ctx.me)
		provider.state.last_progress_at = ctx.now
		provider.state.last_progress_distance = nil
		provider.state.recovery_count = 0
		provider.state.retry_count = 0
		provider.state.retry_window_started_at = 0
		publish(selection_reason, demand)
		return true
	end

	local function emit_recovery(ctx, out, destination, reason)
		local heading = heading_to(ctx.me, destination)
		if heading == nil then
			error('camp pull recovery geometry is unavailable')
		end
		local direction = provider.state.recovery_count % 2 == 0 and 1 or -1
		out[#out + 1] = proposal(ctx, {
			action_type = 'camp_recover',
			action_name = 'recover_movement',
			target_kind = 'none',
			target_id = 0,
			target_name = '',
			reason_code = reason,
			priority_band = 225,
			detail = {
				heading = heading + direction * (math.pi / 2),
			},
		})
		provider.state.last_intent = 'recover'
		provider.state.recovery_count = provider.state.recovery_count + 1
		provider.state.last_progress_at = ctx.now
	end

	local function emit_move_to_target(ctx, out, mob, action)
		local heading = heading_to(ctx.me, mob)
		if heading == nil then
			error('camp pull approach geometry is unavailable')
		end
		out[#out + 1] = proposal(ctx, {
			action_type = 'camp_approach',
			action_name = 'approach',
			target_kind = 'mob',
			target_id = provider.state.target_id,
			target_name = provider.state.target_name,
			reason_code = 'PULL_APPROACH',
			detail = {
				heading = heading,
				action_range = action.max_range,
				cast_range = action.cast_range,
			},
		})
		provider.state.last_intent = 'approach'
	end

	local function emit_stop(ctx, out, reason)
		out[#out + 1] = proposal(ctx, {
			action_type = 'camp_stop',
			action_name = 'stop',
			target_kind = 'none',
			target_id = 0,
			target_name = '',
			reason_code = reason,
			priority_band = 220,
		})
		provider.state.last_intent = 'stop'
	end

	local function emit_pull_action(ctx, out, config, action)
		local ready, ready_reason, ready_kind = action_ready(action.action_name, provider.state.target_id)
		if not ready or ready_kind ~= action.action_type then
			publish('PULL_ACTION_NOT_READY:' .. tostring(ready_reason))
			return
		end
		out[#out + 1] = proposal(ctx, {
			action_type = action.action_type,
			action_name = action.action_name,
			target_kind = 'mob',
			target_id = provider.state.target_id,
			target_name = provider.state.target_name,
			max_range = action.max_range,
			movement_policy = 'must_stop',
			expected_ack = action.action_type == 'spell' and 'spell_start' or 'action_start',
			expected_effect = 'pull_action_result',
			reason_code = 'PULL_SEND_ACTION',
			priority_band = 220,
			urgency = 1.0,
			detail = {
				pull_action = true,
				action_type = action.action_type,
				action_name = action.action_name,
				action_range = action.max_range,
				cast_range = action.cast_range,
			},
		})
		provider.state.last_intent = action.action_type
	end

	local function emit_return(ctx, out, anchor)
		local heading = heading_to(ctx.me, anchor)
		if heading == nil then
			error('camp pull return geometry is unavailable')
		end
		out[#out + 1] = proposal(ctx, {
			action_type = 'camp_return',
			action_name = 'return_to_camp',
			target_kind = 'none',
			target_id = 0,
			target_name = '',
			reason_code = 'PULL_RETURN_TO_CAMP',
			priority_band = 220,
			detail = {
				heading = heading,
				camp_x = anchor.x,
				camp_y = anchor.y,
			},
		})
		provider.state.last_intent = 'return'
	end

	function provider.acquire_lane(ctx)
		require_table(ctx, 'ctx')
		if provider.state.name ~= 'IDLE' then
			return true
		end
		local config = config_from_context(ctx)
		if config.enabled ~= true or rawget(_G, 'Start_Engine') ~= true then
			return false
		end
		if ctx.player_present == false
			or (type(ctx.player) == 'table'
				and type(ctx.player.vitals) == 'table'
				and tonumber(ctx.player.vitals.hpp) == 0) then
			return false
		end
		local anchor, anchor_reason = resolve_camp_anchor()
		if type(anchor) ~= 'table' then
			if type(anchor_reason) ~= 'string' or anchor_reason == '' then
				error('camp anchor contract requires a reason when unavailable')
			end
			publish(anchor_reason)
			return false
		end
		provider.state.camp_distance = policy.distance_2d(ctx.me, anchor)
		local action, action_reason = action_contract(config)
		if action == nil then
			publish(action_reason)
			return false
		end
		provider.state.action_range = action.max_range
		provider.state.cast_range = action.cast_range
		local friendly_claims = get_friendly_claims()
		local demanded, demand = policy.pull_demand(config, ctx.mob_array, friendly_claims)
		if not demanded then
			publish('PULL_QUOTA_SATISFIED', demand)
			return false
		end
		return begin_journey(ctx, config, anchor, friendly_claims, demand)
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		local config = config_from_context(ctx)
		if config.enabled ~= true or rawget(_G, 'Start_Engine') ~= true then
			if provider.state.name ~= 'IDLE' then
				provider.state.name = 'ABORT_STOP'
				emit_stop(ctx, out, config.enabled == true and 'PULL_ENGINE_OFF' or 'PULL_DISABLED')
				publish(config.enabled == true and 'PULL_ENGINE_OFF' or 'PULL_DISABLED')
			else
				publish(config.enabled == true and 'PULL_ENGINE_OFF' or 'PULL_DISABLED')
			end
			return
		end
		if ctx.player_present == false
			or (type(ctx.player) == 'table'
				and type(ctx.player.vitals) == 'table'
				and tonumber(ctx.player.vitals.hpp) == 0) then
			if provider.state.name ~= 'IDLE' then
				provider.state.name = 'ABORT_STOP'
				emit_stop(ctx, out, 'PULL_PLAYER_UNAVAILABLE')
			end
			publish('PULL_PLAYER_UNAVAILABLE')
			return
		end
		local anchor, anchor_reason = resolve_camp_anchor()
		if type(anchor) ~= 'table' then
			if provider.state.name ~= 'IDLE' then
				provider.state.name = 'ABORT_STOP'
				emit_stop(ctx, out, tostring(anchor_reason or 'PULL_CAMP_UNAVAILABLE'))
			else
				publish(tostring(anchor_reason or 'PULL_CAMP_UNAVAILABLE'))
			end
			return
		end
		provider.state.camp_distance = policy.distance_2d(ctx.me, anchor)
		if provider.state.name == 'ABORT_STOP' then
			emit_stop(ctx, out, provider.state.last_reason ~= '' and provider.state.last_reason or 'PULL_ABORT_STOP')
			return
		end
		local action, action_reason = action_contract(config)
		if action == nil then
			publish(action_reason)
			return
		end
		provider.state.action_range = action.max_range
		provider.state.cast_range = action.cast_range
		update_target_observation(ctx)
		local friendly_claims = get_friendly_claims()
		local demanded, demand = policy.pull_demand(config, ctx.mob_array, friendly_claims)

		if action_not_dispatched() and not demanded then
			provider.state.name = 'RETURN_TO_CAMP'
			provider.state.last_progress_distance = nil
			publish('PULL_QUOTA_SATISFIED_BEFORE_ACTION', demand)
		end

		if provider.state.name == 'IDLE' then
			if not demanded then
				publish('PULL_QUOTA_SATISFIED', demand)
				return
			end
			if not begin_journey(ctx, config, anchor, friendly_claims, demand) then
				return
			end
		end

		if provider.state.name == 'APPROACH' then
			local mob = current_target(ctx)
			local eligible, reason = policy.candidate_eligible(
				config,
				ctx,
				anchor,
				provider.state.cooldowns,
				function(candidate)
					return ignored(ctx.settings, candidate)
				end,
				mob
			)
			if not eligible then
				cooldown_target(config, ctx.now, reason)
			else
				local distance = target_distance(mob)
				if distance == nil then
					cooldown_target(config, ctx.now, 'PULL_TARGET_DISTANCE_UNAVAILABLE')
				elseif distance > action.cast_range then
					record_breadcrumb(ctx.me)
					if movement_stalled(ctx.now, distance) then
						if provider.state.recovery_count < 2 then
							emit_recovery(ctx, out, mob, 'PULL_MOVEMENT_STALLED')
							publish('PULL_MOVEMENT_RECOVERY', demand)
							return
						end
						cooldown_target(config, ctx.now, 'PULL_MOVEMENT_STALLED')
					else
						emit_move_to_target(ctx, out, mob, action)
						publish('PULL_APPROACH', demand)
						return
					end
				else
					provider.state.name = 'SETTLE'
					provider.state.settle_until = 0
					reset_progress(ctx.now, distance)
				end
			end
		end

		if provider.state.name == 'SETTLE' then
			if provider.state.settle_until == 0 then
				emit_stop(ctx, out, 'PULL_PRECAST_STOP')
				publish('PULL_PRECAST_STOP', demand)
				return
			end
			if ctx.now < provider.state.settle_until then
				publish('PULL_PRECAST_SETTLE', demand)
				return
			end
			provider.state.name = 'SEND_ACTION'
		end

		if provider.state.name == 'SEND_ACTION' then
			local mob = current_target(ctx)
			local distance = target_distance(mob)
			if distance == nil or distance > action.cast_range then
				provider.state.name = 'APPROACH'
				publish('PULL_RANGE_CHANGED', demand)
				return
			end
			emit_pull_action(ctx, out, config, action)
			return
		end

		if provider.state.name == 'WAIT_ACTION_RESULT' then
			if ctx.now - provider.state.action_sent_at > config.retry_window_seconds then
				provider.state.action_in_flight = pull_action_in_flight(
					provider.state.target_id,
					action.action_type,
					action.action_name
				)
				if provider.state.action_in_flight then
					publish('PULL_ACTION_IN_FLIGHT', demand)
					return
				end
				provider.note_action_result(false, ctx.now, config)
			else
				provider.state.action_in_flight = true
				publish('PULL_WAIT_ACTION_RESULT', demand)
				return
			end
		end

		if provider.state.name == 'WAIT_TARGET_REACTION' then
			local mob = current_target(ctx)
			local claim_id = tonumber(mob and mob.claim_id) or 0
			local reacted = mob == nil
				or (tonumber(mob.hpp) or 100) < 100
				or (claim_id > 0 and friendly_claims[claim_id] == true)
				or tonumber(mob.status) == 1
			if reacted then
				provider.state.name = 'RETURN_TO_CAMP'
				provider.state.last_reason = 'PULL_TARGET_REACTED'
				provider.state.last_progress_distance = nil
			elseif provider.state.reaction_deadline > 0
				and ctx.now >= provider.state.reaction_deadline then
				cooldown_target(config, ctx.now, 'PULL_REACTION_TIMEOUT')
			else
				publish('PULL_WAIT_TARGET_REACTION', demand)
				return
			end
		end

		if provider.state.name == 'RETURN_TO_CAMP' then
			local distance = policy.distance_2d(ctx.me, anchor)
			if distance == nil then
				reset('PULL_RETURN_GEOMETRY_UNAVAILABLE')
				return
			end
			if distance <= config.camp_arrival_yalms then
				emit_stop(ctx, out, 'PULL_CAMP_ARRIVED')
				publish('PULL_CAMP_ARRIVED', demand)
				return
			end
			local destination = provider.state.breadcrumbs[#provider.state.breadcrumbs] or anchor
			local destination_distance = policy.distance_2d(ctx.me, destination)
			if destination_distance == nil then
				provider.state.name = 'ABORT_STOP'
				emit_stop(ctx, out, 'PULL_RETURN_GEOMETRY_UNAVAILABLE')
				return
			end
			if #provider.state.breadcrumbs > 0 and destination_distance <= 0.75 then
				table.remove(provider.state.breadcrumbs)
				provider.state.last_progress_distance = nil
				destination = provider.state.breadcrumbs[#provider.state.breadcrumbs] or anchor
				destination_distance = policy.distance_2d(ctx.me, destination)
			end
			if movement_stalled(ctx.now, destination_distance) then
				if provider.state.recovery_count < 2 then
					emit_recovery(ctx, out, destination, 'PULL_RETURN_STALLED')
					publish('PULL_RETURN_RECOVERY', demand)
					return
				end
				provider.state.name = 'ABORT_STOP'
				emit_stop(ctx, out, 'PULL_RETURN_STALLED')
				publish('PULL_RETURN_STALLED', demand)
				return
			end
			emit_return(ctx, out, destination)
			publish('PULL_RETURN_TO_CAMP', demand)
		end
	end

	function provider.revalidate(selected, ctx)
		require_table(selected, 'selected')
		require_table(ctx, 'ctx')
		local config = config_from_context(ctx)
		local action_type = tostring(selected.action_type or '')
		if action_type == 'camp_stop' and provider.state.name == 'ABORT_STOP' then
			return true, 'PULL_ABORT_STOP'
		end
		if config.enabled ~= true then
			return false, 'PULL_DISABLED'
		end
		local anchor, reason = resolve_camp_anchor()
		if type(anchor) ~= 'table' then
			return false, reason
		end
		if action_type == 'camp_approach' then
			return provider.state.name == 'APPROACH'
				and tonumber(selected.target_id) == provider.state.target_id,
				'PULL_APPROACH_STALE'
		end
		if action_type == 'camp_stop' then
			return provider.state.name == 'SETTLE' or provider.state.name == 'RETURN_TO_CAMP',
				'PULL_STOP_STALE'
		end
		if action_type == 'camp_return' then
			return provider.state.name == 'RETURN_TO_CAMP', 'PULL_RETURN_STALE'
		end
		if action_type == 'camp_recover' then
			return provider.state.name == 'APPROACH' or provider.state.name == 'RETURN_TO_CAMP',
				'PULL_RECOVERY_STALE'
		end
		if action_type == 'spell' or action_type == 'ja' then
			local action, action_reason = action_contract(config)
			if action == nil then
				return false, action_reason
			end
			if provider.state.name ~= 'SEND_ACTION'
				or action.action_type ~= action_type
				or action.action_name ~= selected.action_name
				or tonumber(selected.target_id) ~= provider.state.target_id then
				return false, 'PULL_ACTION_STALE'
			end
			local mob = current_target(ctx)
			local distance = target_distance(mob)
			return distance ~= nil and distance <= action.cast_range, 'PULL_ACTION_RANGE_CHANGED'
		end
		return false, 'PULL_PROPOSAL_TYPE_INVALID'
	end

	function provider.note_dispatch(selected, now, config)
		require_table(config, 'config')
		local action_type = tostring(selected.action_type or '')
		if action_type == 'camp_stop' and provider.state.name == 'SETTLE' then
			provider.state.settle_until = now + config.settle_seconds
		elseif action_type == 'camp_stop' and provider.state.name == 'RETURN_TO_CAMP' then
			reset('PULL_COMPLETE')
		elseif action_type == 'camp_stop' and provider.state.name == 'ABORT_STOP' then
			reset('PULL_ABORTED')
		elseif action_type == 'spell' or action_type == 'ja' then
			provider.state.name = 'WAIT_ACTION_RESULT'
			provider.state.action_sent_at = now
			if provider.state.retry_window_started_at == 0 then
				provider.state.retry_window_started_at = now
			end
			provider.state.last_reason = 'PULL_ACTION_SENT'
		end
	end

	function provider.note_settle_stop(now, settle_seconds)
		provider.state.settle_until = now + settle_seconds
	end

	function provider.note_action_result(success, now, config)
		if provider.state.name ~= 'WAIT_ACTION_RESULT' then
			return false
		end
		if success then
			provider.state.action_in_flight = false
			provider.state.name = 'WAIT_TARGET_REACTION'
			provider.state.reaction_deadline = now + config.reaction_timeout_seconds
			provider.state.last_reason = 'PULL_ACTION_SUCCEEDED'
		else
			provider.state.action_in_flight = false
			if provider.state.retry_window_started_at == 0 then
				provider.state.retry_window_started_at = provider.state.action_sent_at
			end
			local inside_window = now - provider.state.retry_window_started_at
				<= config.retry_window_seconds
			if inside_window and provider.state.retry_count < config.retry_limit then
				provider.state.retry_count = provider.state.retry_count + 1
				provider.state.name = 'SETTLE'
				provider.state.settle_until = now + config.settle_seconds
				provider.state.last_reason = 'PULL_ACTION_RETRY'
			else
				cooldown_target(config, now, 'PULL_ACTION_FAILED')
			end
		end
		return true
	end

	function provider.active()
		return provider.state.name ~= 'IDLE'
	end

	function provider.movement_reserved(config)
		return M.movement_reserved(config)
	end

	function provider.status_snapshot()
		return {
			state = provider.state.name,
			target_id = provider.state.target_id,
			target_name = provider.state.target_name,
			reason = provider.state.last_reason,
			detail = provider.state.last_detail,
			last_intent = provider.state.last_intent,
			active_count = provider.state.active_count,
			quota = provider.state.quota,
			camp_distance = provider.state.camp_distance,
			target_camp_distance = provider.state.target_camp_distance,
			target_distance = provider.state.target_distance,
			target_hpp = provider.state.target_hpp,
			target_status = provider.state.target_status,
			target_claim_id = provider.state.target_claim_id,
			action_in_flight = provider.state.action_in_flight,
			action_range = provider.state.action_range,
			cast_range = provider.state.cast_range,
			cooldown_until = provider.state.cooldown_until,
			breadcrumb_count = #provider.state.breadcrumbs,
			recovery_count = provider.state.recovery_count,
			retry_count = provider.state.retry_count,
		}
	end

	function provider.reset(reason)
		reset(reason)
	end

	return provider
end

return M
