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

local original_packets = package.loaded.packets
local original_uc_time = package.loaded.uc_time
local original_uc_settarget = package.loaded.uc_settarget
local original_windower = rawget(_G, 'windower')

local now = 100.0
local injected = {}
local commands = {}
local events = {}
local current_target = nil
local targets = {
	[2002] = { id = 2002, index = 22, spawn_type = 16, valid_target = true },
	[2003] = { id = 2003, index = 23, spawn_type = 16, valid_target = true },
	[3001] = { id = 3001, index = 31, spawn_type = 2, valid_target = true },
}
local player = { id = 1001, index = 11 }

package.loaded.uc_time = {
	now = function()
		return now
	end,
}
package.loaded.packets = {
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
		get_mob_by_id = function(id)
			return targets[tonumber(id)]
		end,
		get_player = function()
			return player
		end,
		get_mob_by_target = function(target)
			assert_equal(target, 't', 'camera unlock must inspect current target')
			return current_target
		end,
	},
	send_command = function(command)
		commands[#commands + 1] = command
	end,
	register_event = function(name, callback)
		events[name] = callback
		return name
	end,
})

package.loaded.uc_settarget = nil
local settarget = require('uc_settarget')

assert_true(type(events.prerender) == 'function', 'uc_settarget must register a prerender unlock observer')

local ok, reason = settarget.select_by_id(2002)
assert_true(ok, 'mob target selection should succeed: ' .. tostring(reason))
assert_equal(#injected, 1, 'target selection packet count')
assert_equal(injected[1]._dir, 'incoming', 'target selection packet direction')
assert_equal(injected[1]._id, 0x058, 'target selection packet id')
assert_equal(injected[1].fields['Player'], player.id, 'target packet player id')
assert_equal(injected[1].fields['Target'], targets[2002].id, 'target packet target id')
assert_equal(injected[1].fields['Player Index'], player.index, 'target packet player index')
assert_equal(#commands, 0, 'camera unlock must wait until the selected mob becomes current')

ok, reason = events.prerender()
assert_false(ok, 'prerender before target selection should not toggle lock')
assert_equal(reason, 'TARGET_NOT_SELECTED_YET', 'preselection unlock reason')
assert_equal(#commands, 0, 'no premature lock toggle')

current_target = targets[2002]
ok, reason = events.prerender()
assert_true(ok, 'selected mob should be de-locked: ' .. tostring(reason))
assert_equal(reason, 'UNLOCKED', 'successful unlock reason')
assert_equal(#commands, 1, 'camera unlock command count')
assert_equal(commands[1], '@input /lockon', 'camera unlock command')

ok, reason = events.prerender()
assert_false(ok, 'completed unlock must not repeat')
assert_equal(reason, 'NO_PENDING_UNLOCK', 'completed unlock state')
assert_equal(#commands, 1, 'completed unlock must be one-shot')

current_target = nil
now = 200.0
ok, reason = settarget.select_by_id(2003)
assert_true(ok, 'second mob target selection should succeed: ' .. tostring(reason))
now = 201.1
current_target = targets[2003]
ok, reason = events.prerender()
assert_false(ok, 'stale unlock request must expire instead of toggling a later camera state')
assert_equal(reason, 'UNLOCK_TIMEOUT', 'stale unlock timeout reason')
assert_equal(#commands, 1, 'expired unlock must not send a command')

now = 300.0
current_target = nil
ok, reason = settarget.select_by_id(3001)
assert_true(ok, 'non-mob target selection should still succeed: ' .. tostring(reason))
current_target = targets[3001]
ok, reason = events.prerender()
assert_false(ok, 'non-mob target selection should not alter camera lock state')
assert_equal(reason, 'NO_PENDING_UNLOCK', 'non-mob unlock state')
assert_equal(#commands, 1, 'non-mob target must not send a lock toggle')

package.loaded.packets = original_packets
package.loaded.uc_time = original_uc_time
package.loaded.uc_settarget = original_uc_settarget
rawset(_G, 'windower', original_windower)

print('selftest_settarget_camera_unlock: PASS')
