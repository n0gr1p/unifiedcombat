local M = {}

local SCHEMA_VERSION = 1

local TYPE_ORDER = {
	number = 1,
	string = 2,
	boolean = 3,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(value, name)
	if type(value) ~= 'function' then
		error(name .. ' must be a function')
	end
	return value
end

local function require_number(value, name)
	if type(value) ~= 'number' then
		error(name .. ' must be a number')
	end
	return value
end

local function require_safe_component(value, name)
	if type(value) ~= 'string' or value == '' then
		error(name .. ' must be a non-empty string')
	end
	if value:match('^[%w_-]+$') == nil then
		error(name .. ' may contain letters, numbers, underscore, and hyphen only')
	end
	return value
end

local function join_path(left, right)
	if type(left) ~= 'string' or left == '' then
		error('Scholar capture base path must be a non-empty string')
	end
	if type(right) ~= 'string' or right == '' then
		error('Scholar capture path component must be a non-empty string')
	end
	local tail = left:sub(-1)
	if tail == '\\' or tail == '/' then
		return left .. right
	end
	return left .. '\\' .. right
end

local function sorted_keys(value)
	local keys = {}
	for key in pairs(value) do
		local key_type = type(key)
		if TYPE_ORDER[key_type] == nil then
			error('Scholar capture table keys must be number, string, or boolean')
		end
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		local left_type = type(left)
		local right_type = type(right)
		if left_type ~= right_type then
			return TYPE_ORDER[left_type] < TYPE_ORDER[right_type]
		end
		if left_type == 'number' then
			return left < right
		end
		return tostring(left) < tostring(right)
	end)
	return keys
end

