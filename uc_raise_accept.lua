local active_config = require('uc_active_config')
local uc_time = require('uc_time')

local M = {}

M.RAISE_DIALOG_PACKET_ID = 0x0F9
M.ACTION_PACKET_ID = 0x01A
M.RAISE_DIALOG_CATEGORY = 0x01
M.RAISE_ACCEPT_ACTION_CATEGORY = 0x0D
M.RAISE_ACCEPT_DEDUPE_S = 2.0

local DEAD_STATUS = {
	[2] = true,
	[3] = true,
}

local runtime = {
	registered = false,
	last_accept_at = nil,
	accept_count = 0,
	last_reason = '',
}

local function log(message)
	local line = tostring(message or '')
	local diag = rawget(_G, 'UC_LOG_DIAG')
	if type(diag) == 'function' then
		pcall(diag, 'recovery', line)
	end
end

local function current_player_mob()
	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	if type(ffxi) ~= 'table' then
		return nil
	end

	if type(ffxi.get_mob_by_target) == 'function' then
		local ok, mob = pcall(ffxi.get_mob_by_target, 'me')
		if ok and type(mob) == 'table' then
			return mob
		end
	end

	local player = nil
	if type(ffxi.get_player) == 'function' then
		local ok, value = pcall(ffxi.get_player)
		if ok and type(value) == 'table' then
			player = value
		end
	end
	if player and type(ffxi.get_mob_by_id) == 'function' and tonumber(player.id) then
		local ok, mob = pcall(ffxi.get_mob_by_id, tonumber(player.id))
		if ok and type(mob) == 'table' then
			return mob
		end
	end
	return player
end

function M.setting_enabled()
	local ok, configured = pcall(active_config.get_path, 'config.ownership.auto_accept_raise')
	return ok and configured == true
end

function M.player_is_dead(player)
	return type(player) == 'table' and DEAD_STATUS[tonumber(player.status)] == true
end

local function is_raise_dialogue(packet)
	if type(packet) ~= 'table' then
		return false
	end
	local category = packet['Category']
	if tonumber(category) == M.RAISE_DIALOG_CATEGORY then
		return true
	end
	return tostring(category or ''):lower() == 'raise dialogue'
end

local function inject_accept(player)
	local packets = require('packets')
	local target_id = tonumber(player and player.id) or 0
	local target_index = tonumber(player and player.index) or 0
	if target_id <= 0 or target_index <= 0 then
		return false, 'PLAYER_IDENTITY_UNAVAILABLE'
	end

	local ok_new, packet = pcall(packets.new, 'outgoing', M.ACTION_PACKET_ID, {
		['Target'] = target_id,
		['Target Index'] = target_index,
		['Category'] = M.RAISE_ACCEPT_ACTION_CATEGORY,
		['Param'] = 0,
	})
	if not ok_new or type(packet) ~= 'table' then
		return false, 'PACKET_BUILD_FAIL'
	end
	local ok_inject = pcall(function()
		packets.inject(packet)
	end)
	if not ok_inject then
		return false, 'PACKET_INJECT_FAIL'
	end
	return true
end

function M.on_incoming_chunk(id, data, at)
	if tonumber(id) ~= M.RAISE_DIALOG_PACKET_ID then
		return false, 'NOT_RAISE_PACKET'
	end
	if not M.setting_enabled() then
		runtime.last_reason = 'DISABLED'
		return false, runtime.last_reason
	end

	local packets = require('packets')
	local ok_parse, packet = pcall(packets.parse, 'incoming', data)
	if not ok_parse or type(packet) ~= 'table' then
		runtime.last_reason = 'PACKET_PARSE_FAIL'
		log('RAISE_ACCEPT_REJECT reason=' .. runtime.last_reason)
		return false, runtime.last_reason
	end
	if not is_raise_dialogue(packet) then
		runtime.last_reason = 'NOT_RAISE_DIALOGUE'
		return false, runtime.last_reason
	end

	local player = current_player_mob()
	if not M.player_is_dead(player) then
		runtime.last_reason = 'PLAYER_NOT_DEAD'
		log('RAISE_ACCEPT_REJECT reason=' .. runtime.last_reason)
		return false, runtime.last_reason
	end

	local now = tonumber(at) or uc_time.now()
	if runtime.last_accept_at ~= nil
		and (now - runtime.last_accept_at) < M.RAISE_ACCEPT_DEDUPE_S then
		runtime.last_reason = 'DUPLICATE_GATE'
		return false, runtime.last_reason
	end

	local accepted, reason = inject_accept(player)
	if not accepted then
		runtime.last_reason = tostring(reason or 'INJECT_FAILED')
		log('RAISE_ACCEPT_REJECT reason=' .. runtime.last_reason)
		return false, runtime.last_reason
	end

	runtime.last_accept_at = now
	runtime.accept_count = runtime.accept_count + 1
	runtime.last_reason = 'ACCEPTED'
	log(('RAISE_ACCEPT dialog=raise source=0x0F9 count=%d'):format(runtime.accept_count))

	local windower_ref = rawget(_G, 'windower')
	if type(windower_ref) == 'table' and type(windower_ref.add_to_chat) == 'function' then
		pcall(windower_ref.add_to_chat, 207, 'UnifiedCombat: accepted Raise.')
	end
	return true, runtime.last_reason
end

function M.reset_runtime()
	runtime.last_accept_at = nil
	runtime.accept_count = 0
	runtime.last_reason = ''
end

function M.status()
	return {
		registered = runtime.registered,
		last_accept_at = runtime.last_accept_at,
		accept_count = runtime.accept_count,
		last_reason = runtime.last_reason,
	}
end

function M.register()
	if runtime.registered then
		return true
	end
	local windower_ref = rawget(_G, 'windower')
	if type(windower_ref) ~= 'table' or type(windower_ref.register_event) ~= 'function' then
		return false, 'WINDOWER_EVENT_API_UNAVAILABLE'
	end

	windower_ref.register_event('incoming chunk', function(id, data)
		local ok, err = pcall(M.on_incoming_chunk, id, data)
		if not ok then
			log('RAISE_ACCEPT_ERROR reason=' .. tostring(err))
		end
	end)
	windower_ref.register_event('zone change', function()
		M.reset_runtime()
	end)
	windower_ref.register_event('logout', function()
		M.reset_runtime()
	end)
	windower_ref.register_event('unload', function()
		M.reset_runtime()
	end)

	runtime.registered = true
	return true
end

M._test = {
	runtime = runtime,
	is_raise_dialogue = is_raise_dialogue,
	inject_accept = inject_accept,
}

return M
