local uc_config_normalizer = require('uc_config_normalizer')

local M = {}

local DURABLE_CONFIG_DOMAINS = {
	'ui',
	'command',
	'combat',
	'abilities',
	'defensive',
	'movement',
	'follow',
	'targeting',
	'tank',
	'sleep',
	'spells',
	'maintenance',
	'debug',
	'ownership',
	'legacy',
}

local KEY_TYPE_ORDER = {
	number = 1,
	string = 2,
	boolean = 3,
	table = 4,
}

local function trim_string(value)
	if type(value) ~= 'string' then
		return ''
	end
	return (value:match('^%s*(.-)%s*$') or '')
end

local function normalize_optional_string(value, default_value)
	local trimmed = trim_string(value)
	if trimmed == '' then
		return default_value
	end
	return trimmed
end

local function safe_character_component(value)
	local trimmed = trim_string(value):lower()
	trimmed = trimmed:gsub('[^%w%-_]+', '_')
	trimmed = trimmed:gsub('_+', '_')
	trimmed = trimmed:gsub('^_+', ''):gsub('_+$', '')
	if trimmed == '' then
		return 'unknown'
	end
	return trimmed
end

local function safe_job_component(value)
	local trimmed = trim_string(value):upper()
	trimmed = trimmed:gsub('[^%w%-_]+', '_')
	trimmed = trimmed:gsub('_+', '_')
	trimmed = trimmed:gsub('^_+', ''):gsub('_+$', '')
	if trimmed == '' then
		return 'UNKNOWN'
	end
	return trimmed
end

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		return {}
	end
	visited[value] = true
	local out = {}
	for key, inner_value in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner_value, visited)
	end
	visited[value] = nil
	return out
end

local function sorted_keys(value)
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		local left_type = type(left)
		local right_type = type(right)
		if left_type ~= right_type then
			return (KEY_TYPE_ORDER[left_type] or 99) < (KEY_TYPE_ORDER[right_type] or 99)
		end
		if left_type == 'number' then
			return left < right
		end
		return tostring(left) < tostring(right)
	end)
	return keys
end

local function is_identifier_key(key)
	return type(key) == 'string' and key:match('^[_%a][_%w]*$') ~= nil
end

local function serialize_value(value, indent, seen)
	local value_type = type(value)
	if value_type == 'nil' then
		return 'nil'
	elseif value_type == 'number' or value_type == 'boolean' then
		return tostring(value)
	elseif value_type == 'string' then
		return string.format('%q', value)
	elseif value_type ~= 'table' then
		return string.format('%q', tostring(value))
	end

	local visited = seen or {}
	if visited[value] then
		error('cycle detected while serializing structured profile')
	end
	visited[value] = true

	local next_indent = indent + 2
	local pad = string.rep(' ', indent)
	local next_pad = string.rep(' ', next_indent)
	local parts = { '{' }
	local keys = sorted_keys(value)
	for i = 1, #keys do
		local key = keys[i]
		local serialized_key
		if is_identifier_key(key) then
			serialized_key = key
		else
			serialized_key = '[' .. serialize_value(key, next_indent, visited) .. ']'
		end
		parts[#parts + 1] = '\n' .. next_pad .. serialized_key .. ' = ' .. serialize_value(value[key], next_indent, visited) .. ','
	end
	parts[#parts + 1] = '\n' .. pad .. '}'
	visited[value] = nil
	return table.concat(parts)
end

local function pick_durable_config_domains(config)
	local out = {}
	for i = 1, #DURABLE_CONFIG_DOMAINS do
		local domain = DURABLE_CONFIG_DOMAINS[i]
		local value = type(config) == 'table' and config[domain] or nil
		if type(value) == 'table' then
			out[domain] = clone_value(value)
		end
	end
	return out
end

local function normalized_meta(meta)
	local meta_table = type(meta) == 'table' and meta or {}
	return {
		character = normalize_optional_string(meta_table.character or meta_table.char, 'unknown'),
		main_job = normalize_optional_string(meta_table.main_job or meta_table.job, 'UNKNOWN'),
		sub_job = normalize_optional_string(meta_table.sub_job, 'UNKNOWN'),
		profile_key = normalize_optional_string(meta_table.profile_key),
		exported_at = normalize_optional_string(meta_table.exported_at, os.date('!%Y-%m-%dT%H:%M:%SZ')),
	}
end

function M.build_structured_profile(settings, meta)
	local normalized = uc_config_normalizer.normalize(settings, meta)
	local resolved_meta = normalized_meta(meta)
	if resolved_meta.profile_key ~= nil then
		return {
			version = 2,
			profile = {
				schema_version = 2,
				engine = 'UC',
				character = resolved_meta.character,
				main_job = safe_job_component(resolved_meta.main_job),
				sub_job = safe_job_component(resolved_meta.sub_job),
				source = 'exported_from_v1_settings',
				exported_at = resolved_meta.exported_at,
				profile_key = resolved_meta.profile_key,
			},
			config = pick_durable_config_domains(normalized),
		}
	end
	return {
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = resolved_meta.character,
			main_job = safe_job_component(resolved_meta.main_job),
			sub_job = safe_job_component(resolved_meta.sub_job),
			source = 'exported_from_v1_settings',
			exported_at = resolved_meta.exported_at,
		},
		config = pick_durable_config_domains(normalized),
	}
end

function M.serialize_structured_profile(profile)
	local resolved_profile = type(profile) == 'table' and profile or {}
	return 'return ' .. serialize_value(resolved_profile, 0) .. '\n'
end

function M.default_export_path(meta)
	local resolved_meta = normalized_meta(meta)
	return 'data/profiles_v2/' .. safe_character_component(resolved_meta.character) .. '_' .. safe_job_component(resolved_meta.main_job) .. '_' .. safe_job_component(resolved_meta.sub_job) .. '.lua'
end

return M
