local packets = require('packets')
local uc_time = require('uc_time')

local M = {}

local TARGET_UNLOCK_TIMEOUT_S = 1.0
local pending_unlock_target_id = nil
local pending_unlock_deadline = 0

local function clear_pending_unlock()
	pending_unlock_target_id = nil
	pending_unlock_deadline = 0
end

local function arm_pending_unlock(target)
	if type(target) ~= 'table' or tonumber(target.spawn_type) ~= 16 then
		clear_pending_unlock()
		return
	end
	pending_unlock_target_id = tonumber(target.id) or 0
	pending_unlock_deadline = uc_time.now() + TARGET_UNLOCK_TIMEOUT_S
end

function M.on_prerender()
	local tid = tonumber(pending_unlock_target_id) or 0
	if tid <= 0 then
		return false, 'NO_PENDING_UNLOCK'
	end
	if uc_time.now() > (tonumber(pending_unlock_deadline) or 0) then
		clear_pending_unlock()
		return false, 'UNLOCK_TIMEOUT'
	end
	local current = windower.ffxi.get_mob_by_target('t')
	if not current or tonumber(current.id) ~= tid then
		return false, 'TARGET_NOT_SELECTED_YET'
	end
	clear_pending_unlock()
	local ok = pcall(function()
		windower.send_command('@input /lockon')
	end)
	if not ok then
		return false, 'UNLOCK_COMMAND_FAIL'
	end
	return true, 'UNLOCKED'
end

-- Internal SetTarget-equivalent selector.
-- No command fallback by design; callers must handle false return explicitly.
function M.select_by_id(id)
	local tid = tonumber(id)
	if not tid or tid <= 0 then
		return false, 'BAD_ID'
	end
	local target = windower.ffxi.get_mob_by_id(tid)
	if not target or not target.id then
		return false, 'TARGET_NOT_FOUND'
	end
	local player = windower.ffxi.get_player()
	if not player or not player.id or not player.index then
		return false, 'PLAYER_NOT_READY'
	end
	local ok_new, pkt = pcall(function()
		return packets.new('incoming', 0x058, {
			['Player'] = player.id,
			['Target'] = target.id,
			['Player Index'] = player.index,
		})
	end)
	if not ok_new or not pkt then
		return false, 'PACKET_BUILD_FAIL'
	end
	local ok_inj = pcall(function()
		packets.inject(pkt)
	end)
	if not ok_inj then
		return false, 'PACKET_INJECT_FAIL'
	end
	arm_pending_unlock(target)
	return true, 'OK'
end

if type(windower) == 'table' and type(windower.register_event) == 'function' then
	windower.register_event('prerender', M.on_prerender)
end

return M
