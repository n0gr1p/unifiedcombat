local res = require('resources')
local uc_active_config = require('uc_active_config')
local encounter_state = require('uc_encounter_state')
local party_buff_tracker = require('uc_party_buff_tracker')

local M = {}

local last_snapshot_signature = ''

local RAW_ACTOR_NAMES = {
	Ghatjot = true,
	Dhartok = true,
}

local SORTIE_ZONE_NAME = "Outer Ra'Kaznar [U3]"

local function emit(event_code, fields, key, interval)
	local logger = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(logger) == 'function' then
		logger(event_code, fields, key, interval or 0)
	end
end

local function encounter_config()
	local config = uc_active_config.get_path('config.encounter')
	if config == nil then
		return { enabled = false, id = '' }
	end
	if type(config) ~= 'table' then
		error('config.encounter must be a table')
	end
	local out = {
		enabled = config.enabled == true,
		id = tostring(config.id or ''),
	}
	if config.policy ~= nil then
		if type(config.policy) ~= 'table' then
			error('config.encounter.policy must be a table')
		end
		out.policy = {
			water_damage = config.policy.water_damage,
			water_skillchain = config.policy.water_skillchain,
			repeat_action_wall = config.policy.repeat_action_wall,
		}
	end
	if config.tuning ~= nil then
		if type(config.tuning) ~= 'table' then
			error('config.encounter.tuning must be a table')
		end
		out.tuning = {
			repeat_action_guard_s = config.tuning.repeat_action_guard_s,
		}
	end
	return out
end

local function zone_name()
	local info = windower.ffxi.get_info()
	local zone_id = tonumber(info and info.zone)
	local zone = zone_id and res.zones and res.zones[zone_id] or nil
	return tostring(zone and zone.en or '')
end

local function encounter_actors()
	local actors = {}
	local mob_array = windower.ffxi.get_mob_array()
	if type(mob_array) ~= 'table' then
		return actors
	end
	for _, mob in pairs(mob_array) do
		local name = tostring(mob and mob.name or '')
		if name == 'Ghatjot' or name == 'Dhartok' then
			actors[#actors + 1] = {
				id = mob.id,
				name = name,
				x = mob.x,
				y = mob.y,
				z = mob.z,
				facing = mob.facing,
				hpp = mob.hpp,
				status = mob.status,
			}
		end
	end
	table.sort(actors, function(left, right)
		return (tonumber(left.id) or 0) < (tonumber(right.id) or 0)
	end)
	return actors
end

