package.path = package.path .. ';./?.lua'

local geo_maintenance = require('uc_geo_maintenance')

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(
			message or 'values differ',
			tostring(expected),
			tostring(actual)
		))
	end
end

local resources = {
	['Geo-Frailty'] = {
		id = 768,
		en = 'Geo-Frailty',
		range = 12,
		targets = {
			Enemy = true,
		},
	},
	['Indi-Haste'] = {
		id = 795,
		en = 'Indi-Haste',
		range = 1,
		targets = {
			Self = true,
		},
	},
}

local camp_anchor = {
	x = 10,
	y = 20,
}

local function new_provider()
	return geo_maintenance.new({
		action_ready = function()
			return true, 'ready', 'spell'
		end,
		get_spell_resource = function(name)
			return resources[name]
		end,
		get_ja_resource = function(name)
			return {
				id = 1000,
				en = name,
			}
		end,
		get_party_members = function()
			return {}
		end,
		get_friendly_claims = function()
			return {
				[900] = true,
			}
		end,
		resolve_camp_anchor = function()
			return camp_anchor, 'CAMP_READY'
		end,
		action_effective_range = function()
			return 20.0
		end,
		target_is_actionable = function(target)
			return type(target) == 'table' and tonumber(target.hpp) > 0
		end,
		target_is_ignored = function()
			return false
		end,
		player_is_moving = function()
			return false
		end,
		pull_active = function()
			return false
		end,
		log = function()
		end,
		action_timeline_log = function()
		end,
	})
end

local function config()
	return {
		enabled = true,
		geo_spell = 'Geo-Frailty',
		geo_target = {
			kind = 'current_enemy',
			name = nil,
		},
		indi_spell = 'Indi-Haste',
		ordering = 'geo_first',
		require_camp = true,
		camp_tolerance_yalms = 1.0,
		unknown_existing_policy = 'wait_for_clear',
		entrust = {
			enabled = false,
		},
		luopan = {
			use_blaze_of_glory = false,
			use_ecliptic_attrition = false,
			use_life_cycle = false,
			life_cycle_hpp = 50,
			replace_out_of_position = false,
			max_camp_distance_yalms = 6.0,
		},
	}
end

local function context(now)
	local target = {
		id = 200,
		name = 'Apex Bat',
		hpp = 100,
		distance = 25,
		valid_target = true,
		spawn_type = 16,
		claim_id = 900,
	}
	return {
		now = now,
		settings = {
			config = {
				maintenance = {
					geo = config(),
				},
			},
		},
		player_present = true,
		player = {
			id = 100,
			name = 'Geomancer',
			main_job = 'GEO',
			buffs = {},
		},
		player_id = 100,
		player_name = 'Geomancer',
		me = {
			id = 100,
			name = 'Geomancer',
			x = 10,
			y = 20,
		},
		target_present = false,
		target = {},
		target_id_snapshot = 0,
		pet_present = false,
		mob_array = {
			target,
		},
		mobs_by_id = {
			[200] = target,
		},
	}
end

local original_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)

local provider = new_provider()
local ctx = context(1.0)
local out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'missing effects should emit one action')
assert_equal(out[1].provider, 'maintenance_geo', 'GEO provider id mismatch')
assert_equal(out[1].action_name, 'Geo-Frailty', 'geo_first should emit Geo spell')
assert_equal(out[1].target_id, 200, 'Geo target id mismatch')

provider.note_dispatch(out[1], 1.1)
ctx.now = 2.0
ctx.pet_present = true
ctx.pet = {
	id = 300,
	name = 'Luopan',
}
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'observed luopan should advance to Indi')
assert_equal(out[1].action_name, 'Indi-Haste', 'Indi follow-up mismatch')
assert_equal(out[1].target_id, 100, 'Indi must target self')

provider.note_dispatch(out[1], 2.1)
ctx.now = 3.0
ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
out = {}
provider.collect(ctx, out)
assert_equal(#out, 0, 'observed desired effects should converge')
assert_equal(provider.status.state, 'converged', 'converged state mismatch')

local unknown_provider = new_provider()
local unknown_ctx = context(5.0)
unknown_ctx.pet_present = true
unknown_ctx.pet = {
	id = 301,
	name = 'Luopan',
}
out = {}
unknown_provider.collect(unknown_ctx, out)
assert_equal(#out, 0, 'unknown existing luopan must not be overwritten')
assert_equal(unknown_provider.status.state, 'unknown_existing', 'unknown luopan state mismatch')

local camp_provider = new_provider()
local camp_ctx = context(6.0)
camp_ctx.me.x = 15
out = {}
camp_provider.collect(camp_ctx, out)
assert_equal(#out, 0, 'GEO maintenance must hold outside camp tolerance')
assert_equal(camp_provider.status.reason, 'GEO_AWAY_FROM_CAMP', 'camp hold reason mismatch')

local moving_provider = geo_maintenance.new({
	action_ready = function()
		return true, 'ready', 'spell'
	end,
	get_spell_resource = function(name)
		return resources[name]
	end,
	get_ja_resource = function(name)
		return {
			id = 1000,
			en = name,
		}
	end,
	get_party_members = function()
		return {}
	end,
	get_friendly_claims = function()
		return {
			[900] = true,
		}
	end,
	resolve_camp_anchor = function()
		return camp_anchor, 'CAMP_READY'
	end,
	action_effective_range = function()
		return 20.0
	end,
	target_is_actionable = function()
		return true
	end,
	target_is_ignored = function()
		return false
	end,
	player_is_moving = function()
		return true
	end,
	pull_active = function()
		return false
	end,
	log = function()
	end,
	action_timeline_log = function()
	end,
})
out = {}
moving_provider.collect(context(7.0), out)
assert_equal(#out, 0, 'moving player must not emit GEO spells')
assert_equal(moving_provider.status.reason, 'player_moving', 'moving hold reason mismatch')

if original_engine == nil then
	rawset(_G, 'Start_Engine', nil)
else
	rawset(_G, 'Start_Engine', original_engine)
end

assert_true(type(_G.UC_GEO_MAINTENANCE_STATUS) == 'table', 'GEO status overlay missing')
io.stdout:write('selftest_geo_maintenance: OK\n')
