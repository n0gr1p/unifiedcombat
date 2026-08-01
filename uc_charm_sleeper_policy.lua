local M = {}

local cached_policy = nil

local function require_text(value, field)
	if type(value) ~= 'string' or value == '' then
		error(('charm sleeper policy requires non-empty string field %s'):format(field))
	end
	return value
end

local function duration_seconds(value, field)
	if type(value) == 'number' and value > 0 then
		return value
	end
	if type(value) == 'string' then
		local upper = tonumber(value:match('^%s*%d+%s*%-%s*(%d+)%s*$'))
		if upper and upper > 0 then
			return upper
		end
	end
	error(('charm sleeper policy requires numeric or numeric-range duration at %s'):format(field))
end

local function extract_array(raw, key)
	local _, open_at = raw:find('"' .. key .. '"%s*:%s*%[')
	if open_at == nil then
		error(('charm sleeper policy requires JSON array %s'):format(key))
	end
	local depth = 0
	local quoted = false
	local escaped = false
	for index = open_at, #raw do
		local char = raw:sub(index, index)
		if quoted then
			if escaped then
				escaped = false
			elseif char == '\\' then
				escaped = true
			elseif char == '"' then
				quoted = false
			end
		elseif char == '"' then
			quoted = true
		elseif char == '[' then
			depth = depth + 1
		elseif char == ']' then
			depth = depth - 1
			if depth == 0 then
				return raw:sub(open_at + 1, index - 1)
			end
		end
	end
	error(('unterminated charm sleeper policy JSON array %s'):format(key))
end

local function string_array(raw, key)
	local out = {}
	for value in extract_array(raw, key):gmatch('"([%w_]+)"') do
		out[#out + 1] = value
	end
	if #out == 0 then
		error(('charm sleeper policy JSON array %s is empty'):format(key))
	end
	return out
end

local function object_array(raw, key)
	local blob = extract_array(raw, key)
	local out = {}
	local start_at = nil
	local depth = 0
	local quoted = false
	local escaped = false
	for index = 1, #blob do
		local char = blob:sub(index, index)
		if quoted then
			if escaped then
				escaped = false
			elseif char == '\\' then
				escaped = true
			elseif char == '"' then
				quoted = false
			end
		elseif char == '"' then
			quoted = true
		elseif char == '{' then
			if depth == 0 then
				start_at = index
			end
			depth = depth + 1
		elseif char == '}' then
			depth = depth - 1
			if depth < 0 then
				error(('invalid object nesting in charm sleeper policy array %s'):format(key))
			end
			if depth == 0 then
				out[#out + 1] = blob:sub(start_at, index)
				start_at = nil
			end
		end
	end
	if depth ~= 0 or #out == 0 then
		error(('invalid or empty object array in charm sleeper policy %s'):format(key))
	end
	return out
end

local function object_string(raw, key, field)
	return require_text(raw:match('"' .. key .. '"%s*:%s*"(.-)"'), field)
end

local function object_number(raw, key, field)
	local value = tonumber(raw:match('"' .. key .. '"%s*:%s*([%-]?%d+%.?%d*)'))
	if value == nil then
		error(('charm sleeper policy requires numeric field %s'):format(field))
	end
	return value
end

local function object_duration(raw, key, field)
	local numeric_value = tonumber(raw:match('"' .. key .. '"%s*:%s*([%-]?%d+%.?%d*)'))
	if numeric_value ~= nil then
		return duration_seconds(numeric_value, field)
	end
	return duration_seconds(raw:match('"' .. key .. '"%s*:%s*"(.-)"'), field)
end

local function load_policy(addon_path)
	local path = require_text(addon_path, 'addon_path') .. 'docs/ffxi_charmed_player_sleep_spells.json'
	local file, open_error = io.open(path, 'r')
	if not file then
		error(('unable to open charm sleeper policy at %s: %s'):format(path, tostring(open_error)))
	end
	local raw = file:read('*a')
	file:close()
	if type(raw) ~= 'string' or raw == '' then
		error(('charm sleeper policy is empty at %s'):format(path))
	end
	if not raw:find('"dataset"%s*:%s*"ffxi_charmed_player_sleep_spells"') then
		error(('unexpected charm sleeper policy dataset at %s'):format(path))
	end

	local excluded = {}
	for _, spell_id in ipairs(string_array(raw, 'exclude_by_default')) do
		excluded[require_text(spell_id, 'selector_policy.exclude_by_default[]')] = true
	end
	local by_id = {}
	for index, row in ipairs(object_array(raw, 'sleep_spells')) do
		local id = object_string(row, 'id', ('sleep_spells[%d].id'):format(index))
		if by_id[id] ~= nil then
			error(('duplicate charm sleeper policy spell id %s'):format(id))
		end
		by_id[id] = row
	end

	local spells = {}
	local effect_ids = {}
	for index, spell_id in ipairs(string_array(raw, 'default_sort_order')) do
		spell_id = require_text(spell_id, ('selector_policy.default_sort_order[%d]'):format(index))
		local row = by_id[spell_id]
		if type(row) ~= 'string' then
			error(('charm sleeper policy order references unknown spell id %s'):format(spell_id))
		end
		if excluded[spell_id] ~= true then
			local buff_id = object_number(row, 'windower_buff_id', spell_id .. '.inflicts_status.windower_buff_id')
			local range_yalms = object_number(row, 'range_yalms', spell_id .. '.targeting.range_yalms')
			local area = object_string(row, 'area', spell_id .. '.targeting.area')
			if not buff_id or buff_id <= 0 then
				error(('charm sleeper policy spell %s has invalid windower buff id'):format(spell_id))
			end
			if not range_yalms or range_yalms <= 0 then
				error(('charm sleeper policy spell %s has invalid range'):format(spell_id))
			end
			if area ~= 'aoe_gaze_centered_on_caster' then
				spells[#spells + 1] = {
					id = spell_id,
					name = object_string(row, 'name', spell_id .. '.name'),
					duration_s = object_duration(row, 'base_duration_seconds', spell_id .. '.base_duration_seconds'),
					effect_id = buff_id,
					range_yalms = range_yalms,
					area = area,
				}
				effect_ids[buff_id] = true
			end
		end
	end
	if #spells == 0 then
		error('charm sleeper policy contains no enabled safe spells')
	end
	return {
		path = path,
		spells = spells,
		effect_ids = effect_ids,
	}
end

function M.get(addon_path)
	if cached_policy == nil then
		cached_policy = load_policy(addon_path)
	end
	return cached_policy
end

function M.reset_for_tests()
	cached_policy = nil
end

return M