local function buff_names(buff_ids)
	local names = {}
	for i = 1, #(buff_ids or {}) do
		local buff_id = tonumber(buff_ids[i]) or 0
		local buff = buff_id > 0 and res.buffs and res.buffs[buff_id] or nil
		if buff and type(buff.en) == 'string' and buff.en ~= '' then
			names[#names + 1] = buff.en
		end
	end
	return names
end

local function observed_members()
	local members = {}
	local party = windower.ffxi.get_party()
	local player = windower.ffxi.get_player()
	local self_id = tonumber(player and player.id) or 0
	if type(party) ~= 'table' then
		return members
	end
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for i = 1, #keys do
		local entry = party[keys[i]]
		local mob = entry and entry.mob or nil
		local member_id = tonumber(mob and mob.id) or 0
		if member_id > 0 then
			local source = 'unavailable'
			local ids = nil
			if member_id == self_id then
				if type(player.buffs) == 'table' then
					source = 'local_player'
					ids = player.buffs
				end
			else
				local packet = party_buff_tracker.get(member_id)
				if type(packet) == 'table' and type(packet.buffs) == 'table' then
					source = 'party_packet_0x076'
					ids = packet.buffs
				end
			end
			members[#members + 1] = {
				id = member_id,
				name = tostring(mob.name or ''),
				source = source,
				buff_names = buff_names(ids),
			}
		end
	end
	return members
end

local function snapshot_signature(snapshot, reason)
	local boss = snapshot.boss or {}
	return table.concat({
		tostring(snapshot.enabled),
		tostring(snapshot.configured_id or ''),
		tostring(snapshot.resolved_id or ''),
		tostring(snapshot.phase or ''),
		tostring(snapshot.error or ''),
		tostring(boss.id or 0),
		tostring(reason or ''),
	}, ':')
end

function M.observe(now)
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('uc_encounter_runtime.observe requires now')
	end
	local configured, configure_reason = encounter_state.configure(encounter_config(), 'active_config_changed')
	if not configured then
		local snapshot = encounter_state.snapshot()
		local signature = snapshot_signature(snapshot, configure_reason)
		if signature ~= last_snapshot_signature then
			last_snapshot_signature = signature
			emit('ENCOUNTER_STATE', {
				configured_id = snapshot.configured_id,
				phase = snapshot.phase,
				reason = configure_reason,
			})
		end
		return false, configure_reason
	end
	if configure_reason == 'DISABLED' then
		return false, configure_reason
	end
	local ok, reason = encounter_state.observe_snapshot({
		now = observed_at,
		zone_name = zone_name(),
		actors = encounter_actors(),
		members = observed_members(),
	})
	local snapshot = encounter_state.snapshot()
	local signature = snapshot_signature(snapshot, reason)
	if signature ~= last_snapshot_signature then
		last_snapshot_signature = signature
		emit('ENCOUNTER_STATE', {
			configured_id = snapshot.configured_id,
			resolved_id = snapshot.resolved_id,
			phase = snapshot.phase,
			boss_id = snapshot.boss and snapshot.boss.id or 0,
			reason = reason,
		})
	end
	return ok, reason
end

local function ability_name_from_action(act, category)
	local ability_id = 0
	if category == 7 then
		local target = type(act.targets) == 'table' and act.targets[1] or nil
		local action = target and type(target.actions) == 'table' and target.actions[1] or nil
		ability_id = tonumber(action and action.param) or 0
	elseif category == 11 then
		ability_id = tonumber(act.param) or 0
	end
	local ability = ability_id > 0 and res.monster_abilities and res.monster_abilities[ability_id] or nil
	return tostring(ability and ability.en or ''), ability_id
end

local function authoritative_target(act)
	if type(act.targets) ~= 'table' or #act.targets ~= 1 then
		return 0, nil, type(act.targets) == 'table' and #act.targets or 0
	end
	local target_id = tonumber(act.targets[1] and act.targets[1].id) or 0
	if target_id <= 0 then
		return 0, nil, 1
	end
	local target = windower.ffxi.get_mob_by_id(target_id)
	if type(target) ~= 'table' or tonumber(target.x) == nil or tonumber(target.y) == nil then
		return target_id, nil, 1
	end
	return target_id, {
		x = tonumber(target.x),
		y = tonumber(target.y),
		z = tonumber(target.z),
	}, 1
end

local function raw_action_summary(target)
	local summaries = {}
	for i = 1, #(target.actions or {}) do
		local action = target.actions[i]
		local add_effect = type(action and action.add_effect) == 'table' and action.add_effect or nil
		summaries[#summaries + 1] = table.concat({
			'a' .. tostring(i),
			'message=' .. tostring(action and action.message or ''),
			'param=' .. tostring(action and action.param or ''),
			'reaction=' .. tostring(action and action.reaction or ''),
			'animation=' .. tostring(action and action.animation or ''),
			'effect=' .. tostring(action and action.effect or ''),
			'stagger=' .. tostring(action and action.stagger or ''),
			'add_message=' .. tostring(add_effect and add_effect.message or ''),
			'add_param=' .. tostring(add_effect and add_effect.param or ''),
		}, ',')
	end
	return table.concat(summaries, '/')
end

