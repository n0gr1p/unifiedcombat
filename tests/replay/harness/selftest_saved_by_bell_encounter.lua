package.path = './?.lua;' .. package.path

local saved_resources = package.loaded.resources
local saved_encounter = package.loaded.uc_saved_by_bell_encounter
local saved_provider = package.loaded.uc_provider_saved_by_bell
local saved_timeline = rawget(_G, 'UC_ACTION_TIMELINE_LOG')

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

package.loaded.resources = {
	spells = {
		[1] = { id = 1, en = 'Geo-Poison' },
		[2] = { id = 2, en = 'Geo-Fade' },
		[3] = { id = 3, en = 'Geo-Malaise' },
		[4] = { id = 4, en = 'Geo-Vex' },
		[5] = { id = 5, en = 'Geo-Languor' },
		[6] = { id = 6, en = 'Geo-Slow' },
		[7] = { id = 7, en = 'Geo-Paralysis' },
		[8] = { id = 8, en = 'Geo-Gravity' },
		[101] = { id = 101, en = 'Stone' },
		[102] = { id = 102, en = 'Water' },
		[103] = { id = 103, en = 'Aero' },
		[104] = { id = 104, en = 'Fire' },
		[105] = { id = 105, en = 'Blizzard' },
		[106] = { id = 106, en = 'Thunder' },
	},
}

package.loaded.uc_saved_by_bell_encounter = nil
package.loaded.uc_provider_saved_by_bell = nil

