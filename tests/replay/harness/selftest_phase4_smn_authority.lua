package.path = './?.lua;' .. package.path

package.loaded.uc_reaction_runtime = {
	smn_rage_should_hold = function()
		return false, '', nil
	end,
}

local maintenance_module = require('uc_smn_maintenance')
local adapter_module = require('uc_smn_pet_combat_adapter')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_false(value, message)
	assert_equal(value, false, message)
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local source = fh:read('*a')
	fh:close()
	return source
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

local function summoner_config(opts)
	opts = opts or {}
	local enabled = opts.enabled
	if enabled == nil then enabled = true end
	local engage = opts.engage
	if engage == nil then engage = true end
	local rage_enabled = opts.rage_enabled
	if rage_enabled == nil then rage_enabled = true end
	return {
		enabled = enabled,
		avatar = opts.avatar or 'Ifrit',
		maintenance = {
			avatar_favor = opts.favor == true,
			ward = {
				enabled = opts.ward == true,
				actions = opts.ward_actions or {},
			},
		},
		pet_combat = {
			engage_on_combat_start = engage,
			offensive_action = {
				enabled = rage_enabled,
				action = opts.rage_action or 'Flaming Crush',
				usage = 'on_cooldown',
				target_hpp_above_enabled = false,
				target_hpp_above = 50,
				pet_tp_above_enabled = false,
				pet_tp_above = 2000,
			},
		},
	}
end

local function flat_settings(opts)
	opts = opts or {}
	return {
		summoner_enabled = opts.enabled == true,
		summoner_avatar = opts.avatar or 'Garuda',
		summoner_avatar_favor = opts.favor == true,
		summoner_ward_enabled = opts.ward == true,
		summoner_ward_action = opts.ward_action or '',
		summoner_ward_actions = opts.ward_action or '',
		summoner_engage_on_combat_start = opts.engage == true,
		summoner_rage_enabled = opts.rage_enabled == true,
		summoner_rage_action = opts.rage_action or 'Predator Claws',
		summoner_rage_usage = 'on_cooldown',
		summoner_rage_target_hpp_above_enabled = false,
		summoner_rage_target_hpp_above = 50,
		summoner_rage_pet_tp_above_enabled = false,
		summoner_rage_pet_tp_above = 2000,
	}
end

local function base_ctx(config, flat)
	return {
		now = 10,
		config = { summoner = config },
		settings = flat,
		player_present = true,
		player = {
			id = 100,
			name = 'Tester',
			main_job = 'SMN',
			vitals = { mp = 1000 },
			buffs = {},
		},
		player_id = 100,
		player_name = 'Tester',
		pet_present = false,
		pet_id = 0,
		pet_name = '',
		pet_status = 0,
		pet_target_id = 0,
		pet_target_matches_current = false,
		pet_tp = 3000,
		target_id = 300,
		target_hpp = 100,
		combat_generation = 1,
		ability_recasts_present = true,
		ability_recasts = {
			[170] = 0,
			[172] = 0,
			[173] = 0,
			[174] = 0,
		},
		pet = {
			id = 200,
			name = 'Ifrit',
			x = 4,
			y = 0,
		},
		target = {
			id = 300,
			name = 'Enemy',
			hpp = 100,
			valid_target = true,
			x = 5,
			y = 0,
		},
	}
end

local maintenance = maintenance_module.new({
	action_ready = function(name)
		if name == 'Ifrit' or name == 'Garuda' then
			return true, '', 'spell'
		end
		if name == "Avatar's Favor" then
			return true, '', 'ja'
		end
		return false, 'not_ready', 'none'
	end,
	coordinator_can_attempt = function() return true, '', 0 end,
	player_is_moving = function() return false end,
	get_ja_resource = function() return nil end,
	log = function() end,
})

local adapter = adapter_module.new({
	get_ja_resource = function(name)
		if name == 'Flaming Crush' then
			return { mp_cost = 164, range = 2 }
		end
		if name == 'Predator Claws' then
			return { mp_cost = 165, range = 2 }
		end
		return nil
	end,
	action_effective_range = function() return 3.9 end,
})

local function collect_maintenance(ctx)
	local out = {}
	maintenance.collect(ctx, out)
	return out
end

