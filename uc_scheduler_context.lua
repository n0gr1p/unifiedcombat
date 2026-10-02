local M = {}

local pet_target_diagnostic = {}

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_scheduler_context requires function dependency: ' .. tostring(name))
	end
	return fn
end

local function reset_pet_target_diagnostic(active)
	pet_target_diagnostic = {
		active = active == true,
		samples = 0,
		pet_present_samples = 0,
		pet_engaged_samples = 0,
		nonzero_target_index_samples = 0,
		resolved_target_id_samples = 0,
		matching_current_target_samples = 0,
		engaged_without_target_index_samples = 0,
		engaged_without_target_id_samples = 0,
		transitions = 0,
		last_signature = '',
		current_at = 0,
		current_pet_id = 0,
		current_pet_name = '',
		current_pet_status = -1,
		current_pet_target_index = 0,
		current_pet_target_id = 0,
		current_target_index = 0,
		current_target_id = 0,
		current_matches_target = false,
	}
end

local function copy_pet_target_diagnostic()
	local copy = {}
	for key, value in pairs(pet_target_diagnostic) do
		copy[key] = value
	end
	return copy
end

local function observe_pet_target_diagnostic(ctx)
	if pet_target_diagnostic.active ~= true then
		return
	end
	pet_target_diagnostic.samples = pet_target_diagnostic.samples + 1
	if ctx.pet_present == true then
		pet_target_diagnostic.pet_present_samples = pet_target_diagnostic.pet_present_samples + 1
	end
	if ctx.pet_status == 1 then
		pet_target_diagnostic.pet_engaged_samples = pet_target_diagnostic.pet_engaged_samples + 1
	end
	if ctx.pet_target_index > 0 then
		pet_target_diagnostic.nonzero_target_index_samples =
			pet_target_diagnostic.nonzero_target_index_samples + 1
	end
	if ctx.pet_target_id > 0 then
		pet_target_diagnostic.resolved_target_id_samples =
			pet_target_diagnostic.resolved_target_id_samples + 1
	end
	if ctx.pet_target_matches_current == true then
		pet_target_diagnostic.matching_current_target_samples =
			pet_target_diagnostic.matching_current_target_samples + 1
	end
	if ctx.pet_status == 1 and ctx.pet_target_index == 0 then
		pet_target_diagnostic.engaged_without_target_index_samples =
			pet_target_diagnostic.engaged_without_target_index_samples + 1
	end
	if ctx.pet_status == 1 and ctx.pet_target_id == 0 then
		pet_target_diagnostic.engaged_without_target_id_samples =
			pet_target_diagnostic.engaged_without_target_id_samples + 1
	end
	pet_target_diagnostic.current_at = ctx.now
	pet_target_diagnostic.current_pet_id = ctx.pet_id
	pet_target_diagnostic.current_pet_name = ctx.pet_name
	pet_target_diagnostic.current_pet_status = ctx.pet_status
	pet_target_diagnostic.current_pet_target_index = ctx.pet_target_index
	pet_target_diagnostic.current_pet_target_id = ctx.pet_target_id
	pet_target_diagnostic.current_target_index = ctx.target_index
	pet_target_diagnostic.current_target_id = ctx.target_id_snapshot
	pet_target_diagnostic.current_matches_target = ctx.pet_target_matches_current
	local signature = table.concat({
		tostring(ctx.pet_id),
		tostring(ctx.pet_status),
		tostring(ctx.pet_target_index),
		tostring(ctx.pet_target_id),
		tostring(ctx.target_index),
		tostring(ctx.target_id_snapshot),
		tostring(ctx.pet_target_matches_current),
	}, ':')
	if signature ~= pet_target_diagnostic.last_signature then
		pet_target_diagnostic.transitions = pet_target_diagnostic.transitions + 1
		pet_target_diagnostic.last_signature = signature
	end
end

function M.start_pet_target_diagnostic()
	reset_pet_target_diagnostic(true)
	return copy_pet_target_diagnostic()
end

function M.stop_pet_target_diagnostic()
	pet_target_diagnostic.active = false
	return copy_pet_target_diagnostic()
end