local function raw_target_summaries(act)
	local targets = {}
	local actions = {}
	for i = 1, #(act.targets or {}) do
		local target = act.targets[i]
		local target_id = tonumber(target and target.id) or 0
		local mob = target_id > 0 and windower.ffxi.get_mob_by_id(target_id) or nil
		local x = tonumber(mob and mob.x)
		local y = tonumber(mob and mob.y)
		local z = tonumber(mob and mob.z)
		targets[#targets + 1] = table.concat({
			't' .. tostring(i),
			'id=' .. tostring(target_id),
			'x=' .. tostring(x or ''),
			'y=' .. tostring(y or ''),
			'z=' .. tostring(z or ''),
		}, ',')
		actions[#actions + 1] = 't' .. tostring(i) .. '[' .. raw_action_summary(target or {}) .. ']'
	end
	return table.concat(targets, '/'), table.concat(actions, '/')
end

local function emit_raw_encounter_candidate(act, category, ability_name, ability_id, observed_at)
	if zone_name() ~= SORTIE_ZONE_NAME then
		return false
	end
	local actor_id = tonumber(act.actor_id) or 0
	local actor = actor_id > 0 and windower.ffxi.get_mob_by_id(actor_id) or nil
	local actor_name = tostring(actor and actor.name or '')
	if RAW_ACTOR_NAMES[actor_name] ~= true then
		return false
	end
	local targets_summary, actions_summary = raw_target_summaries(act)
	emit('ENCOUNTER_RAW_ABILITY_CANDIDATE', {
		actor_id = actor_id,
		actor_name = actor_name,
		category = category,
		phase = category == 7 and 'readied' or 'completed',
		ability_id = ability_id,
		ability_key = ability_name:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''),
		ability_name = ability_name,
		action_param = tonumber(act.param) or 0,
		target_count = type(act.targets) == 'table' and #act.targets or 0,
		targets_summary = targets_summary,
		actions_summary = actions_summary,
		observed_at = observed_at,
		zone_name = SORTIE_ZONE_NAME,
	})
	return true
end

function M.on_action(act, now)
	if type(act) ~= 'table' then
		error('uc_encounter_runtime.on_action requires act')
	end
	local category = tonumber(act.category) or 0
	if category ~= 7 and category ~= 11 then
		return false, 'ACTION_NOT_ENCOUNTER_ABILITY'
	end
	local ability_name, ability_id = ability_name_from_action(act, category)
	if ability_name == '' then
		return false, 'ABILITY_RESOURCE_UNRESOLVED'
	end
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('uc_encounter_runtime.on_action requires now')
	end
	emit_raw_encounter_candidate(act, category, ability_name, ability_id, observed_at)
	local target_id, target_position, target_count = authoritative_target(act)
	local ok, reason = encounter_state.observe_ability({
		actor_id = tonumber(act.actor_id) or 0,
		ability_name = ability_name,
		phase = category == 7 and 'readied' or 'completed',
		target_id = target_id,
		target_position = target_position,
		observed_at = observed_at,
	})
	if ok then
		emit('ENCOUNTER_ABILITY', {
			actor_id = tonumber(act.actor_id) or 0,
			ability_id = ability_id,
			ability_name = ability_name,
			phase = category == 7 and 'readied' or 'completed',
			target_id = target_id,
			target_count = target_count,
			target_x = target_position and target_position.x or '',
			target_y = target_position and target_position.y or '',
			target_z = target_position and target_position.z or '',
			reason = reason,
		})
	end
	return ok, reason
end

