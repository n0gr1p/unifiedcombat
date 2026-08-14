local camp_pull_registry = require('uc_camp_pull_registry')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_combat %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_combat deps.%s must be a function'):format(name))
	end
	return value
end

local function require_number(deps, name)
	local value = tonumber(deps[name])
	if value == nil then
		error(('uc_provider_combat deps.%s must be numeric'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local build_partner_target_set = require_function(deps, 'build_partner_target_set')
	local select_ws_plan = require_function(deps, 'select_ws_plan')
	local action_timeline_log = require_function(deps, 'action_timeline_log')
	local combat_domain_enabled = require_function(deps, 'combat_domain_enabled')
	local sleep_enabled = require_function(deps, 'sleep_enabled')
	local sleep_spell_list = require_function(deps, 'sleep_spell_list')
	local is_live_actionable_target = require_function(deps, 'is_live_actionable_target')
	local build_friendly_claims = require_function(deps, 'build_friendly_claims')
	local mob_targets_friendly_member = require_function(deps, 'mob_targets_friendly_member')
	local sleep_max_target_distance = require_function(deps, 'sleep_max_target_distance')
	local target_sleep_suppressed = require_function(deps, 'target_sleep_suppressed')
	local select_sleep_spell = require_function(deps, 'select_sleep_spell')
	local combat_autotarget = require_function(deps, 'combat_autotarget')
	local tank_enabled = require_function(deps, 'tank_enabled')
	local debug_enabled = require_function(deps, 'debug_enabled')
	local combat_prime = require_function(deps, 'combat_prime')
	local fight_leader_enabled = require_function(deps, 'fight_leader_enabled')
	local fight_leader_id = require_function(deps, 'fight_leader_id')
	local fight_leader_target_id = require_function(deps, 'fight_leader_target_id')
	local select_pull = require_function(deps, 'select_pull')
	local build_party_id_set = require_function(deps, 'build_party_id_set')
	local prime_unclaimed_party_aggressive_ok = require_function(deps, 'prime_unclaimed_party_aggressive_ok')
	local pending_engage_state = require_function(deps, 'pending_engage_state')
	local pending_engage_live = require_function(deps, 'pending_engage_live')
	local collect_ordered_abilities = require_function(deps, 'collect_ordered_abilities')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local action_ready = require_function(deps, 'action_ready')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local log_ja_sched = require_function(deps, 'log_ja_sched')
	local phase1 = require_table(deps.phase1, 'deps.phase1')
	local action_state = require_table(deps.action_state, 'deps.action_state')
	local skillchain_priority = require_number(deps, 'skillchain_priority')
	local aftermath_priority = require_number(deps, 'aftermath_priority')
	local sleep_priority = require_number(deps, 'sleep_priority')
	local tank_engage_priority = require_number(deps, 'tank_engage_priority')
	local default_engage_priority = require_number(deps, 'default_engage_priority')
	local tank_engage_urgency = require_number(deps, 'tank_engage_urgency')
	local default_engage_urgency = require_number(deps, 'default_engage_urgency')

	local provider = {}

	function provider.collect_offense(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		if not bool_setting(ctx.settings.weaponskill_active, false) then
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true or tonumber(player.status) ~= 1 then
			return
		end
		local tp = tonumber(player.vitals and player.vitals.tp) or 0
		if tp < 1000 then
			return
		end
		local target = ctx.target
		if ctx.target_present ~= true or not target.valid_target
			or target.spawn_type ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
			return
		end
		local partner_target_set = build_partner_target_set(ctx.settings)
		if partner_target_set[tonumber(target.id) or 0] == true then
			return
		end
		local ws_selection, ws_pick_reason = select_ws_plan(ctx.settings, tonumber(target.id) or 0)
		if type(ws_selection) ~= 'table' then
			return
		end
		local ws = tostring(ws_selection.ws_name or '')
		if ws == '' then
			return
		end
		local required_tp = ws_selection.required_tp
		if type(required_tp) ~= 'number'
			or required_tp % 1 ~= 0
			or required_tp < 1000
			or required_tp > 3000 then
			error('combat WS selection required_tp must be an integer from 1000 to 3000')
		end
		if tp < required_tp then
			return
		end
		local skillchain_plan = ws_selection.skillchain_plan
		local urgency = (tp - 1000) / 2000
		if urgency < 0 then
			urgency = 0
		elseif urgency > 1 then
			urgency = 1
		end
		local priority_band = 70
		local reason_code = 'tp_ready'
		if type(skillchain_plan) == 'table' then
			priority_band = skillchain_priority
			reason_code = tostring(ws_pick_reason or '') == 'SC_NOT_READY'
				and 'skillchain_continuation_pending'
				or tostring(ws_pick_reason or '') == 'SC_DISPATCH_PENDING_RESULT'
				and 'skillchain_continuation_awaiting_result'
				or 'skillchain_continuation'
			local planned_at = tonumber(skillchain_plan.planned_at) or 0
			local earliest = tonumber(skillchain_plan.earliest_execute_at) or planned_at
			local latest = tonumber(skillchain_plan.latest_safe_at) or planned_at
			local width = math.max(0.1, latest - earliest)
			local remaining = math.max(0, latest - planned_at)
			urgency = clamp_urgency(1 - (remaining / width))
			if skillchain_plan.high_risk == true then
				urgency = 1
			end
			action_timeline_log('SC_CONTINUATION_PROPOSED', {
				target_id = tonumber(target.id) or 0,
				resonance_generation = tonumber(skillchain_plan.resonance_generation) or 0,
				ws_id = tonumber(skillchain_plan.ws_id) or 0,
				ws_name = ws,
				predicted_result = tostring(skillchain_plan.predicted_result or ''),
				band = priority_band,
				urgency = ('%.2f'):format(urgency),
				earliest_execute_at = tonumber(skillchain_plan.earliest_execute_at) or 0,
				preferred_execute_at = tonumber(skillchain_plan.preferred_execute_at) or 0,
				latest_safe_at = tonumber(skillchain_plan.latest_safe_at) or 0,
			}, nil, 0)
		elseif tostring(ws_pick_reason or '') == 'AM_READY' then
			priority_band = aftermath_priority
			reason_code = 'aftermath_ready'
			urgency = 1
		end
		out[#out + 1] = {
			proposal_id = ('combat.ws.%s.%d.%d'):format(ws, tonumber(target.id) or 0, math.floor(ctx.now * 1000)),
			family_id = type(skillchain_plan) == 'table' and 'combat.ws.skillchain' or 'combat.ws.primary',
			provider = 'combat',
			action_type = 'ws',
			action_name = ws,
			target_kind = 'mob',
			target_id = tonumber(target.id) or 0,
			target_name = tostring(target.name or ''),
			priority_band = priority_band,
			urgency = clamp_urgency(urgency),
			starvation_eligible = type(skillchain_plan) ~= 'table',
			created_at = ctx.now,
			expires_at = ctx.now + 0.30,
			commit_deadline = ctx.now + 0.20,
			movement_policy = 'requires_range',
			range_policy = { min = 0.0, max = 5.5, los_required = true },
			recast_key = ('ws:%s'):format(ws),
			duplicate_suppression_key = ('ws:%s:%d'):format(ws, tonumber(target.id) or 0),
			lock_class = 'offense_action',
			expected_ack = 'action_start',
			expected_effect = 'ws_effect',
			sticky = true,
			can_preempt_movement = false,
			can_preempt_same_band = false,
			reason_code = reason_code,
			required_tp = required_tp,
			skillchain_plan = skillchain_plan,
			smart_aoe_guard = ws_selection.smart_aoe_guard == true,
			detail = {
				tp = tp,
				ws_pick_reason = tostring(ws_pick_reason or ''),
				resonance_generation = tonumber(skillchain_plan and skillchain_plan.resonance_generation) or 0,
				predicted_result = tostring(skillchain_plan and skillchain_plan.predicted_result or ''),
				earliest_execute_at = tonumber(skillchain_plan and skillchain_plan.earliest_execute_at) or 0,
				preferred_execute_at = tonumber(skillchain_plan and skillchain_plan.preferred_execute_at) or 0,
				latest_safe_at = tonumber(skillchain_plan and skillchain_plan.latest_safe_at) or 0,
			},
			legacy_command = ('input /ws \"%s\" <t>'):format(ws),
			required_setting = 'weaponskill_active',
		}
	end

	function provider.sleep_target_eligible(ctx, mob, current_target_id, claims_set, partner_target_set)
		if not is_live_actionable_target(mob, ctx.now, true) then
			return false
		end
		local tid = tonumber(mob.id) or 0
		if tid <= 0 then
			return false
		end
		if current_target_id > 0 and tid == current_target_id then
			return false
		end
		if partner_target_set[tid] == true then
			return false
		end
		local claim_id = tonumber(mob.claim_id) or 0
		local friendly_claim = claims_set[claim_id] == true
		local unclaimed_friendly_aggressor = claim_id == 0
			and mob_targets_friendly_member(mob, claims_set, ctx.now)
		if not friendly_claim and not unclaimed_friendly_aggressor then
			return false
		end
		if tonumber(mob.status) ~= 1 then
			return false
		end
		if (tonumber(mob.hpp) or 0) <= 99 then
			return false
		end
		local dist = mob.distance and mob.distance:sqrt() or 999
		if dist > sleep_max_target_distance(ctx.settings) then
			return false
		end
		if target_sleep_suppressed(ctx.settings, tid, ctx.now) then
			return false
		end
		return true
	end

	function provider.collect_sleep(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		if not bool_setting(combat_domain_enabled(), false) then
			return
		end
		if not bool_setting(sleep_enabled(ctx.settings), false) then
			return
		end
		local configured_sleep_spells = sleep_spell_list(ctx.settings)
		if #configured_sleep_spells == 0 then
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true then
			return
		end
		local current_target = ctx.target_present == true and ctx.target or nil
		local current_target_id = 0
		if current_target and is_live_actionable_target(current_target, ctx.now, true) then
			current_target_id = tonumber(current_target.id) or 0
		end
		local _, claims_set = build_friendly_claims()
		local partner_target_set = build_partner_target_set(ctx.settings)
		local best = nil
		local marray = ctx.mob_array
		for _, mob in pairs(marray) do
			if provider.sleep_target_eligible(ctx, mob, current_target_id, claims_set, partner_target_set) then
				local spell_pick = select_sleep_spell(ctx.settings, mob)
				if spell_pick then
					local tid = tonumber(mob.id) or 0
					local dist = tonumber(spell_pick.dist) or 999
					if not best
						or dist < best.dist
						or (dist == best.dist and tid < best.target_id) then
						best = {
							target_id = tid,
							target_name = tostring(mob.name or ''),
							dist = dist,
							spell_name = tostring(spell_pick.name or ''),
							spell_index = tonumber(spell_pick.index) or 0,
							range_max = tonumber(spell_pick.range_max) or 0,
							target_hpp = tonumber(mob.hpp) or 0,
						}
					end
				end
			end
		end
		if not best then
			return
		end
		local urgency = 0.55
		if best.range_max > 0 then
			urgency = 1.0 - math.min(1.0, best.dist / best.range_max)
			if urgency < 0.55 then
				urgency = 0.55
			end
		end
		out[#out + 1] = {
			proposal_id = ('combat.sleep.%s.%d.%d'):format(
				tostring(best.spell_name),
				tonumber(best.target_id) or 0,
				math.floor(ctx.now * 1000)
			),
			family_id = 'combat.sleep.primary',
			provider = 'combat',
			action_type = 'spell',
			action_name = tostring(best.spell_name),
			target_kind = 'mob',
			target_id = tonumber(best.target_id) or 0,
			target_name = tostring(best.target_name or ''),
			priority_band = sleep_priority,
			urgency = clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.30,
			commit_deadline = ctx.now + 0.20,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = tonumber(best.range_max) or 0, los_required = true },
			recast_key = ('sleep:%s'):format(tostring(best.spell_name)),
			duplicate_suppression_key = ('sleep:%s:%d'):format(
				tostring(best.spell_name),
				tonumber(best.target_id) or 0
			),
			lock_class = 'offense_action',
			expected_ack = 'action_start',
			expected_effect = 'spell_effect',
			sticky = false,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = 'sleep_add_control',
			detail = {
				sleep_spell_index = tonumber(best.spell_index) or 0,
				sleep_target_distance = tonumber(best.dist) or 0,
				sleep_target_hpp = tonumber(best.target_hpp) or 0,
				sleep_configured_count = #configured_sleep_spells,
				allow_target_id_send = true,
			},
			legacy_command = ('input /ma \"%s\" %d'):format(
				tostring(best.spell_name),
				tonumber(best.target_id) or 0
			),
			required_setting = 'sleep',
		}
	end

	function provider.collect_engage(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		if not bool_setting(combat_domain_enabled(), false) then
			return
		end
		if not bool_setting(combat_autotarget(ctx.settings), false) then
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true then
			return
		end
		local tank_mode = bool_setting(tank_enabled(ctx.settings), false)
		local engage_priority = tank_mode and tank_engage_priority or default_engage_priority
		local engage_urgency = tank_mode and tank_engage_urgency or default_engage_urgency
		local engaged = tonumber(player.status) == 1
		local function engage_action_state_summary()
			local now_value = ctx.now
			local cooldown_until = tonumber(action_state.cooldown_until) or 0
			local post_spell_tail_until = tonumber(action_state.post_spell_tail_until) or 0
			local action_start = tonumber(action_state.action_start) or 0
			local action_end = tonumber(action_state.action_end) or 0
			local acting = action_end < action_start
			local parts = {
				('kind=%s'):format(tostring(action_state.last_send_kind or '')),
				('acting=%s'):format(acting and '1' or '0'),
				('cooldown=%.2f'):format(math.max(0, cooldown_until - now_value)),
				('tail=%.2f'):format(math.max(0, post_spell_tail_until - now_value)),
			}
			return table.concat(parts, ',')
		end
		local function engage_pending_state_summary()
			local pending = pending_engage_state(phase1)
			if type(pending) ~= 'table' then
				return 'inactive'
			end
			local retry_ready_at = tonumber(pending.retry_ready_at) or 0
			local retry_count = tonumber(pending.retry_count) or 0
			if pending_engage_live(phase1, ctx.now) then
				return ('active:retry=%.2f,count=%d'):format(math.max(0, retry_ready_at - ctx.now), retry_count)
			end
			return ('stale:count=%d'):format(retry_count)
		end
		local function existing_top_proposal_summary()
			local top = type(out) == 'table' and out[1] or nil
			if type(top) ~= 'table' then
				return '', '', ''
			end
			return tostring(top.family_id or ''), tostring(top.provider or ''), tostring(top.action_name or '')
		end
		local function log_engage_proposal_probe(event_code, target, skip_reason, pull_owner_state, claim_check)
			if not target or tonumber(player.status) == 1 then
				return
			end
			local dist = target.distance and target.distance:sqrt() or 999
			local top_family, top_provider, top_action = existing_top_proposal_summary()
			action_timeline_log(event_code, {
				tid = tonumber(target.id) or 0,
				name = tostring(target.name or ''),
				role = tank_mode and 'tank' or 'default',
				tank = tank_mode and 1 or 0,
				status = tonumber(player.status) or 0,
				pull_owner = tostring(pull_owner_state or ''),
				target_valid = target.valid_target == true and 1 or 0,
				range = ('%.2f'):format(tonumber(dist) or 999),
				claim_check = tostring(claim_check or ''),
				pending_engage = engage_pending_state_summary(),
				action_state = engage_action_state_summary(),
				top_family = top_family,
				top_provider = top_provider,
				top_action = top_action,
				reason = tostring(skip_reason or ''),
			}, ('engage_proposal_probe:%s:%d:%s'):format(
				tostring(event_code or ''),
				tonumber(target.id) or 0,
				tostring(skip_reason or '')
			), 0.50)
		end
		local fight_leader_force_target_id = 0
		local fight_leader_on = bool_setting(fight_leader_enabled(ctx.settings), false)
		local leader_id = fight_leader_id(ctx.settings)
		if fight_leader_on and leader_id > 0 then
			fight_leader_force_target_id = tonumber(fight_leader_target_id(leader_id)) or 0
		end
		if engaged and fight_leader_force_target_id <= 0 then
			return
		end
		if engaged and fight_leader_force_target_id > 0 then
			local current_target_id = tonumber(ctx.target_present == true and ctx.target and ctx.target.id) or 0
			if current_target_id == fight_leader_force_target_id then
				return
			end
		end
		local target = nil
		if fight_leader_force_target_id > 0 then
			target = ctx.mobs_by_id[fight_leader_force_target_id]
		end
		if not target then
			target = ctx.target_present == true and ctx.target or nil
		end
		if not target or not target.valid_target or tonumber(target.spawn_type) ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
			if debug_enabled(ctx.settings) then
				_G.UC_LAST_SCHED_ACTION = '[p1]engage:collect_skip:no_valid_target'
			end
			if target then
				log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED', target, 'no_valid_target', 'inactive', 'not_checked')
			end
			return
		end
		local pull_owner_state = 'inactive'
		local pull_pick = select_pull(ctx.settings)
		if type(pull_pick) == 'table' then
			local pull_tid = tonumber(pull_pick.target_id) or 0
			local this_tid = tonumber(target.id) or 0
			pull_owner_state = ('candidate:%s:%s:%d'):format(
				tostring(pull_pick.provider or ''),
				tostring(pull_pick.action_name or pull_pick.action_type or ''),
				pull_tid
			)
			if pull_tid > 0 and this_tid > 0 and pull_tid == this_tid then
				if debug_enabled(ctx.settings) then
					_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_skip:pull_owner tid=%d action=%s:%s'):format(
						this_tid,
						tostring(pull_pick.action_type or ''),
						tostring(pull_pick.action_name or '')
					)
				end
				log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED', target, 'pull_owner', pull_owner_state, 'not_checked')
				return
			end
		end
		local _, claims_set = build_friendly_claims()
		local claim_id = tonumber(target.claim_id) or 0
		local party_ids = build_party_id_set()
		local party_claimed_ok = claims_set[claim_id] == true
		local camp_pull_order = camp_pull_registry.combat_order(target, claims_set)
		local camp_pull_ok = camp_pull_order ~= nil
		local prime_unclaimed_ok = prime_unclaimed_party_aggressive_ok(ctx.settings, target, party_ids)
		local force_leader_engage = fight_leader_force_target_id > 0
			and fight_leader_force_target_id == (tonumber(target.id) or 0)
		local claim_check = ('party_claimed=%s,camp_pull=%s,prime_unclaimed=%s,force_leader=%s,claim_id=%d'):format(
			party_claimed_ok and '1' or '0',
			camp_pull_ok and tostring(camp_pull_order) or '0',
			prime_unclaimed_ok and '1' or '0',
			force_leader_engage and '1' or '0',
			claim_id
		)
		if not party_claimed_ok and not camp_pull_ok and not prime_unclaimed_ok and not force_leader_engage then
			if debug_enabled(ctx.settings) then
				_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_skip:policy claim=%d st=%d prime=%s'):format(
					claim_id,
					tonumber(target.status) or 0,
					tostring(bool_setting(combat_prime(ctx.settings), false))
				)
			end
			log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED', target, 'claim_policy', pull_owner_state, claim_check)
			return
		end
		if debug_enabled(ctx.settings) then
			if force_leader_engage then
				_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_emit_force_leader tid=%d name=%s'):format(
					tonumber(target.id) or 0,
					tostring(target.name or '')
				)
			else
				_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_emit tid=%d name=%s'):format(
					tonumber(target.id) or 0,
					tostring(target.name or '')
				)
			end
		end
		action_timeline_log('ENGAGE_PROPOSED', {
			tid = tonumber(target.id) or 0,
			name = tostring(target.name or ''),
			band = engage_priority,
			urgency = ('%.2f'):format(clamp_urgency(engage_urgency)),
		}, ('engage_proposed:%d'):format(tonumber(target.id) or 0), 0.50)
		log_engage_proposal_probe('ENGAGE_PROPOSAL_CREATED', target, 'engage_ready', pull_owner_state, claim_check)
		out[#out + 1] = {
			proposal_id = ('combat.engage.%d.%d'):format(tonumber(target.id) or 0, math.floor(ctx.now * 1000)),
			family_id = 'combat.engage.primary',
			provider = 'combat',
			action_type = 'engage',
			action_name = 'engage_target',
			target_kind = 'mob',
			target_id = tonumber(target.id) or 0,
			target_name = tostring(target.name or ''),
			priority_band = engage_priority,
			urgency = clamp_urgency(engage_urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.30,
			commit_deadline = ctx.now + 0.20,
			movement_policy = 'can_move',
			range_policy = { min = 0.0, max = 30.0, los_required = false },
			recast_key = 'engage:attack_on',
			duplicate_suppression_key = ('engage:%d'):format(tonumber(target.id) or 0),
			lock_class = 'offense_action',
			expected_ack = 'action_start',
			expected_effect = 'engage',
			sticky = true,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = 'engage_ready',
			detail = {},
			required_setting = 'autotarget',
		}
	end

	function provider.collect_ja(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		if not bool_setting(ctx.settings.ability_active, false) then
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true or tonumber(player.status) ~= 1 then
			return
		end
		local tank_mode = bool_setting(tank_enabled(ctx.settings), false)
		local ordered = collect_ordered_abilities(ctx.settings, 6)
		if #ordered == 0 then
			return
		end
		local target = ctx.target_present == true and ctx.target or nil
		local partner_target_set = build_partner_target_set(ctx.settings)
		for _, name in ipairs(ordered) do
			local ja = get_ja_resource(name)
			if ja then
				local ok_ready, reason, kind = action_ready(name, target and target.id or 0)
				if ok_ready and kind == 'ja' then
					local target_kind = 'self'
					local target_id = tonumber(player.id) or 0
					local target_name = tostring(player.name or '')
					local ja_targets = tostring(ja.targets or '')
					local ja_target_ok = true
					if ja_targets == '{Enemy}' then
						if not target or not target.valid_target or target.spawn_type ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
							ja_target_ok = false
						end
						if ja_target_ok and partner_target_set[tonumber(target.id) or 0] == true then
							ja_target_ok = false
						end
						if ja_target_ok then
							local range = action_effective_range(ja.range)
							if range > 0 then
								local dist = target.distance and target.distance:sqrt() or 999
								if dist > range then
									ja_target_ok = false
								end
							end
						end
						if ja_target_ok then
							target_kind = 'mob'
							target_id = tonumber(target.id) or 0
							target_name = tostring(target.name or '')
						end
					end
					if ja_target_ok then
						local priority_band = tank_mode and 99 or 70
						out[#out + 1] = {
							proposal_id = ('combat.ja.%s.%d.%d'):format(tostring(name), target_id, math.floor(ctx.now * 1000)),
							family_id = 'combat.ja.primary',
							provider = 'combat',
							action_type = 'ja',
							action_name = tostring(name),
							target_kind = target_kind,
							target_id = target_id,
							target_name = target_name,
							priority_band = priority_band,
							urgency = 0.35,
							starvation_eligible = true,
							created_at = ctx.now,
							expires_at = ctx.now + 0.30,
							commit_deadline = ctx.now + 0.20,
							movement_policy = 'must_stop',
							range_policy = { min = 0.0, max = 10.0, los_required = false },
							recast_key = ('ja:%s'):format(tostring(name)),
							duplicate_suppression_key = ('ja:%s:%d'):format(tostring(name), target_id),
							lock_class = 'offense_action',
							expected_ack = 'action_start',
							expected_effect = 'ja_effect',
							sticky = false,
							can_preempt_movement = true,
							can_preempt_same_band = false,
							reason_code = 'ability_ready',
							detail = {
								ability = tostring(name),
							},
							legacy_command = target_kind == 'self'
								and ('input /ja \"%s\" <me>'):format(tostring(name))
								or ('input /ja \"%s\" %d'):format(tostring(name), target_id),
							required_setting = 'ability_active',
						}
						break
					else
						log_ja_sched(('collect_skip name=\"%s\" reason=TARGET_INVALID status=%s target_id=%s'):format(
							tostring(name),
							tostring(player.status or ''),
							tostring(target and target.id or 0)
						))
					end
				elseif kind == 'ja' then
					log_ja_sched(('collect_skip name=\"%s\" reason=%s status=%s pending=%s'):format(
						tostring(name),
						tostring(reason or 'NOT_READY'),
						tostring(player.status or ''),
						tostring((phase1.pending and phase1.pending.action_name) or '')
					))
				end
			end
		end
	end

	return provider
end

return M
