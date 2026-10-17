package.path = './?.lua;' .. package.path

local geo_maintenance = require('uc_geo_maintenance')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_contains(source, needle, message)
	if not source:find(needle, 1, true) then
		error(message or ('missing text: ' .. needle))
	end
end

local function assert_not_contains(source, needle, message)
	if source:find(needle, 1, true) then
		error(message or ('unexpected text: ' .. needle))
	end
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local source = fh:read('*a')
	fh:close()
	return source
end

local resources = {
	['Geo-Frailty'] = { id = 768, en = 'Geo-Frailty', range = 12, targets = { Enemy = true } },
	['Indi-Haste'] = { id = 795, en = 'Indi-Haste', range = 1, targets = { Self = true } },
}

local function geo_config(enabled)
	return {
		enabled = enabled == true,
		geo_spell = 'Geo-Frailty',
		geo_target = { kind = 'current_enemy', name = nil },
		indi_spell = 'Indi-Haste',
		ordering = 'geo_first',
		require_camp = false,
		camp_tolerance_yalms = 1.0,
		enemy_geo_requires_camp_radius = false,
		unknown_existing_policy = 'wait_for_clear',
		entrust = { enabled = false, spell = nil, target_name = nil },
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

local function blocked_by_names(source, mob)
	if type(source) ~= 'table' or type(mob) ~= 'table' then return false end
	local names = type(source.targeting) == 'table'
		and source.targeting.target_ignore_names
		or source.target_ignore_names
	if type(names) ~= 'table' then return false end
	local needle = tostring(mob.name or ''):lower()
	for i = 1, #names do
		if tostring(names[i] or ''):lower() == needle then return true end
	end
	return false
end

local function new_provider()
	return geo_maintenance.new({
		geo_maintenance_priority = 210,
		geo_creation_priority = 240,
		action_ready = function(name)
			if resources[name] ~= nil then return true, 'ready', 'spell' end
			return true, 'ready', 'ja'
		end,
		get_spell_resource = function(name) return resources[name] end,
		get_ja_resource = function(name) return { id = 1000, en = name } end,
		get_party_members = function() return {} end,
		get_friendly_claims = function() return { [900] = true } end,
		resolve_camp_anchor = function() return { x = 0, y = 0 }, 'CAMP_READY' end,
		action_effective_range = function() return 20.0 end,
		target_is_actionable = function(target)
			return type(target) == 'table' and tonumber(target.hpp) > 0
		end,
		target_is_ignored = blocked_by_names,
		player_is_moving = function() return false end,
		pull_active = function() return false end,
		log = function() end,
		action_timeline_log = function() end,
	})
end

local function context(canonical, compatibility, canonical_ignore, flat_ignore)
	local target = {
		id = 200,
		name = 'Apex Bat',
		hpp = 100,
		distance = 25,
		x = 5,
		y = 0,
		valid_target = true,
		spawn_type = 16,
		claim_id = 900,
	}
	return {
		now = 1.0,
		config = {
			maintenance = { geo = canonical },
			targeting = { target_ignore_names = canonical_ignore or {} },
		},
		settings = {
			maintenance_geo = compatibility,
			config = { maintenance = { geo = compatibility } },
			target_ignore_names = flat_ignore or {},
		},
		player_present = true,
		player = { id = 100, name = 'Geomancer', main_job = 'GEO', buffs = {} },
		player_id = 100,
		player_name = 'Geomancer',
		me = { id = 100, name = 'Geomancer', x = 0, y = 0 },
		target_present = false,
		target = {},
		target_id_snapshot = 0,
		pet_present = false,
		mob_array = { target },
		mobs_by_id = { [200] = target },
	}
end

local function collect_once(ctx)
	local provider = new_provider()
	local out = {}
	provider.collect(ctx, out)
	return provider, out
end

local function test_config_adapter_authority()
	local canonical = geo_config(true)
	canonical.ordering = 'indi_first'
	canonical.camp_tolerance_yalms = 2.25
	canonical.luopan.life_cycle_hpp = 44
	local compatibility = geo_config(false)
	compatibility.ordering = 'geo_first'
	compatibility.camp_tolerance_yalms = 9.0
	compatibility.luopan.life_cycle_hpp = 90
	local resolved = geo_maintenance.config_from_context(context(canonical, compatibility))
	assert_equal(resolved, canonical, 'GEO adapter must return canonical maintenance.geo subtree')
	assert_true(resolved.enabled, 'canonical GEO enabled must beat compatibility disabled')
	assert_equal(resolved.ordering, 'indi_first', 'canonical GEO ordering must win')
	assert_equal(resolved.camp_tolerance_yalms, 2.25, 'canonical GEO camp tolerance must win')
	assert_equal(resolved.luopan.life_cycle_hpp, 44, 'canonical Luopan policy must win')
end

local function test_enablement_authority()
	local provider, out = collect_once(context(geo_config(false), geo_config(true)))
	assert_equal(#out, 0, 'canonical GEO OFF must beat compatibility ON')
	assert_equal(provider.status.state, 'disabled', 'canonical GEO OFF status')
	provider, out = collect_once(context(geo_config(true), geo_config(false)))
	assert_equal(#out, 1, 'canonical GEO ON must beat compatibility OFF')
	assert_equal(out[1].action_name, 'Geo-Frailty', 'canonical GEO action must be proposed')
end

local function test_target_ignore_authority()
	local _, out = collect_once(context(geo_config(true), geo_config(true), { 'Apex Bat' }, {}))
	assert_equal(#out, 0, 'canonical GEO target-ignore entry must beat flat empty state')
	_, out = collect_once(context(geo_config(true), geo_config(true), {}, { 'Apex Bat' }))
	assert_equal(#out, 1, 'canonical empty target-ignore list must beat flat blocked state')
	assert_equal(out[1].target_name, 'Apex Bat', 'canonical target eligibility must select enemy')
end

local function test_static_boundary()
	local provider_source = read_all('uc_geo_maintenance.lua')
	local scheduler_source = read_all('unified_scheduler.lua')
	assert_not_contains(provider_source, 'ctx.settings', 'GEO provider must not consume compatibility scheduler settings')
	assert_not_contains(provider_source, 'settings.config', 'GEO provider must not consume nested compatibility config')
	assert_contains(provider_source, 'function M.config_from_context(ctx)', 'GEO provider must expose canonical config adapter')
	assert_contains(provider_source, "require_table(ctx.config, 'ctx.config')", 'GEO adapter must require canonical root config')
	assert_contains(provider_source, 'local config = M.config_from_context(ctx)', 'GEO runtime paths must use canonical adapter')
	assert_contains(provider_source, 'target_is_ignored(ctx.config, mob)', 'GEO target ignore must receive canonical root config')
	assert_contains(scheduler_source, 'target_is_ignored = function(config, mob)', 'GEO scheduler target-ignore dependency must accept config')
	assert_contains(scheduler_source, 'uc_scheduler_config.targeting_ignore_names_from_config(config)',
		'GEO scheduler target-ignore dependency must project canonical targeting policy')
end

local previous_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)
local ok, err = pcall(function()
	test_config_adapter_authority()
	test_enablement_authority()
	test_target_ignore_authority()
	test_static_boundary()
end)
rawset(_G, 'Start_Engine', previous_engine)
if not ok then error(err, 0) end

print('selftest_phase4_geo_authority: OK (maintenance config + target-ignore authority)')