function M.observe_action_result(event)
	if type(event) ~= 'table' then
		error('uc_encounter_runtime.observe_action_result requires event')
	end
	local target_id = tonumber(event.target_id) or 0
	local target = target_id > 0 and windower.ffxi.get_mob_by_id(target_id) or nil
	local target_name = tostring(target and target.name or '')
	if zone_name() == SORTIE_ZONE_NAME and RAW_ACTOR_NAMES[target_name] == true then
		emit('ENCOUNTER_RAW_ACTION_RESULT_CANDIDATE', {
			action_class = tostring(event.action_class or ''),
			action_key = tostring(event.action_key or ''),
			action_name = tostring(event.action_name or ''),
			actor_id = tonumber(event.actor_id) or 0,
			target_id = target_id,
			target_name = target_name,
			observed_at = tonumber(event.observed_at),
			success = event.success == true,
		})
	end
	local ok, reason = encounter_state.observe_successful_action(event)
	if ok then
		emit('ENCOUNTER_ACTION_SUCCESS', {
			action_class = event.action_class,
			action_key = event.action_key,
			action_name = event.action_name,
			actor_id = event.actor_id,
			target_id = event.target_id,
			observed_at = event.observed_at,
		})
	end
	return ok, reason
end

function M.observe_boss_defeat(target_id)
	local ok, reason = encounter_state.observe_boss_defeat(target_id)
	if ok then
		emit('ENCOUNTER_BOSS_DEFEATED', {
			target_id = tonumber(target_id) or 0,
		})
	end
	return ok, reason
end

function M.validate_proposal(ctx, proposal)
	local ok, reason, policy_decision = require('uc_encounter_policy').validate(
		ctx,
		proposal,
		encounter_state.snapshot()
	)
	if type(policy_decision) == 'table' then
		encounter_state.record_policy_decision(policy_decision)
		local event_code = policy_decision.mode == 'enforce'
			and 'ENCOUNTER_POLICY_REJECT' or 'ENCOUNTER_POLICY_WARN'
		emit(event_code, policy_decision, table.concat({
			'encounter_policy',
			tostring(policy_decision.policy_id or ''),
			tostring(policy_decision.proposal_id or ''),
		}, ':'), 0.50)
	end
	return ok, reason
end

function M.reset(reason)
	last_snapshot_signature = ''
	encounter_state.reset(reason)
end

function M.snapshot()
	return encounter_state.snapshot()
end

local function point_text(point)
	if type(point) ~= 'table' then
		return 'unresolved'
	end
	local x = tonumber(point.x)
	local y = tonumber(point.y)
	if x == nil or y == nil then
		return 'unresolved'
	end
	local z = tonumber(point.z)
	if z == nil then
		return ('%.2f,%.2f,z-unresolved'):format(x, y)
	end
	return ('%.2f,%.2f,%.2f'):format(x, y, z)
end

