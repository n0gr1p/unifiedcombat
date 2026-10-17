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
	'uc_provider_combat',
	'uc_combat_extensions',
	'uc_camp_pull_registry',
	'uc_run_ownership',
	'uc_scheduler_config',
	'uc_ability_pipeline',
}) do
	saved[name] = package.loaded[name]
end
local previous_engine = rawget(_G, 'Start_Engine')

package.loaded.uc_provider_combat = nil
package.loaded.uc_scheduler_config = nil
package.loaded.uc_ability_pipeline = nil
package.loaded.uc_combat_extensions = {
	new = function()
		return {
			collect_priority_offense = function() return false end,
			auto_engage_enabled_from_config = function() return true end,
		}
	end,
}
package.loaded.uc_camp_pull_registry = {}
package.loaded.uc_run_ownership = {
	filter_generic_abilities = function(_settings, abilities)
		local out = {}
		for i = 1, #(abilities or {}) do out[i] = abilities[i] end
		return out
	end,
}

local scheduler_config = require('uc_scheduler_config')
local ability_pipeline = require('uc_ability_pipeline')
local combat_provider = require('uc_provider_combat')

local function bool_setting(value, default_value)
	if value == nil then return default_value end
	return value == true
end

local function make_provider()
	return combat_provider.new({
		bool_setting = bool_setting,
		clamp_urgency = function(value) return value end,
		build_partner_target_set = function() return {} end,
		select_ws_plan = function() return nil end,
		weaponskill_enabled = function() return false end,
		abilities_enabled = scheduler_config.abilities_enabled_from_config,
		abilities_allow_unengaged = scheduler_config.abilities_allow_unengaged_from_config,
		action_timeline_log = function() end,
		combat_domain_enabled = function() return true end,
		sleep_enabled = function() return false end,
		sleep_spell_list = function() return {} end,
		is_live_actionable_target = function() return true end,
		build_friendly_claims = function() return {}, {} end,
		mob_targets_friendly_member = function() return false end,
		sleep_max_target_distance = function() return 20 end,
		target_sleep_suppressed = function() return false end,
		select_sleep_spell = function() return nil end,
		combat_autotarget = function() return false end,
		tank_enabled = function() return false end,
		debug_enabled = function() return false end,
		combat_prime = function() return false end,
		fight_leader_enabled = function() return false end,
		fight_leader_id = function() return 0 end,
		fight_leader_target_id = function() return 0 end,
		add_control_enabled = function() return false end,
		select_pull = function() return nil end,
		build_party_id_set = function() return {} end,
		prime_unclaimed_party_aggressive_ok = function() return false end,
		pending_engage_state = function() return nil end,
		pending_engage_live = function() return false end,
		collect_ordered_abilities = ability_pipeline.collect_ordered_from_config,
		get_ja_resource = function(name)
			if name == '' then return nil end
			return { en = name, name = name, targets = '{Self}', range = 0 }
		end,
		action_ready = function(name)
			if name == '' then return false, 'NOT_READY', 'ja' end
			return true, 'OK', 'ja'
		end,
		action_effective_range = function() return 0 end,
		log_ja_sched = function() end,
		phase1 = {},
		action_state = {},
		skillchain_priority = 131,
		aftermath_priority = 108,
		sleep_priority = 142,
		tank_engage_priority = 107,
		default_engage_priority = 72,
		tank_engage_urgency = 0.90,
		default_engage_urgency = 0.55,
	})
end

local function enemy_target(id)
	return {
		id = id or 900,
		name = 'Colibri',
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		distance = { sqrt = function() return 2 end },
	}
end

local function base_config()
	return {
		combat = {
			autotarget = true,
			weaponskill = { enabled = true },
		},
		abilities = {
			enabled = true,
			allow_unengaged = false,
			configured = { 'Sentinel' },
			legacy_slots = { 'Provoke' },
			wsabilities = {},
		},
	}
end

local function base_ctx()
	return {
		now = 10,
		config = base_config(),
		settings = {
			ability_active = false,
			ability_allow_unengaged = true,
			abilities = { 'Berserk' },
			ability1 = 'Warcry',
		},
		player_present = true,
		player = { id = 1, name = 'TestPLD', status = 1, vitals = { tp = 0 } },
		target_present = true,
		target = enemy_target(900),
		mobs_by_id = {},
		mob_array = {},
		party = {},
	}
end