local events = {}
_G.UC_ACTION_TIMELINE_LOG = function(code, fields)
	events[#events + 1] = { code = code, fields = fields }
end

local encounter = require('uc_saved_by_bell_encounter')

local expected = {
	['Geo-Poison'] = { 'Thunder' },
	['Geo-Fade'] = { 'Water' },
	['Geo-Malaise'] = { 'Stone' },
	['Geo-Vex'] = { 'Stone', 'Water', 'Blizzard' },
	['Geo-Languor'] = { 'Aero', 'Fire', 'Thunder' },
	['Geo-Slow'] = { 'Aero' },
	['Geo-Paralysis'] = { 'Fire' },
	['Geo-Gravity'] = { 'Blizzard' },
}
for geo_spell, weakness in pairs(expected) do
	local actual = encounter.weakness_spells(geo_spell)
	assert_equal(#actual, #weakness, geo_spell .. ' weakness count')
	for i = 1, #weakness do
		assert_equal(actual[i], weakness[i], geo_spell .. ' weakness spell ' .. tostring(i))
	end
end

assert_true(encounter.configure({ enabled = true, id = 'saved_by_the_bell' }), 'encounter must configure')

local boss = { id = 1000, name = 'Bygone Geomancer', hpp = 100, status = 1, x = 0, y = 0, z = 0 }
local function snapshot(now, luopans)
	return encounter.observe_snapshot({
		now = now,
		boss = boss,
		luopans = luopans or {},
		player_id = 9000,
		player_name = 'Tester',
	})
end

local ok, reason = snapshot(1.0)
assert_true(ok, 'boss appearance must activate encounter')
assert_equal(reason, 'BOSS_ACTIVE', 'boss activation reason')
assert_equal(encounter.snapshot().phase, 'active', 'active phase')

local function spell_start(spell_id, target_id)
	return {
		actor_id = 1000,
		category = 8,
		targets = {
			{
				id = target_id or 9000,
				actions = { { param = spell_id } },
			},
		},
	}
end

ok, reason = encounter.on_action(spell_start(3), 1.1, {
	actor_name = 'Bygone Geomancer',
	target_position = { x = 5, y = 5, z = 0 },
})
assert_true(ok, 'Geo-Malaise cast must be tracked')
assert_equal(reason, 'GEO_CAST_TRACKED', 'Geo-Malaise cast reason')

snapshot(1.3, {
	{ id = 2001, name = 'Luopan', hpp = 100, status = 1, x = 5, y = 5, z = 0 },
})
local state = encounter.snapshot()
assert_true(type(state.luopans[2001]) == 'table', 'new Luopan must bind to tracked cast')
assert_equal(state.luopans[2001].geo_spell, 'Geo-Malaise', 'bound Geo spell')
assert_equal(state.luopans[2001].weakness_spells[1], 'Stone', 'Malaise weakness')

local mobs = {
	[2001] = { id = 2001, name = 'Luopan', hpp = 100, valid_target = true },
}
local ready = { Stone = true }
local provider = require('uc_provider_saved_by_bell').new({
	snapshot = encounter.snapshot,
	action_ready = function(name)
		return ready[name] == true, ready[name] and '' or 'not_ready', 'spell'
	end,
	clamp_urgency = function(v) return v end,
	get_mob_by_id = function(id) return mobs[id] end,
	priority_band = 140,
})
local out = {}
provider.collect({ now = 1.4 }, out)
assert_equal(#out, 1, 'bound Luopan must emit one nuke proposal')
assert_equal(out[1].provider, 'encounter_saved_by_bell', 'provider identity')
assert_equal(out[1].action_name, 'Stone', 'Malaise nuke')
assert_equal(out[1].target_id, 2001, 'Malaise target ID')
assert_equal(out[1].legacy_command, 'input /ma "Stone" 2001', 'target-ID nuke command')
assert_true(out[1].detail.allow_target_id_send == true, 'off-target ID send flag')

snapshot(1.6, {})
state = encounter.snapshot()
assert_equal(state.destroyed_count, 1, 'destroyed tracked Luopan count')
assert_true(state.seen_luopans[2001] == nil, 'disappeared Luopan ID must be reusable')

-- A Luopan already present when the boss is first observed must never be guessed.
encounter.reset('baseline_test')
assert_true(encounter.configure({ enabled = true, id = 'saved_by_the_bell' }), 'reconfigure baseline test')
encounter.observe_snapshot({
	now = 2.0,
	boss = boss,
	luopans = { { id = 2100, name = 'Luopan', hpp = 100, status = 1, x = 1, y = 1, z = 0 } },
	player_id = 9000,
	player_name = 'Tester',
})
state = encounter.snapshot()
assert_true(state.luopans[2100] == nil, 'baseline Luopan must remain unbound')
assert_true(type(state.unbound_luopans[2100]) == 'table', 'baseline Luopan must be recorded as unbound')

-- Two overlapping pending casts are correlated by the cast target positions rather than entity ID order.
assert_true(encounter.on_action(spell_start(1), 2.1, {
	actor_name = 'Bygone Geomancer',
	target_position = { x = 0, y = 0, z = 0 },
}))
assert_true(encounter.on_action(spell_start(6), 2.2, {
	actor_name = 'Bygone Geomancer',
	target_position = { x = 10, y = 0, z = 0 },
}))
snapshot(2.4, {
	{ id = 2100, name = 'Luopan', hpp = 100, status = 1, x = 1, y = 1, z = 0 },
	{ id = 2101, name = 'Luopan', hpp = 100, status = 1, x = 10, y = 0, z = 0 },
	{ id = 2102, name = 'Luopan', hpp = 100, status = 1, x = 0, y = 0, z = 0 },
})
state = encounter.snapshot()
assert_equal(state.luopans[2101].geo_spell, 'Geo-Slow', 'position match must bind Slow')
assert_equal(state.luopans[2102].geo_spell, 'Geo-Poison', 'position match must bind Poison')
assert_equal(#state.pending_casts, 0, 'matched casts must be consumed')

mobs[2101] = { id = 2101, name = 'Luopan', hpp = 100, valid_target = true }
mobs[2102] = { id = 2102, name = 'Luopan', hpp = 100, valid_target = true }
ready = { Aero = true, Thunder = true }
out = {}
provider.collect({ now = 2.5 }, out)
assert_equal(#out, 1, 'oldest bound Luopan should be selected')
assert_equal(out[1].target_id, 2101, 'oldest/lowest ID position-bound Luopan')
assert_equal(out[1].action_name, 'Aero', 'Slow weakness spell')

mobs[2101].hpp = 0
out = {}
provider.collect({ now = 2.6 }, out)
assert_equal(out[1].target_id, 2102, 'dead Luopan must be skipped')
assert_equal(out[1].action_name, 'Thunder', 'Poison weakness spell')

-- Vex can fall through its valid opposite-Light options when the cheapest spell is unavailable.
encounter.reset('vex_test')
assert_true(encounter.configure({ enabled = true, id = 'saved_by_the_bell' }), 'reconfigure Vex test')
snapshot(3.0)
assert_true(encounter.on_action(spell_start(4), 3.1, {
	actor_name = 'Bygone Geomancer',
	target_position = { x = 4, y = 4, z = 0 },
}))
snapshot(3.3, {
	{ id = 2200, name = 'Luopan', hpp = 100, status = 1, x = 4, y = 4, z = 0 },
})
mobs = {
	[2200] = { id = 2200, name = 'Luopan', hpp = 100, valid_target = true },
}
ready = { Water = true }
provider = require('uc_provider_saved_by_bell').new({
	snapshot = encounter.snapshot,
	action_ready = function(name)
		return ready[name] == true, ready[name] and '' or 'not_ready', 'spell'
	end,
	clamp_urgency = function(v) return v end,
	get_mob_by_id = function(id) return mobs[id] end,
	priority_band = 140,
})
out = {}
provider.collect({ now = 3.4 }, out)
assert_equal(out[1].action_name, 'Water', 'Vex must use next ready valid weakness')

-- An expired cast must fail closed rather than guessing a later Luopan identity.
encounter.reset('expiry_test')
assert_true(encounter.configure({ enabled = true, id = 'saved_by_the_bell' }), 'reconfigure expiry test')
snapshot(4.0)
assert_true(encounter.on_action(spell_start(8), 4.1, {
	actor_name = 'Bygone Geomancer',
	target_position = { x = 8, y = 8, z = 0 },
}))
snapshot(10.0, {
	{ id = 2300, name = 'Luopan', hpp = 100, status = 1, x = 8, y = 8, z = 0 },
})
state = encounter.snapshot()
assert_true(state.luopans[2300] == nil, 'expired cast must not bind Luopan')
assert_true(type(state.unbound_luopans[2300]) == 'table', 'expired-cast Luopan must remain unbound')

-- Non-Geo and wrong-actor spell starts are ignored.
local ignored = encounter.on_action({
	actor_id = 1000,
	category = 8,
	targets = { { id = 9000, actions = { { param = 101 } } } },
}, 10.1, { actor_name = 'Bygone Geomancer' })
assert_true(not ignored, 'non-Geo spell must be ignored')
ignored = encounter.on_action(spell_start(3), 10.2, { actor_name = 'Other Mob' })
assert_true(not ignored, 'wrong actor name must be ignored')

local runtime_file = assert(io.open('./uc_encounter_runtime.lua', 'r'))
local runtime_source = runtime_file:read('*a')
runtime_file:close()
assert_true(runtime_source:find("windower.ffxi.get_mob_by_target('pet')", 1, true) ~= nil,
	'runtime must identify the local player pet')
assert_true(runtime_source:find('and id ~= local_pet_id', 1, true) ~= nil,
	'runtime must exclude the player-owned Luopan')
assert_true(runtime_source:find("config.id == 'saved_by_the_bell'", 1, true) ~= nil,
	'runtime must select the Saved by the Bell encounter')

local scheduler_file = assert(io.open('./unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(scheduler_source:find('scheduler.providers.saved_by_bell.collect(ctx, out)', 1, true) ~= nil,
	'Saved by the Bell provider must participate in scheduler collection')
assert_true(scheduler_source:find("provider == 'encounter_saved_by_bell'", 1, true) ~= nil,
	'Saved by the Bell provider must use normal combat spell dispatch')

package.loaded.resources = saved_resources
package.loaded.uc_saved_by_bell_encounter = saved_encounter
package.loaded.uc_provider_saved_by_bell = saved_provider
_G.UC_ACTION_TIMELINE_LOG = saved_timeline

io.stdout:write('selftest_saved_by_bell_encounter: OK\n')
