package.path = package.path .. ';./?.lua'

local geo_maintenance = require('uc_geo_maintenance')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(
			message or 'values differ', tostring(expected), tostring(actual)
		))
	end
end

local function assert_no_action(out, action_name, message)
	for i = 1, #out do
		if tostring(out[i].action_name or '') == action_name then
			error(message or ('unexpected action: ' .. action_name))
		end
	end
end

local resources = {
	['Geo-Frailty'] = {
		id = 768,
		en = 'Geo-Frailty',
		range = 12,
		targets = { Enemy = true },
	},
	['Indi-Haste'] = {
		id = 795,
		en = 'Indi-Haste',
		range = 1,
		targets = { Self = true },
	},
	['Indi-Malaise'] = {
		id = 798,
		en = 'Indi-Malaise',
		range = 1,
		targets = { Self = true },
	},
}

local function new_provider()
	return geo_maintenance.new({
		geo_maintenance_priority = 210,
		geo_creation_priority = 240,
		action_ready = function(name)
			if resources[name] ~= nil then
				return true, 'ready', 'spell'
			end
			return true, 'ready', 'ja'
		end,
		get_spell_resource = function(name)
			return resources[name]
		end,
		get_ja_resource = function(name)
			return { id = 1000, en = name }
		end,
		get_party_members = function()
			return {}
		end,
		get_friendly_claims = function()
			return { [900] = true }
		end,
		resolve_camp_anchor = function()
			return { x = 10, y = 20 }, 'CAMP_READY'
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
		geo_target = { kind = 'current_enemy' },
		indi_spell = 'Indi-Haste',
		ordering = 'indi_first',
		require_camp = false,
		camp_tolerance_yalms = 1.0,
		enemy_geo_requires_camp_radius = false,
		unknown_existing_policy = 'wait_for_clear',
		entrust = { enabled = false },
		luopan = {
			placement = 'target',
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
		name = 'Zerde',
		hpp = 100,
		distance = 25,
		x = 10,
		y = 20,
		valid_target = true,
		spawn_type = 16,
		claim_id = 900,
	}
	return {
		now = now,
		settings = { config = { maintenance = { geo = config() } } },
		player_present = true,
		player = {
			id = 100,
			name = 'Geomancer',
			main_job = 'GEO',
			buffs = {},
		},
		player_id = 100,
		player_name = 'Geomancer',
		me = { id = 100, name = 'Geomancer', x = 10, y = 20 },
		pet_present = false,
		mob_array = { target },
		mobs_by_id = { [200] = target },
	}
end

local original_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)

local provider = new_provider()
local ctx = context(1.0)
local out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'pre-pull Indi proposal count')
assert_equal(out[1].action_name, 'Indi-Haste', 'pre-pull Indi proposal')
provider.note_dispatch(out[1], 1.1)
ctx.now = 2.0
ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().owned_indi_spell, 'Indi-Haste', 'observed Indi ownership')
assert_no_action(out, 'Indi-Haste', 'observed pre-pull Indi must not recast')

-- Activity/profile transitions may temporarily disable the engine or maintenance
-- policy, but neither transition removes the live Indi-Colure effect in game.
rawset(_G, 'Start_Engine', false)
ctx.now = 3.0
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().owned_indi_spell, 'Indi-Haste', 'engine-off transition must retain owned Indi identity')

rawset(_G, 'Start_Engine', true)
ctx.now = 4.0
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().owned_indi_spell, 'Indi-Haste', 'combat startup must retain pre-pull Indi identity')
assert_no_action(out, 'Indi-Haste', 'combat startup must not redundantly recast pre-pull Indi')

ctx.settings.config.maintenance.geo.enabled = false
ctx.now = 5.0
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().owned_indi_spell, 'Indi-Haste', 'config-disable transition must retain owned Indi identity')
ctx.settings.config.maintenance.geo.enabled = true

-- A maintenance-domain handoff clears transient action state only. Exact effect
-- identity must survive because the real buff survives the handoff.
provider.reset('GEO_MAINTENANCE_DOMAIN_DISABLED')
assert_equal(provider.status_snapshot().owned_indi_spell, 'Indi-Haste', 'maintenance-domain reset must retain owned Indi identity')
ctx.now = 6.0
out = {}
provider.collect(ctx, out)
assert_no_action(out, 'Indi-Haste', 'domain handoff must not cause redundant Indi recast')

-- Pending-token timeout is unrelated to exact Indi ownership and must not erase it.
provider.note_dispatch({
	action_type = 'ja',
	action_name = 'Life Cycle',
	target_id = 100,
	detail = { geo_kind = 'life_cycle_complete' },
}, 6.1)
ctx.now = 15.0
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().owned_indi_spell, 'Indi-Haste', 'pending timeout must retain owned Indi identity')

-- A legitimate configured replacement remains possible while the generic buff
-- is still active because the old exact identity is retained and compared.
ctx.settings.config.maintenance.geo.indi_spell = 'Indi-Malaise'
ctx.now = 16.0
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'configured Indi replacement proposal count')
assert_equal(out[1].action_name, 'Indi-Malaise', 'configured Indi replacement must be proposed')

-- Actual loss of the generic Indi-Colure effect clears exact ownership.
ctx.player.buffs = {}
ctx.now = 17.0
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().owned_indi_spell, nil, 'lost Indi-Colure must clear owned Indi identity')

if original_engine == nil then
	rawset(_G, 'Start_Engine', nil)
else
	rawset(_G, 'Start_Engine', original_engine)
end

io.stdout:write('selftest_geo_indi_ownership: OK\n')
