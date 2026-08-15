local M = {}

local definitions = {
	sortie_ghatjot = {
		id = 'sortie_ghatjot',
		family = 'sortie_plovid',
		actor_name = 'Ghatjot',
		zone_id = 133,
		zone_name = "Outer Ra'Kaznar [U2]",
		policy = {
			water_damage = 'enforce',
			water_skillchain = 'enforce',
			repeat_action_wall = 'off',
		},
		tuning = {
			repeat_action_guard_s = 10.0,
		},
	},
	sortie_dhartok = {
		id = 'sortie_dhartok',
		family = 'sortie_plovid',
		actor_name = 'Dhartok',
		zone_id = 133,
		zone_name = "Outer Ra'Kaznar [U2]",
		policy = {
			water_damage = 'enforce',
			water_skillchain = 'enforce',
			repeat_action_wall = 'warn',
		},
		tuning = {
			repeat_action_guard_s = 10.0,
		},
	},
}

local function copy_table(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copy_table(item)
	end
	return out
end

local function copy_definition(definition)
	if type(definition) ~= 'table' then
		return nil
	end
	return {
		id = definition.id,
		family = definition.family,
		actor_name = definition.actor_name,
		zone_id = definition.zone_id,
		zone_name = definition.zone_name,
		policy = copy_table(definition.policy),
		tuning = copy_table(definition.tuning),
	}
end

function M.get(encounter_id)
	return copy_definition(definitions[tostring(encounter_id or '')])
end

function M.ids()
	return { 'sortie_ghatjot', 'sortie_dhartok' }
end

return M
