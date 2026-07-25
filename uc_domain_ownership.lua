local active_config = require('uc_active_config')

local M = {}

local DOMAIN_PATHS = {
	combat = 'config.ownership.domain_combat_enabled',
	defensive = 'config.ownership.domain_defensive_enabled',
	movement = 'config.ownership.domain_movement_enabled',
	maintenance = 'config.ownership.domain_maintenance_enabled',
}

local LEGACY_MARKER_PATHS = {
	combat = 'config.ownership.scheduler_dark_launch_combat',
	defensive = 'config.ownership.scheduler_dark_launch_defensive',
	movement = 'config.ownership.scheduler_dark_launch_movement',
	maintenance = 'config.ownership.scheduler_dark_launch_maintenance',
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

-- The scheduler_dark_launch_* fields remain in the profile contract until a
-- profile migration can remove them. Phase 5 does not use them to select a
-- runtime execution path.
function M.legacy_marker(domain)
	return require_boolean(path_for(LEGACY_MARKER_PATHS, domain))
end

function M.snapshot()
	return {
		combat = M.is_enabled('combat'),
		defensive = M.is_enabled('defensive'),
		movement = M.is_enabled('movement'),
		maintenance = M.is_enabled('maintenance'),
		legacy_markers = {
			combat = M.legacy_marker('combat'),
			defensive = M.legacy_marker('defensive'),
			movement = M.legacy_marker('movement'),
			maintenance = M.legacy_marker('maintenance'),
		},
	}
end

return M
