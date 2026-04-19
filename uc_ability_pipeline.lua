local M = {}

function M.collect_ordered(settings, slots_count)
	local out = {}
	local seen = {}
	if type(settings) ~= 'table' then
		return out
	end
	if type(settings.abilities) == 'table' then
		for _, ability in ipairs(settings.abilities) do
			if ability and ability ~= '' and not seen[ability] then
				seen[ability] = true
				out[#out + 1] = ability
			end
		end
	end
	if #out == 0 then
		local n = tonumber(slots_count) or 6
		for i = 1, n do
			local key = 'ability' .. tostring(i)
			local ability = settings[key]
			if ability and ability ~= '' and not seen[ability] then
				seen[ability] = true
				out[#out + 1] = ability
			end
		end
	end
	return out
end

local function player_has_buff(buff_id, buffs)
	if type(buff_id) ~= 'number' or type(buffs) ~= 'table' then
		return false
	end
	if table.contains then
		return table.contains(buffs, buff_id)
	end
	for _, b in ipairs(buffs) do
		if b == buff_id then
			return true
		end
	end
	return false
end

function M.execute_ordered_abilities(args)
	local settings = args and args.settings or {}
	local ability_active = args and args.ability_active
	if ability_active ~= true then
		return 0
	end
	local can_cast = args and args.can_cast_fn
	local cast = args and args.cast_fn
	if type(can_cast) ~= 'function' or type(cast) ~= 'function' then
		return 0
	end
	local abilities = (args and args.abilities) or M.collect_ordered(settings, args and args.slots_count)
	local job_abilities = args and args.job_abilities
	local skip_custom = args and args.skip_fn
	local player_buffs = (args and args.player_buffs) or {}
	local sent = 0
	for _, ability in ipairs(abilities) do
		local skip = false
		if type(skip_custom) == 'function' then
			skip = skip_custom(ability) == true
		end
		if not skip and type(job_abilities) == 'table' and type(ability) == 'string' and ability ~= '' and type(job_abilities.with) == 'function' then
			local ja = job_abilities:with('en', ability)
			local status = ja and ja.status or nil
			if player_has_buff(status, player_buffs) then
				skip = true
			end
		end
		if not skip and can_cast(ability) then
			cast(ability)
			sent = sent + 1
		end
	end
	return sent
end

return M