function M.pet_target_diagnostic_status()
	return copy_pet_target_diagnostic()
end

function M.build(settings, phase1, deps)
	if type(phase1) ~= 'table' then
		error('uc_scheduler_context requires phase1 state')
	end
	local get_player = require_function(deps, 'get_player')
	local get_mob_by_target = require_function(deps, 'get_mob_by_target')
	local get_mob_by_index = require_function(deps, 'get_mob_by_index')
	local get_party = require_function(deps, 'get_party')
	local get_mob_array = require_function(deps, 'get_mob_array')
	local get_config = require_function(deps, 'get_config')
	local now = require_function(deps, 'now')

	local raw_config = get_config()
	local config = type(raw_config) == 'table' and raw_config or {}
	local raw_player = get_player()
	local raw_me = get_mob_by_target('me')
	local raw_target = get_mob_by_target('t')
	local raw_pet = get_mob_by_target('pet')
	local raw_party = get_party()
	local raw_mob_array = get_mob_array()
	local player = raw_player or {}
	local me = raw_me or {}
	local target = raw_target or {}
	local pet = raw_pet or {}
	local party = raw_party or {}
	local mob_array = raw_mob_array or {}
	local mobs_by_id = {}
	local mobs_by_index = {}
	for _, mob in pairs(mob_array) do
		local mob_id = tonumber(mob and mob.id) or 0
		if mob_id > 0 then
			mobs_by_id[mob_id] = mob
		end
		local mob_index = tonumber(mob and mob.index) or 0
		if mob_index > 0 then
			mobs_by_index[mob_index] = mob
		end
	end
	if tonumber(target.id) and tonumber(target.id) > 0 then
		mobs_by_id[tonumber(target.id)] = target
	end
	if tonumber(target.index) and tonumber(target.index) > 0 then
		mobs_by_index[tonumber(target.index)] = target
	end
	if tonumber(me.id) and tonumber(me.id) > 0 then
		mobs_by_id[tonumber(me.id)] = me
	end
	if tonumber(me.index) and tonumber(me.index) > 0 then
		mobs_by_index[tonumber(me.index)] = me
	end
	if tonumber(pet.id) and tonumber(pet.id) > 0 then
		mobs_by_id[tonumber(pet.id)] = pet
	end
	if tonumber(pet.index) and tonumber(pet.index) > 0 then
		mobs_by_index[tonumber(pet.index)] = pet
	end
	local pet_target_index = tonumber(pet.target_index) or 0
	local target_index = tonumber(target.index) or 0
	local pet_target = nil
	if pet_target_index > 0 then
		pet_target = get_mob_by_index(pet_target_index)
	end
	local pet_status = tonumber(pet.status)
	if pet_status == nil then
		pet_status = -1
	end

	phase1.tick = (tonumber(phase1.tick) or 0) + 1
	local ctx = {
		now = now(),
		tick = phase1.tick,
		config = config,
		settings = settings or {},
		player = player,
		player_present = raw_player ~= nil,
		me = me,
		me_present = raw_me ~= nil,
		target = target,
		target_present = raw_target ~= nil,
		pet = pet,
		pet_present = raw_pet ~= nil and (tonumber(pet.id) or 0) > 0,
		party = party,
		mob_array = mob_array,
		mobs_by_id = mobs_by_id,
		mobs_by_index = mobs_by_index,
		player_status = tonumber(player.status) or -1,
		player_id = tonumber(player.id) or 0,
		player_name = tostring(player.name or ''),
		me_id = tonumber(me.id) or 0,
		me_name = tostring(me.name or ''),
		pet_id = tonumber(pet.id) or 0,
		pet_index = tonumber(pet.index) or 0,
		pet_name = tostring(pet.name or ''),
		pet_status = pet_status,
		pet_target_index = pet_target_index,
		pet_target_id = tonumber(pet_target and pet_target.id) or 0,
		target_index = target_index,
		target_id_snapshot = tonumber(target.id) or 0,
		pet_target_matches_current = pet_target_index > 0
			and target_index > 0
			and pet_target_index == target_index,
	}
	observe_pet_target_diagnostic(ctx)
	return ctx
end

reset_pet_target_diagnostic(false)

return M
