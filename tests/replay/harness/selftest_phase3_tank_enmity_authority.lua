package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_false(value, message)
	assert_equal(value, false, message)
end

local function assert_contains(source, needle, message)
	if not source:find(needle, 1, true) then
		error(message or ('missing expected text: ' .. tostring(needle)))
	end
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local content = fh:read('*a')
	fh:close()
	return content
end

local saved = {}
for _, name in ipairs({
	'uc_provider_tank_enmity',
	'uc_provider_run_tank',
	'uc_tank_pet_enmity',
	'resources',
}) do
	saved[name] = package.loaded[name]
end
local previous_engine = rawget(_G, 'Start_Engine')
local previous_windower = rawget(_G, 'windower')

local scheduler_config = require('uc_scheduler_config')

local observed_pet_settings = nil
local pet_violation = {
	mob = {
		id = 900,
		name = 'Zerde',
		valid_target = true,
		spawn_type = 16,
		hpp = 90,
		status = 1,
		distance = 16,
	},
	victim_id = 300,
	victim_name = 'Ifrit',
	victim_hpp = 40,
	owner_id = 200,
	owner_name = 'Summoner',
	mob_hpp = 90,
	dist = 4,
}
package.loaded.uc_tank_pet_enmity = {
	find_violation = function(settings)
		observed_pet_settings = settings
		return pet_violation
	end,
}
package.loaded.uc_provider_run_tank = {
	new = function()
		return { collect = function() end }
	end,
}
package.loaded.resources = {
	spells = {
		with = function(_, key, name)
			if key == 'en' and name == 'Flash' then
				return { en = 'Flash', range = 12 }
			end
			return nil
		end,
	},
	job_abilities = {
		with = function(_, key, name)
			if key == 'en' and name == 'Provoke' then
				return { en = 'Provoke', range = 10 }
			end
			return nil
		end,
	},
}
rawset(_G, 'windower', {
	ffxi = {
		get_party = function() return {} end,
		get_mob_by_index = function() return nil end,
		get_mob_by_id = function(id)
			if tonumber(id) == 900 then return pet_violation.mob end
			return nil
		end,
		get_mob_array = function() return { pet_violation.mob } end,
	},
})
package.loaded.uc_provider_tank_enmity = nil
local tank_provider = require('uc_provider_tank_enmity')

local function bool_setting(value, default_value)
	if value == nil then return default_value end
	return value == true
end

local function provider()
	return tank_provider.new({
		bool_setting = bool_setting,
		abilities_allow_unengaged = scheduler_config.abilities_allow_unengaged_from_config,
		select_tank_enmity = function() return nil end,
		action_ready = function(name, target_id)
			if name == 'Flash' and tonumber(target_id) == 900 then
				return true, 'READY', 'spell'
		end
		return false, 'NOT_READY', 'spell'
		end,
		action_effective_range = function() return 20 end,
		log_tank_sched = function() end,
		clamp_urgency = function(value) return value end,
	})
end

local function config(tank_enabled, include_pets, actions, ignore_names)
	return {
		tank = {
			enabled = tank_enabled,
			enmity = {
				actions = actions or { 'spell:Flash' },
				include_pets = include_pets,
			},
		},
		targeting = {
			target_ignore_names = ignore_names or {},
		},
		abilities = {
			allow_unengaged = true,
		},
	}
end

local function context(cfg, flat)
	return {
		now = 10,
		config = cfg,
		settings = flat or {
			tank = false,
			tank_enmity_actions = { 'ja:Provoke' },
			tank_enmity_include_pets = false,
			target_ignore_names = { 'Flat Ignore' },
		},
		player_present = true,
		player = { id = 100, name = 'Tank', status = 1 },
		mobs_by_id = { [900] = pet_violation.mob },
	}
end

local function test_accessors()
	local cfg = config(true, true, { 'spell:Flash', { name = 'Provoke' } }, { 'Ignored Mob' })
	assert_true(scheduler_config.tank_enabled_from_config(cfg), 'canonical tank enabled accessor')
	assert_equal(scheduler_config.tank_enmity_actions_from_config(cfg)[1], 'spell:Flash',
		'canonical tank action list accessor')
	assert_true(scheduler_config.tank_enmity_include_pets_from_config(cfg),
		'canonical include-pets accessor')
	assert_true(scheduler_config.tank_enmity_action_configured_from_config(cfg, 'Flash'),
		'canonical action matcher must strip explicit kind prefix')
	assert_true(scheduler_config.tank_enmity_action_configured_from_config(cfg, 'Provoke'),
		'canonical action matcher must support table entries')
	assert_false(scheduler_config.tank_enmity_action_configured_from_config(cfg, 'Sentinel'),
		'unconfigured tank action must fail closed')
	assert_true(scheduler_config.required_setting_value_from_config(cfg, 'tank'),
		'ranker tank resolver true mismatch')
	cfg.tank.enabled = false
	assert_false(scheduler_config.required_setting_value_from_config(cfg, 'tank'),
		'ranker tank resolver must preserve canonical false')
end

