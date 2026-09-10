local M = {
	MODULE_NAME = 'uc_runtime_bootstrap',
	SCHEMA_VERSION = 1,
	EXPECTED_SCHEDULER_REVISION = '20260910-sequence-dispatch-2',
	EXPECTED_ENGINE_REVISION = '20260910-runtime-refresh-1',
}

local SOURCE_FILES = {
	'UnifiedCombat.lua',
	'unified_engine.lua',
	'unified_scheduler.lua',
	'unified_combat_core.lua',
	'uc_reaction_runtime.lua',
	'uc_reaction_sequence_runtime.lua',
	'uc_combat_extensions_sequence.lua',
	'uc_scheduler_command_ownership.lua',
	'uc_smn_pet_combat_adapter.lua',
	'uc_pet_commands.lua',
	'uc_runtime_bootstrap.lua',
}

local function normalize_addon_path(path)
	if type(path) ~= 'string' or path == '' then
		return nil
	end
	path = path:gsub('\\', '/')
	if path:sub(-1) ~= '/' then
		path = path .. '/'
	end
	return path
end

local function trim(value)
	if type(value) ~= 'string' then
		return ''
	end
	return value:match('^%s*(.-)%s*$') or ''
end

local function read_all(path)
	local fh, err = io.open(path, 'rb')
	if not fh then
		return nil, err
	end
	local ok, content = pcall(function()
		return fh:read('*a')
	end)
	pcall(function()
		fh:close()
	end)
	if not ok then
		return nil, content
	end
	return content
end

local function read_first_line(path)
	local content = read_all(path)
	if type(content) ~= 'string' then
		return nil
	end
	local line = content:match('([^\r\n]+)')
	line = trim(line)
	if line == '' then
		return nil
	end
	return line
end

local function hash_update(hash, text)
	for i = 1, #text do
		hash = (hash * 33 + text:byte(i)) % 4294967296
	end
	return hash
end

local function hash_text(text)
	return string.format('%08x', hash_update(5381, tostring(text or '')))
end

local function hash_file(path)
	local fh, err = io.open(path, 'rb')
	if not fh then
		return nil, err
	end
	local hash = 5381
	while true do
		local chunk = fh:read(65536)
		if chunk == nil then
			break
		end
		hash = hash_update(hash, chunk)
	end
	pcall(function()
		fh:close()
	end)
	return string.format('%08x', hash)
end

local function is_absolute_path(path)
	if path:sub(1, 1) == '/' then
		return true
	end
	return path:match('^%a:[/\\]') ~= nil
end

local function normalize_dir(path)
	if type(path) ~= 'string' or path == '' then
		return nil
	end
	path = path:gsub('\\', '/')
	if path:sub(-1) ~= '/' then
		path = path .. '/'
	end
	return path
end

local function git_dir(addon_path)
	local direct_head = addon_path .. '.git/HEAD'
	if read_first_line(direct_head) ~= nil then
		return addon_path .. '.git/'
	end
	local git_file = read_first_line(addon_path .. '.git')
	if git_file == nil then
		return nil
	end
	local path = trim(git_file:match('^gitdir:%s*(.+)$'))
	if path == '' then
		return nil
	end
	if not is_absolute_path(path) then
		path = addon_path .. path
	end
	return normalize_dir(path)
end

local function git_head(addon_path)
	local dir = git_dir(addon_path)
	if dir == nil then
		return 'unavailable'
	end
	local head = read_first_line(dir .. 'HEAD')
	if head == nil then
		return 'unavailable'
	end
	local ref = trim(head:match('^ref:%s*(.+)$'))
	local sha = nil
	if ref ~= '' then
		sha = read_first_line(dir .. ref)
		if sha == nil then
			local packed = read_all(dir .. 'packed-refs')
			if type(packed) == 'string' then
				for line in packed:gmatch('[^\r\n]+') do
					if line:sub(1, 1) ~= '#' and line:sub(1, 1) ~= '^' then
						local packed_sha, packed_ref = line:match('^(%x+)%s+(.+)$')
						if packed_ref == ref then
							sha = packed_sha
							break
						end
					end
				end
			end
		end
	else
		sha = head
	end
	sha = trim(sha)
	if sha:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') then
		return sha:sub(1, 12)
	end
	return 'unavailable'
end

local function owned_module(name)
	if type(name) ~= 'string' then
		return false
	end
	return name == 'remote_bridge'
		or name:match('^uc_') ~= nil
		or name:match('^unified_') ~= nil
end

