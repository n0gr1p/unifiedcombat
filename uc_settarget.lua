local packets = require('packets')

local M = {}

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
	return true, 'OK'
end

return M
