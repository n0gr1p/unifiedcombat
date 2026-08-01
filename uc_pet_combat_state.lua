local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

function M.new()
	return {
		generation = 0,
		active = false,
		target_id = 0,
		satisfied_engagements = {},
		current_pet_id = 0,
		observed_pet_id = 0,
		observed_pet_target_id = 0,
		observed_pet_target_at = 0,
	}
end

function M.reset(state)
	state = require_table(state, 'pet combat state')
	state.generation = 0
	state.active = false
	state.target_id = 0
	state.satisfied_engagements = {}
	state.current_pet_id = 0
	state.observed_pet_id = 0
	state.observed_pet_target_id = 0
	state.observed_pet_target_at = 0
end

function M.observe_target(state, target_valid, target_id)
	state = require_table(state, 'pet combat state')
	target_id = tonumber(target_id)
	if target_valid == true then
		if target_id == nil or target_id <= 0 then
			error('valid pet combat target requires a positive target id')
		end
		if state.active ~= true or state.target_id ~= target_id then
			state.generation = state.generation + 1
			state.active = true
			state.target_id = target_id
		end
	else
		state.active = false
	end
	return state.generation
end

function M.engagement_key(generation, pet_id)
	generation = tonumber(generation)
	pet_id = tonumber(pet_id)
	if generation == nil or generation <= 0 or generation ~= math.floor(generation) then
		error('pet combat generation must be a positive integer')
	end
	if pet_id == nil or pet_id <= 0 or pet_id ~= math.floor(pet_id) then
		error('pet server id must be a positive integer')
	end
	return ('%d:%d'):format(generation, pet_id)
end

function M.mark_engaged(state, generation, pet_id)
	state = require_table(state, 'pet combat state')
	local key = M.engagement_key(generation, pet_id)
	state.satisfied_engagements[key] = true
	return key
end

function M.is_engaged(state, generation, pet_id)
	state = require_table(state, 'pet combat state')
	return state.satisfied_engagements[M.engagement_key(generation, pet_id)] == true
end

function M.observe_pet_state(state, pet_present, pet_id, pet_status)
	state = require_table(state, 'pet combat state')
	pet_id = tonumber(pet_id)
	pet_status = tonumber(pet_status)
	if pet_id == nil or pet_id < 0 or pet_id ~= math.floor(pet_id) then
		error('observed pet server id must be a non-negative integer')
	end
	if pet_status == nil then
		error('observed pet status must be numeric')
	end
	if pet_present ~= true or pet_id == 0 then
		state.current_pet_id = 0
		state.observed_pet_id = 0
		state.observed_pet_target_id = 0
		state.observed_pet_target_at = 0
		return
	end
	if state.current_pet_id ~= pet_id or pet_status ~= 1 then
		state.observed_pet_id = 0
		state.observed_pet_target_id = 0
		state.observed_pet_target_at = 0
	end
	state.current_pet_id = pet_id
end

function M.current_pet_id(state)
	state = require_table(state, 'pet combat state')
	return state.current_pet_id
end

function M.observe_pet_melee_target(state, pet_id, target_id, observed_at)
	state = require_table(state, 'pet combat state')
	pet_id = tonumber(pet_id)
	target_id = tonumber(target_id)
	observed_at = tonumber(observed_at)
	if pet_id == nil or pet_id <= 0 or pet_id ~= math.floor(pet_id) then
		error('observed pet server id must be a positive integer')
	end
	if target_id == nil or target_id <= 0 or target_id ~= math.floor(target_id) then
		error('observed pet target server id must be a positive integer')
	end
	if observed_at == nil or observed_at < 0 then
		error('observed pet target time must be a non-negative number')
	end
	state.observed_pet_id = pet_id
	state.observed_pet_target_id = target_id
	state.observed_pet_target_at = observed_at
end

function M.observed_pet_target(state, pet_id)
	state = require_table(state, 'pet combat state')
	pet_id = tonumber(pet_id)
	if pet_id == nil or pet_id <= 0 or pet_id ~= math.floor(pet_id) then
		error('pet server id must be a positive integer')
	end
	if state.observed_pet_id ~= pet_id then
		return 0, 0
	end
	return state.observed_pet_target_id, state.observed_pet_target_at
end

return M