local function test_provider_canonical_authority()
	local p = provider()

	-- Canonical tank ON + flat OFF must operate.
	observed_pet_settings = nil
	local cfg = config(true, true, { 'spell:Flash' }, { 'Canonical Ignore' })
	local out = {}
	p.collect(context(cfg, {
		tank = false,
		tank_enmity_actions = { 'ja:Provoke' },
		tank_enmity_include_pets = false,
		target_ignore_names = { 'Flat Ignore' },
	}), out)
	assert_equal(#out, 1, 'canonical tank ON/include-pets ON must beat flat OFF state')
	assert_equal(out[1].action_name, 'Flash', 'canonical enmity action list must beat conflicting flat list')
	assert_equal(out[1].required_setting, 'tank', 'tank proposal must carry canonical rank dependency')
	assert_equal(observed_pet_settings.target_ignore_names[1], 'Canonical Ignore',
		'pet-enmity target ignore must come from canonical targeting config')

	-- Canonical tank OFF + flat ON must fail closed, including the pet path.
	out = {}
	cfg = config(false, true, { 'spell:Flash' }, {})
	p.collect(context(cfg, {
		tank = true,
		tank_enmity_actions = { 'spell:Flash' },
		tank_enmity_include_pets = true,
	}), out)
	assert_equal(#out, 0, 'canonical tank OFF + flat ON must block tank-enmity proposals')

	-- Canonical include-pets OFF + flat ON must keep pet recovery disabled.
	out = {}
	cfg = config(true, false, { 'spell:Flash' }, {})
	p.collect(context(cfg, {
		tank = true,
		tank_enmity_actions = { 'spell:Flash' },
		tank_enmity_include_pets = true,
	}), out)
	assert_equal(#out, 0, 'canonical include-pets OFF + flat ON must block pet recovery')

	-- Canonical action removal must beat a flat configured action.
	out = {}
	cfg = config(true, true, { 'ja:Provoke' }, {})
	p.collect(context(cfg, {
		tank = true,
		tank_enmity_actions = { 'spell:Flash' },
		tank_enmity_include_pets = true,
	}), out)
	assert_equal(#out, 0, 'canonical action list must beat flat Flash configuration')
end

local function test_static_wiring()
	local core = read_all('unified_combat_core.lua')
	local provider_source = read_all('uc_provider_tank_enmity.lua')
	local combat = read_all('uc_provider_combat.lua')
	local target = read_all('uc_provider_target_control.lua')
	local run = read_all('uc_provider_run_tank.lua')
	local no_tp = read_all('uc_run_no_tp.lua')
	local scheduler = read_all('unified_scheduler.lua')

	assert_contains(core, 'view.tank = scheduler_config.tank_enabled_from_config(config)',
		'core scheduler view must source canonical tank enabled')
	assert_contains(core, 'view.tank_enmity_actions = scheduler_config.tank_enmity_actions_from_config(config)',
		'core scheduler view must source canonical enmity actions')
	assert_contains(provider_source, 'scheduler_config.tank_enabled_from_config(ctx.config)',
		'tank provider must fail closed from canonical tank state')
	assert_contains(provider_source, 'scheduler_config.tank_enmity_include_pets_from_config(config)',
		'pet-enmity toggle must come from canonical config')
	assert_contains(provider_source, 'configured_enmity_actions(config)',
		'pet-enmity recovery action list must come from canonical config')
	assert_contains(provider_source, 'pet_settings.target_ignore_names = scheduler_config.targeting_ignore_names_from_config(config)',
		'pet-enmity ignore list must use canonical targeting config')
	assert_contains(provider_source, "required_setting = 'tank'",
		'tank-enmity proposal must carry canonical tank dependency')
	assert_contains(combat, 'tank_enabled(ctx.config)',
		'combat tank weighting must read canonical tank state')
	assert_contains(target, 'tank_enabled(ctx.config)',
		'target-control tank weighting must read canonical tank state')
	assert_contains(run, 'scheduler_config.tank_enabled_from_config(ctx.config)',
		'RUN provider shared tank gate must be canonical')
	assert_contains(run, 'scheduler_config.abilities_allow_unengaged_from_config(ctx.config)',
		'RUN provider unengaged gate must retain canonical ability authority')
	assert_contains(no_tp, 'scheduler_config.tank_enabled_from_config(config)',
		'RUN no-TP facing shared tank gate must be canonical')
	assert_contains(scheduler, 'uc_scheduler_config.tank_enmity_action_configured_from_config(config, selected.action_name)',
		'tank-enmity dispatch must revalidate configured action')
	assert_contains(scheduler, "tank_enmity_diag('TANK_ENMITY_DROP_TANK_DISABLED'",
		'tank-enmity dispatch must reject canonical tank disable')
end

local function main()
	rawset(_G, 'Start_Engine', true)
	test_accessors()
	test_provider_canonical_authority()
	test_static_wiring()
	io.stdout:write('selftest_phase3_tank_enmity_authority: OK (tank gate + actions + pets + dispatch wiring)\n')
end

local ok, err = pcall(main)
rawset(_G, 'Start_Engine', previous_engine)
rawset(_G, 'windower', previous_windower)
for name, value in pairs(saved) do package.loaded[name] = value end
if not ok then error(err, 0) end