local function test_maintenance_authority()
	_G.Start_Engine = true

	local canonical_off = summoner_config({ enabled = false })
	local flat_on = flat_settings({
		enabled = true,
		avatar = 'Garuda',
		favor = true,
		ward = true,
		ward_action = 'Hastega II',
		engage = true,
		rage_enabled = true,
	})
	local out = collect_maintenance(base_ctx(canonical_off, flat_on))
	assert_equal(#out, 0, 'canonical SMN disabled must beat flat enabled state')
	assert_equal(_G.UC_SMN_MAINTENANCE_STATUS.state, 'disabled', 'canonical disabled maintenance status')

	local canonical_on = summoner_config({ enabled = true, avatar = 'Ifrit' })
	local flat_off = flat_settings({
		enabled = false,
		avatar = 'Garuda',
		engage = false,
		rage_enabled = false,
	})
	local ctx = base_ctx(canonical_on, flat_off)
	out = collect_maintenance(ctx)
	assert_equal(#out, 1, 'canonical SMN enabled must beat flat disabled state')
	assert_equal(out[1].action_name, 'Ifrit', 'canonical avatar must beat conflicting flat avatar')

	local selected = out[1]
	ctx.config.summoner.avatar = 'Garuda'
	local valid, reason = maintenance.revalidate(selected, ctx)
	assert_false(valid, 'revalidation must use current canonical Summoner config')
	assert_equal(reason, 'stale_summon', 'canonical avatar change revalidation reason')
end

local function test_pet_combat_authority()
	local canonical_off = summoner_config({
		enabled = true,
		avatar = 'Ifrit',
		engage = false,
		rage_enabled = false,
	})
	local flat_on = flat_settings({
		enabled = true,
		avatar = 'Garuda',
		engage = true,
		rage_enabled = true,
		rage_action = 'Predator Claws',
	})
	local ctx = base_ctx(canonical_off, flat_on)
	ctx.pet_present = true
	ctx.pet_id = 200
	ctx.pet_name = 'Ifrit'
	local snapshot = adapter.snapshot(ctx)
	assert_true(snapshot.enabled, 'canonical enabled SMN pet snapshot')
	assert_true(snapshot.correct_pet, 'canonical avatar must determine correct pet')
	assert_equal(snapshot.config.avatar, 'Ifrit', 'snapshot must retain canonical avatar')
	assert_equal(adapter.engagement(snapshot, ctx), nil, 'canonical engage OFF must beat flat engage ON')
	assert_equal(adapter.offensive_action(snapshot, ctx), nil, 'canonical Rage OFF must beat flat Rage ON')

	local canonical_on = summoner_config({
		enabled = true,
		avatar = 'Ifrit',
		engage = true,
		rage_enabled = true,
		rage_action = 'Flaming Crush',
	})
	local flat_off = flat_settings({
		enabled = false,
		avatar = 'Garuda',
		engage = false,
		rage_enabled = false,
		rage_action = 'Predator Claws',
	})
	ctx = base_ctx(canonical_on, flat_off)
	ctx.pet_present = true
	ctx.pet_id = 200
	ctx.pet_name = 'Ifrit'
	snapshot = adapter.snapshot(ctx)
	local engage = adapter.engagement(snapshot, ctx)
	assert_true(type(engage) == 'table', 'canonical engage ON must beat flat engage OFF')
	assert_equal(engage.action_name, 'Assault', 'canonical engagement action')
	local rage = adapter.offensive_action(snapshot, ctx)
	assert_true(type(rage) == 'table', 'canonical Rage ON must beat flat Rage OFF')
	assert_equal(rage.action_name, 'Flaming Crush', 'canonical Rage action must beat conflicting flat action')
end

local function test_static_boundary()
	local maintenance_source = read_all('uc_smn_maintenance.lua')
	local adapter_source = read_all('uc_smn_pet_combat_adapter.lua')
	local runtime_source = read_all('uc_smn_runtime.lua')

	assert_not_contains(maintenance_source, 'ctx.settings', 'SMN maintenance must not consume flat scheduler settings')
	assert_not_contains(adapter_source, 'ctx.settings', 'SMN pet combat must not consume flat scheduler settings')
	assert_not_contains(maintenance_source, 'config_from_settings', 'SMN maintenance must not rebuild config from flat state')
	assert_not_contains(adapter_source, 'config_from_settings', 'SMN pet combat must not rebuild config from flat state')
	assert_contains(maintenance_source, 'runtime.config_from_config(ctx.config)', 'SMN maintenance canonical config reader')
	assert_contains(adapter_source, 'runtime.config_from_config(ctx.config)', 'SMN pet combat canonical config reader')
	assert_contains(runtime_source, 'function M.config_from_config(config)', 'SMN runtime must expose canonical config reader')
	assert_contains(runtime_source, 'Compatibility parser for legacy/direct callers and migration tests only.',
		'legacy SMN flat parser must be explicitly classified as compatibility-only')
end

test_maintenance_authority()
test_pet_combat_authority()
test_static_boundary()

print('selftest_phase4_smn_authority: OK (maintenance + pet combat)')
