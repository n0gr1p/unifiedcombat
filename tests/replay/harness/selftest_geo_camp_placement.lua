local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_near(actual, expected, epsilon, message)
	if type(actual) ~= 'number' or math.abs(actual - expected) > epsilon then
		error(('%s: expected %.6f, got %s'):format(message, expected, tostring(actual)))
	end
end

local previous_windower = rawget(_G, 'windower')
local previous_settings = rawget(_G, 'UC_SETTINGS')
local previous_geo_status = rawget(_G, 'UC_GEO_MAINTENANCE_STATUS')
local previous_placement_status = rawget(_G, 'UC_GEO_CAMP_PLACEMENT_STATUS')
local previous_packets = package.loaded['packets']
local previous_resources = package.loaded['resources']
local previous_camp_anchor = package.loaded['uc_camp_anchor']
local previous_active_config = package.loaded['uc_active_config']
local previous_module = package.loaded['uc_geo_camp_placement']

local parsed_packet = nil
local camp = { x = 100.0, y = 200.0 }
local me = { id = 1, index = 1, name = 'Tester', x = 100.1, y = 199.9, z = 7.0 }
local mobs = {
	[1001] = { id = 1001, index = 51, name = 'Enemy', x = 110.0, y = 205.0, z = 5.0 },
	[2001] = { id = 2001, index = 61, name = 'Friend', x = 98.0, y = 207.0, z = 6.5 },
}
local active_geo = {
	camp_tolerance_yalms = 1.0,
	luopan = {
		replace_out_of_position = true,
	},
}
local registered_callback = nil

package.loaded['packets'] = {
	parse = function(direction, data)
		assert_equal(direction, 'outgoing', 'packet direction')
		assert_equal(data, 'raw-packet', 'packet raw data')
		local out = {}
		for key, value in pairs(parsed_packet or {}) do
			out[key] = value
		end
		return out
	end,
	build = function(packet)
		local fields = {
			Target = packet['Target'],
			TargetIndex = packet['Target Index'],
			Category = packet['Category'],
			Param = packet['Param'],
			X = packet['X Offset'],
			Y = packet['Y Offset'],
			Z = packet['Z Offset'],
		}
		return ('built:%d:%d:%d:%d:%.6f:%.6f:%.6f'):format(
			fields.Target,
			fields.TargetIndex,
			fields.Category,
			fields.Param,
			fields.X,
			fields.Y,
			fields.Z
		)
	end,
}

package.loaded['resources'] = {
	spells = {
		[818] = { id = 818, en = 'Geo-Frailty' },
		[1] = { id = 1, en = 'Cure' },
	},
}

package.loaded['uc_camp_anchor'] = {
	resolve_current_anchor = function()
		if camp == nil then
			return nil, 'CAMP_UNSET'
		end
		return camp, 'CAMP_READY'
	end,
}

package.loaded['uc_active_config'] = {
	get_path = function(path)
		if path == 'config.maintenance.geo' then
			return active_geo
		end
		return nil
	end,
}

windower = {
	ffxi = {
		get_mob_by_id = function(id)
			return mobs[id]
		end,
		get_mob_by_target = function(target)
			if target == 'me' then
				return me
			end
			return nil
		end,
	},
	register_event = function(name, callback)
		assert_equal(name, 'outgoing chunk', 'registered event')
		registered_callback = callback
		return 1
	end,
}

package.loaded['uc_geo_camp_placement'] = nil
local placement = require('uc_geo_camp_placement')

local function geo_packet(target_id, target_index)
	return {
		['Target'] = target_id,
		['Target Index'] = target_index,
		['Category'] = 0x03,
		['Param'] = 818,
		['X Offset'] = 0,
		['Y Offset'] = 0,
		['Z Offset'] = 0,
	}
end

local function arm_uc_geo(spell)
	_G.UC_GEO_MAINTENANCE_STATUS = {
		state = 'dispatched',
		pending_kind = 'geo',
		pending_spell = spell or 'Geo-Frailty',
	}
end

-- Feature off: packet is untouched.
parsed_packet = geo_packet(1001, 51)
active_geo.luopan.replace_out_of_position = false
arm_uc_geo()
assert_equal(placement.rewrite_outgoing(0x01A, 'raw-packet', false, true), nil, 'disabled placement')
assert_equal(_G.UC_GEO_CAMP_PLACEMENT_STATUS.reason, 'GEO_CAMP_PLACEMENT_DISABLED', 'disabled reason')
active_geo.luopan.replace_out_of_position = true

-- Manual/unowned Geo casts are untouched.
_G.UC_GEO_MAINTENANCE_STATUS = nil
assert_equal(placement.rewrite_outgoing(0x01A, 'raw-packet', false, true), nil, 'manual geo placement')
assert_equal(_G.UC_GEO_CAMP_PLACEMENT_STATUS.reason, 'GEO_RUNTIME_STATUS_UNAVAILABLE', 'manual reason')

-- Wrong UC pending spell is untouched.
arm_uc_geo('Geo-Malaise')
assert_equal(placement.rewrite_outgoing(0x01A, 'raw-packet', false, true), nil, 'wrong pending spell')
assert_equal(_G.UC_GEO_CAMP_PLACEMENT_STATUS.reason, 'GEO_PENDING_SPELL_MISMATCH', 'wrong spell reason')

