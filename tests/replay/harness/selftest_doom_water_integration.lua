local function read_all(path)
	local handle, err = io.open(path, 'rb')
	if not handle then
		error(('failed to open %s: %s'):format(path, tostring(err)))
	end
	local text = handle:read('*a')
	handle:close()
	return text
end

local function assert_contains(text, needle, label)
	if not text:find(needle, 1, true) then
		error(label .. ' missing: ' .. needle)
	end
end

local scheduler = read_all('unified_scheduler.lua')
local addon = read_all('UnifiedCombat.lua')

assert_contains(addon, "windower.register_event('add item'", 'Windower add-item event wiring')
assert_contains(addon, '_G.UC_SCHED_OnAddItem(bag, index, item_id, count)', 'add-item scheduler forwarding')
assert_contains(scheduler, "doom_water_state = require('uc_doom_water').new_state()", 'scheduler Doom state ownership')
assert_contains(scheduler, "get_item = windower.ffxi.get_item", 'supported inventory retrieval API wiring')
assert_contains(scheduler, "function scheduler.on_add_item(bag, index, item_id, count)", 'scheduler add-item continuation')
assert_contains(scheduler, "require('uc_doom_water').on_add_item(", 'event-driven staging confirmation')
assert_contains(scheduler, 'settings._sched_next_defensive_at = 0', 'same-tick Cursna/status-removal fallback')
assert_contains(scheduler, "require('uc_doom_water').reset(scheduler.doom_water_state, 'ZONE_CHANGE')", 'zone reset')

io.stdout:write('selftest_doom_water_integration: OK\n')
