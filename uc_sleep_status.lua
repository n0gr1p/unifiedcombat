local M = {}

M.effect_ids = {
	[2] = true,
	[19] = true,
}

function M.validate_resources(resources_buffs)
	if type(resources_buffs) ~= 'table' then
		error('sleep status validation requires buff resources')
	end
	for effect_id in pairs(M.effect_ids) do
		local resource = resources_buffs[effect_id]
		if type(resource) ~= 'table' or tostring(resource.en or ''):lower() ~= 'sleep' then
			error(('sleep status resource mismatch for buff id %d'):format(effect_id))
		end
	end
	return true
end

function M.has_sleep(buff_list)
	if type(buff_list) ~= 'table' then
		error('sleep status check requires a buff list')
	end
	for _, buff_id in ipairs(buff_list) do
		if M.effect_ids[tonumber(buff_id) or 0] == true then
			return true
		end
	end
	return false
end

return M
