local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_maintenance %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_maintenance deps.%s must be a function'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local log_def_sched = require_function(deps, 'log_def_sched')
	local is_city_zone = require_function(deps, 'is_city_zone')
	local ensure_buff_cache = require_function(deps, 'ensure_buff_cache')
	local number = require_function(deps, 'number')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local action_timeline_action_state_summary = require_function(deps, 'action_timeline_action_state_summary')
	local action_timeline_log = require_function(deps, 'action_timeline_log')
	local cor_propose = require_function(deps, 'cor_propose')
	local get_party_members = require_function(deps, 'get_party_members')
	local action_ready = require_function(deps, 'action_ready')
	local clear_local_brd_spell_failure = require_function(deps, 'clear_local_brd_spell_failure')
	local pending_mark_failed = require_function(deps, 'pending_mark_failed')
	local count_matching_buffs = require_function(deps, 'count_matching_buffs')
	local phase1 = require_table(deps.phase1, 'deps.phase1')
	local maintenance_buff_cache = require_table(deps.maintenance_buff_cache, 'deps.maintenance_buff_cache')
	local action_timeline_state = require_table(deps.action_timeline_state, 'deps.action_timeline_state')
	local brd_maintenance_priority = tonumber(deps.brd_maintenance_priority)
	if brd_maintenance_priority == nil then
		error('uc_provider_maintenance deps.brd_maintenance_priority must be numeric')
	end

	local provider = {}

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			log_def_sched('MAINT_SKIP reason=ENGINE_OFF')
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true then
			log_def_sched('MAINT_SKIP reason=NO_PLAYER')
			return
		end
		local job = tostring(player.main_job or '')
		if job == '' then
			log_def_sched('MAINT_SKIP reason=NO_JOB')
			return
		end
		local gate = phase1.maintenance_next_at or {}
		phase1.maintenance_next_at = gate
		if is_city_zone() then
			log_def_sched('MAINT_SKIP reason=CITY_ZONE')
			gate.cor_rolls = 0
			gate.brd_songs = 0
			return
		end
		local now = ctx.now
		ensure_buff_cache()
		local buff_list = player.buffs or {}
		local function log_maint_candidate(event_code, key, action_name, source_provider, reason, urgency, priority_band, detail, interval)
			detail = type(detail) == 'table' and detail or {}
			local fields = {
				spell = (tostring(detail.cast_type or '') == 'spell' or tostring(detail.action_type or '') == 'spell') and tostring(action_name or '') or '',
				action = tostring(action_name or ''),
				target = tostring(detail.target_name or player.name or ''),
				target_id = tonumber(detail.target_id) or tonumber(player.id) or 0,
				provider = tostring(source_provider or ''),
				band = priority_band,
				urgency = urgency ~= nil and ('%.2f'):format(clamp_urgency(urgency)) or '',
				reason = tostring(reason or ''),
				status = tonumber(player.status) or 0,
				action_state = action_timeline_action_state_summary(now),
				range = detail.range or '',
				target_valid = detail.target_valid,
			}
			for extra_key, extra_value in pairs(detail) do
				if fields[extra_key] == nil or fields[extra_key] == '' then
					fields[extra_key] = extra_value
				end
			end
			action_timeline_log(event_code, fields, ('maint_candidate:%s:%s:%s'):format(tostring(event_code or ''), tostring(key or ''), tostring(reason or '')), interval or 2.0)
		end
		local function maybe_emit(key, source_provider, action_type, action_name, reason_code, urgency, priority_band, proposal_throttle_s, detail)
			detail = type(detail) == 'table' and detail or {}
			detail.cast_type = action_type
			detail.action_type = action_type
			local proposal_target_id = tonumber(detail.target_id)
			local proposal_target_name = tostring(detail.target_name or '')
			if proposal_target_id == nil then
				proposal_target_id = tonumber(player.id) or 0
				proposal_target_name = tostring(player.name or '')
			end
			if proposal_target_id <= 0 or proposal_target_name == '' then
				error('maintenance proposal requires an explicit valid target')
			end
			detail.target_name = proposal_target_name
			detail.target_id = proposal_target_id
			if action_type == 'spell' then
				local out_of_combat = tonumber(player.status) ~= 1
				if out_of_combat then
					local lor_actor_mod = require('lor/lor_actor')
					if type(lor_actor_mod) ~= 'table'
						or type(lor_actor_mod.Actor) ~= 'table'
						or type(lor_actor_mod.Actor.new) ~= 'function' then
						error('uc_provider_maintenance lor/lor_actor contract is invalid')
					end
					local actor = rawget(_G, 'UC_SCHED_MAINT_LOCAL_ACTOR')
					if actor == nil then
						actor = lor_actor_mod.Actor.new()
						rawset(_G, 'UC_SCHED_MAINT_LOCAL_ACTOR', actor)
					end
					if type(actor) ~= 'table' or type(actor.is_moving) ~= 'function' then
						error('uc_provider_maintenance local actor contract is invalid')
					end
					local moving = actor:is_moving() == true
					if moving then
						detail.proposal_emitted = '0'
						log_maint_candidate('MAINT_BUFF_CANDIDATE_HELD', key, action_name, source_provider, 'player_moving', urgency, priority_band, detail, 2.0)
						return false, 'player_moving', 0
					end
				end
			end
			local next_at = number(gate[key], 0)
			if now < next_at then
				detail.throttle_key = tostring(key or '')
				detail.now_value = ('%.2f'):format(now)
				detail.next_allowed_at = ('%.2f'):format(next_at)
				detail.remaining_s = ('%.2f'):format(math.max(0, next_at - now))
				detail.last_maintenance_action = tostring(action_timeline_state.last_maintenance_dispatch_action or '')
				detail.last_maintenance_token = tostring(action_timeline_state.last_maintenance_dispatch_token or '')
				detail.proposal_emitted = '0'
				log_maint_candidate('MAINT_BUFF_CANDIDATE_HELD', key, action_name, source_provider, 'throttle', urgency, priority_band, detail, 2.0)
				return false, 'throttle', math.max(0, next_at - now)
			end
			if type(proposal_throttle_s) ~= 'number' then
				error('maintenance proposal throttle must be numeric')
			end
			if proposal_throttle_s > 0 then
				gate[key] = now + proposal_throttle_s
			end
			detail.proposal_emitted = '1'
			log_maint_candidate('MAINT_BUFF_CANDIDATE_READY', key, action_name, source_provider, reason_code, urgency, priority_band, detail, 0.50)
			out[#out + 1] = {
				proposal_id = ('maint.%s.%d'):format(key, math.floor(now * 1000)),
				family_id = ('maintenance.%s'):format(key),
				provider = source_provider,
				action_type = action_type,
				action_name = action_name,
				target_kind = proposal_target_id == (tonumber(player.id) or 0) and 'self' or 'ally',
				target_id = proposal_target_id,
				target_name = proposal_target_name,
				priority_band = priority_band,
				urgency = clamp_urgency(urgency),
				starvation_eligible = true,
				created_at = now,
				expires_at = now + 0.40,
				commit_deadline = now + 0.25,
				movement_policy = 'must_stop',
				range_policy = { min = 0.0, max = 20.0, los_required = false },
				recast_key = ('maint:%s'):format(key),
				duplicate_suppression_key = ('maint:%s:%d'):format(key, proposal_target_id),
				lock_class = 'support_action',
				expected_ack = 'action_start',
				expected_effect = 'buff_gain',
				sticky = true,
				can_preempt_movement = true,
				can_preempt_same_band = false,
				reason_code = reason_code,
				detail = detail or { job = job },
				legacy_command = '',
			}
			return true, nil, 0
		end
		if job == 'COR' then
			local action = cor_propose(ctx.settings)
			if action and action.action_name and action.action_name ~= '' then
				local key = 'cor_rolls'
				local next_at = number(gate[key], 0)
				if now >= next_at then
					gate[key] = now + 1.0
					local urgency = clamp_urgency(tonumber(action.urgency) or 0.65)
					local action_name = tostring(action.action_name or '')
					local target_name = tostring(action.target_name or '<me>')
					local target_kind = tostring(action.target_kind or 'self')
					local target_id = tonumber(action.target_id) or 0
					out[#out + 1] = {
						proposal_id = ('maint.cor.%s.%d'):format(action_name, math.floor(now * 1000)),
						family_id = 'maintenance.cor.rolls',
						provider = 'maintenance_cor',
						action_type = 'ja',
						action_name = action_name,
						target_kind = target_kind,
						target_id = target_id,
						target_name = target_name,
						priority_band = 75,
						urgency = urgency,
						starvation_eligible = true,
						created_at = now,
						expires_at = now + 0.40,
						commit_deadline = now + 0.25,
						movement_policy = 'must_stop',
						range_policy = { min = 0.0, max = 20.0, los_required = false },
						recast_key = ('maint:cor:%s'):format(action_name),
						duplicate_suppression_key = ('maint:cor:%s:%d'):format(action_name, target_id),
						lock_class = 'support_action',
						expected_ack = 'action_start',
						expected_effect = 'buff_gain',
						sticky = true,
						can_preempt_movement = true,
						can_preempt_same_band = false,
						reason_code = tostring(action.reason_code or 'cor_roll_maint'),
						detail = action.detail or { job = job },
					}
					log_maint_candidate('MAINT_BUFF_CANDIDATE_READY', key, action_name, 'maintenance_cor', tostring(action.reason_code or 'cor_roll_maint'), urgency, 75, {
						target_name = target_name,
						target_id = target_id,
						action_type = 'ja',
					}, 0.50)
				else
					log_maint_candidate('MAINT_BUFF_CANDIDATE_HELD', key, tostring(action.action_name or ''), 'maintenance_cor', 'throttle', tonumber(action.urgency) or 0.65, 75, {
						target_name = tostring(action.target_name or '<me>'),
						target_id = tonumber(action.target_id) or 0,
						action_type = 'ja',
					}, 2.0)
				end
			else
				log_def_sched('MAINT_COR_SKIP reason=PROPOSE_NIL')
				log_maint_candidate('MAINT_BUFF_CANDIDATE_SKIPPED', 'cor_rolls', '', 'maintenance_cor', 'propose_nil', 0.65, 75, {
					action_type = 'ja',
				}, 2.0)
				gate.cor_rolls = 0
			end
		elseif job == 'BRD' or tostring(player.sub_job or '') == 'BRD' then
			local brd_config = require('uc_active_config').get_path('config.maintenance.brd')
			local brd_maintenance = require('uc_brd_maintenance')
			local brd_positioning = require('uc_brd_positioning')
			local brd_party_members = get_party_members(ctx)
			for _, member in ipairs(brd_party_members) do
				if member.is_self == true then
					member.x = ctx.me.x
					member.y = ctx.me.y
					member.z = ctx.me.z
				end
				member.in_song_range, member.song_distance = require('uc_brd_party_song_state').in_recovery_range(
					member,
					brd_config.recovery_range_yalms,
					function(member_id)
						return ctx.mobs_by_id[tonumber(member_id) or 0]
					end
				)
			end
			local action = brd_maintenance.propose(brd_config, {
				now = now,
				player = player,
				party_members = brd_party_members,
				action_ready = action_ready,
			})
			if type(action) == 'table' and tostring(action.action_name or '') ~= '' then
				local camp_anchor = require('uc_camp_anchor').resolve_current_anchor()
				local pulling_config = require('uc_active_config').get_path('config.combat.pulling')
				local formation_status = rawget(_G, 'UC_FORMATION_STATUS')
				local allow_formation_partial = type(formation_status) == 'table'
					and formation_status.enabled == true
					and formation_status.kind == 'generic'
					and formation_status.phase == 'active'
				if type(pulling_config) ~= 'table' or tonumber(pulling_config.leash_yalms) == nil then
					error('Bard positioning requires normalized combat.pulling configuration')
				end
				local ready_to_emit, positioning_reason = brd_positioning.prepare({
					enabled = brd_config.reposition_for_party_songs,
					now = now,
					action = action,
					me = ctx.me,
					party_members = brd_party_members,
					ignore_names = brd_config.recovery_ignore_names,
					radius = brd_config.recovery_range_yalms,
					camp_anchor = camp_anchor,
					camp_leash_yalms = camp_anchor and pulling_config.leash_yalms or nil,
					allow_formation_partial = allow_formation_partial,
				})
				if ready_to_emit ~= true then
					local positioning_status = brd_positioning.status()
					brd_maintenance.note_positioning_block(positioning_reason, positioning_status)
					if positioning_status.phase == 'waiting' or positioning_status.phase == 'failed' then
						brd_maintenance.defer_positioning(positioning_reason)
					end
					action = nil
				end
			end
			local failure = brd_maintenance.take_scheduler_failure()
			if type(failure) == 'table' then
				clear_local_brd_spell_failure({
					terminal_outcome = tostring(failure.reason or 'brd_spell_failure'),
				})
				local retry_delay = tonumber(failure.retry_delay) or 0.75
				pending_mark_failed(now, tostring(failure.reason or 'brd_spell_failure'), retry_delay)
				gate.brd_songs = math.max(tonumber(gate.brd_songs) or 0, now + retry_delay)
				action = nil
			end
			if type(action) == 'table' and tostring(action.action_name or '') ~= '' then
				maybe_emit(
					'brd_songs',
					'maintenance_brd',
					tostring(action.action_type or ''),
					tostring(action.action_name or ''),
					tostring(action.reason_code or 'brd_song_maintenance'),
					tonumber(action.urgency) or 0.75,
					brd_maintenance_priority,
					0,
					action.detail
				)
			elseif failure == nil then
				gate.brd_songs = 0
			end
		end
	end

	return provider
end

return M
