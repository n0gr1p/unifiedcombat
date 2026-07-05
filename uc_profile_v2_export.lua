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

local function default_fs_deps()
	return {
		open = function(path, mode)
			return io.open(path, mode)
		end,
		exists = function(path)
			local handle = io.open(path, 'rb')
			if handle then
				handle:close()
				return true
			end
			return false
		end,
		rename = function(from_path, to_path)
			return os.rename(from_path, to_path)
		end,
		remove = function(path)
			return os.remove(path)
		end,
	}
end

local function resolve_fs_deps(deps)
	local resolved = default_fs_deps()
	if type(deps) ~= 'table' then
		return resolved
	end
	for key, value in pairs(deps) do
		resolved[key] = value
	end
	return resolved
end

local function parent_path(path)
	if type(path) ~= 'string' then
		return nil
	end
	return path:match('^(.*)[/\\][^/\\]+$')
end

local function base_name(path)
	if type(path) ~= 'string' then
		return nil
	end
	return path:match('([^/\\]+)$')
end

local function join_path(dir_path, leaf)
	if type(dir_path) ~= 'string' or dir_path == '' then
		return leaf
	end
	local sep = dir_path:find('\\', 1, true) and '\\' or '/'
	return dir_path .. sep .. leaf
end

local function candidate_sidecar_path(path, suffix, attempt)
	local dir_path = parent_path(path)
	local leaf = base_name(path) or path
	local extra = attempt > 1 and tostring(attempt) or ''
	return join_path(dir_path, leaf .. suffix .. extra)
end

local function call_dep(fn, ...)
	local ok, first, second = pcall(fn, ...)
	if not ok then
		return false, tostring(first)
	end
	if first == nil then
		return false, tostring(second or 'operation returned nil')
	end
	return true, first
end

local function dep_exists(deps, path)
	local ok, exists_or_err = pcall(deps.exists, path)
	if not ok then
		return false, tostring(exists_or_err)
	end
	return exists_or_err == true, nil
end

local function pick_available_sidecar_path(path, suffix, deps)
	for attempt = 1, 10 do
		local candidate = candidate_sidecar_path(path, suffix, attempt)
		local exists, err = dep_exists(deps, candidate)
		if err ~= nil then
			return nil, err
		end
		if not exists then
			return candidate, nil
		end
	end
	return nil, 'no available sidecar path'
end

local function cleanup_path(deps, path)
	local exists, exists_err = dep_exists(deps, path)
	if exists_err ~= nil then
		return false, exists_err
	end
	if not exists then
		return true, nil
	end
	return call_dep(deps.remove, path)
end

local function durable_write_file(path, content, deps)
	deps = resolve_fs_deps(deps)
	if type(path) ~= 'string' or path == '' then
		return {
			ok = false,
			path = path,
			stage = 'validate',
			error = 'missing export path',
		}
	end
	if type(content) ~= 'string' then
		return {
			ok = false,
			path = path,
			stage = 'validate',
			error = 'missing export content',
		}
	end

	local temp_path, temp_err = pick_available_sidecar_path(path, '.tmp', deps)
	if not temp_path then
		return {
			ok = false,
			path = path,
			stage = 'prepare_temp',
			error = temp_err,
		}
	end

	local temp_handle, open_err = deps.open(temp_path, 'wb')
	if not temp_handle then
		return {
			ok = false,
			path = path,
			temp_path = temp_path,
			stage = 'open_temp',
			error = tostring(open_err),
		}
	end

	local write_ok, write_result, write_detail = pcall(function()
		return temp_handle:write(content)
	end)
	if not write_ok or write_result == nil then
		pcall(function()
			temp_handle:close()
		end)
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return {
			ok = false,
			path = path,
			temp_path = temp_path,
			stage = 'write_temp',
			error = not write_ok and tostring(write_result) or tostring(write_detail or 'temp write returned nil'),
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		}
	end

	local close_ok, close_result = pcall(function()
		return temp_handle:close()
	end)
	if not close_ok or close_result == nil then
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return {
			ok = false,
			path = path,
			temp_path = temp_path,
			stage = 'close_temp',
			error = not close_ok and tostring(close_result) or 'temp close returned nil',
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		}
	end

	local final_exists, exists_err = dep_exists(deps, path)
	if exists_err ~= nil then
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return {
			ok = false,
			path = path,
			temp_path = temp_path,
			stage = 'check_final',
			error = exists_err,
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		}
	end

	local backup_path = nil
	if final_exists then
		backup_path, temp_err = pick_available_sidecar_path(path, '.bak', deps)
		if not backup_path then
			local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
			return {
				ok = false,
				path = path,
				temp_path = temp_path,
				stage = 'prepare_backup',
				error = temp_err,
				temp_cleanup_ok = cleanup_ok,
				temp_cleanup_error = cleanup_err,
			}
		end
		local move_old_ok, move_old_err = call_dep(deps.rename, path, backup_path)
		if not move_old_ok then
			local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
			return {
				ok = false,
				path = path,
				temp_path = temp_path,
				backup_path = backup_path,
				stage = 'backup_final',
				error = move_old_err,
				temp_cleanup_ok = cleanup_ok,
				temp_cleanup_error = cleanup_err,
			}
		end
	end

	local promote_ok, promote_err = call_dep(deps.rename, temp_path, path)
	if not promote_ok then
		local restore_ok = false
		local restore_err = nil
		if backup_path ~= nil then
			restore_ok, restore_err = call_dep(deps.rename, backup_path, path)
		end
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return {
			ok = false,
			path = path,
			temp_path = temp_path,
			backup_path = backup_path,
			stage = 'promote',
			error = promote_err,
			restore_ok = restore_ok,
			restore_error = restore_err,
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		}
	end

	local backup_cleanup_ok = true
	local backup_cleanup_err = nil
	if backup_path ~= nil then
		backup_cleanup_ok, backup_cleanup_err = cleanup_path(deps, backup_path)
	end

	return {
		ok = true,
		path = path,
		temp_path = temp_path,
		backup_path = backup_path,
		stage = 'done',
		backup_cleanup_ok = backup_cleanup_ok,
		backup_cleanup_error = backup_cleanup_err,
	}
end

function M.write_structured_profile_export(profile, meta, deps)
	local path = M.default_export_path(meta)
	local ok_render, content = pcall(M.serialize_structured_profile, profile)
	if not ok_render then
		return {
			ok = false,
			path = path,
			stage = 'render',
			error = tostring(content),
		}
	end
	return durable_write_file(path, content, deps)
end

return M
