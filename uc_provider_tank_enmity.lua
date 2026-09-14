local res = require('resources')
local scheduler_config = require('uc_scheduler_config')
local pet_enmity = require('uc_tank_pet_enmity')

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

local function resource_by_name(collection, name)
	if type(collection) ~= 'table' then return nil end
	if type(collection.with) == 'function' then
		local ok, value = pcall(collection.with, collection, 'en', name)
		if ok and type(value) == 'table' then return value end
	end
	for _, value in pairs(collection) do
		if type(value) == 'table' and tostring(value.en or '') == name then return value end
	end
	return nil
end

local function configured_enmity_actions(settings)
	local source = scheduler_config.tank_enmity_actions(settings)
	if type(source) == 'string' then
		local parsed = {}
		for token in source:gmatch('[^|]+') do parsed[#parsed + 1] = token end
		source = parsed
	end
	if type(source) ~= 'table' then return {} end
	local actions = {}
	for i = 1, #source do
		local entry = source[i]
		local name = type(entry) == 'table'
			and tostring(entry.name or entry.entry or entry.raw or '')
			or tostring(entry or '')
		local _, explicit_name = name:match('^(%a+)%s*:%s*(.+)$')
		if explicit_name ~= nil then name = explicit_name end
		name = name:match('^%s*(.-)%s*$') or ''
		if name ~= '' then actions[#actions + 1] = name end
	end
	return actions
end

local function action_range(action_name, kind, action_effective_range)
	local resource = kind == 'spell'
		and resource_by_name(res.spells, action_name)
		or resource_by_name(res.job_abilities, action_name)
	local range = action_effective_range(resource and resource.range or 0)
	if not range or range <= 0 then return 20.0 end
	return range
end

local function pet_pick(settings, player, action_ready, action_effective_range)
	if scheduler_config.tank_enmity_include_pets(settings) ~= true then return nil end
	local violation = pet_enmity.find_violation(settings, player)
	if type(violation) ~= 'table' or type(violation.mob) ~= 'table' then return nil end
	local target_id = tonumber(violation.mob.id) or 0
	if target_id <= 0 then return nil end
	for _, action_name in ipairs(configured_enmity_actions(settings)) do
		local ready, _, kind = action_ready(action_name, target_id)
		kind = tostring(kind or ''):lower()
		if ready == true and (kind == 'ja' or kind == 'spell') then
			return {
				kind = kind,
				name = action_name,
				target_id = target_id,
				target_name = tostring(violation.mob.name or ''),
				victim_id = tonumber(violation.victim_id) or 0,
				victim_name = tostring(violation.victim_name or ''),
				victim_hpp = tonumber(violation.victim_hpp) or 100,
				victim_kind = 'pet',
				owner_id = tonumber(violation.owner_id) or 0,
				owner_name = tostring(violation.owner_name or ''),
				mob_hpp = tonumber(violation.mob_hpp) or 0,
				dist = tonumber(violation.dist) or 0,
				action_range = action_range(action_name, kind, action_effective_range),
				reason = 'PET_ENMITY_READY',
			}
		end
	end
	return nil
end

local function prefer_pet_pick(pet, player_pick)
	if type(pet) ~= 'table' then return player_pick end
	if type(player_pick) ~= 'table' then return pet end
	local pet_hpp = tonumber(pet.victim_hpp) or 100
	local player_hpp = tonumber(player_pick.victim_hpp) or 100
	if pet_hpp ~= player_hpp then return pet_hpp < player_hpp and pet or player_pick end
	local pet_dist = tonumber(pet.dist) or math.huge
	local player_dist = tonumber(player_pick.dist) or math.huge
	if pet_dist ~= player_dist then return pet_dist < player_dist and pet or player_pick end
	local pet_mob_hpp = tonumber(pet.mob_hpp) or 0
	local player_mob_hpp = tonumber(player_pick.mob_hpp) or 0
	if pet_mob_hpp ~= player_mob_hpp then return pet_mob_hpp > player_mob_hpp and pet or player_pick end
	return (tonumber(pet.target_id) or math.huge) < (tonumber(player_pick.target_id) or math.huge) and pet or player_pick
end

local function emit_pet_violation(pick, action_name, kind, log_tank_sched)
	if tostring(pick.victim_kind or '') ~= 'pet' then return end
	log_tank_sched(('pet_enmity_violation mob="%s" victim="%s" victim_id=%d owner="%s" owner_id=%d recovery="%s" kind=%s'):format(
		tostring(pick.target_name or ''),
		tostring(pick.victim_name or ''),
		tonumber(pick.victim_id) or 0,
		tostring(pick.owner_name or ''),
		tonumber(pick.owner_id) or 0,
		tostring(action_name or ''),
		tostring(kind or '')
	))
	local timeline = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(timeline) == 'function' then
		pcall(timeline, 'TANK_ENMITY_VIOLATION', {
			mob = tostring(pick.target_name or ''),
			mob_id = tonumber(pick.target_id) or 0,
			victim = tostring(pick.victim_name or ''),
			victim_id = tonumber(pick.victim_id) or 0,
			victim_kind = 'pet',
			owner = tostring(pick.owner_name or ''),
			owner_id = tonumber(pick.owner_id) or 0,
			recovery = tostring(action_name or ''),
			action_type = tostring(kind or ''),
		}, ('tank_pet_enmity:%d:%d'):format(tonumber(pick.target_id) or 0, tonumber(pick.victim_id) or 0), 0.5)
	end
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
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then return end
		local player = ctx.player
		if ctx.player_present ~= true then return end
		run_provider.collect(ctx, out)
		local engaged = tonumber(player.status) == 1
		local allow_unengaged = bool_setting(ctx.settings.ability_allow_unengaged, false)
		if not engaged and not allow_unengaged then return end
		local pick = prefer_pet_pick(
			pet_pick(ctx.settings, player, action_ready, action_effective_range),
			select_tank_enmity(ctx.settings)
		)
		if type(pick) ~= 'table' then return end
		local kind = tostring(pick.kind or ''):lower()
		if kind ~= 'ja' and kind ~= 'spell' then return end
		local action_name = tostring(pick.name or '')
		local target_id = tonumber(pick.target_id) or 0
		if action_name == '' or target_id <= 0 then return end
		if not engaged then
			local mobs_by_id = type(ctx.mobs_by_id) == 'table' and ctx.mobs_by_id or {}
			if not valid_enemy_target(mobs_by_id[target_id]) then
				log_tank_sched(('collect_skip action="%s" kind=%s reason=UNENGAGED_TARGET_INVALID target_id=%d'):format(
					tostring(action_name), tostring(kind), target_id))
				return
			end
		end
		local ready_ok, ready_reason, ready_kind = action_ready(action_name, target_id)
		if not ready_ok then
			log_tank_sched(('collect_skip action="%s" kind=%s reason=%s target_id=%d'):format(
				tostring(action_name), tostring(kind), tostring(ready_reason or 'NOT_READY'), target_id))
			return
		end
		if tostring(ready_kind or '') ~= kind then
			log_tank_sched(('collect_skip action="%s" kind=%s reason=KIND_MISMATCH resolved=%s target_id=%d'):format(
				tostring(action_name), tostring(kind), tostring(ready_kind or ''), target_id))
			return
		end
		emit_pet_violation(pick, action_name, kind, log_tank_sched)
		local prio = 99
		local urgency = 0.85
		local victim_hpp = tonumber(pick.victim_hpp) or 0
		if victim_hpp > 0 then
			urgency = clamp_urgency(1.0 - (math.min(victim_hpp, 100) / 100.0))
			if urgency < 0.60 then urgency = 0.60 end
		end
		local action_range_value = tonumber(pick.action_range)
		if not action_range_value or action_range_value <= 0 then action_range_value = 20.0 end
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
			range_policy = { min = 0.0, max = math.max(1.0, action_range_value), los_required = false },
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
				victim_id = tonumber(pick.victim_id) or 0,
				victim_name = tostring(pick.victim_name or ''),
				victim_hpp = tonumber(pick.victim_hpp) or 0,
				victim_kind = tostring(pick.victim_kind or 'player'),
				owner_id = tonumber(pick.owner_id) or 0,
				owner_name = tostring(pick.owner_name or ''),
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
