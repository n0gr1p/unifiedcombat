---@diagnostic disable: undefined-global

local M = {}

local packets = require('packets')
local res = require('resources')
local uc_camp_anchor = require('uc_camp_anchor')
local uc_active_config = require('uc_active_config')

local ACTION_PACKET_ID = 0x01A
local MAGIC_CATEGORY = 0x03

local registered = false

local function finite_number(value)
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
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

local function geo_spell_name(spell_id)
	local spell = spell_by_id(spell_id)
	local name = type(spell) == 'table' and tostring(spell.en or '') or ''
	if name:match('^Geo%-') == nil then
		return nil
	end
	return name
end

local function geo_config()
	local active = nil
	local ok_active, value = pcall(uc_active_config.get_path, 'config.maintenance.geo')
	if ok_active and type(value) == 'table' then
		active = value
	end
	if active ~= nil then
		return active
	end
	local settings = rawget(_G, 'UC_SETTINGS')
	if type(settings) == 'table' and type(settings.maintenance_geo) == 'table' then
		return settings.maintenance_geo
	end
	return nil
end

local function camp_placement_enabled(config)
	return type(config) == 'table'
		and type(config.luopan) == 'table'
		and config.luopan.placement == 'camp'
end

local function matching_uc_geo_dispatch(spell_name)
	local status = rawget(_G, 'UC_GEO_MAINTENANCE_STATUS')
	if type(status) ~= 'table' then
		return false, 'GEO_RUNTIME_STATUS_UNAVAILABLE'
	end
	if tostring(status.state or '') ~= 'dispatched' then
		return false, 'GEO_NOT_UC_DISPATCHED'
	end
	if tostring(status.pending_kind or '') ~= 'geo' then
		return false, 'GEO_PENDING_KIND_MISMATCH'
	end
	if tostring(status.pending_spell or '') ~= tostring(spell_name or '') then
		return false, 'GEO_PENDING_SPELL_MISMATCH'
	end
	return true, 'GEO_UC_DISPATCH_MATCH'
end

local function set_status(reason, detail)
	detail = type(detail) == 'table' and detail or {}
	local status = {
		reason = tostring(reason or ''),
		rewritten = detail.rewritten == true,
		blocked = detail.blocked == true,
		spell = tostring(detail.spell or ''),
		spell_id = tonumber(detail.spell_id) or 0,
		target_id = tonumber(detail.target_id) or 0,
		target_index = tonumber(detail.target_index) or 0,
		target_x = finite_number(detail.target_x),
		target_y = finite_number(detail.target_y),
		target_z = finite_number(detail.target_z),
		camp_x = finite_number(detail.camp_x),
		camp_y = finite_number(detail.camp_y),
		camp_z = finite_number(detail.camp_z),
		x_offset = finite_number(detail.x_offset),
		y_offset = finite_number(detail.y_offset),
		z_offset = finite_number(detail.z_offset),
	}
	_G.UC_GEO_CAMP_PLACEMENT_STATUS = status
	return status
end

local function reject(reason, detail)
	set_status(reason, detail)
	return nil
end

local function fail_closed(data, reason, detail)
	detail = type(detail) == 'table' and detail or {}
	detail.blocked = true
	set_status(reason, detail)
	return data, true
end

local function target_position(target_id)
	local id = tonumber(target_id)
	if id == nil or id <= 0 then
		return nil
	end
	local ok, target = pcall(windower.ffxi.get_mob_by_id, id)
	if not ok or type(target) ~= 'table' then
		return nil
	end
	local x = finite_number(target.x)
	local y = finite_number(target.y)
	local z = finite_number(target.z)
	if x == nil or y == nil or z == nil then
		return nil
	end
	return {
		id = tonumber(target.id) or id,
		index = tonumber(target.index) or 0,
		name = tostring(target.name or ''),
		x = x,
		y = y,
		z = z,
	}
end