-- Enemy-target Geo is rewritten to camp XYZ while preserving legal target fields.
arm_uc_geo()
parsed_packet = geo_packet(1001, 51)
local rewritten, blocked = placement.rewrite_outgoing(0x01A, 'raw-packet', false, true)
assert_equal(blocked, false, 'blocked state preserved')
assert_equal(
	rewritten,
	'built:1001:51:3:818:-10.000000:-5.000000:2.000000',
	'enemy rewrite payload'
)
local status = _G.UC_GEO_CAMP_PLACEMENT_STATUS
assert_equal(status.rewritten, true, 'enemy rewrite status')
assert_equal(status.blocked, false, 'enemy rewrite not blocked')
assert_equal(status.target_id, 1001, 'enemy target id preserved')
assert_near(status.camp_x, 100.0, 0.000001, 'enemy camp x')
assert_near(status.camp_y, 200.0, 0.000001, 'enemy camp y')
assert_near(status.camp_z, 7.0, 0.000001, 'enemy camp z')
assert_near(status.x_offset, -10.0, 0.000001, 'enemy x offset')
assert_near(status.y_offset, -5.0, 0.000001, 'enemy y offset')
assert_near(status.z_offset, 2.0, 0.000001, 'enemy z offset')

-- Friendly-target Geo uses identical placement math. Target kind is deliberately
-- irrelevant to the packet layer; the legal entity target remains unchanged.
parsed_packet = geo_packet(2001, 61)
arm_uc_geo()
rewritten = placement.rewrite_outgoing(0x01A, 'raw-packet', false, true)
assert_equal(
	rewritten,
	'built:2001:61:3:818:2.000000:-7.000000:0.500000',
	'friendly rewrite payload'
)
status = _G.UC_GEO_CAMP_PLACEMENT_STATUS
assert_equal(status.target_id, 2001, 'friendly target id preserved')
assert_near(status.x_offset, 2.0, 0.000001, 'friendly x offset')
assert_near(status.y_offset, -7.0, 0.000001, 'friendly y offset')
assert_near(status.z_offset, 0.5, 0.000001, 'friendly z offset')

-- Once an exact UC-owned camp-placement cast is identified, unsafe placement
-- conditions fail closed rather than silently creating a target-centered Luopan.
camp = nil
parsed_packet = geo_packet(1001, 51)
arm_uc_geo()
local failed_data, failed_blocked = placement.rewrite_outgoing(0x01A, 'raw-packet', false, true)
assert_equal(failed_data, 'raw-packet', 'missing camp preserves packet buffer')
assert_equal(failed_blocked, true, 'missing camp blocks owned Geo packet')
assert_equal(_G.UC_GEO_CAMP_PLACEMENT_STATUS.reason, 'CAMP_UNSET', 'missing camp reason')
assert_equal(_G.UC_GEO_CAMP_PLACEMENT_STATUS.blocked, true, 'missing camp blocked status')
camp = { x = 100.0, y = 200.0 }

-- Camp v2 does not own Z, so fail closed if caster is not at camp.
me.x = 105.0
me.y = 205.0
arm_uc_geo()
failed_data, failed_blocked = placement.rewrite_outgoing(0x01A, 'raw-packet', false, true)
assert_equal(failed_data, 'raw-packet', 'away from camp preserves packet buffer')
assert_equal(failed_blocked, true, 'away from camp blocks owned Geo packet')
assert_equal(
	_G.UC_GEO_CAMP_PLACEMENT_STATUS.reason,
	'CAMP_Z_UNAVAILABLE_AWAY_FROM_CAMP',
	'away from camp reason'
)
me.x = 100.1
me.y = 199.9

-- Non-Geo and non-magic packets are ignored.
parsed_packet = geo_packet(1001, 51)
parsed_packet['Param'] = 1
assert_equal(placement.rewrite_outgoing(0x01A, 'raw-packet', false, true), nil, 'non-geo spell')
parsed_packet = geo_packet(1001, 51)
parsed_packet['Category'] = 0x02
assert_equal(placement.rewrite_outgoing(0x01A, 'raw-packet', false, true), nil, 'non-magic action')
assert_equal(placement.rewrite_outgoing(0x015, 'raw-packet', false, true), nil, 'other packet id')

-- Registration passes the latest modified buffer through the rewriter.
parsed_packet = geo_packet(1001, 51)
arm_uc_geo()
assert_equal(placement.register(), true, 'placement register')
assert_equal(type(registered_callback), 'function', 'placement callback registered')
local callback_result = registered_callback(0x01A, 'original-packet', 'raw-packet', true, false)
assert_equal(
	callback_result,
	'built:1001:51:3:818:-10.000000:-5.000000:2.000000',
	'registered callback rewrite'
)

_G.UC_SETTINGS = previous_settings
_G.UC_GEO_MAINTENANCE_STATUS = previous_geo_status
_G.UC_GEO_CAMP_PLACEMENT_STATUS = previous_placement_status
rawset(_G, 'windower', previous_windower)
package.loaded['packets'] = previous_packets
package.loaded['resources'] = previous_resources
package.loaded['uc_camp_anchor'] = previous_camp_anchor
package.loaded['uc_active_config'] = previous_active_config
package.loaded['uc_geo_camp_placement'] = previous_module

io.stdout:write('selftest_geo_camp_placement: OK\n')
