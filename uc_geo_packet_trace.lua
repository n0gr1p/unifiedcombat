---@diagnostic disable: undefined-global

local M = {}

local packets = require('packets')
local res = require('resources')

local ACTION_PACKET_ID = 0x01A
local MAGIC_CATEGORY = 0x03
local PET_OBSERVE_TIMEOUT_S = 6.0
local PET_OBSERVE_INTERVAL_S = 0.20

local socket_ok, socket_mod = pcall(require, 'socket')
local socket_gettime = socket_ok and type(socket_mod) == 'table' and socket_mod.gettime or nil
local trace_sequence = 0

local function now_s()
	if type(socket_gettime) == 'function' then
		return socket_gettime()
	end
	return os.time()
end

local function timestamp()
	local now = now_s()
	local base = os.date('%Y-%m-%d %H:%M:%S')
	local ms = math.floor((now % 1) * 1000)
	return ('%s.%03d'):format(base, ms)
end

local function finite_number(value)
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

local function path_sep()
	return package.config:sub(1, 1) == '\\' and '\\' or '/'
end

local function safe_char_name(name)
	local n = tostring(name or 'unknown'):lower():gsub('[^%w%-_]+', '_')
	if n == '' then
		return 'unknown'
	end
	return n
end

local function ensure_log_dir()
	local ap = windower and windower.addon_path or nil
	if type(ap) ~= 'string' or ap == '' then
		return nil
	end
	local sep = path_sep()
	local data_dir = ap .. 'data' .. sep
	local log_dir = data_dir .. 'logs' .. sep
	if type(windower) == 'table' and windower.dir_exists and windower.create_dir then
		if not windower.dir_exists(data_dir) then
			windower.create_dir(data_dir)
		end
		if not windower.dir_exists(log_dir) then
			windower.create_dir(log_dir)
		end
	end
	return log_dir
end

local function append_log(text)
	if type(text) ~= 'string' or text == '' then
		return false
	end
	local ok = pcall(function()
		local player = windower.ffxi.get_player()
		local dir = ensure_log_dir()
		if not dir then
			return
		end
		local path = dir .. safe_char_name(player and player.name) .. '_geo_packet_trace.log'
		local file = io.open(path, 'a')
		if not file then
			return
		end
		file:write(timestamp(), '\t', text:gsub('\r?\n', ' '), '\n')
		file:close()
	end)
	return ok
end

