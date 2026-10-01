local doom_water = require('uc_doom_water')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, label)
	if value ~= true then
		error(label .. ' expected=true actual=' .. tostring(value))
	end
end

local function new_fixture()
	local f = {
		now = 10.0,
		enabled = true,
		doomed = true,
		reserve_count = 0,
		use_count = 0,
		move_count = 0,
		last_move = nil,
		logs = {},
		items = {
			[0] = {},
			[5] = {},
			[6] = {},
		},
		bag_info = {
			[0] = { enabled = true, max = 80, count = 10 },
			[5] = { enabled = true, max = 80, count = 0 },
			[6] = { enabled = false, max = 80, count = 0 },
		},
		bags = {
			[0] = { id = 0, api = 'inventory' },
			[3] = { id = 3, api = 'temporary' },
			[5] = { id = 5, api = 'case' },
			[6] = { id = 6, api = 'safe' },
		},
	}
	f.deps = {
		now = function() return f.now end,
		enabled = function() return f.enabled end,
		player_has_doom = function() return f.doomed end,
		holy_water_item_id = 1234,
		item_resources = {},
		bag_resources = f.bags,
		get_items = function(bag)
			return f.items[tonumber(bag) or -1]
		end,
		get_bag_info = function(bag)
			return f.bag_info[tonumber(bag) or -1]
		end,
		get_item = function(bag, slot, count)
			f.move_count = f.move_count + 1
			f.last_move = { bag = bag, slot = slot, count = count }
			return true
		end,
		reserve_lane = function()
			f.reserve_count = f.reserve_count + 1
		end,
		use_holy_water = function()
			f.use_count = f.use_count + 1
			return true
		end,
		log = function(message)
			f.logs[#f.logs + 1] = message
		end,
	}
	return f
end

-- No Holy Water means the emergency path must not reserve the lane.
do
	local f = new_fixture()
	local state = doom_water.new_state()
	local blocked, reason = doom_water.step(state, f.deps)
	assert_equal(blocked, false, 'no-water block')
	assert_equal(reason, 'DOOM_WATER_NO_ACCESSIBLE_ITEM', 'no-water reason')
	assert_equal(f.reserve_count, 0, 'no-water reserve')
	assert_equal(f.use_count, 0, 'no-water use')
	assert_equal(f.move_count, 0, 'no-water move')
end

-- Holy Water already in Inventory is used immediately and enters a real reuse hold.
do
	local f = new_fixture()
	f.items[0] = { { id = 1234, count = 2, slot = 4 } }
	local state = doom_water.new_state()
	local blocked, reason = doom_water.step(state, f.deps)
	assert_true(blocked, 'inventory water block')
	assert_equal(reason, 'BLOCK_DOOM_WATER', 'inventory water reason')
	assert_equal(f.use_count, 1, 'inventory water use')
	assert_equal(state.phase, 'cooldown', 'inventory water phase')
	f.now = 10.2
	blocked, reason = doom_water.step(state, f.deps)
	assert_true(blocked, 'reuse hold block')
	assert_equal(reason, 'BLOCK_DOOM_WATER_HOLD', 'reuse hold reason')
	assert_equal(f.use_count, 1, 'reuse hold must not use again')
end

-- Accessible-bag water is staged exactly once; unrelated item events do nothing.
do
	local f = new_fixture()
	f.items[5] = { { id = 1234, count = 7, slot = 19 } }
	local state = doom_water.new_state()
	local blocked, reason = doom_water.step(state, f.deps)
	assert_true(blocked, 'stage block')
	assert_equal(reason, 'BLOCK_DOOM_WATER_STAGING', 'stage reason')
	assert_equal(state.phase, 'staging', 'stage phase')
	assert_equal(f.move_count, 1, 'stage move count')
	assert_equal(f.last_move.bag, 5, 'stage source bag')
	assert_equal(f.last_move.slot, 19, 'stage source slot')
	assert_equal(f.last_move.count, 1, 'stage count')
	local event_used, event_reason = doom_water.on_add_item(state, 0, 8, 9999, 1, f.deps)
	assert_equal(event_used, false, 'unrelated add event')
	assert_equal(event_reason, 'UNRELATED_ITEM', 'unrelated add reason')
	assert_equal(f.use_count, 0, 'unrelated add use count')

	-- Server/Windower confirms the staged Holy Water in Inventory.
	f.items[0] = { { id = 1234, count = 1, slot = 8 } }
	event_used, event_reason = doom_water.on_add_item(state, 0, 8, 1234, 1, f.deps)
	assert_true(event_used, 'confirmed add dispatch')
	assert_equal(event_reason, 'BLOCK_DOOM_WATER', 'confirmed add reason')
	assert_equal(f.use_count, 1, 'confirmed add immediate use')
	assert_equal(state.phase, 'cooldown', 'confirmed add cooldown phase')
end

-- A failed/missing stage confirmation is bounded; normal status removal may resume.
do
	local f = new_fixture()
	f.items[5] = { { id = 1234, count = 1, slot = 11 } }
	local state = doom_water.new_state()
	local blocked = doom_water.step(state, f.deps)
	assert_true(blocked, 'timeout setup block')
	f.now = 11.01
	blocked, reason = doom_water.step(state, f.deps)
	assert_equal(blocked, false, 'stage timeout block')
	assert_equal(reason, 'DOOM_WATER_STAGE_TIMEOUT', 'stage timeout reason')
	assert_equal(state.phase, 'idle', 'stage timeout reset')
	assert_equal(f.use_count, 0, 'stage timeout use count')
end

-- Inventory full means staging is not a viable attempt and must fall through.
do
	local f = new_fixture()
	f.items[5] = { { id = 1234, count = 3, slot = 12 } }
	f.bag_info[0].count = 80
	local state = doom_water.new_state()
	local blocked, reason = doom_water.step(state, f.deps)
	assert_equal(blocked, false, 'inventory-full block')
	assert_equal(reason, 'DOOM_WATER_INVENTORY_FULL', 'inventory-full reason')
	assert_equal(f.move_count, 0, 'inventory-full move')
	assert_equal(f.reserve_count, 0, 'inventory-full reserve')
end

-- Disabled bags must not count as usable Holy Water sources.
do
	local f = new_fixture()
	f.items[6] = { { id = 1234, count = 9, slot = 3 } }
	local state = doom_water.new_state()
	local blocked, reason = doom_water.step(state, f.deps)
	assert_equal(blocked, false, 'disabled-bag block')
	assert_equal(reason, 'DOOM_WATER_NO_ACCESSIBLE_ITEM', 'disabled-bag reason')
end

-- If Doom disappears while a move is in flight, the add-item event must not use water.
do
	local f = new_fixture()
	f.items[5] = { { id = 1234, count = 1, slot = 7 } }
	local state = doom_water.new_state()
	assert_true(doom_water.step(state, f.deps), 'doom-gone setup')
	f.doomed = false
	f.items[0] = { { id = 1234, count = 1, slot = 2 } }
	local acted, reason = doom_water.on_add_item(state, 0, 2, 1234, 1, f.deps)
	assert_equal(acted, false, 'doom-gone add event')
	assert_equal(reason, 'DOOM_GONE_BEFORE_STAGE_CONFIRM', 'doom-gone add reason')
	assert_equal(f.use_count, 0, 'doom-gone use')
	assert_equal(state.phase, 'idle', 'doom-gone reset')
end

-- After a real Holy Water action cooldown expires, no remaining water falls through.
do
	local f = new_fixture()
	f.items[0] = { { id = 1234, count = 1, slot = 1 } }
	local state = doom_water.new_state()
	assert_true(doom_water.step(state, f.deps), 'last-water initial use')
	f.items[0] = {}
	f.now = 11.21
	local blocked, reason = doom_water.step(state, f.deps)
	assert_equal(blocked, false, 'last-water fallback block')
	assert_equal(reason, 'DOOM_WATER_NO_ACCESSIBLE_ITEM', 'last-water fallback reason')
	assert_equal(f.use_count, 1, 'last-water use count')
end

io.stdout:write('selftest_doom_water: OK\n')
