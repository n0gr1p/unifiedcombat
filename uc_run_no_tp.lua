local run_config = require('uc_run_config')
local scheduler_config = require('uc_scheduler_config')

local M = {}

local function truthy(value)
	if value == true or value == 1 then return true end
	if type(value) == 'string' then
		local lowered = value:lower()
		return lowered == 'true' or lowered == 'on' or lowered == '1' or lowered == 'yes'
	end
	return false
end

local function valid_enemy(target)
	return type(target) == 'table'
		and target.valid_target == true
		and tonumber(target.spawn_type) == 16
		and (tonumber(target.hpp) or 0) > 0
		and (tonumber(target.id) or 0) > 0
end

function M.enabled(settings, player)
	if type(player) ~= 'table' or tostring(player.main_job or '') ~= 'RUN' then
		return false
	end
	if tonumber(player.status) ~= 1 then
		return false
	end
	if not truthy(scheduler_config.tank_enabled(settings)) then
		return false
	end
	local cfg = run_config.active(settings)
	return cfg.enabled == true and cfg.no_tp_mode == true
end

function M.target_id(settings, player, target)
	if not M.enabled(settings, player) or not valid_enemy(target) then
		return 0
	end
	return tonumber(target.id) or 0
end

return M
