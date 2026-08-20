local active_config = require('uc_active_config')

local M = {}

M.WEAKNESS_BUFF_ID = 1
M.BLOCK_REASON = 'RECOVERY_HOLD_WEAKNESS'

local runtime = {
	active = false,
	transition_count = 0,
}

local function truthy(value)
	if value == true or value == 1 then
		return true
	end
	if type(value) == 'string' then
		local normalized = value:lower()
		return normalized == 'true' or normalized == 'on'
			or normalized == '1' or normalized == 'yes'
	end
	return false
end

local function current_player()
	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	if type(ffxi) ~= 'table' or type(ffxi.get_player) ~= 'function' then
		return nil
	end
	local ok, player = pcall(ffxi.get_player)
	if not ok then
		return nil
	end
	return player
end

function M.validate_resources(buffs)
	if type(buffs) ~= 'table' then
		error('recovery hold requires the Windower buff resource table')
	end
	local weakness = buffs[M.WEAKNESS_BUFF_ID]
	local name = type(weakness) == 'table' and tostring(weakness.en or ''):lower() or ''
	if name ~= 'weakness' then
		error('Windower buff id 1 must resolve to weakness')
	end
	return true
end

function M.setting_enabled(settings)
	local configured = active_config.get_path('config.ownership.pause_automation_while_weakened')
	if configured ~= nil then
		return configured == true
	end
	return truthy(type(settings) == 'table' and settings.pause_automation_while_weakened or nil)
end

function M.player_is_weakened(player)
	local buffs = type(player) == 'table' and player.buffs or nil
	if type(buffs) ~= 'table' then
		return false
	end
	-- Windower exposes both normal and repeated-death/double weakness as buff id 1.
	for _, buff_id in pairs(buffs) do
		if tonumber(buff_id) == M.WEAKNESS_BUFF_ID then
			return true
		end
	end
	return false
end

function M.active(settings, player)
	if not M.setting_enabled(settings) then
		return false
	end
	return M.player_is_weakened(player or current_player())
end

function M.current()
	return M.active(rawget(_G, 'UC_SETTINGS'), nil)
end

local function publish(active)
	_G.UC_RECOVERY_HOLD_ACTIVE = active == true
	_G.UC_RECOVERY_HOLD_STATUS = active == true and 'Weakness' or ''
end

function M.update(settings, player, hooks)
	local next_active = M.active(settings, player)
	local entered = next_active and not runtime.active
	local cleared = runtime.active and not next_active
	runtime.active = next_active
	if entered or cleared then
		runtime.transition_count = runtime.transition_count + 1
	end
	publish(next_active)

	local callbacks = type(hooks) == 'table' and hooks or {}
	if entered and type(callbacks.on_enter) == 'function' then
		callbacks.on_enter()
	elseif cleared and type(callbacks.on_clear) == 'function' then
		callbacks.on_clear()
	end

	return {
		active = next_active,
		entered = entered,
		cleared = cleared,
		reason = next_active and M.BLOCK_REASON or '',
		transition_count = runtime.transition_count,
	}
end

function M.status()
	return {
		active = runtime.active,
		reason = runtime.active and M.BLOCK_REASON or '',
		transition_count = runtime.transition_count,
	}
end

function M.reset_runtime()
	runtime.active = false
	runtime.transition_count = 0
	publish(false)
end

return M
