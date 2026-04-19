local packets = require('packets')

local M = {}

local CATEGORY_ENGAGE = 0x02
local CATEGORY_DISENGAGE = 0x04
local CATEGORY_SWITCH_TARGET = 0x0F

local function build_action_packet(target_id, target_index, category)
	return packets.new('outgoing', 0x01A, {
		['Target'] = target_id or 0,
		['Target Index'] = target_index or 0,
		['Category'] = category,
		['Param'] = 0,
		['_unknown1'] = 0,
		['X Offset'] = 0,
		['Z Offset'] = 0,
		['Y Offset'] = 0,
	})
end

local function get_target_from_id(id)
	local tid = tonumber(id)
	if not tid or tid <= 0 then
		return nil, 'BAD_ID'
	end
	local target = windower.ffxi.get_mob_by_id(tid)
	if not target or not target.id or not target.index then
		return nil, 'TARGET_NOT_FOUND'
	end
	return target, 'OK'
end

local function get_current_target()
	local target = windower.ffxi.get_mob_by_target('t')
	if not target or not target.id or not target.index then
		return nil, 'NO_CURRENT_TARGET'
	end
	return target, 'OK'
end

function M.engage_target(target_id)
	local target, err = get_target_from_id(target_id)
	if not target then
		return false, err
	end
	local ok_new, pkt = pcall(function()
		return build_action_packet(target.id, target.index, CATEGORY_ENGAGE)
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

function M.switch_target(target_id)
	local target, err = get_target_from_id(target_id)
	if not target then
		return false, err
	end
	local ok_new, pkt = pcall(function()
		return build_action_packet(target.id, target.index, CATEGORY_SWITCH_TARGET)
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

function M.engage_current_target()
	local target, err = get_current_target()
	if not target then
		return false, err
	end
	return M.engage_target(target.id)
end

function M.disengage()
	local target = windower.ffxi.get_mob_by_target('t')
	local target_id = (target and target.id) or 0
	local target_index = (target and target.index) or 0
	local ok_new, pkt = pcall(function()
		return build_action_packet(target_id, target_index, CATEGORY_DISENGAGE)
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
