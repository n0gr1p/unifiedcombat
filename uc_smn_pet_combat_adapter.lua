local capabilities = require('uc_smn_capabilities')
local runtime = require('uc_smn_runtime')
local pup_adapter_module = require('uc_pup_pet_combat_adapter')
local rage_gate = require('uc_reaction_smn_rage_gate')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_smn_pet_combat_adapter deps.%s must be a function'):format(name))
	end
	return value
end

local function timeline_log(event_code, fields, dedupe_key, interval)
	local logger = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(logger) == 'function' then
		pcall(logger, event_code, fields, dedupe_key, interval or 0)
	end
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local pup_adapter = pup_adapter_module.new(deps)
	local active_job_adapter = 'NONE'

	local adapter = {}

	local function emit_rage_check(ctx, action_name, eligible, reason, fields)
		local payload = {
			action = tostring(action_name or ''),
			eligible = eligible == true,
			reason = tostring(reason or ''),
			pet_id = tonumber(ctx.pet_id) or 0,
			target_id = tonumber(ctx.target_id) or tonumber(ctx.target and ctx.target.id) or 0,
			target_hpp = tonumber(ctx.target_hpp) or tonumber(ctx.target and ctx.target.hpp) or 0,
			pet_tp = tonumber(ctx.pet_tp) or 0,
			astral_conduit = type(ctx.player) == 'table'
				and type(ctx.player.buffs) == 'table'
				and runtime.has_buff(ctx.player, runtime.BUFF_ASTRAL_CONDUIT)
				or false,
		}
		for key, value in pairs(type(fields) == 'table' and fields or {}) do
			payload[key] = value
		end
		local key = ('smn_rage:%s:%s:%d'):format(
			tostring(action_name or ''),
			tostring(reason or ''),
			tonumber(payload.target_id) or 0
		)
		timeline_log('SMN_RAGE_CHECK', payload, key, 1.0)
	end

	function adapter.snapshot(ctx)
		require_table(ctx, 'ctx')
		if ctx.player_present == true and tostring(ctx.player.main_job or '') == 'PUP' then
			active_job_adapter = 'PUP'
			local snapshot = pup_adapter.snapshot(ctx)
			snapshot._job_adapter = 'PUP'
			return snapshot
		end
		if ctx.player_present ~= true or tostring(ctx.player.main_job or '') ~= 'SMN' then
			active_job_adapter = 'NONE'
			return {
				enabled = false,
				valid = false,
				correct_pet = false,
				_job_adapter = 'NONE',
			}
		end
		active_job_adapter = 'SMN'
		local config, validation = runtime.config_from_settings(ctx.settings)
		local snapshot = {
			enabled = false,
			valid = false,
			correct_pet = false,
			config = config,
			validation = validation,
			_job_adapter = 'SMN',
		}
		if config.enabled ~= true or validation.valid ~= true or validation.avatar_valid ~= true then
			return snapshot
		end
		snapshot.enabled = true
		snapshot.valid = true
		snapshot.avatar = capabilities.avatar(config.avatar)
		snapshot.correct_pet = ctx.pet_present == true and ctx.pet_name == snapshot.avatar.name
		if snapshot.correct_pet then
			snapshot.pet_id = ctx.pet_id
		end
		return snapshot
	end

	function adapter.maintenance(snapshot, ctx)
		if snapshot._job_adapter == 'PUP' then
			return pup_adapter.maintenance(snapshot, ctx)
		end
		return nil
	end

	function adapter.engagement(snapshot, ctx)
		if snapshot._job_adapter == 'PUP' then
			return pup_adapter.engagement(snapshot, ctx)
		end
		require_table(snapshot, 'Summoner pet combat snapshot')
		require_table(ctx, 'ctx')
		if snapshot.correct_pet ~= true or snapshot.config.pet_combat.engage_on_combat_start ~= true then
			return nil
		end
		local ready = runtime.recast_ready(ctx, runtime.RECAST_ASSAULT)
		if not ready then
			return nil
		end
		return {
			kind = 'assault',
			action_name = 'Assault',
			priority_band = runtime.PRIORITY_ASSAULT,
			urgency = 0.78,
			recast_id = runtime.RECAST_ASSAULT,
			retry_key = ('smn:assault:%d:%d'):format(ctx.combat_generation, snapshot.pet_id),
			command = {
				kind = 'assault',
				action_name = 'Assault',
				pet_id = snapshot.pet_id,
				target_id = ctx.target_id,
				combat_generation = ctx.combat_generation,
				retry_key = ('smn:assault:%d:%d'):format(ctx.combat_generation, snapshot.pet_id),
			},
		}
	end

	function adapter.offensive_action(snapshot, ctx)
		if snapshot._job_adapter == 'PUP' then
			return pup_adapter.offensive_action(snapshot, ctx)
		end
		require_table(snapshot, 'Summoner pet combat snapshot')
		require_table(ctx, 'ctx')
		local configured = snapshot.config.pet_combat.offensive_action
		if snapshot.correct_pet ~= true
			or configured.enabled ~= true
			or snapshot.validation.rage_valid ~= true
			or snapshot.validation.rage == nil then
			return nil
		end
		local rage = snapshot.validation.rage
		local held, hold_reason, hold = rage_gate.should_hold(ctx.target_id)
		if held == true then
			emit_rage_check(ctx, rage.name, false, hold_reason or 'reaction_pretrigger_hold', {
				reaction_rule_index = type(hold) == 'table' and hold.rule_index or nil,
				reaction_source_name = type(hold) == 'table' and hold.source_name or nil,
				reaction_action_type = type(hold) == 'table' and hold.action_type or nil,
				reaction_action_name = type(hold) == 'table' and hold.action_name or nil,
			})
			return nil
		end
		if configured.usage ~= 'on_cooldown' then
			error('unsupported Summoner offensive action usage: ' .. tostring(configured.usage))
		end
		if configured.target_hpp_above_enabled == true then
			local target_hpp = ctx.target_hpp
			local target_hpp_above = configured.target_hpp_above
			if type(target_hpp) ~= 'number' then
				error('Summoner Rage target HPP must be numeric when the target HPP gate is enabled')
			end
			if type(target_hpp_above) ~= 'number' then
				error('Summoner Rage target HPP threshold must be numeric when the target HPP gate is enabled')
			end
			if target_hpp <= target_hpp_above then
				emit_rage_check(ctx, rage.name, false, 'target_hpp_gate', {
					target_hpp_above = target_hpp_above,
				})
				return nil
			end
		end
		if configured.pet_tp_above_enabled == true then
			local pet_tp = ctx.pet_tp
			local pet_tp_above = configured.pet_tp_above
			if pet_tp == nil then
				emit_rage_check(ctx, rage.name, false, 'pet_tp_unavailable', {
					pet_tp_above = pet_tp_above,
				})
				return nil
			end
			if type(pet_tp_above) ~= 'number' then
				error('Summoner pet TP threshold must be numeric when the pet TP gate is enabled')
			end
			if pet_tp <= pet_tp_above then
				emit_rage_check(ctx, rage.name, false, 'pet_tp_gate', {
					pet_tp_above = pet_tp_above,
				})
				return nil
			end
		end
		local resource = get_ja_resource(rage.name)
		if resource == nil then
			error('Summoner Rage resource missing: ' .. rage.name)
		end
		local player_mp = runtime.player_mp(ctx.player)
		local mp_cost = tonumber(resource.mp_cost)
		if mp_cost == nil then
			error('Summoner Rage MP cost must be numeric')
		end
		local range = action_effective_range(resource.range)
		local distance, center_distance, pet_model_size, target_model_size = runtime.pet_distance(ctx.pet, ctx.target)
		local recast_value = type(ctx.ability_recasts) == 'table'
			and tonumber(ctx.ability_recasts[runtime.RECAST_RAGE]) or nil
		local diagnostic = {
			mp = player_mp,
			mp_cost = mp_cost,
			recast = recast_value,
			center_distance = center_distance,
			pet_model_size = pet_model_size,
			target_model_size = target_model_size,
			edge_distance = distance,
			range = range,
		}
		local ready, recast_reason = runtime.recast_ready(ctx, runtime.RECAST_RAGE)
		if not ready then
			emit_rage_check(ctx, rage.name, false, recast_reason, diagnostic)
			return nil
		end
		if player_mp < mp_cost then
			emit_rage_check(ctx, rage.name, false, 'insufficient_mp', diagnostic)
			return nil
		end
		if distance == nil then
			emit_rage_check(ctx, rage.name, false, 'distance_unavailable', diagnostic)
			return nil
		end
		if distance > range then
			emit_rage_check(ctx, rage.name, false, 'out_of_range', diagnostic)
			return nil
		end
		emit_rage_check(ctx, rage.name, true, 'eligible', diagnostic)
		return {
			action_name = rage.name,
			priority_band = runtime.PRIORITY_RAGE,
			urgency = 0.70,
			action_id = rage.id,
			recast_id = runtime.RECAST_RAGE,
			range = range,
			distance = distance,
			retry_key = ('smn:rage:%s'):format(rage.name),
			command = {
				kind = 'rage',
				action_name = rage.name,
				action_id = rage.id,
				recast_id = runtime.RECAST_RAGE,
				recast_before = ctx.ability_recasts[runtime.RECAST_RAGE],
				pet_id = snapshot.pet_id,
				target_id = ctx.target_id,
				combat_generation = ctx.combat_generation,
				retry_key = ('smn:rage:%s'):format(rage.name),
			},
		}
	end

	function adapter.revalidate(snapshot, selected, ctx)
		if snapshot._job_adapter == 'PUP' then
			return pup_adapter.revalidate(snapshot, selected, ctx)
		end
		require_table(snapshot, 'Summoner pet combat snapshot')
		require_table(selected, 'selected')
		require_table(ctx, 'ctx')
		if snapshot.correct_pet ~= true then
			return false, 'avatar_mismatch'
		end
		local detail = require_table(selected.detail, 'selected.detail')
		local command = require_table(detail.pet_command, 'selected.detail.pet_command')
		if ctx.pet_id ~= command.pet_id then
			return false, 'stale_pet'
		end
		if ctx.combat_generation ~= command.combat_generation
			or ctx.target_id ~= command.target_id
			or ctx.target_valid ~= true
			or ctx.target_hpp <= 0 then
			return false, 'stale_target'
		end
		if command.kind == 'rage' then
			local current = adapter.offensive_action(snapshot, ctx)
			if current == nil or current.action_name ~= command.action_name then
				return false, 'rage_not_executable'
			end
		elseif command.kind == 'assault' then
			if adapter.engagement(snapshot, ctx) == nil then
				return false, 'assault_not_executable'
			end
		else
			return false, 'unsupported_pet_combat_command'
		end
		return true, ''
	end

	function adapter.observe_action(act, observed_at)
		if active_job_adapter ~= 'PUP' then
			return false
		end
		return pup_adapter.observe_action(act, observed_at)
	end

	function adapter.observe_coordinator_event(event)
		if active_job_adapter == 'PUP' then
			pup_adapter.observe_coordinator_event(event)
		end
	end

	return adapter
end

return M
