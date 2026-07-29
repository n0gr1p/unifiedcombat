local M = {}

local EXPECTED_HEADER = table.concat({
	'avatar',
	'summon_spell_id',
	'summon_spell',
	'action_category',
	'action_id',
	'action_name',
	'effect_id',
	'effect_name',
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
				local effect_id = nil
				local effect_name = nil
				if category == 'ward' then
					effect_id = required_integer(fields[7], 'effect_id', line_number)
					effect_name = required_text(fields[8], 'effect_name', line_number)
				elseif fields[7] ~= '' or fields[8] ~= '' then
					file:close()
					error(('Summoner capability catalog line %d: Rage rows must not define a maintained effect'):format(line_number))
				end

				local avatar = catalog.avatars[avatar_name]
				if avatar == nil then
					avatar = {
						name = avatar_name,
						summon_spell_id = summon_spell_id,
						summon_spell = summon_spell,
						wards = {},
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
					effect_id = effect_id,
					effect_name = effect_name,
				}
				local actions = category == 'ward' and avatar.wards or avatar.rages
				actions[#actions + 1] = action
				by_name[action_name] = action
				catalog.actions_by_id[action_id] = action
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

return M
