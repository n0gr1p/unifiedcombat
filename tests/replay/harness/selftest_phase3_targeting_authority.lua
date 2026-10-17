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

local previous_engine = rawget(_G, 'Start_Engine')
local saved_target_provider = package.loaded['uc_provider_target_control']

local scheduler_config = require('uc_scheduler_config')
local target_ignore = require('uc_target_ignore')
local add_priority = require('uc_add_priority')
package.loaded['uc_provider_target_control'] = nil
local target_provider = require('uc_provider_target_control')

local function bool_setting(value, default_value)
	if value == nil then return default_value end
	return value == true
end

local function make_provider()
	return target_provider.new({
		bool_setting = bool_setting,
		combat_autotarget = function() return true end,
		combat_domain_enabled = function() return true end,
		tank_enabled = function() return false end,
		select_target = function()
			return {
				target_id = 900,
				target_name = 'Priority Mob',
				hpp = 100,
				death_switch = false,
				death_switch_incumbent_id = 0,
			}
		end,
		add_control_enabled = function(settings, config)
			local leader_enabled = type(settings) == 'table' and settings.fight_leader == true
			return leader_enabled and scheduler_config.targeting_add_control_from_config(config)
		end,
		select_pull = function() return nil end,
		action_timeline_log = function() end,
		clamp_urgency = function(value) return value end,
		tank_target_priority = 106,
		tank_target_urgency = 0.9,
		death_switch_priority = 148,
		death_switch_urgency = 1.0,
	})
end

local function provider_ctx(canonical_add_control, flat_add_control)
	return {
		now = 10,
		config = {
			combat = { autotarget = true },
			targeting = {
				add_control = canonical_add_control,
				targets = { 'Priority Mob' },
				add_priority_names = { 'Fallback Mob' },
				target_ignore_names = { 'Ignored Mob' },
			},
		},
		settings = {
			add_control = flat_add_control,
			fight_leader = true,
		},
		player_present = true,
		player = { id = 1, status = 1 },
		target_present = true,
		target = { id = 800, name = 'Old Mob', valid_target = true, spawn_type = 16, hpp = 100 },
	}
end

local function test_provider_add_control_authority()
	local provider = make_provider()
	local out = {}
	provider.collect_target(provider_ctx(true, false), out)
	assert_equal(#out, 1, 'canonical Add Control ON + flat OFF must allow engaged retarget proposal')
	assert_true(out[1].detail.add_control_retarget, 'canonical Add Control proposal must be marked as add-control retarget')
	assert_equal(out[1].target_id, 900, 'canonical Add Control target id mismatch')

	out = {}
	provider.collect_target(provider_ctx(false, true), out)
	assert_equal(#out, 0, 'canonical Add Control OFF + flat ON must keep engaged retarget blocked')
end

local function test_priority_authority()
	local config = {
		targeting = {
			add_control = true,
			targets = { 'High Priority', 'Low Priority' },
			add_priority_names = { 'Compatibility Only' },
			target_ignore_names = {},
		},
	}
	local flat = {
		add_priority_names = { 'Flat First', 'High Priority' },
	}
	local canonical = scheduler_config.targeting_priority_names_from_config(config)
	assert_equal(canonical[1], 'High Priority', 'canonical targeting.targets must be first priority')
	assert_equal(canonical[2], 'Low Priority', 'canonical targeting.targets order must be preserved')
	assert_equal(#canonical, 2, 'canonical targeting.targets must beat conflicting compatibility list')

	local projected = {
		add_priority_names = canonical,
	}
	assert_equal(add_priority.rank_for_mob_name(projected, 'High Priority'), 1,
		'canonical priority rank must beat flat ordering')
	assert_equal(add_priority.rank_for_mob_name(projected, 'Low Priority'), 2,
		'canonical second priority rank mismatch')
	assert_equal(add_priority.rank_for_mob_name(projected, flat.add_priority_names[1]), 3,
		'flat-only priority name must remain ineligible')

	config.targeting.targets = {}
	config.targeting.add_priority_names = { 'Compatibility Fallback' }
	canonical = scheduler_config.targeting_priority_names_from_config(config)
	assert_equal(canonical[1], 'Compatibility Fallback',
		'canonical normalized add_priority_names must remain fallback when targeting.targets is empty')
end

local function test_target_ignore_authority()
	local config = {
		targeting = {
			add_control = false,
			targets = {},
			add_priority_names = {},
			target_ignore_names = { 'Ignored Mob' },
		},
	}
	local flat = {
		target_ignore_names = { 'Flat Only Mob' },
	}
	local projected = {
		target_ignore_names = scheduler_config.targeting_ignore_names_from_config(config),
	}
	assert_true(target_ignore.is_mob_blocked(projected, { name = 'Ignored Mob' }),
		'canonical target ignore name must block')
	assert_false(target_ignore.is_mob_blocked(projected, { name = flat.target_ignore_names[1] }),
		'flat-only target ignore name must not override canonical list')

	config.targeting.target_ignore_names = {}
	flat.target_ignore_names = { 'Ignored Mob' }
	projected.target_ignore_names = scheduler_config.targeting_ignore_names_from_config(config)
	assert_false(target_ignore.is_mob_blocked(projected, { name = 'Ignored Mob' }),
		'canonical empty ignore list must beat conflicting flat ignore entry')
end

local function test_static_wiring()
	local core = read_all('unified_combat_core.lua')
	local target = read_all('uc_provider_target_control.lua')
	local combat = read_all('uc_provider_combat.lua')
	local scheduler = read_all('uc_scheduler_config.lua')

	assert_contains(core, 'view.add_control = scheduler_config.targeting_add_control_from_config(config)',
		'core scheduler view must source Add Control from canonical targeting config')
	assert_contains(core, 'view.add_priority_names = scheduler_config.targeting_priority_names_from_config(config)',
		'core scheduler view must source target priority names from canonical targeting config')
	assert_contains(core, 'view.target_ignore_names = scheduler_config.targeting_ignore_names_from_config(config)',
		'core scheduler view must source target ignore names from canonical targeting config')
	assert_contains(core, 'function core.add_control_enabled_for_scheduler(settings, config)',
		'Add Control scheduler helper must accept canonical config')
	assert_contains(target, 'add_control_enabled(ctx.settings, ctx.config)',
		'target-control provider must pass canonical config to Add Control gate')
	assert_contains(target, 'select_target(ctx.settings, ctx.config)',
		'target-control provider must pass canonical config to target selection')
	assert_contains(combat, 'add_control_enabled(ctx.settings, ctx.config)',
		'fight-leader engage arbitration must use the canonical Add Control gate')
	assert_contains(scheduler, 'local names = targeting.targets',
		'canonical priority accessor must prefer targeting.targets')
	assert_contains(scheduler, 'names = targeting.add_priority_names',
		'canonical priority accessor must retain normalized compatibility fallback')
end

local function main()
	rawset(_G, 'Start_Engine', true)
	assert_true(scheduler_config.targeting_add_control_from_config({ targeting = { add_control = true } }),
		'canonical Add Control true accessor mismatch')
	assert_false(scheduler_config.targeting_add_control_from_config({ targeting = { add_control = false } }),
		'canonical Add Control false accessor mismatch')
	test_provider_add_control_authority()
	test_priority_authority()
	test_target_ignore_authority()
	test_static_wiring()
	io.stdout:write('selftest_phase3_targeting_authority: OK (add-control + priority + ignore authority)\n')
end

local ok, err = pcall(main)
rawset(_G, 'Start_Engine', previous_engine)
package.loaded['uc_provider_target_control'] = saved_target_provider
if not ok then error(err, 0) end
