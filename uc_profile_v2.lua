local uc_config_normalizer = require('uc_config_normalizer')
local uc_active_config = require('uc_active_config')

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

local function path_separator(path)
	if type(path) == 'string' and path:find('\\', 1, true) then
		return '\\'
	end
	return '/'
end

local function join_path(left, right)
	if type(left) ~= 'string' or left == '' then
		return right
	end
	if type(right) ~= 'string' or right == '' then
		return left
	end
	if left:sub(-1) == '/' or left:sub(-1) == '\\' then
		return left .. right
	end
	return left .. path_separator(left) .. right
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
	-- Keep legacy mirrors in runtime state, but do not carry them through the
	-- durable v2 round-trip check. UI-authored files are allowed to omit them.
	if type(out.targeting) == 'table' then
		out.targeting.add_priority_names = nil
	end
	out.sleep = nil
	return out
end

local function strip_durable_profile_overrides(config)
	if type(config) ~= 'table' then
		return config
	end
	if type(config.abilities) == 'table' then
		config.abilities.legacy_slots = nil
	end
	if type(config.targeting) == 'table' then
		config.targeting.legacy_slots = nil
		config.targeting.add_priority_names = nil
	end
	config.sleep = nil
	return config
end

local function append_path(prefix, key)
	local key_string = tostring(key)
	if prefix == nil or prefix == '' then
		return key_string
	end
	if type(key) == 'string' and key:match('^[_%a][_%w]*$') ~= nil then
		return prefix .. '.' .. key_string
	end
	return prefix .. '[' .. key_string .. ']'
end

local function collect_union_keys(left, right)
	local seen = {}
	local keys = {}
	if type(left) == 'table' then
		for key in pairs(left) do
			if not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
	end
	if type(right) == 'table' then
		for key in pairs(right) do
			if not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
	end
	table.sort(keys, function(left_key, right_key)
		local left_type = type(left_key)
		local right_type = type(right_key)
		if left_type ~= right_type then
			return (KEY_TYPE_ORDER[left_type] or 99) < (KEY_TYPE_ORDER[right_type] or 99)
		end
		if left_type == 'number' then
			return left_key < right_key
		end
		return tostring(left_key) < tostring(right_key)
	end)
	return keys
end