local function quoted_string(value)
	local out = { '"' }
	for index = 1, #value do
		local byte = value:byte(index)
		if byte == 34 then
			out[#out + 1] = '\\"'
		elseif byte == 92 then
			out[#out + 1] = '\\\\'
		elseif byte == 10 then
			out[#out + 1] = '\\n'
		elseif byte == 13 then
			out[#out + 1] = '\\r'
		elseif byte == 9 then
			out[#out + 1] = '\\t'
		elseif byte < 32 or byte == 127 then
			out[#out + 1] = ('\\%03d'):format(byte)
		else
			out[#out + 1] = string.char(byte)
		end
	end
	out[#out + 1] = '"'
	return table.concat(out)
end

local function serialize_value(value, seen)
	local value_type = type(value)
	if value_type == 'nil' then
		return 'nil'
	elseif value_type == 'number' then
		if value ~= value or value == math.huge or value == -math.huge then
			error('Scholar capture numbers must be finite')
		end
		return tostring(value)
	elseif value_type == 'boolean' then
		return value and 'true' or 'false'
	elseif value_type == 'string' then
		return quoted_string(value)
	elseif value_type ~= 'table' then
		error('Scholar capture values must be serializable Lua data')
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar capture values must not contain cycles')
	end
	visited[value] = true
	local parts = { '{' }
	local keys = sorted_keys(value)
	for index = 1, #keys do
		local key = keys[index]
		parts[#parts + 1] = '['
		parts[#parts + 1] = serialize_value(key, visited)
		parts[#parts + 1] = ']='
		parts[#parts + 1] = serialize_value(value[key], visited)
		parts[#parts + 1] = ','
	end
	parts[#parts + 1] = '}'
	visited[value] = nil
	return table.concat(parts)
end

local function production_dependencies()
	return {
		addon_path = function()
			local windower_ref = rawget(_G, 'windower')
			if type(windower_ref) ~= 'table'
				or type(windower_ref.addon_path) ~= 'string'
				or windower_ref.addon_path == '' then
				error('windower.addon_path is unavailable for Scholar capture')
			end
			return windower_ref.addon_path
		end,
		dir_exists = function(path)
			local windower_ref = rawget(_G, 'windower')
			if type(windower_ref) ~= 'table'
				or type(windower_ref.dir_exists) ~= 'function' then
				error('windower.dir_exists is unavailable for Scholar capture')
			end
			return windower_ref.dir_exists(path)
		end,
		create_dir = function(path)
			local windower_ref = rawget(_G, 'windower')
			if type(windower_ref) ~= 'table'
				or type(windower_ref.create_dir) ~= 'function' then
				error('windower.create_dir is unavailable for Scholar capture')
			end
			return windower_ref.create_dir(path)
		end,
		open_file = function(path, mode)
			return io.open(path, mode)
		end,
		file_exists = function(path)
			local handle = io.open(path, 'rb')
			if handle == nil then
				return false
			end
			handle:close()
			return true
		end,
		file_stamp = function()
			return os.date('!%Y%m%dT%H%M%SZ')
		end,
	}
end

local function resolved_dependencies(deps)
	local production = production_dependencies()
	if deps == nil then
		return production
	end
	require_table(deps, 'Scholar capture dependencies')
	local names = {
		'addon_path', 'dir_exists', 'create_dir', 'open_file', 'file_exists', 'file_stamp',
	}
	local out = {}
	for index = 1, #names do
		local name = names[index]
		out[name] = require_function(deps[name], 'Scholar capture deps.' .. name)
	end
	return out
end

function M.new(deps)
	deps = resolved_dependencies(deps)
	local recorder = {
		active = nil,
		last = nil,
		last_sample_signature = '',
	}

	local function write_entry(entry)
		local active = recorder.active
		if active == nil then
			error('Scholar capture is not active')
		end
		local line = 'return ' .. serialize_value(entry) .. '\n'
		local write_result, write_error = active.handle:write(line)
		if write_result == nil then
			error('Scholar capture write failed: ' .. tostring(write_error))
		end
		local flush_result, flush_error = active.handle:flush()
		if flush_result == nil then
			error('Scholar capture flush failed: ' .. tostring(flush_error))
		end
	end

	function recorder.start(meta, now)
		require_table(meta, 'Scholar capture metadata')
		now = require_number(now, 'Scholar capture start time')
		if recorder.active ~= nil then
			return false, 'Scholar capture is already active.', recorder.active.path
		end
		local label = require_safe_component(meta.label, 'Scholar capture label')
		local character = require_safe_component(meta.character, 'Scholar capture character')
		local main_job = require_safe_component(meta.main_job, 'Scholar capture main job')
		local sub_job = require_safe_component(meta.sub_job, 'Scholar capture sub job')
		if main_job ~= 'SCH' then
			error('Scholar capture main job must be SCH')
		end
		local addon_path = deps.addon_path()
		local data_path = join_path(addon_path, 'data')
		if deps.dir_exists(data_path) ~= true then
			error('Scholar capture requires the addon data directory: ' .. data_path)
		end
		local capture_path = join_path(data_path, 'sch_captures')
		if deps.dir_exists(capture_path) ~= true then
			deps.create_dir(capture_path)
			if deps.dir_exists(capture_path) ~= true then
				error('Scholar capture output directory could not be created: ' .. capture_path)
			end
		end
		local file_name = character .. '_' .. label .. '_' .. require_safe_component(
			deps.file_stamp(),
			'Scholar capture timestamp'
		) .. '.lua.log'
		local path = join_path(capture_path, file_name)
		if deps.file_exists(path) then
			error('Scholar capture output path already exists: ' .. path)
		end
		local handle, open_error = deps.open_file(path, 'wb')
		if handle == nil then
			error('Scholar capture output open failed: ' .. tostring(open_error))
		end
		recorder.active = {
			path = path,
			handle = handle,
			label = label,
			character = character,
			current_mark = 'session_start',
			started_at = now,
			trace_count = 0,
		}
		recorder.last_sample_signature = ''
		write_entry({
			kind = 'session_start',
			schema_version = SCHEMA_VERSION,
			label = label,
			character = character,
			main_job = main_job,
			sub_job = sub_job,
			started_at = now,
		})
		return true, 'Scholar capture started.', path
	end

	function recorder.mark(label, now)
		now = require_number(now, 'Scholar capture mark time')
		if recorder.active == nil then
			return false, 'Scholar capture is not active.'
		end
		label = require_safe_component(label, 'Scholar capture mark')
		recorder.active.current_mark = label
		write_entry({
			kind = 'mark',
			label = label,
			at = now,
		})
		return true, 'Scholar capture mark recorded: ' .. label
	end

	function recorder.record_trace(record, now)
		require_table(record, 'Scholar capture trace record')
		now = require_number(now, 'Scholar capture trace time')
		if recorder.active == nil then
			return false, 'Scholar capture is not active.'
		end
		recorder.active.trace_count = recorder.active.trace_count + 1
		write_entry({
			kind = 'trace',
			mark = recorder.active.current_mark,
			trace_index = recorder.active.trace_count,
			recorded_at = now,
			record = record,
		})
		return true, 'Scholar trace persisted.'
	end

	function recorder.record_sample(sample, now)
		require_table(sample, 'Scholar capture sample')
		now = require_number(now, 'Scholar capture sample time')
		if recorder.active == nil then
			return false, 'Scholar capture is not active.'
		end
		local sample_signature = serialize_value(sample)
		if sample_signature == recorder.last_sample_signature then
			return false, 'Scholar capture sample is unchanged.'
		end
		recorder.last_sample_signature = sample_signature
		write_entry({
			kind = 'sample',
			mark = recorder.active.current_mark,
			recorded_at = now,
			sample = sample,
		})
		return true, 'Scholar sample persisted.'
	end

	function recorder.stop(reason, now)
		now = require_number(now, 'Scholar capture stop time')
		if recorder.active == nil then
			return false, 'Scholar capture is not active.', nil
		end
		if type(reason) ~= 'string' or reason == '' then
			error('Scholar capture stop reason must be a non-empty string')
		end
		local active = recorder.active
		write_entry({
			kind = 'session_stop',
			reason = reason,
			stopped_at = now,
			trace_count = active.trace_count,
		})
		local close_result, close_error = active.handle:close()
		if close_result == nil then
			error('Scholar capture close failed: ' .. tostring(close_error))
		end
		recorder.last = {
			path = active.path,
			label = active.label,
			character = active.character,
			trace_count = active.trace_count,
			started_at = active.started_at,
			stopped_at = now,
			reason = reason,
		}
		recorder.active = nil
		recorder.last_sample_signature = ''
		return true, 'Scholar capture stopped.', recorder.last.path
	end

	function recorder.status()
		if recorder.active ~= nil then
			return {
				active = true,
				path = recorder.active.path,
				label = recorder.active.label,
				mark = recorder.active.current_mark,
				trace_count = recorder.active.trace_count,
				started_at = recorder.active.started_at,
			}
		end
		return {
			active = false,
			last = recorder.last,
		}
	end

	return recorder
end

return M
