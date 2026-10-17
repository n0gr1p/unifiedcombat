package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
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

local saved_provider = package.loaded['uc_provider_combat']
local saved_extensions = package.loaded['uc_combat_extensions']
local saved_camp_registry = package.loaded['uc_camp_pull_registry']
local previous_engine = rawget(_G, 'Start_Engine')

package.loaded['uc_provider_combat'] = nil
package.loaded['uc_combat_extensions'] = {
	new = function()
		return {
			collect_priority_offense = function()
				return false
			end,
			auto_engage_enabled_from_config = function()
				return true
			end,
		}
	end,
}
package.loaded['uc_camp_pull_registry'] = {
	combat_order = function()
		return nil
	end,
}

local scheduler_config = require('uc_scheduler_config')
local combat_provider = require('uc_provider_combat')

local function bool_setting(value, default_value)
	if value == nil then
		return default_value
	end
	return value == true
end

local function make_provider(observed)
	return combat_provider.new({
		bool_setting = bool_setting,
		clamp_urgency = function(value) return value end,
		build_partner_target_set = function() return {} end,
		select_ws_plan = function(settings, target_id, config)
			observed.settings = settings
			observed.target_id = target_id
			observed.config = config
			return {
				ws_name = 'Savage Blade',
				required_tp = 1000,
				smart_aoe_guard = true,
			}, 'READY'
		end,
		weaponskill_enabled = scheduler_config.combat_weaponskill_enabled_from_config,
		abilities_enabled = function() return false end,
		abilities_allow_unengaged = function() return false end,
		action_timeline_log = function() end,
		combat_domain_enabled = function() return true end,
		sleep_enabled = function() return false end,
		sleep_spell_list = function() return {} end,
		is_live_actionable_target = function() return true end,
		build_friendly_claims = function() return {}, { [1001] = true } end,
		mob_targets_friendly_member = function() return false end,
		sleep_max_target_distance = function() return 20 end,
		target_sleep_suppressed = function() return false end,
		select_sleep_spell = function() return nil end,
		combat_autotarget = function() return true end,
		tank_enabled = function() return false end,
		debug_enabled = function() return false end,
		combat_prime = function() return false end,
		fight_leader_enabled = function() return false end,
		fight_leader_id = function() return 0 end,
		fight_leader_target_id = function() return 0 end,
		add_control_enabled = function() return false end,
		select_pull = function() return nil end,
		build_party_id_set = function() return { [1] = true } end,
		prime_unclaimed_party_aggressive_ok = function() return false end,
		pending_engage_state = function() return nil end,
		pending_engage_live = function() return false end,
		collect_ordered_abilities = function() return {} end,
		get_ja_resource = function() return nil end,
		action_ready = function() return false, 'NOT_READY', '' end,
		action_effective_range = function() return 20 end,
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

local function run_provider(canonical_enabled, flat_enabled)
	local observed = {}
	local provider = make_provider(observed)
	local config = {
		combat = {
			weaponskill = {
				enabled = canonical_enabled,
			},
		},
	}
	local settings = {
		weaponskill_active = flat_enabled,
	}
	local out = {}
	provider.collect_offense({
		now = 10,
		config = config,
		settings = settings,
		player_present = true,
		player = { id = 1, status = 1, vitals = { tp = 1000 } },
		target_present = true,
		target = {
			id = 900,
			name = 'Colibri',
			valid_target = true,
			spawn_type = 16,
			hpp = 100,
			claim_id = 1001,
		},
		mobs_by_id = {},
		mob_array = {},
		party = {},
	}, out)
	return out, observed, config, settings
end

local function assert_static_wiring()
	local provider = read_all('uc_provider_combat.lua')
	local scheduler = read_all('unified_scheduler.lua')
	local core = read_all('unified_combat_core.lua')
	local dispatch_plan = read_all('uc_scheduler_dispatch_plan.lua')

	assert_contains(provider, 'weaponskill_enabled(ctx.config)',
		'WS provider enablement must read canonical config')
	assert_contains(provider, 'select_ws_plan(ctx.settings, tonumber(target.id) or 0, ctx.config)',
		'WS provider must pass canonical config to the planner')
	assert_contains(scheduler, 'weaponskill_enabled = uc_scheduler_config.combat_weaponskill_enabled_from_config',
		'scheduler must inject canonical WS enablement')
	assert_contains(scheduler, 'try_dispatch_ws_with_intent(ws, expected_tid, settings, selected.skillchain_plan, config)',
		'scheduler WS dispatch must carry canonical config')
	assert_contains(dispatch_plan, 'selected.action_name,\n\t\t\tctx.config',
		'Smart AoE rank-commit revalidation must carry canonical config')
	assert_contains(dispatch_plan, "'rank_commit',\n\t\t\tctx.config",
		'skillchain rank-commit revalidation must carry canonical config')

	local required = {
		'view.weaponskill_active = weaponskill.enabled == true',
		"view.weaponskill = tostring(weaponskill.primary or '')",
		'view.ws1 = view.weaponskill',
		"view.ws_mode = tostring(weaponskill.mode or 'smart')",
		'view.weaponskill_min_tp = weaponskill.minimum_tp',
		'view.weaponskill_allow_aoe = weaponskill.allow_aoe ~= false',
		'view.fast_skillchain = weaponskill.fast_skillchain == true',
		'view.weaponskill_no_skillchain_targets = weaponskill.no_skillchain_targets or {}',
		"view.skillchain_target = tostring(weaponskill.skillchain_target or 'auto')",
		'view.wait_ignore_names = weaponskill.wait_ignore_names or {}',
		'view.aftermath_enabled = weaponskill.aftermath_enabled == true',
		"view.aftermath_ws = tostring(weaponskill.aftermath_ws or '')",
		'view.spam = combat.spam == true',
		'view.solo = legacy.solo == true',
	}
	for i = 1, #required do
		assert_contains(core, required[i], 'canonical WS settings view missing field: ' .. required[i])
	end
	assert_contains(core, 'local ws_settings = scheduler_weaponskill_settings_view(settings, config)',
		'WS planner/revalidators must derive a canonical settings view')
end

local function main()
	rawset(_G, 'Start_Engine', true)
	local out, observed, config, settings = run_provider(true, false)
	assert_equal(#out, 1, 'canonical WS ON + flat OFF must propose')
	assert_equal(out[1].action_name, 'Savage Blade', 'canonical WS proposal action mismatch')
	assert_equal(observed.config, config, 'planner must receive the canonical config object')
	assert_equal(observed.settings, settings, 'planner must retain compatibility settings for unmigrated non-WS inputs')
	assert_equal(observed.target_id, 900, 'planner target id mismatch')

	out, observed = run_provider(false, true)
	assert_equal(#out, 0, 'canonical WS OFF + flat ON must not propose')
	assert_equal(observed.config, nil, 'disabled canonical WS must stop before planner evaluation')

	assert_static_wiring()
	io.stdout:write('selftest_phase3_weaponskill_authority: OK (provider contradiction + full WS field wiring)\n')
end

local ok, err = pcall(main)
rawset(_G, 'Start_Engine', previous_engine)
package.loaded['uc_provider_combat'] = saved_provider
package.loaded['uc_combat_extensions'] = saved_extensions
package.loaded['uc_camp_pull_registry'] = saved_camp_registry
if not ok then
	error(err, 0)
end