local function camp_position()
	local ok_camp, camp, camp_reason = pcall(uc_camp_anchor.resolve_current_anchor)
	if not ok_camp or type(camp) ~= 'table' then
		return nil, ok_camp and tostring(camp_reason or 'CAMP_UNSET') or 'CAMP_RESOLVE_FAILED'
	end
	local camp_x = finite_number(camp.x)
	local camp_y = finite_number(camp.y)
	local camp_z = finite_number(camp.z)
	if camp_x == nil or camp_y == nil then
		return nil, 'CAMP_XY_UNAVAILABLE'
	end
	if camp_z == nil then
		return nil, 'CAMP_Z_UNAVAILABLE'
	end

	return {
		x = camp_x,
		y = camp_y,
		z = camp_z,
	}, 'CAMP_READY'
end

function M.rewrite_outgoing(id, data, blocked, injected)
	if blocked == true or tonumber(id) ~= ACTION_PACKET_ID or type(data) ~= 'string' then
		return nil
	end

	local ok_parse, packet = pcall(packets.parse, 'outgoing', data)
	if not ok_parse or type(packet) ~= 'table' then
		return reject('GEO_PACKET_PARSE_FAILED')
	end
	if tonumber(packet['Category']) ~= MAGIC_CATEGORY then
		return nil
	end

	local spell_name = geo_spell_name(packet['Param'])
	if spell_name == nil then
		return nil
	end

	local config = geo_config()
	if not camp_placement_enabled(config) then
		return reject('GEO_CAMP_PLACEMENT_DISABLED', {
			spell = spell_name,
			spell_id = packet['Param'],
			target_id = packet['Target'],
			target_index = packet['Target Index'],
		})
	end

	local owned, owned_reason = matching_uc_geo_dispatch(spell_name)
	if not owned then
		return reject(owned_reason, {
			spell = spell_name,
			spell_id = packet['Param'],
			target_id = packet['Target'],
			target_index = packet['Target Index'],
		})
	end

	-- From this point onward this is the exact Geo spell UC just dispatched with
	-- camp placement enabled. If we cannot produce a trustworthy replacement,
	-- block the packet rather than silently creating a target-centered Luopan.
	local target = target_position(packet['Target'])
	if target == nil then
		return fail_closed(data, 'GEO_CAMP_TARGET_POSITION_UNAVAILABLE', {
			spell = spell_name,
			spell_id = packet['Param'],
			target_id = packet['Target'],
			target_index = packet['Target Index'],
		})
	end

	local camp, camp_reason = camp_position()
	if camp == nil then
		return fail_closed(data, camp_reason, {
			spell = spell_name,
			spell_id = packet['Param'],
			target_id = packet['Target'],
			target_index = packet['Target Index'],
			target_x = target.x,
			target_y = target.y,
			target_z = target.z,
		})
	end

	local x_offset = camp.x - target.x
	local y_offset = camp.y - target.y
	local z_offset = camp.z - target.z
	packet['X Offset'] = x_offset
	packet['Y Offset'] = y_offset
	packet['Z Offset'] = z_offset

	local ok_build, rewritten = pcall(packets.build, packet)
	if not ok_build or type(rewritten) ~= 'string' then
		return fail_closed(data, 'GEO_CAMP_PACKET_BUILD_FAILED', {
			spell = spell_name,
			spell_id = packet['Param'],
			target_id = packet['Target'],
			target_index = packet['Target Index'],
			target_x = target.x,
			target_y = target.y,
			target_z = target.z,
			camp_x = camp.x,
			camp_y = camp.y,
			camp_z = camp.z,
		})
	end

	set_status('GEO_CAMP_PACKET_REWRITTEN', {
		rewritten = true,
		spell = spell_name,
		spell_id = packet['Param'],
		target_id = packet['Target'],
		target_index = packet['Target Index'],
		target_x = target.x,
		target_y = target.y,
		target_z = target.z,
		camp_x = camp.x,
		camp_y = camp.y,
		camp_z = camp.z,
		x_offset = x_offset,
		y_offset = y_offset,
		z_offset = z_offset,
	})

	return rewritten, blocked
end

function M.register()
	if registered then
		return true
	end
	if type(windower) ~= 'table' or type(windower.register_event) ~= 'function' then
		return false
	end
	windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
		local data = modified or original
		return M.rewrite_outgoing(id, data, blocked, injected)
	end)
	registered = true
	return true
end

return M