function M.status_lines()
	local snapshot = encounter_state.snapshot()
	local boss = snapshot.boss or {}
	local last_ability = snapshot.last_ability or {}
	local cesspool = snapshot.cesspool or {}
	local policy_modes = snapshot.policy_modes or {}
	local policy_violation = snapshot.last_policy_violation or {}
	local policy_rejection = snapshot.last_policy_rejection or {}
	local lines = {
		('encounter enabled=%s configured=%s resolved=%s family=%s phase=%s error=%s'):format(
			tostring(snapshot.enabled == true),
			tostring(snapshot.configured_id or ''),
			tostring(snapshot.resolved_id or ''),
			tostring(snapshot.family or ''),
			tostring(snapshot.phase or ''),
			tostring(snapshot.error or '')
		),
		('boss name=%s id=%d hpp=%s status=%s origin=%s'):format(
			tostring(boss.name or ''),
			tonumber(boss.id) or 0,
			tostring(boss.hpp or ''),
			tostring(boss.status or ''),
			point_text(snapshot.origin)
		),
		('last_ability name=%s phase=%s target_id=%d observed_at=%s'):format(
			tostring(last_ability.name or ''),
			tostring(last_ability.phase or ''),
			tonumber(last_ability.target_id) or 0,
			tostring(last_ability.observed_at or '')
		),
		('origin_candidate=%s candidate_since=%s capture_stable_s=%.2f capture_tolerance=%.2f'):format(
			point_text(snapshot.origin_candidate),
			tostring(snapshot.origin_candidate_since or ''),
			encounter_state.ORIGIN_CAPTURE_STABLE_S,
			encounter_state.ORIGIN_CAPTURE_TOLERANCE
		),
		('policy water_damage=%s water_skillchain=%s repeat_action_wall=%s repeat_guard_s=%s'):format(
			tostring(policy_modes.water_damage or ''),
			tostring(policy_modes.water_skillchain or ''),
			tostring(policy_modes.repeat_action_wall or ''),
			tostring(snapshot.tuning and snapshot.tuning.repeat_action_guard_s or '')
		),
		('last_policy_violation id=%s mode=%s reason=%s action=%s target_id=%s at=%s'):format(
			tostring(policy_violation.policy_id or ''),
			tostring(policy_violation.mode or ''),
			tostring(policy_violation.reason or ''),
			tostring(policy_violation.action_name or ''),
			tostring(policy_violation.target_id or ''),
			tostring(policy_violation.observed_at or '')
		),
		('last_policy_rejection id=%s reason=%s action=%s target_id=%s at=%s'):format(
			tostring(policy_rejection.policy_id or ''),
			tostring(policy_rejection.reason or ''),
			tostring(policy_rejection.action_name or ''),
			tostring(policy_rejection.target_id or ''),
			tostring(policy_rejection.observed_at or '')
		),
		('cesspool active=%s observed_at=%s expires_at=%s pair_index=%d confidence=%s'):format(
			tostring(cesspool.active == true),
			tostring(cesspool.observed_at or ''),
			tostring(cesspool.expires_at or ''),
			tonumber(cesspool.pair_index) or 0,
			tostring(cesspool.sequence_confidence or '')
		),
		('repeat_action_observations=%d hazard_candidates=%d unresolved_hazards=%d last_hazard=%s'):format(
			(function()
				local count = 0
				for _ in pairs(snapshot.recent_repeat_actions or {}) do
					count = count + 1
				end
				return count
			end)(),
			#(snapshot.hazard_candidates or {}),
			tonumber(snapshot.unresolved_hazard_observations) or 0,
			tostring(snapshot.last_hazard_diagnostic or '')
		),
		('last_reset_reason=%s'):format(tostring(snapshot.last_reset_reason or '')),
	}
	for i = 1, #(snapshot.status_context or {}) do
		local member = snapshot.status_context[i]
		lines[#lines + 1] = ('status member=%s id=%d source=%s poison=%s taint=%s'):format(
			tostring(member.member_name or ''),
			tonumber(member.member_id) or 0,
			tostring(member.source or ''),
			tostring(member.poison == true),
			tostring(member.taint == true)
		)
	end
	local repeat_keys = {}
	for key in pairs(snapshot.recent_repeat_actions or {}) do
		repeat_keys[#repeat_keys + 1] = key
	end
	table.sort(repeat_keys)
	for i = 1, #repeat_keys do
		local action = snapshot.recent_repeat_actions[repeat_keys[i]]
		lines[#lines + 1] = ('repeat key=%s name=%s actor_id=%d target_id=%d observed_at=%s'):format(
			tostring(repeat_keys[i]),
			tostring(action.action_name or ''),
			tonumber(action.actor_id) or 0,
			tonumber(action.target_id) or 0,
			tostring(action.observed_at or '')
		)
	end
	for i = 1, #(snapshot.hazard_candidates or {}) do
		local candidate = snapshot.hazard_candidates[i]
		lines[#lines + 1] = ('hazard_candidate sequence=%d position=%s target_id=%d observed_at=%s source=%s'):format(
			tonumber(candidate.sequence) or 0,
			point_text(candidate),
			tonumber(candidate.target_id) or 0,
			tostring(candidate.observed_at or ''),
			tostring(candidate.source or '')
		)
	end
	return lines
end

return M