local function diff_values(left, right, path, differences)
	if left == right then
		return
	end
	if type(left) ~= type(right) then
		differences[#differences + 1] = path
		return
	end
	if type(left) ~= 'table' then
		differences[#differences + 1] = path
		return
	end

	local keys = collect_union_keys(left, right)
	for i = 1, #keys do
		local key = keys[i]
		local next_path = append_path(path, key)
		local left_value = left[key]
		local right_value = right[key]
		if left_value == nil and right_value == nil then
			-- no-op
		elseif left_value == nil or right_value == nil then
			differences[#differences + 1] = next_path
		else
			diff_values(left_value, right_value, next_path, differences)
		end
	end
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

function M.build_durable_config(settings, meta)
	local normalized = uc_config_normalizer.normalize(settings, meta)
	return pick_durable_config_domains(normalized)
end

function M.serialize_structured_profile(profile)
	local resolved_profile = type(profile) == 'table' and profile or {}
	return 'return ' .. serialize_value(resolved_profile, 0) .. '\n'
end

function M.default_export_path(meta)
	local resolved_meta = normalized_meta(meta)
	local meta_table = type(meta) == 'table' and meta or {}
	local base_path = trim_string(meta_table.addon_path or meta_table.base_path)
	local dir_path
	if base_path ~= '' then
		dir_path = join_path(join_path(base_path, 'data'), 'profiles_v2')
	else
		dir_path = 'data/profiles_v2'
	end
	return join_path(dir_path, safe_character_component(resolved_meta.character) .. '_' .. safe_job_component(resolved_meta.main_job) .. '_' .. safe_job_component(resolved_meta.sub_job) .. '.lua')
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
		dir_exists = function(path)
			local w = rawget(_G, 'windower')
			if type(w) ~= 'table' or type(w.dir_exists) ~= 'function' then
				return nil, 'windower.dir_exists unavailable'
			end
			return w.dir_exists(path)
		end,
		create_dir = function(path)
			local w = rawget(_G, 'windower')
			if type(w) ~= 'table' or type(w.create_dir) ~= 'function' then
				return nil, 'windower.create_dir unavailable'
			end
			return w.create_dir(path)
		end,
		read_all = function(path)
			local handle, open_err = io.open(path, 'rb')
			if not handle then
				return nil, open_err
			end
			local content = handle:read('*a')
			handle:close()
			if type(content) ~= 'string' or content == '' then
				return nil, 'empty file'
			end
			return content
		end,
		load_chunk = function(content, chunk_name)
			return loadstring(content, chunk_name)
		end,
		execute_chunk = function(chunk)
			return chunk()
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

local function dep_dir_exists(deps, path)
	if type(deps.dir_exists) ~= 'function' then
		return false, 'directory check unavailable'
	end
	local ok, exists_or_err, detail = pcall(deps.dir_exists, path)
	if not ok then
		return false, tostring(exists_or_err)
	end
	if exists_or_err == true then
		return true, nil
	end
	if exists_or_err == false then
		return false, nil
	end
	return false, tostring(detail or exists_or_err or 'directory check returned nil')
end

local function ensure_output_dir(path, deps)
	local dir_path = parent_path(path)
	if type(dir_path) ~= 'string' or dir_path == '' then
		return false, nil, 'path resolution failed'
	end

	local exists, exists_err = dep_dir_exists(deps, dir_path)
	if exists_err ~= nil then
		return false, dir_path, exists_err
	end
	if exists then
		return true, dir_path, nil
	end
	if type(deps.create_dir) ~= 'function' then
		return false, dir_path, 'directory create unavailable'
	end

	local ok_create, create_result, create_detail = pcall(deps.create_dir, dir_path)
	if not ok_create then
		return false, dir_path, tostring(create_result)
	end

	local exists_after, exists_after_err = dep_dir_exists(deps, dir_path)
	if exists_after_err ~= nil then
		return false, dir_path, exists_after_err
	end
	if not exists_after then
		return false, dir_path, tostring(create_detail or create_result or 'directory still missing after create')
	end
	return true, dir_path, nil
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

local function fail_result(path, stage, reason, detail, extra)
	local result = {
		ok = false,
		path = path,
		stage = stage,
		reason = reason,
		error = detail,
		detail = detail,
	}
	if type(extra) == 'table' then
		for key, value in pairs(extra) do
			result[key] = value
		end
	end
	return result
end

local function durable_write_file(path, content, deps)
	deps = resolve_fs_deps(deps)
	if type(path) ~= 'string' or path == '' then
		return fail_result(path, 'validate', 'missing export path', 'missing export path')
	end
	if type(content) ~= 'string' then
		return fail_result(path, 'validate', 'serialization failed', 'missing export content')
	end

	local dir_ok, dir_path, dir_err = ensure_output_dir(path, deps)
	if not dir_ok then
		return fail_result(path, 'prepare_dir', 'output directory unavailable', dir_err, {
			dir_path = dir_path,
		})
	end

	local temp_path, temp_err = pick_available_sidecar_path(path, '.tmp', deps)
	if not temp_path then
		return fail_result(path, 'prepare_temp', 'temp path unavailable', temp_err)
	end

	local temp_handle, open_err = deps.open(temp_path, 'wb')
	if not temp_handle then
		return fail_result(path, 'open_temp', 'temp open failed', tostring(open_err), {
			temp_path = temp_path,
		})
	end

	local write_ok, write_result, write_detail = pcall(function()
		return temp_handle:write(content)
	end)
	if not write_ok or write_result == nil then
		pcall(function()
			temp_handle:close()
		end)
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return fail_result(path, 'write_temp', 'temp write failed', not write_ok and tostring(write_result) or tostring(write_detail or 'temp write returned nil'), {
			temp_path = temp_path,
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		})
	end

	local close_ok, close_result, close_detail = pcall(function()
		return temp_handle:close()
	end)
	if not close_ok or close_result == nil then
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return fail_result(path, 'close_temp', 'temp close failed', not close_ok and tostring(close_result) or tostring(close_detail or 'temp close returned nil'), {
			temp_path = temp_path,
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		})
	end

	local final_exists, exists_err = dep_exists(deps, path)
	if exists_err ~= nil then
		local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
		return fail_result(path, 'check_final', 'final path check failed', exists_err, {
			temp_path = temp_path,
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		})
	end

	local backup_path = nil
	if final_exists then
		backup_path, temp_err = pick_available_sidecar_path(path, '.bak', deps)
		if not backup_path then
			local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
			return fail_result(path, 'prepare_backup', 'backup path unavailable', temp_err, {
				temp_path = temp_path,
				temp_cleanup_ok = cleanup_ok,
				temp_cleanup_error = cleanup_err,
			})
		end
		local move_old_ok, move_old_err = call_dep(deps.rename, path, backup_path)
		if not move_old_ok then
			local cleanup_ok, cleanup_err = cleanup_path(deps, temp_path)
			return fail_result(path, 'backup_final', 'backup failed', move_old_err, {
				temp_path = temp_path,
				backup_path = backup_path,
				temp_cleanup_ok = cleanup_ok,
				temp_cleanup_error = cleanup_err,
			})
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
		return fail_result(path, 'promote', 'temp promote failed', promote_err, {
			temp_path = temp_path,
			backup_path = backup_path,
			restore_ok = restore_ok,
			restore_error = restore_err,
			temp_cleanup_ok = cleanup_ok,
			temp_cleanup_error = cleanup_err,
		})
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
		return fail_result(path, 'render', 'serialization failed', tostring(content))
	end
	return durable_write_file(path, content, deps)
end

function M.validate_structured_profile_file(meta, validator, deps)
	local path = M.default_export_path(meta)
	deps = resolve_fs_deps(deps)

	local ok_read, content_or_err, read_detail = pcall(deps.read_all, path)
	if not ok_read then
		return {
			ok = false,
			path = path,
			stage = 'read',
			error = tostring(content_or_err),
			detail = tostring(content_or_err),
			reason = 'read failed',
		}
	end
	if type(content_or_err) ~= 'string' or content_or_err == '' then
		local detail = tostring(read_detail or content_or_err or 'empty file')
		return {
			ok = false,
			path = path,
			stage = 'read',
			error = detail,
			detail = detail,
			reason = 'read failed',
		}
	end

	local ok_load, chunk_or_err, load_detail = pcall(deps.load_chunk, content_or_err, '@' .. path)
	if not ok_load then
		return {
			ok = false,
			path = path,
			stage = 'load',
			error = tostring(chunk_or_err),
			detail = tostring(chunk_or_err),
			reason = 'parse failed',
		}
	end
	if type(chunk_or_err) ~= 'function' then
		local detail = tostring(load_detail or 'chunk load returned nil')
		return {
			ok = false,
			path = path,
			stage = 'load',
			error = detail,
			detail = detail,
			reason = 'parse failed',
		}
	end

	local ok_exec, payload_or_err = pcall(deps.execute_chunk, chunk_or_err)
	if not ok_exec then
		return {
			ok = false,
			path = path,
			stage = 'execute',
			error = tostring(payload_or_err),
			detail = tostring(payload_or_err),
			reason = 'load failed',
		}
	end
	if type(payload_or_err) ~= 'table' then
		return {
			ok = false,
			path = path,
			stage = 'shape',
			error = 'structured profile file must return a table',
			detail = 'structured profile file must return a table',
			reason = 'invalid payload',
		}
	end
	if payload_or_err.version ~= 2 then
		return {
			ok = false,
			path = path,
			stage = 'shape',
			error = 'structured profile version must be 2',
			detail = 'structured profile version must be 2',
			reason = 'invalid version',
		}
	end
	if type(payload_or_err.profile) ~= 'table' then
		return {
			ok = false,
			path = path,
			stage = 'shape',
			error = 'structured profile metadata missing',
			detail = 'structured profile metadata missing',
			reason = 'missing profile',
		}
	end
	if type(payload_or_err.config) ~= 'table' then
		return {
			ok = false,
			path = path,
			stage = 'shape',
			error = 'structured profile config missing',
			detail = 'structured profile config missing',
			reason = 'missing config',
		}
	end

	if type(validator) == 'function' then
		local ok_validate, validation = pcall(validator, payload_or_err)
		if not ok_validate then
			return {
				ok = false,
				path = path,
				stage = 'contract',
				error = tostring(validation),
				detail = tostring(validation),
				reason = 'contract failed',
				payload = payload_or_err,
			}
		end
		if type(validation) ~= 'table' or validation.ok ~= true then
			local error_message = nil
			if type(validation) == 'table' and type(validation.errors) == 'table' and type(validation.errors[1]) == 'string' then
				error_message = validation.errors[1]
			end
			return {
				ok = false,
				path = path,
				stage = 'contract',
				error = tostring(error_message or 'structured profile contract validation failed'),
				detail = tostring(error_message or 'structured profile contract validation failed'),
				reason = 'contract failed',
				payload = payload_or_err,
				validation = validation,
			}
		end
		return {
			ok = true,
			path = path,
			stage = 'done',
			payload = payload_or_err,
			validation = validation,
		}
	end

	return {
		ok = true,
		path = path,
		stage = 'done',
		payload = payload_or_err,
	}
end

function M.diff_durable_config(current_config, target_config)
	local differences = {}
	diff_values(strip_durable_profile_overrides(clone_value(current_config)), strip_durable_profile_overrides(clone_value(target_config)), 'config', differences)
	return {
		count = #differences,
		differences = differences,
	}
end

function M.diff_structured_profile_file_against_settings(settings, meta, validator, deps)
	local validation = M.validate_structured_profile_file(meta, validator, deps)
	if type(validation) ~= 'table' or validation.ok ~= true or type(validation.payload) ~= 'table' then
		if type(validation) == 'table' then
			validation.count = 0
			validation.differences = {}
		end
		return validation
	end

	local current_config = M.build_durable_config(settings, meta)
	local diff = M.diff_durable_config(current_config, validation.payload.config)
	return {
		ok = true,
		path = validation.path,
		stage = 'done',
		payload = validation.payload,
		validation = validation.validation,
		count = diff.count,
		differences = diff.differences,
		current_config = current_config,
	}
end

function M.inspect_structured_profile_file_against_settings(settings, meta, validator, deps)
	local diff = M.diff_structured_profile_file_against_settings(settings, meta, validator, deps)
	if type(diff) ~= 'table' then
		return {
			ok = false,
			path = M.default_export_path(meta),
			stage = 'inspect',
			error = 'structured profile status helper returned invalid result',
			reason = 'inspect failed',
		}
	end
	return diff
end

local function structured_profile_status_result(path, state, valid, reason, diff_count, meta, payload)
	local resolved_meta = type(meta) == 'table' and meta or {}
	local resolved_profile = type(payload) == 'table' and type(payload.profile) == 'table' and payload.profile or nil
	return {
		path = path,
		state = state,
		valid = valid == true,
		diff_count = tonumber(diff_count) or 0,
		reason = reason,
		source = resolved_profile and resolved_profile.source or resolved_meta.source,
		character = resolved_profile and resolved_profile.character or resolved_meta.character,
		main_job = resolved_profile and resolved_profile.main_job or resolved_meta.main_job,
		sub_job = resolved_profile and resolved_profile.sub_job or resolved_meta.sub_job,
	}
end

function M.inspect_structured_profile_status(settings, meta, validator, deps)
	deps = resolve_fs_deps(deps)
	local path = M.default_export_path(meta)

	local exists, exists_err = dep_exists(deps, path)
	if exists_err ~= nil then
		return structured_profile_status_result(path, 'error', false, tostring(exists_err), 0, meta)
	end
	if not exists then
		return structured_profile_status_result(path, 'missing', false, 'missing file', 0, meta)
	end

	local validation = M.validate_structured_profile_file(meta, validator, deps)
	if type(validation) ~= 'table' then
		return structured_profile_status_result(path, 'error', false, 'structured profile status helper returned invalid result', 0, meta)
	end
	if validation.ok ~= true or type(validation.payload) ~= 'table' then
		local state = validation.stage == 'read' and 'error' or 'invalid'
		local reason = validation.error or validation.reason or 'structured profile invalid'
		return structured_profile_status_result(validation.path or path, state, false, tostring(reason), 0, meta, validation.payload)
	end

	local ok_current_config, current_config = pcall(M.build_durable_config, settings, meta)
	if not ok_current_config or type(current_config) ~= 'table' then
		return structured_profile_status_result(validation.path or path, 'error', false, tostring(current_config or 'runtime config normalization failed'), 0, meta, validation.payload)
	end
	local diff = M.diff_durable_config(current_config, validation.payload.config)
	local state = diff.count == 0 and 'valid_match' or 'valid_diff'
	local reason = diff.count == 0 and 'runtime matches file' or 'runtime differs from file'
	return structured_profile_status_result(validation.path or path, state, true, reason, diff.count, meta, validation.payload)
end

local function apply_result_to_active_profile(current_settings, payload, meta, deps)
	deps = type(deps) == 'table' and deps or {}
	local build_durable_config = deps.build_durable_config or M.build_durable_config
	local diff_durable_config = deps.diff_durable_config or M.diff_durable_config
	if type(build_durable_config) ~= 'function' or type(diff_durable_config) ~= 'function' then
		return {
			ok = false,
			stage = 'convert',
			error = 'structured profile apply helpers unavailable',
		}
	end
	if type(payload) ~= 'table' or type(payload.config) ~= 'table' then
		return {
			ok = false,
			stage = 'convert',
			error = 'structured profile config missing',
		}
	end

	local active_profile, active_err = uc_active_config.build_active_profile_from_v2_payload(payload, {
		character = meta and meta.character or nil,
		main_job = meta and meta.main_job or nil,
		sub_job = meta and meta.sub_job or nil,
		profile_key = meta and meta.profile_key or nil,
		source = 'UC_PROFILE_V2',
		exported_at = meta and meta.exported_at or nil,
	})
	if type(active_profile) ~= 'table' then
		return {
			ok = false,
			stage = 'convert',
			error = tostring(active_err or 'structured profile active profile build failed'),
		}
	end

	local candidate, projection_err = uc_active_config.project_flat_settings(active_profile, current_settings)
	if type(candidate) ~= 'table' then
		return {
			ok = false,
			stage = 'convert',
			error = tostring(projection_err or 'structured profile projection failed'),
			active_profile = active_profile,
		}
	end

	local ok_current, candidate_config = pcall(build_durable_config, candidate, meta)
	if not ok_current or type(candidate_config) ~= 'table' then
		return {
			ok = false,
			stage = 'convert',
			error = tostring(candidate_config),
			active_profile = active_profile,
		}
	end

	local diff = diff_durable_config(candidate_config, payload.config)
	if type(diff) ~= 'table' then
		return {
			ok = false,
			stage = 'convert',
			error = 'structured profile diff helper returned invalid result',
			active_profile = active_profile,
		}
	end
	if diff.count ~= 0 then
		return {
			ok = false,
			stage = 'convert',
			error = 'structured profile conversion mismatch',
			detail = diff.differences and diff.differences[1] or nil,
			first_difference = diff.differences and diff.differences[1] or nil,
			count = diff.count,
			differences = diff.differences or {},
			active_profile = active_profile,
			candidate = candidate,
			candidate_config = candidate_config,
		}
	end

	return {
		ok = true,
		stage = 'done',
		active_profile = active_profile,
		candidate = candidate,
		projected_settings = candidate,
		candidate_config = candidate_config,
		count = diff.count,
		differences = diff.differences or {},
	}
end

function M.build_settings_candidate_from_structured_profile(current_settings, payload, meta, deps)
	return apply_result_to_active_profile(current_settings, payload, meta, deps)
end

function M.apply_structured_profile_file_to_settings(current_settings, meta, validator, deps)
	local validation = M.validate_structured_profile_file(meta, validator, deps)
	if type(validation) ~= 'table' or validation.ok ~= true or type(validation.payload) ~= 'table' then
		return validation
	end

	local apply_result = apply_result_to_active_profile(current_settings, validation.payload, meta, deps)
	if type(apply_result) ~= 'table' then
		return {
			ok = false,
			path = validation.path,
			stage = 'convert',
			error = 'structured profile apply helper returned invalid result',
		}
	end
	if apply_result.ok ~= true then
		apply_result.path = validation.path
		return apply_result
	end

	local current_config = M.build_durable_config(current_settings, meta)
	local diff = M.diff_durable_config(current_config, validation.payload.config)

	return {
		ok = true,
		path = validation.path,
		stage = 'done',
		payload = validation.payload,
		validation = validation.validation,
		active_profile = apply_result.active_profile,
		candidate = apply_result.candidate,
		projected_settings = apply_result.projected_settings,
		candidate_config = apply_result.candidate_config,
		count = diff.count,
		differences = diff.differences,
		current_config = current_config,
	}
end

return M
