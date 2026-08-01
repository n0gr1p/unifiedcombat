local zone_id = 100
local sent = {}
local previous_windower = rawget(_G, 'windower')
local previous_camp_module = package.loaded['uc_camp_anchor']

windower = {
	send_ipc_message = function(message)
		sent[#sent + 1] = message
	end,
	ffxi = {
		get_info = function()
			return { zone = zone_id }
		end,
		get_player = function()
			return { name = 'Setter' }
		end,
		get_mob_by_target = function(target)
			if target == 'me' then
				return { x = 12.5, y = -8.25 }
			end
			return nil
		end,
	},
}

package.loaded['uc_camp_anchor'] = nil
local camp = require('uc_camp_anchor')

local function assert_true(value, message)
	if not value then
		error(message or 'expected true')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local anchor, reason = camp.resolve_current_anchor()
assert_equal(anchor, nil, 'unset camp must not resolve')
assert_equal(reason, 'CAMP_UNSET', 'unset camp reason mismatch')

local ok
ok, reason = camp.set_current_position()
assert_true(ok, 'local camp capture must succeed')
assert_equal(reason, 'CAMP_SET', 'local camp reason mismatch')
assert_equal(#sent, 1, 'local camp capture must broadcast once')
assert_true(sent[1]:find('uc_camp_anchor_v1|set|100|12.500000|-8.250000|Setter', 1, true) == 1, 'camp IPC payload mismatch')

anchor, reason = camp.resolve_current_anchor()
assert_true(type(anchor) == 'table', 'captured camp must resolve')
assert_equal(reason, 'CAMP_READY', 'captured camp reason mismatch')
assert_equal(anchor.x, 12.5, 'captured camp x mismatch')
assert_equal(anchor.y, -8.25, 'captured camp y mismatch')
assert_equal(anchor.set_by, 'Setter', 'captured camp setter mismatch')

local consumed
consumed, ok, reason = camp.on_ipc_message('uc_camp_anchor_v1|set|100|1.25|2.5|Other')
assert_true(consumed and ok, 'valid remote camp must be consumed')
assert_equal(reason, 'CAMP_SET', 'remote camp reason mismatch')
anchor = camp.resolve_current_anchor()
assert_equal(anchor.x, 1.25, 'remote camp x mismatch')
assert_equal(anchor.y, 2.5, 'remote camp y mismatch')
assert_equal(anchor.set_by, 'Other', 'remote camp setter mismatch')

zone_id = 101
anchor, reason = camp.resolve_current_anchor()
assert_equal(anchor, nil, 'cross-zone camp must not resolve')
assert_equal(reason, 'CAMP_ZONE_MISMATCH', 'cross-zone camp reason mismatch')

zone_id = 100
consumed, ok, reason = camp.on_ipc_message('uc_camp_anchor_v1|set|100|nan|2.5|Other')
assert_true(consumed and not ok, 'invalid coordinates must fail closed')
assert_equal(reason, 'CAMP_COORDINATES_INVALID', 'invalid coordinate reason mismatch')

ok, reason = camp.clear_shared()
assert_true(ok, 'shared clear must succeed')
assert_equal(reason, 'CAMP_CLEARED', 'shared clear reason mismatch')
assert_equal(#sent, 2, 'shared clear must broadcast once')
anchor, reason = camp.resolve_current_anchor()
assert_equal(anchor, nil, 'cleared camp must not resolve')
assert_equal(reason, 'CAMP_UNSET', 'cleared camp reason mismatch')

package.loaded['uc_camp_anchor'] = previous_camp_module
rawset(_G, 'windower', previous_windower)

print('selftest_camp_anchor: OK')
