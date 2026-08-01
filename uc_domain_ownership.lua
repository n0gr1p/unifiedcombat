local active_config = require('uc_active_config')

local M = {}

local DOMAIN_PATHS = {
	combat = 'config.ownership.domain_combat_enabled',
	defensive = 'config.ownership.domain_defensive_enabled',
	movement = 'config.ownership.domain_movement_enabled',
	maintenance = 'config.ownership.domain_maintenance_enabled',
}

local function path_for(paths, domain)
	local name = tostring(domain or '')
	local path = paths[name]
	if path == nil then
		error('uc_domain_ownership unknown domain: ' .. name)
	end
	return path
end

local function require_boolean(path)
	local value = active_config.get_path(path)
	if type(value) ~= 'boolean' then
		error('uc_domain_ownership requires boolean active config at ' .. path)
	end
	return value
end

function M.is_enabled(domain)
	return require_boolean(path_for(DOMAIN_PATHS, domain))
end

function M.snapshot()
	return {
		combat = M.is_enabled('combat'),
		defensive = M.is_enabled('defensive'),
		movement = M.is_enabled('movement'),
		maintenance = M.is_enabled('maintenance'),
	}
end

return M