local function hex_bytes(raw)
	if type(raw) ~= 'string' then
		return ''
	end
	local out = {}
	for i = 1, #raw do
		out[#out + 1] = ('%02X'):format(raw:byte(i))
	end
	return table.concat(out, ' ')
end

local function spell_by_id(spell_id)
	local id = tonumber(spell_id)
	if id == nil then
		return nil
	end
	local spell = res.spells and res.spells[id] or nil
	if spell == nil and res.spells and type(res.spells.with) == 'function' then
		spell = res.spells:with('id', id)
	end
	return spell
end

local function is_geo_spell(spell)
	local name = type(spell) == 'table' and tostring(spell.en or '') or ''
	return name:match('^Geo%-') ~= nil
end

local function mob_by_id(id)
	local target_id = tonumber(id)
	if target_id == nil or target_id <= 0 then
		return nil
	end
	local ok, mob = pcall(windower.ffxi.get_mob_by_id, target_id)
	if not ok or type(mob) ~= 'table' then
		return nil
	end
	return mob
end

local function current_camp()
	local ok_require, camp_anchor = pcall(require, 'uc_camp_anchor')
	if not ok_require or type(camp_anchor) ~= 'table' or type(camp_anchor.resolve_current_anchor) ~= 'function' then
		return nil, 'CAMP_RESOLVER_UNAVAILABLE'
	end
	local ok_resolve, camp, reason = pcall(camp_anchor.resolve_current_anchor)
	if not ok_resolve then
		return nil, 'CAMP_RESOLVE_FAILED'
	end
	if type(camp) ~= 'table' then
		return nil, tostring(reason or 'CAMP_UNSET')
	end
	return camp, tostring(reason or 'CAMP_SET')
end

local function number_text(value)
	local n = finite_number(value)
	if n == nil then
		return 'nil'
	end
	return ('%.6f'):format(n)
end

local function id_text(value)
	local n = tonumber(value)
	if n == nil then
		return 'nil'
	end
	return ('%.0f'):format(n)
end

local function observe_new_luopan(trace_id, prior_pet_id, predicted)
	if type(coroutine) ~= 'table' or type(coroutine.schedule) ~= 'function' then
		return
	end
	local deadline = now_s() + PET_OBSERVE_TIMEOUT_S
	local function sample()
		local pet = windower.ffxi.get_mob_by_target('pet')
		local pet_id = tonumber(pet and pet.id) or 0
		if type(pet) == 'table' and pet_id > 0 and pet_id ~= (tonumber(prior_pet_id) or 0) then
			local dx = finite_number(pet.x) and finite_number(predicted and predicted.x)
				and (finite_number(pet.x) - finite_number(predicted.x)) or nil
			local dy = finite_number(pet.y) and finite_number(predicted and predicted.y)
				and (finite_number(pet.y) - finite_number(predicted.y)) or nil
			local dz = finite_number(pet.z) and finite_number(predicted and predicted.z)
				and (finite_number(pet.z) - finite_number(predicted.z)) or nil
			append_log(('event=GEO_LUOPAN_OBSERVED trace=%d pet_id=%s pet_index=%s pet_name=%q pet_x=%s pet_y=%s pet_z=%s predicted_x=%s predicted_y=%s predicted_z=%s delta_x=%s delta_y=%s delta_z=%s'):format(
				trace_id,
				id_text(pet.id),
				id_text(pet.index),
				tostring(pet.name or ''),
				number_text(pet.x),
				number_text(pet.y),
				number_text(pet.z),
				number_text(predicted and predicted.x),
				number_text(predicted and predicted.y),
				number_text(predicted and predicted.z),
				number_text(dx),
				number_text(dy),
				number_text(dz)
			))
			return
		end
		if now_s() < deadline then
			coroutine.schedule(sample, PET_OBSERVE_INTERVAL_S)
		else
			append_log(('event=GEO_LUOPAN_OBSERVE_TIMEOUT trace=%d prior_pet_id=%s'):format(
				trace_id,
				id_text(prior_pet_id)
			))
		end
	end
	coroutine.schedule(sample, PET_OBSERVE_INTERVAL_S)
end

function M.observe_outgoing(id, data, blocked, injected)
	if blocked == true or tonumber(id) ~= ACTION_PACKET_ID or type(data) ~= 'string' then
		return false
	end

	local ok_parse, packet = pcall(packets.parse, 'outgoing', data)
	if not ok_parse or type(packet) ~= 'table' then
		return false
	end
	if tonumber(packet['Category']) ~= MAGIC_CATEGORY then
		return false
	end

	local spell = spell_by_id(packet['Param'])
	if not is_geo_spell(spell) then
		return false
	end

	trace_sequence = trace_sequence + 1
	local trace_id = trace_sequence
	local player = windower.ffxi.get_player()
	local me = windower.ffxi.get_mob_by_target('me')
	local target = mob_by_id(packet['Target'])
	local prior_pet = windower.ffxi.get_mob_by_target('pet')
	local camp, camp_reason = current_camp()

	local x_offset = finite_number(packet['X Offset']) or 0
	local z_offset = finite_number(packet['Z Offset']) or 0
	local y_offset = finite_number(packet['Y Offset']) or 0
	local predicted = nil
	if type(target) == 'table' then
		local tx = finite_number(target.x)
		local ty = finite_number(target.y)
		local tz = finite_number(target.z)
		if tx ~= nil and ty ~= nil then
			predicted = {
				x = tx + x_offset,
				y = ty + y_offset,
				z = tz ~= nil and (tz + z_offset) or nil,
			}
		end
	end

	local info = windower.ffxi.get_info()
	local line = ('event=GEO_ACTION_PACKET trace=%d id=0x01A spell_id=%s spell=%q category=%s target_id=%s target_index=%s x_offset=%s y_offset=%s z_offset=%s injected=%s zone=%s player=%q player_id=%s self_x=%s self_y=%s self_z=%s target_name=%q target_x=%s target_y=%s target_z=%s predicted_x=%s predicted_y=%s predicted_z=%s camp_reason=%s camp_x=%s camp_y=%s prior_pet_id=%s raw=%q'):format(
		trace_id,
		id_text(packet['Param']),
		tostring(spell.en or ''),
		id_text(packet['Category']),
		id_text(packet['Target']),
		id_text(packet['Target Index']),
		number_text(x_offset),
		number_text(y_offset),
		number_text(z_offset),
		tostring(injected == true),
		id_text(info and info.zone),
		tostring(player and player.name or ''),
		id_text(player and player.id),
		number_text(me and me.x),
		number_text(me and me.y),
		number_text(me and me.z),
		tostring(target and target.name or ''),
		number_text(target and target.x),
		number_text(target and target.y),
		number_text(target and target.z),
		number_text(predicted and predicted.x),
		number_text(predicted and predicted.y),
		number_text(predicted and predicted.z),
		tostring(camp_reason),
		number_text(camp and camp.x),
		number_text(camp and camp.y),
		id_text(prior_pet and prior_pet.id),
		hex_bytes(data)
	)
	append_log(line)

	_G.UC_LAST_GEO_PACKET_TRACE = {
		trace_id = trace_id,
		spell_id = tonumber(packet['Param']),
		spell_name = tostring(spell.en or ''),
		target_id = tonumber(packet['Target']),
		target_index = tonumber(packet['Target Index']),
		x_offset = x_offset,
		y_offset = y_offset,
		z_offset = z_offset,
		predicted_x = predicted and predicted.x or nil,
		predicted_y = predicted and predicted.y or nil,
		predicted_z = predicted and predicted.z or nil,
		observed_at = now_s(),
	}

	observe_new_luopan(trace_id, prior_pet and prior_pet.id or 0, predicted)
	return true
end

return M
