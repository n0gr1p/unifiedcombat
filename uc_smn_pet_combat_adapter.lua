local capabilities = require('uc_smn_capabilities')
local runtime = require('uc_smn_runtime')

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

function M.new(deps)
	deps = require_table(deps, 'deps')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local action_effective_range = require_function(deps, 'action_effective_range')

	local adapter = {}

	function adapter.snapshot(ctx)
		require_table(ctx, 'ctx')
		if ctx.player_present ~= true or tostring(ctx.player.main_job or '') ~= 'SMN' then
			return {
				enabled = false,
				valid = false,
				correct_pet = false,
			}
		end
		local config, validation = runtime.config_from_settings(ctx.settings)
		local snapshot = {
			enabled = false,
			valid = false,
			correct_pet = false,
			config = config,
			validation = validation,
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

	function adapter.engagement(snapshot, ctx)
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
		require_table(snapshot, 'Summoner pet combat snapshot')
		require_table(ctx, 'ctx')
		local configured = snapshot.config.pet_combat.offensive_action
		if snapshot.correct_pet ~= true
			or configured.enabled ~= true
			or snapshot.validation.rage_valid ~= true
			or snapshot.validation.rage == nil then
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
				return nil
			end
		end
		if configured.pet_tp_above_enabled == true then
			local pet_tp = ctx.pet_tp
			local pet_tp_above = configured.pet_tp_above
			if pet_tp == nil then
				return nil
			end
			if type(pet_tp_above) ~= 'number' then
				error('Summoner pet TP threshold must be numeric when the pet TP gate is enabled')
			end
			if pet_tp <= pet_tp_above then
				return nil
			end
		end
		local ready = runtime.recast_ready(ctx, runtime.RECAST_RAGE)
		if not ready then
			return nil
		end
		local rage = snapshot.validation.rage
		local resource = get_ja_resource(rage.name)
		if resource == nil then
			error('Summoner Rage resource missing: ' .. rage.name)
		end
		local player_mp = runtime.player_mp(ctx.player)
		local mp_cost = tonumber(resource.mp_cost)
		if mp_cost == nil then
			error('Summoner Rage MP cost must be numeric')
		end
		if player_mp < mp_cost then
			return nil
		end
		local range = action_effective_range(resource.range)
		local distance = runtime.pet_distance(ctx.pet, ctx.target)
		if distance == nil or distance > range then
			return nil
		end
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

	return adapter
end

return M