local function purge_loaded_modules()
	local purge = {}
	for name in pairs(package.loaded) do
		if name ~= M.MODULE_NAME and owned_module(name) then
			purge[#purge + 1] = name
		end
	end
	table.sort(purge)
	for i = 1, #purge do
		package.loaded[purge[i]] = nil
	end
	return purge
end

local function source_fingerprints(addon_path)
	local files = {}
	local combined = {}
	for i = 1, #SOURCE_FILES do
		local relative = SOURCE_FILES[i]
		local digest, err = hash_file(addon_path .. relative)
		if digest == nil then
			digest = 'missing:' .. tostring(err or 'unknown')
		end
		files[relative] = digest
		combined[#combined + 1] = relative .. '=' .. digest
	end
	return files, hash_text(table.concat(combined, '\n'))
end

function M.begin(options)
	options = type(options) == 'table' and options or {}
	local addon_path = normalize_addon_path(options.addon_path)
	if addon_path == nil then
		error('UnifiedCombat runtime bootstrap requires windower.addon_path')
	end
	local purged = purge_loaded_modules()
	local files, source_fingerprint = source_fingerprints(addon_path)
	local status = {
		schema_version = M.SCHEMA_VERSION,
		addon_path = addon_path,
		git_revision = git_head(addon_path),
		source_fingerprint = source_fingerprint,
		files = files,
		purged_modules = purged,
		purged_count = #purged,
		expected_scheduler_revision = M.EXPECTED_SCHEDULER_REVISION,
		expected_engine_revision = M.EXPECTED_ENGINE_REVISION,
		integrity_ok = nil,
		integrity_error = '',
	}
	_G.UC_RUNTIME_FINGERPRINT = status
	return status
end

function M.finalize(status, modules)
	if type(status) ~= 'table' then
		error('UnifiedCombat runtime bootstrap status must be a table')
	end
	modules = type(modules) == 'table' and modules or {}
	local scheduler = modules.scheduler
	local engine = modules.engine
	status.scheduler_revision = type(scheduler) == 'table' and tostring(scheduler.runtime_revision or '') or ''
	status.engine_revision = type(engine) == 'table' and tostring(engine.runtime_revision or '') or ''
	local problems = {}
	if status.scheduler_revision ~= M.EXPECTED_SCHEDULER_REVISION then
		problems[#problems + 1] = 'scheduler expected=' .. M.EXPECTED_SCHEDULER_REVISION
			.. ' loaded=' .. (status.scheduler_revision ~= '' and status.scheduler_revision or 'missing')
	end
	if status.engine_revision ~= M.EXPECTED_ENGINE_REVISION then
		problems[#problems + 1] = 'engine expected=' .. M.EXPECTED_ENGINE_REVISION
			.. ' loaded=' .. (status.engine_revision ~= '' and status.engine_revision or 'missing')
	end
	status.integrity_ok = #problems == 0
	status.integrity_error = table.concat(problems, '; ')
	_G.UC_RUNTIME_FINGERPRINT = status
	return status.integrity_ok, status
end

function M.timeline_fields(status)
	status = type(status) == 'table' and status or {}
	return {
		git = tostring(status.git_revision or 'unavailable'),
		source = tostring(status.source_fingerprint or 'unavailable'),
		scheduler = tostring(status.scheduler_revision or 'missing'),
		engine = tostring(status.engine_revision or 'missing'),
		purged = tonumber(status.purged_count) or 0,
		integrity = status.integrity_ok == true and 'ok' or 'failed',
	}
end

function M.summary_line(status)
	local fields = M.timeline_fields(status)
	return ('UnifiedCombat runtime: git=%s source=%s scheduler=%s engine=%s purged=%d integrity=%s'):format(
		fields.git,
		fields.source,
		fields.scheduler,
		fields.engine,
		fields.purged,
		fields.integrity
	)
end

function M.status_lines(status)
	status = type(status) == 'table' and status or {}
	local lines = { M.summary_line(status) }
	for i = 1, #SOURCE_FILES do
		local relative = SOURCE_FILES[i]
		local digest = type(status.files) == 'table' and status.files[relative] or nil
		lines[#lines + 1] = ('  %s=%s'):format(relative, tostring(digest or 'unavailable'))
	end
	local purged = type(status.purged_modules) == 'table' and status.purged_modules or {}
	if #purged == 0 then
		lines[#lines + 1] = '  purged modules: none'
	else
		local index = 1
		while index <= #purged do
			local chunk = {}
			for i = index, math.min(index + 7, #purged) do
				chunk[#chunk + 1] = purged[i]
			end
			lines[#lines + 1] = '  purged modules: ' .. table.concat(chunk, ',')
			index = index + 8
		end
	end
	if status.integrity_ok == false then
		lines[#lines + 1] = '  integrity error: ' .. tostring(status.integrity_error or 'unknown')
	end
	return lines
end

return M
