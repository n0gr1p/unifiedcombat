local M = {}

local EXPECTED_HEADER = table.concat({
	'avatar',
	'summon_spell_id',
	'summon_spell',
	'action_category',
	'action_id',
	'action_name',
	'effect_ids',
	'effect_names',
}, '\t')

local function module_directory()
	local source = debug.getinfo(1, 'S').source
	if type(source) ~= 'string' or source:sub(1, 1) ~= '@' then
		error('Summoner capability catalog: module source path is unavailable')
	end
	local path = source:sub(2)
	local directory = path:match('^(.*[\\/])')
	if directory == nil then
		error('Summoner capability catalog: module directory is unavailable')
	end
	return directory
end

local function split_tsv(line)
	local fields = {}
	local start_at = 1
	while true do
		local tab_at = line:find('\t', start_at, true)
		if tab_at == nil then
			fields[#fields + 1] = line:sub(start_at)
			return fields
		end
		fields[#fields + 1] = line:sub(start_at, tab_at - 1)
		start_at = tab_at + 1
	end
end

local function required_text(value, field, line_number)
	if type(value) ~= 'string' or value == '' then
		error(('Summoner capability catalog line %d: %s is required'):format(line_number, field))
	end
	return value
end

local function required_integer(value, field, line_number)
	local number = tonumber(value)
	if number == nil or number % 1 ~= 0 or number <= 0 then
		error(('Summoner capability catalog line %d: %s must be a positive integer'):format(line_number, field))
	end
	return number
end

local function split_effect_list(value, field, line_number)
	local values = {}
	local start_at = 1
	while true do
		local separator_at = value:find('|', start_at, true)
		local item = separator_at == nil and value:sub(start_at) or value:sub(start_at, separator_at - 1)
		if item == '' then
			error(('Summoner capability catalog line %d: %s contains an empty entry'):format(line_number, field))
		end
		values[#values + 1] = item
		if separator_at == nil then
			return values
		end
		start_at = separator_at + 1
	end
end

local function effect_lists(effect_ids_value, effect_names_value, line_number)
	if effect_ids_value == '-' and effect_names_value == '-' then
		return {}, {}
	end
	if effect_ids_value == '-' or effect_names_value == '-' then
		error(('Summoner capability catalog line %d: effect_ids and effect_names must both be populated or "-"'):format(
			line_number
		))
	end
	local raw_ids = split_effect_list(effect_ids_value, 'effect_ids', line_number)
	local names = split_effect_list(effect_names_value, 'effect_names', line_number)
	if #raw_ids ~= #names then
		error(('Summoner capability catalog line %d: effect_ids and effect_names must have equal lengths'):format(
			line_number
		))
	end
	local ids = {}
	local seen_ids = {}
	for i = 1, #raw_ids do
		local effect_id = required_integer(raw_ids[i], ('effect_ids[%d]'):format(i), line_number)
		if seen_ids[effect_id] then
			error(('Summoner capability catalog line %d: duplicate effect id %d'):format(line_number, effect_id))
		end
		seen_ids[effect_id] = true
		ids[i] = effect_id
	end
	return ids, names
end

local function load_catalog()
	local path = module_directory() .. 'data/summoner_capabilities.tsv'
	local file, open_error = io.open(path, 'r')
	if file == nil then
		error('Summoner capability catalog could not be opened: ' .. tostring(open_error))
	end

	local catalog = {
		path = path,
		avatars = {},
		avatar_order = {},
		actions_by_id = {},
		ward_actions_by_name = {},
		wards_by_name = {},
	}
	local header_seen = false
	local line_number = 0

	for line in file:lines() do
		line_number = line_number + 1
		if line:sub(1, 1) ~= '#' and line ~= '' then
			if not header_seen then
				if line ~= EXPECTED_HEADER then
					file:close()
					error(('Summoner capability catalog line %d: unexpected header'):format(line_number))
				end
				header_seen = true
			else
				local fields = split_tsv(line)
				if #fields ~= 8 then
					file:close()
					error(('Summoner capability catalog line %d: expected 8 tab-separated fields'):format(line_number))
				end

				local avatar_name = required_text(fields[1], 'avatar', line_number)
				local summon_spell_id = required_integer(fields[2], 'summon_spell_id', line_number)
				local summon_spell = required_text(fields[3], 'summon_spell', line_number)
				local category = required_text(fields[4], 'action_category', line_number)
				if category ~= 'ward' and category ~= 'rage' then
					file:close()
					error(('Summoner capability catalog line %d: unsupported action_category %s'):format(line_number, category))
				end
				local action_id = required_integer(fields[5], 'action_id', line_number)
				local action_name = required_text(fields[6], 'action_name', line_number)
				local effect_ids = {}
				local effect_names = {}
				if category == 'ward' then
					effect_ids, effect_names = effect_lists(fields[7], fields[8], line_number)
				elseif fields[7] ~= '-' or fields[8] ~= '-' then
					file:close()
					error(('Summoner capability catalog line %d: Rage rows must not define maintained effects'):format(line_number))
				end

				local avatar = catalog.avatars[avatar_name]
				if avatar == nil then
					avatar = {
						name = avatar_name,
						summon_spell_id = summon_spell_id,
						summon_spell = summon_spell,
						wards = {},
						maintainable_wards = {},
						rages = {},
						ward_by_name = {},
						rage_by_name = {},
					}
					catalog.avatars[avatar_name] = avatar
					catalog.avatar_order[#catalog.avatar_order + 1] = avatar_name
				elseif avatar.summon_spell_id ~= summon_spell_id or avatar.summon_spell ~= summon_spell then
					file:close()
					error(('Summoner capability catalog line %d: inconsistent summon identity for %s'):format(line_number, avatar_name))
				end

				if catalog.actions_by_id[action_id] ~= nil then
					file:close()
					error(('Summoner capability catalog line %d: duplicate action_id %d'):format(line_number, action_id))
				end
				local by_name = category == 'ward' and avatar.ward_by_name or avatar.rage_by_name
				if by_name[action_name] ~= nil then
					file:close()
					error(('Summoner capability catalog line %d: duplicate %s action %s for %s'):format(
						line_number,
						category,
						action_name,
						avatar_name
					))
				end

				local action = {
					id = action_id,
					name = action_name,
					category = category,
					avatar = avatar_name,
					effect_ids = effect_ids,
					effect_names = effect_names,
					maintainable = #effect_ids > 0,
				}
				if #effect_ids == 1 then
					action.effect_id = effect_ids[1]
					action.effect_name = effect_names[1]
				end
				local actions = category == 'ward' and avatar.wards or avatar.rages
				actions[#actions + 1] = action
				by_name[action_name] = action
				catalog.actions_by_id[action_id] = action
				if category == 'ward' then
					if catalog.ward_actions_by_name[action_name] ~= nil then
						file:close()
						error(('Summoner capability catalog line %d: duplicate Ward name %s'):format(
							line_number,
							action_name
						))
					end
					catalog.ward_actions_by_name[action_name] = action
					if action.maintainable then
						avatar.maintainable_wards[#avatar.maintainable_wards + 1] = action
						catalog.wards_by_name[action_name] = action
					end
				end
			end
		end
	end
	file:close()

	if not header_seen then
		error('Summoner capability catalog is missing its header')
	end
	if #catalog.avatar_order == 0 then
		error('Summoner capability catalog contains no supported avatars')
	end
	return catalog
end

local CATALOG = load_catalog()

function M.get()
	return CATALOG
end

function M.avatar(name)
	if type(name) ~= 'string' then
		return nil
	end
	return CATALOG.avatars[name]
end

function M.action(avatar_name, category, action_name)
	local avatar = M.avatar(avatar_name)
	if avatar == nil or type(action_name) ~= 'string' then
		return nil
	end
	if category == 'ward' then
		return avatar.ward_by_name[action_name]
	end
	if category == 'rage' then
		return avatar.rage_by_name[action_name]
	end
	error('Summoner capability lookup: category must be ward or rage')
end

function M.ward(action_name)
	if type(action_name) ~= 'string' then
		return nil
	end
	return CATALOG.wards_by_name[action_name]
end

return M