local function test_canonical_list_collector()
	local config = base_config()
	config.abilities.configured = { 'Sentinel', 'Sentinel', 'Berserk' }
	config.abilities.legacy_slots = { 'Provoke', 'Warcry' }
	local ordered = ability_pipeline.collect_ordered_from_config(config, 6)
	assert_equal(#ordered, 2, 'canonical configured abilities must deduplicate')
	assert_equal(ordered[1], 'Sentinel', 'canonical configured order[1]')
	assert_equal(ordered[2], 'Berserk', 'canonical configured order[2]')

	config.abilities.configured = {}
	config.abilities.legacy_slots = { 'Provoke', 'Provoke', 'Sentinel' }
	ordered = ability_pipeline.collect_ordered_from_config(config, 6)
	assert_equal(#ordered, 2, 'canonical legacy slots must deduplicate')
	assert_equal(ordered[1], 'Provoke', 'canonical legacy fallback order[1]')
	assert_equal(ordered[2], 'Sentinel', 'canonical legacy fallback order[2]')
end

local function test_generic_provider_authority()
	local provider = make_provider()
	local ctx = base_ctx()
	local out = {}

	-- Canonical enabled/list wins over flat disabled/conflicting list.
	provider.collect_ja(ctx, out)
	assert_equal(#out, 1, 'canonical abilities ON + flat OFF must propose')
	assert_equal(out[1].action_name, 'Sentinel', 'canonical configured ability must beat flat configured list')

	-- Canonical OFF wins over flat ON.
	ctx.config.abilities.enabled = false
	ctx.settings.ability_active = true
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 0, 'canonical abilities OFF + flat ON must not propose')

	-- Canonical legacy slots are authoritative fallback when configured list is empty.
	ctx.config.abilities.enabled = true
	ctx.config.abilities.configured = {}
	ctx.config.abilities.legacy_slots = { 'Provoke' }
	ctx.settings.abilities = { 'Sentinel' }
	ctx.settings.ability1 = 'Warcry'
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 1, 'canonical legacy ability fallback must propose')
	assert_equal(out[1].action_name, 'Provoke', 'canonical legacy slot must beat conflicting flat list/slot')

	-- Canonical allow-unengaged false beats flat true.
	ctx.player.status = 0
	ctx.config.abilities.configured = { 'Sentinel' }
	ctx.config.abilities.legacy_slots = {}
	ctx.config.abilities.allow_unengaged = false
	ctx.settings.ability_allow_unengaged = true
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 0, 'canonical unengaged OFF + flat ON must stay blocked')

	-- Canonical allow-unengaged true beats flat false.
	ctx.config.abilities.allow_unengaged = true
	ctx.settings.ability_allow_unengaged = false
	out = {}
	provider.collect_ja(ctx, out)
	assert_equal(#out, 1, 'canonical unengaged ON + flat OFF must propose')
	assert_true(out[1].detail.unengaged_override, 'canonical unengaged proposal must retain diagnostic marker')
end

local function test_required_setting_resolver()
	local config = base_config()
	config.combat.autotarget = false
	config.combat.weaponskill.enabled = false
	config.abilities.enabled = false
	assert_false(scheduler_config.required_setting_value_from_config(config, 'autotarget'),
		'canonical required-setting autotarget false must be preserved')
	assert_false(scheduler_config.required_setting_value_from_config(config, 'weaponskill_active'),
		'canonical required-setting weaponskill false must be preserved')
	assert_false(scheduler_config.required_setting_value_from_config(config, 'ability_active'),
		'canonical required-setting ability false must be preserved')
	config.sleep = { enabled = false }
	assert_false(scheduler_config.required_setting_value_from_config(config, 'sleep'),
		'canonical required-setting Sleep false must be preserved')

	config.combat.autotarget = true
	config.combat.weaponskill.enabled = true
	config.abilities.enabled = true
	assert_true(scheduler_config.required_setting_value_from_config(config, 'autotarget'),
		'canonical required-setting autotarget true mismatch')
	assert_true(scheduler_config.required_setting_value_from_config(config, 'weaponskill_active'),
		'canonical required-setting weaponskill true mismatch')
	assert_true(scheduler_config.required_setting_value_from_config(config, 'ability_active'),
		'canonical required-setting ability true mismatch')
end

local function test_static_wiring()
	local provider = read_all('uc_provider_combat.lua')
	local tank = read_all('uc_provider_tank_enmity.lua')
	local scheduler = read_all('unified_scheduler.lua')
	local core = read_all('unified_combat_core.lua')
	local ranker = read_all('uc_scheduler_ranker.lua')

	assert_contains(provider, 'abilities_enabled(ctx.config)',
		'generic JA enablement must read canonical config')
	assert_contains(provider, 'abilities_allow_unengaged(ctx.config)',
		'generic JA unengaged policy must read canonical config')
	assert_contains(provider, 'collect_ordered_abilities(ctx.config, 6)',
		'generic JA list must come from canonical config')
	assert_contains(tank, 'abilities_allow_unengaged(ctx.config)',
		'tank-enmity unengaged policy must read canonical config')
	assert_contains(scheduler, 'collect_ordered_abilities = ability_pipeline.collect_ordered_from_config',
		'scheduler must inject canonical configured ability collector')
	assert_contains(scheduler, 'abilities_enabled = uc_scheduler_config.abilities_enabled_from_config',
		'scheduler must inject canonical ability enablement')
	assert_contains(scheduler, 'abilities_allow_unengaged = uc_scheduler_config.abilities_allow_unengaged_from_config',
		'scheduler must inject canonical unengaged policy')
	assert_contains(core, 'view.ability_active = abilities.enabled == true',
		'Chivalry WS view must overlay canonical ability enablement')
	assert_contains(core, 'view.abilities = abilities.configured or {}',
		'Chivalry WS view must overlay canonical configured abilities')
	assert_contains(ranker, "require_function(deps, 'required_setting_value')(ctx.config, required_setting)",
		'ranker must revalidate migrated required settings against canonical config')
	assert_contains(scheduler, 'required_setting_value = uc_scheduler_config.required_setting_value_from_config',
		'scheduler must inject canonical required-setting resolver')
end

local function main()
	rawset(_G, 'Start_Engine', true)
	test_canonical_list_collector()
	test_generic_provider_authority()
	test_required_setting_resolver()
	test_static_wiring()
	io.stdout:write('selftest_phase3_abilities_authority: OK (ability policy/list/ranker authority)\n')
end

local ok, err = pcall(main)
rawset(_G, 'Start_Engine', previous_engine)
for name, value in pairs(saved) do
	package.loaded[name] = value
end
if not ok then error(err, 0) end
