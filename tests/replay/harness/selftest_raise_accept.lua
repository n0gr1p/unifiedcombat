local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message or 'expected false')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local original_active_config = package.loaded.uc_active_config
local original_uc_time = package.loaded.uc_time
local original_packets = package.loaded.packets
local original_raise_accept = package.loaded.uc_raise_accept
local original_windower = rawget(_G, 'windower')
local original_settings = rawget(_G, 'UC_SETTINGS')

local configured = nil
local now = 100.0
local player = {
	id = 1001,
	index = 77,
	status = 2,
}
local parsed = {
	Category = 1,
}
local injected = {}
local events = {}

package.loaded.uc_active_config = {
	get_path = function(path)
		assert_equal(path, 'config.ownership.auto_accept_raise', 'auto-accept Raise config path')
		return configured
	end,
}
package.loaded.uc_time = {
	now = function()
		return now
	end,
}
package.loaded.packets = {
	parse = function(direction)
		assert_equal(direction, 'incoming', 'Raise packet parse direction')
		return parsed
	end,
	new = function(direction, id, fields)
		return {
			_dir = direction,
			_id = id,
			fields = fields,
		}
	end,
	inject = function(packet)
		injected[#injected + 1] = packet
	end,
}
rawset(_G, 'windower', {
	ffxi = {
		get_mob_by_target = function(target)
			assert_equal(target, 'me', 'Raise accept must resolve local player')
			return player
		end,
	},
	add_to_chat = function() end,
	register_event = function(name, callback)
		events[name] = callback
		return name
	end,
})
rawset(_G, 'UC_SETTINGS', {
	auto_accept_raise = true,
})

package.loaded.uc_raise_accept = nil
local raise_accept = require('uc_raise_accept')

configured = nil
assert_false(raise_accept.setting_enabled(), 'missing canonical setting must stay disabled even when flat compatibility is true')
configured = false
assert_false(raise_accept.setting_enabled(), 'canonical false must disable auto-accept')
configured = true
assert_true(raise_accept.setting_enabled(), 'canonical true must enable auto-accept')

local ok, reason = raise_accept.on_incoming_chunk(0x0F9, 'raise', now)
assert_true(ok, 'dead player should accept Raise: ' .. tostring(reason))
assert_equal(#injected, 1, 'Raise accept injection count')
assert_equal(injected[1]._dir, 'outgoing', 'Raise accept packet direction')
assert_equal(injected[1]._id, 0x01A, 'Raise accept packet id')
assert_equal(injected[1].fields['Target'], player.id, 'Raise accept target id')
assert_equal(injected[1].fields['Target Index'], player.index, 'Raise accept target index')
assert_equal(injected[1].fields['Category'], 0x0D, 'Raise accept action category')
assert_equal(injected[1].fields['Param'], 0, 'Raise accept param')

ok, reason = raise_accept.on_incoming_chunk(0x0F9, 'raise', now + 0.5)
assert_false(ok, 'duplicate Raise prompt must be gated')
assert_equal(reason, 'DUPLICATE_GATE', 'duplicate Raise reason')
assert_equal(#injected, 1, 'duplicate Raise must not inject again')

parsed = { Category = 2 }
now = now + 3.0
ok, reason = raise_accept.on_incoming_chunk(0x0F9, 'tractor', now)
assert_false(ok, 'Tractor dialogue must never auto-accept')
assert_equal(reason, 'NOT_RAISE_DIALOGUE', 'Tractor rejection reason')
assert_equal(#injected, 1, 'Tractor must not inject')

parsed = { Category = 'Raise dialogue' }
player.status = 0
ok, reason = raise_accept.on_incoming_chunk(0x0F9, 'raise-text-category', now + 3.0)
assert_false(ok, 'living player must not accept Raise dialogue')
assert_equal(reason, 'PLAYER_NOT_DEAD', 'living player rejection reason')
assert_equal(#injected, 1, 'living player must not inject')

player.status = 3
configured = false
ok, reason = raise_accept.on_incoming_chunk(0x0F9, 'raise-disabled', now + 6.0)
assert_false(ok, 'disabled setting must suppress Raise acceptance')
assert_equal(reason, 'DISABLED', 'disabled rejection reason')
assert_equal(#injected, 1, 'disabled setting must not inject')

configured = true
raise_accept.reset_runtime()
ok, reason = raise_accept.on_incoming_chunk(0x0F9, 'raise-retry', now + 6.0)
assert_true(ok, 'reset must allow a fresh Raise prompt: ' .. tostring(reason))
assert_equal(#injected, 2, 'fresh Raise prompt after reset should inject')

assert_true(raise_accept.register(), 'runtime event registration must succeed')
assert_true(type(events['incoming chunk']) == 'function', 'incoming chunk handler must register')
assert_true(type(events['zone change']) == 'function', 'zone reset handler must register')
assert_true(type(events.logout) == 'function', 'logout reset handler must register')
assert_true(type(events.unload) == 'function', 'unload reset handler must register')

raise_accept.reset_runtime()
assert_equal(raise_accept.status().accept_count, 0, 'reset accept count')
assert_equal(raise_accept.status().last_accept_at, nil, 'reset accept timestamp')

package.loaded.uc_active_config = original_active_config
package.loaded.uc_time = original_uc_time
package.loaded.packets = original_packets
package.loaded.uc_raise_accept = original_raise_accept
rawset(_G, 'windower', original_windower)
rawset(_G, 'UC_SETTINGS', original_settings)

print('selftest_raise_accept: PASS')
