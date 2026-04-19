-- Remember last valid weaponskill per equipped weapon-skill set (signature of
-- current get_abilities().weapon_skills). Restores settings when the player
-- swaps weapons away and back without persisting a wrong WS from the UI.

require('sets')
local res = require('resources')

local MELEE_JOBS = {
	WAR = true, MNK = true, SAM = true, DRG = true, DRK = true,
}

local M = {}

local function weapon_skill_signature()
	local abilities = windower.ffxi.get_abilities()
	local ws_ids = abilities and abilities.weapon_skills or {}
	local sorted = {}
	for _, id in ipairs(ws_ids) do
		sorted[#sorted + 1] = id
	end
	table.sort(sorted)
	return table.concat(sorted, ',')
end

function M.valid_ws_name(name)
	if type(name) ~= 'string' then
		return false
	end
	if name == '' then
		return false
	end
	local abilities = windower.ffxi.get_abilities()
	local ws_ids = abilities and abilities.weapon_skills or {}
	local valid_ids = S(ws_ids)
	for _, ws_id in ipairs(ws_ids) do
		local ws = res.weapon_skills[ws_id]
		if ws and ws.en and ws.en == name then
			return true
		end
	end
	local requested = res.weapon_skills:with('en', name)
	return requested ~= nil and valid_ids:contains(requested.id)
end

function M.remember(name)
	if not M.valid_ws_name(name) then
		return
	end
	local sig = weapon_skill_signature()
	if sig == '' then
		return
	end
	_G.UC_WS_LAST_BY_SIG = _G.UC_WS_LAST_BY_SIG or {}
	_G.UC_WS_LAST_BY_SIG[sig] = name
end

function M.recall()
	local sig = weapon_skill_signature()
	if sig == '' then
		return nil
	end
	local name = (_G.UC_WS_LAST_BY_SIG or {})[sig]
	if name and M.valid_ws_name(name) then
		return name
	end
	return nil
end

--- If configured WS is invalid for current weapon but we have memory for this signature, restore settings.
--- Surfaces diagnostics via _G.UC_WS_LAST_DIAG (also sent to remote UI).
function M.sync_settings(settings)
	if type(settings) ~= 'table' then
		return
	end
	local w1, wsk = settings.ws1, settings.weaponskill
	if type(w1) ~= 'string' and w1 ~= nil then
		_G.UC_WS_LAST_DIAG = ('WS_SETTING_BAD_TYPE:ws1=%s'):format(type(w1))
		return
	end
	if type(wsk) ~= 'string' and wsk ~= nil and wsk ~= '' then
		_G.UC_WS_LAST_DIAG = ('WS_SETTING_BAD_TYPE:weaponskill=%s'):format(type(wsk))
		return
	end
	local configured = ''
	if type(w1) == 'string' and w1 ~= '' then
		configured = w1
	elseif type(wsk) == 'string' and wsk ~= '' then
		configured = wsk
	end
	if configured ~= '' and M.valid_ws_name(configured) then
		M.remember(configured)
		_G.UC_WS_LAST_DIAG = ''
		return
	end
	local mem = M.recall()
	if not mem then
		if configured == '' then
			_G.UC_WS_LAST_DIAG = 'WS_NOT_CONFIGURED'
		else
			_G.UC_WS_LAST_DIAG = ('WS_NOT_VALID_FOR_WEAPON:%s'):format(configured)
		end
		return
	end
	_G.UC_WS_LAST_DIAG = ('WS_RESTORED_FROM_MEMORY:%s'):format(mem)
	local p = windower.ffxi.get_player()
	local job = p and p.main_job or ''
	local eng = MELEE_JOBS[job] and 'melee' or 'dd2'
	if eng == 'melee' then
		settings.ws1 = mem
		settings.weaponskill = mem
	else
		settings.weaponskill = mem
		settings.ws1 = nil
	end
end

return M
