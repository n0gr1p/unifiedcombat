package.path = './?.lua;' .. package.path

local food = require('uc_provider_food')
local normalizer = require('uc_config_normalizer_base')
local command_builder = require('uc_scheduler_command_builder')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s (expected=%s actual=%s)'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then error(message) end
end

local moving = false
local inventory = {
	enabled = true,
	[1] = { id = 1001, count = 3 },
}
local provider = food.new({
	get_items = function(bag)
		assert_equal(bag, 'Inventory', 'food must only inspect usable Inventory')
		return inventory
	end,
	player_is_moving = function() return moving end,
	clamp_urgency = function(v) return v end,
	build_action_command = function(name, kind)
		assert_equal(kind, 'item', 'food proposal action kind')
		return ('input /item "%s" <me>'):format(name)
	end,
	buff_resources = {
		[251] = { en = 'Food' },
	},
	item_resources = {
		[1001] = { en = 'Grape Daifuku' },
		[1002] = { en = 'Marine Stewpot' },
	},
	priority_band = 50,
})

local function collect(now, enabled, item, buffs)
	local out = {}
	provider.collect({
		now = now,
		player = { id = 123, name = 'Niightsiide', buffs = buffs or {} },
		config = {
			maintenance = {
				food = {
					enabled = enabled,
					item = item or '',
				},
			},
		},
		settings = {
			food_enabled = not enabled,
			food_item = 'Flat State Must Be Ignored',
		},
	}, out)
	return out
end

assert_equal(#collect(1.0, false, 'Grape Daifuku'), 0, 'disabled canonical food maintenance must emit nothing')

local proposal = collect(2.0, true, 'Grape Daifuku')
assert_equal(#proposal, 1, 'missing Food buff with inventory food must emit one proposal')
assert_equal(proposal[1].provider, 'maintenance_food', 'food provider identity')
assert_equal(proposal[1].action_type, 'item', 'food must be a first-class item action')
assert_equal(proposal[1].action_name, 'Grape Daifuku', 'configured food name')
assert_equal(proposal[1].priority_band, 50, 'food priority band')
assert_equal(proposal[1].target_kind, 'self', 'food target kind')
assert_equal(proposal[1].legacy_command, 'input /item "Grape Daifuku" <me>', 'food command')
assert_equal(proposal[1].movement_policy, 'must_stop', 'food must request a stopped action lane')

inventory = { enabled = true, [1] = { id = 1002, count = 1 } }
local canonical_out = {}
provider.collect({
	now = 2.6,
	player = { id = 123, name = 'Niightsiide', buffs = {} },
	config = {
		maintenance = {
			food = { enabled = true, item = 'Marine Stewpot' },
		},
	},
	settings = {
		food_enabled = false,
		food_item = 'Grape Daifuku',
	},
}, canonical_out)
assert_equal(#canonical_out, 1, 'canonical food config must drive maintenance even when flat compatibility disagrees')
assert_equal(canonical_out[1].action_name, 'Marine Stewpot', 'canonical food item must be authoritative')
inventory = { enabled = true, [1] = { id = 1001, count = 3 } }

assert_equal(#collect(3.2, true, 'Grape Daifuku', { 251 }), 0, 'existing Food buff must never be overwritten')

moving = true
assert_equal(#collect(4.0, true, 'Grape Daifuku'), 0, 'food must wait while the player is moving')
moving = false

inventory = { enabled = true }
assert_equal(#collect(5.0, true, 'Grape Daifuku'), 0, 'missing configured item must not emit an action')
local available, count = provider.inventory_has_item('Grape Daifuku')
assert_true(not available, 'missing inventory helper result')
assert_equal(count, 0, 'missing inventory count')

inventory = { enabled = true, [1] = { id = 1001, count = 2 } }
available, count = provider.inventory_has_item('grape daifuku')
assert_true(available, 'inventory lookup should be case insensitive')
assert_equal(count, 2, 'inventory count must be reported')

local nested = normalizer.normalize({
	maintenance = {
		food = {
			enabled = true,
			item = 'Grape Daifuku',
		},
	},
})
assert_true(nested.maintenance.food.enabled, 'structured food enabled must normalize')
assert_equal(nested.maintenance.food.item, 'Grape Daifuku', 'structured food item must normalize')

local flat = normalizer.normalize({
	food_enabled = true,
	food_item = 'Marine Stewpot',
})
assert_true(flat.maintenance.food.enabled, 'flat food enabled must migrate')
assert_equal(flat.maintenance.food.item, 'Marine Stewpot', 'flat food item must migrate')

local ok = pcall(function()
	normalizer.normalize({
		maintenance = {
			food = { enabled = true, item = '' },
		},
	})
end)
assert_true(not ok, 'enabled food maintenance must require an item name')

local item_command = command_builder.build_action_command({
	action_target_mode = function()
		error('item command must not require spell/JA target metadata')
	end,
}, 'Grape Daifuku', 'item', { is_self = true })
assert_equal(item_command, 'input /item "Grape Daifuku" <me>', 'item command builder')

local scheduler_file = assert(io.open('./unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(scheduler_source:find('scheduler.PRIORITY_BAND_FOOD_MAINTENANCE = 50', 1, true) ~= nil, 'food priority band missing')
assert_true(scheduler_source:find('scheduler.providers.food.collect(ctx, out)', 1, true) ~= nil, 'food provider collection missing')
assert_true(scheduler_source:find("scheduler.providers.food = require('uc_provider_food').new({", 1, true) ~= nil, 'food provider initialization missing')
assert_true(scheduler_source:find("if provider == 'maintenance_food' then", 1, true) ~= nil, 'food dispatch routing missing')
assert_true(scheduler_source:find("action_mark_sent('item'", 1, true) ~= nil, 'food dispatch must enter scheduler action state')

local ranker_file = assert(io.open('./uc_scheduler_ranker.lua', 'r'))
local ranker_source = ranker_file:read('*a')
ranker_file:close()
assert_true(ranker_source:find("action_type == 'item'", 1, true) ~= nil, 'item actions must participate in pending conflict arbitration')

local locks_file = assert(io.open('./uc_scheduler_locks.lua', 'r'))
local locks_source = locks_file:read('*a')
locks_file:close()
assert_true(locks_source:find("action_type == 'item'", 1, true) ~= nil, 'item actions must honor hard cast locks')

io.stdout:write('selftest_food_maintenance: OK\n')
