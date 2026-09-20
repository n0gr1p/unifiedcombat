local function assert_true(condition, message)
	if not condition then
		error(message or 'assertion failed')
	end
end

local function assert_false(condition, message)
	if condition then
		error(message or 'assertion failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values are not equal') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function deep_clone(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, inner_value in pairs(value) do
		out[key] = deep_clone(inner_value)
	end
	return out
end

local function deep_equal(actual, expected, seen)
	if actual == expected then
		return true
	end
	if type(actual) ~= type(expected) then
		return false
	end
	if type(actual) ~= 'table' then
		return actual == expected
	end

	local pair_seen = seen or {}
	pair_seen[actual] = pair_seen[actual] or {}
	if pair_seen[actual][expected] then
		return true
	end
	pair_seen[actual][expected] = true

	local actual_count = 0
	for key, actual_value in pairs(actual) do
		actual_count = actual_count + 1
		if not deep_equal(actual_value, expected[key], pair_seen) then
			return false
		end
	end

	local expected_count = 0
	for _ in pairs(expected) do
		expected_count = expected_count + 1
	end
	return actual_count == expected_count
end

local function assert_deep_equal(actual, expected, message)
	if not deep_equal(actual, expected) then
		error(message or 'tables are not deeply equal')
	end
end

local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local content = fh:read('*a')
	fh:close()
	return content
end

local function load_lua_fixture(path)
	local chunk, err = loadstring(read_file(path), '@' .. path)
	assert_true(type(chunk) == 'function', 'fixture must load as Lua: ' .. tostring(err))
	local ok, payload = pcall(chunk)
	assert_true(ok == true, 'fixture chunk should execute')
	assert_true(type(payload) == 'table', 'fixture must return a table')
	return payload
end

local function build_flat_settings()
	return {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		show_ingame_ui = true,
		engine_enabled = true,
		ability_active = true,
		abilities = { 'Sentinel', 'Rampart' },
		weaponskill_active = true,
		weaponskill = 'Savage Blade',
		ws_mode = 'smart',
		weaponskill_allow_aoe = false,
		fast_skillchain = true,
		weaponskill_no_skillchain_targets = { 'Gyre' },
		skillchain_target = 'light',
		autotarget = true,
		spam = true,
		closer = true,
		manual = false,
		prime = false,
		static = false,
		face = true,
		defensive_enabled = true,
		defensive_cure_enabled = true,
		def_charm_sleeper_enabled = true,
		def_sleep_waker_enabled = true,
		defensive_na_enabled = true,
		defensive_na_limit_enabled = true,
		defensive_na_priority = 'Poison|Paralyze|Dia',
		def_heal_min_tier_cure = 3,
		def_heal_max_tier_cure = 4,
		def_heal_min_missing_hp = 250,
		def_heal_ignore_trusts = true,
		defensive_curaga_enabled = true,
		defensive_curaga_min_targets = 4,
		defensive_waltz_enabled = true,
		defensive_waltz_tp_reserve = 1000,
		defensive_divine_waltz_min_targets = 2,
		defensive_targeted_buffs = 'Terrasjr:Honor March|Nyoourke:Valor Minuet V',
		def_maintain_enemy_debuffs = true,
		defensive_enemy_debuffs = 'Dia III|Distract III',
		move = true,
		spacing = true,
		path_follow_enabled = true,
		path_file_name = 'route-a',
		path_points = { '1,2,3' },
		party_follow = true,
		party_follow_leader_name = 'Leader',
		fight_leader = true,
		fight_leader_selected = 'Niightsiide',
		puller = true,
		puller_name = 'Niightsiide',
		partner = true,
		partner2 = true,
		partner_names = { 'Ponponponponpon', 'Nyoourke' },
		puller_engage_range = 9.5,
		nyzul_coordinator_name = 'Redrogue',
		nyzul_anchor_name = 'Terrasjr',
		nyzul_parking_order = { 'Nyoourke', 'Ponponponponp' },
		wait_ignore_names = { 'Niightsiide' },
		target_ignore_names = { 'Ignore Me' },
		add_control = true,
		add_priority_names = { 'Apex Bat' },
		sleep = true,
		sleepspells = { 'Horde Lullaby II' },
		sleep_max_target_range = 14.0,
		spell_active = true,
		spell = 'Dia',
		debug = true,
		log_def_sched = true,
		domain_combat_enabled = true,
		domain_defensive_enabled = true,
		domain_movement_enabled = true,
		domain_maintenance_enabled = true,
		domain_follow_enabled = true,
		pause_automation_while_weakened = true,
		profile_v2_auto_reload_on_change = true,
		tank = true,
		tank_enmity_actions = { 'Provoke', 'Flash' },
		sub = true,
		hunter = true,
		profiles = {
			UC = {
				PLD = {
					marker = true,
				},
			},
		},
	}
end

local function main()
	local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	local previous_windower = rawget(_G, 'windower')
	package.loaded['uc_active_config'] = nil
	package.loaded['uc_config_normalizer'] = nil
	rawset(_G, 'windower', {
		ffxi = {
			get_party = function()
				return {
					p1 = {
						mob = {
							id = 77,
							name = 'Niightsiide',
						},
					},
					p2 = { mob = { id = 568177, name = 'Ponponponponpon' } },
					p3 = { mob = { id = 558393, name = 'Nyoourke' } },
				}
			end,
			get_mob_by_name = function(name)
				if name == 'Niightsiide' then
					return {
						id = 77,
					}
				end
				return nil
			end,
		},
	})
	local active_config = require('uc_active_config')
	local normalizer = require('uc_config_normalizer')

	local flat = build_flat_settings()
	local flat_snapshot = deep_clone(flat)
	local active_profile = active_config.build_active_profile_from_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	assert_true(type(active_profile) == 'table', 'active profile from settings must be a table')
	assert_equal(active_profile.version, 2, 'active profile version mismatch')
	assert_equal(active_profile.profile.schema_version, 2, 'active profile schema version mismatch')
	assert_equal(active_profile.profile.engine, 'UC', 'active profile engine mismatch')
	assert_equal(active_profile.profile.character, 'Redrogue', 'active profile character mismatch')
	assert_equal(active_profile.profile.main_job, 'PLD', 'active profile main job mismatch')
	assert_equal(active_profile.profile.sub_job, 'WAR', 'active profile sub job mismatch')
	assert_equal(active_profile.profile.source, 'UC_SETTINGS', 'active profile source mismatch')
	assert_equal(active_profile.config.combat.weaponskill.primary, 'Savage Blade', 'active combat WS mismatch')
	assert_equal(active_profile.config.combat.weaponskill.wait_ignore_names[1], 'Niightsiide', 'active wait ignore names mismatch')
	assert_equal(active_profile.config.combat.weaponskill.no_skillchain_targets[1], 'Gyre', 'active no-skillchain target mismatch')
	assert_true(active_profile.config.ownership.profile_v2_auto_reload_on_change == nil, 'active config must ignore legacy auto-reload flag')
	assert_equal(active_profile.config.ownership.pause_automation_while_weakened, true, 'active recovery hold mismatch')
	assert_equal(active_profile.config.defensive.na.limit_enabled, true, 'active status-removal limit mismatch')
	assert_equal(active_profile.config.defensive.na.priority, 'Poison|Paralyze|Dia', 'active status-removal priority mismatch')
	assert_equal(active_profile.config.follow.fight.leader, true, 'active fight leader enabled mismatch')
	assert_equal(active_profile.config.follow.fight.leader_name, 'Niightsiide', 'active fight leader name mismatch')
	assert_equal(active_profile.config.follow.fight.leader_id, 0, 'active fight leader id must stay runtime-owned')
	assert_equal(active_profile.config.follow.partner.puller_name, 'Niightsiide', 'active puller name mismatch')
	assert_equal(active_profile.config.follow.partner.leash_source, 'player', 'active puller leash source mismatch')
	assert_equal(active_profile.config.follow.partner.names[1], 'Ponponponponpon', 'active primary partner name mismatch')
	assert_equal(active_profile.config.follow.partner.names[2], 'Nyoourke', 'active secondary partner name mismatch')
	assert_equal(active_profile.config.follow.partner.engage_range, 9.5, 'active puller engage range mismatch')
	assert_equal(active_profile.config.follow.partner.puller_id, 0, 'active puller id should remain runtime-owned in the durable active profile')
	assert_equal(active_profile.config.follow.nyzul.coordinator_name, 'Redrogue', 'active Nyzul coordinator mismatch')
	assert_equal(active_profile.config.follow.nyzul.anchor_name, 'Terrasjr', 'active Nyzul anchor mismatch')
	assert_equal(active_profile.config.follow.nyzul.parking_order[2], 'Ponponponponp', 'active Nyzul parking order mismatch')
	assert_equal(active_profile.config.targeting.target_ignore_names[1], 'Ignore Me', 'active target ignore names mismatch')
	assert_equal(active_profile.config.targeting.targets[1], 'Apex Bat', 'active add priority targets mismatch')
	assert_equal(active_profile.config.maintenance.enabled, true, 'active maintenance domain mismatch')
	assert_equal(active_profile.config.legacy.hunter, true, 'active legacy hunter mismatch')
	assert_deep_equal(flat, flat_snapshot, 'building active profile must not mutate input settings')

	local disabled_flat = deep_clone(flat)
	disabled_flat.profile_v2_auto_reload_on_change = false
	local disabled_active = active_config.build_active_profile_from_settings(disabled_flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	assert_true(type(disabled_active) == 'table', 'disabled active profile from settings must be a table')
	assert_true(type(disabled_active.config.ownership) == 'table', 'disabled active profile must retain ownership table')
	assert_true(disabled_active.config.ownership.profile_v2_auto_reload_on_change == nil, 'disabled auto-reload flag must be omitted from durable active config')
	local disabled_projected = active_config.project_flat_settings(disabled_active, disabled_flat)
	assert_true(type(disabled_projected) == 'table', 'disabled projection should still succeed')
	assert_true(disabled_projected.profile_v2_auto_reload_on_change == nil, 'disabled auto-reload flag must stay omitted from projected settings')

	local set_ok, stored_profile = active_config.set_active_profile(active_profile)
	assert_true(set_ok == true, 'setting active profile should succeed')
	assert_true(type(stored_profile) == 'table', 'stored active profile must be a table')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == stored_profile, 'stored active profile should be published globally')

	local replacement_profile = active_config.build_active_profile_from_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	replacement_profile.profile.source = 'replaced'
	local prior_identity = rawget(_G, 'UC_ACTIVE_PROFILE')
	local replace_ok, replaced_profile = active_config.set_active_profile(replacement_profile)
	assert_true(replace_ok == true, 'replacing active profile should succeed')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == prior_identity, 'active profile table identity should be preserved')
	assert_true(replaced_profile == prior_identity, 'set_active_profile should update in place')
	assert_equal(active_config.get_config().combat.weaponskill.primary, 'Savage Blade', 'get_config mismatch')
	assert_equal(active_config.get_domain('combat').weaponskill.primary, 'Savage Blade', 'get_domain mismatch')
	assert_equal(active_config.get_path('config.combat.weaponskill.primary'), 'Savage Blade', 'get_path string mismatch')
	assert_equal(active_config.get_path({ 'config', 'combat', 'weaponskill', 'primary' }), 'Savage Blade', 'get_path table mismatch')
	assert_equal(active_config.get_path('config.missing.path', 'fallback'), 'fallback', 'get_path default mismatch')

	local projected = active_config.project_flat_settings(active_config.get_active_profile(), flat)
	assert_true(type(projected) == 'table', 'projected settings should be a table')
	assert_true(projected ~= flat, 'projected settings must be a new table')
	assert_equal(projected.weaponskill, 'Savage Blade', 'projected weaponskill mismatch')
	assert_equal(projected.ws1, 'Savage Blade', 'projected ws1 mismatch')
	assert_equal(projected.weaponskill_allow_aoe, false, 'projected Smart WS AoE preference mismatch')
	assert_equal(projected.fast_skillchain, true, 'projected Fast Skillchain preference mismatch')
	assert_equal(projected.weaponskill_no_skillchain_targets[1], 'Gyre', 'projected no-skillchain target mismatch')
	assert_equal(projected.skillchain_target, 'light', 'projected skillchain target mismatch')
	assert_equal(projected.sleep, true, 'projected sleep mismatch')
	assert_equal(projected.sleepspell, 'Horde Lullaby II', 'projected sleep mirror mismatch')
	assert_equal(projected.sleepspells[1], 'Horde Lullaby II', 'projected sleep list mismatch')
	assert_equal(projected.sleep_max_target_range, 14.0, 'projected sleep target range mismatch')
	assert_equal(projected.def_charm_sleeper_enabled, true, 'projected charm sleeper mirror mismatch')
	assert_equal(projected.def_sleep_waker_enabled, true, 'projected sleep waker mirror mismatch')
	assert_equal(projected.defensive_na_limit_enabled, true, 'projected status-removal limit mismatch')
	assert_equal(projected.defensive_na_priority, 'Poison|Paralyze|Dia', 'projected status-removal priority mismatch')
	assert_equal(projected.defensive_curaga_enabled, true, 'projected Curaga enabled mismatch')
	assert_equal(projected.defensive_curaga_min_targets, 4, 'projected Curaga minimum mismatch')
	assert_equal(projected.defensive_waltz_enabled, true, 'projected Waltz enabled mismatch')
	assert_equal(projected.defensive_waltz_tp_reserve, 1000, 'projected Waltz reserve mismatch')
	assert_equal(projected.defensive_divine_waltz_min_targets, 2, 'projected Divine Waltz minimum mismatch')
	assert_equal(projected.defensive_targeted_buffs, 'Terrasjr:Honor March|Nyoourke:Valor Minuet V', 'projected targeted buff mirror mismatch')
	assert_equal(projected.def_maintain_enemy_debuffs, true, 'projected enemy debuff maintenance mismatch')
	assert_equal(projected.defensive_enemy_debuffs, 'Dia III|Distract III', 'projected enemy debuff list mismatch')
	assert_equal(projected.wait_ignore_names[1], 'Niightsiide', 'projected wait ignore names mismatch')
	assert_equal(projected.ignore[1], 77, 'projected compatibility ignore id mismatch')
	assert_true(projected.profile_v2_auto_reload_on_change == nil, 'projection must omit legacy auto-reload flag')
	assert_equal(projected.pause_automation_while_weakened, true, 'projected recovery hold mismatch')
	assert_equal(projected.fight_leader_name, 'Niightsiide', 'projected fight leader name mismatch')
	assert_equal(projected.fight_leader_id, 77, 'projected fight leader id should resolve from fight leader name')
	assert_equal(projected.fight_leader_selected, 'Niightsiide', 'projected fight leader selected mismatch')
	assert_equal(projected.follow.fight.leader_name, 'Niightsiide', 'projected nested fight leader name mismatch')
	assert_equal(projected.follow.fight.leader_id, 77, 'projected nested fight leader id mismatch')
	assert_equal(projected.follow.fight.leader_selected, 'Niightsiide', 'projected nested fight leader selected mismatch')
	assert_equal(projected.puller_name, 'Niightsiide', 'projected puller name mismatch')
	assert_equal(projected.puller_leash_source, 'player', 'projected puller leash source mismatch')
	assert_equal(projected.puller_id, 77, 'projected puller id should resolve from puller name')
	assert_equal(projected.follow.partner.puller_name, 'Niightsiide', 'projected nested puller name mismatch')
	assert_equal(projected.puller_engage_range, 9.5, 'projected puller engage range mismatch')
	assert_equal(projected.follow.partner.engage_range, 9.5, 'projected nested puller engage range mismatch')
	assert_equal(projected.follow.partner.puller_id, 77, 'projected nested puller id mismatch')
	local camp_profile = deep_clone(active_profile)
	camp_profile.config.follow.partner.leash_source = 'camp'
	local camp_projected, camp_project_error = active_config.project_flat_settings(camp_profile, {})
	assert_true(camp_projected ~= nil and camp_project_error == nil, 'camp leash profile should project cleanly')
	assert_equal(camp_projected.puller_leash_source, 'camp', 'camp leash source projection mismatch')
	assert_equal(camp_projected.puller_id, 0, 'camp leash must not resolve a stale player id')
	assert_equal(projected.nyzul_coordinator_name, 'Redrogue', 'projected Nyzul coordinator mismatch')
	assert_equal(projected.nyzul_anchor_name, 'Terrasjr', 'projected Nyzul anchor mismatch')
	assert_equal(projected.nyzul_parking_order[1], 'Nyoourke', 'projected Nyzul parking order mismatch')
	assert_equal(projected.follow.nyzul.anchor_name, 'Terrasjr', 'projected nested Nyzul anchor mismatch')
	local no_nyzul_profile = deep_clone(active_profile)
	no_nyzul_profile.config.follow.nyzul = nil
	local no_nyzul_projected, no_nyzul_error = active_config.project_flat_settings(no_nyzul_profile, flat)
	assert_true(no_nyzul_projected ~= nil and no_nyzul_error == nil, 'profile without Nyzul config should project cleanly')
	assert_true(no_nyzul_projected.nyzul_coordinator_name == nil, 'omitted Nyzul config must clear stale coordinator')
	assert_true(no_nyzul_projected.nyzul_anchor_name == nil, 'omitted Nyzul config must clear stale anchor')
	assert_true(no_nyzul_projected.nyzul_parking_order == nil, 'omitted Nyzul config must clear stale parking order')
	assert_true(no_nyzul_projected.follow.nyzul == nil, 'omitted Nyzul config must clear stale nested roster')
	local stale_canonical_base = deep_clone(flat)
	stale_canonical_base.config = deep_clone(active_profile.config)
	stale_canonical_base.config.combat.weaponskill.minimum_tp = 3000
	stale_canonical_base.config.encounter = {
		enabled = true,
		id = 'sortie_ghatjot',
		policy = {
			water_damage = 'enforce',
			water_skillchain = 'enforce',
			repeat_action_wall = 'off',
		},
		tuning = {
			repeat_action_guard_s = 10,
		},
	}
	stale_canonical_base.combat = deep_clone(stale_canonical_base.config.combat)
	stale_canonical_base.encounter = deep_clone(stale_canonical_base.config.encounter)
	local replacement_profile = deep_clone(active_profile)
	replacement_profile.config.combat.weaponskill.minimum_tp = 2000
	replacement_profile.config.encounter = nil
	local replacement_projected, replacement_error = active_config.project_flat_settings(replacement_profile, stale_canonical_base)
	assert_true(replacement_projected ~= nil and replacement_error == nil, 'profile replacement should discard stale canonical config sources')
	assert_true(replacement_projected.config == nil, 'flat profile projection must remove a stale config wrapper')
	assert_true(replacement_projected.combat == nil, 'flat profile projection must remove a stale canonical combat domain')
	assert_true(replacement_projected.encounter == nil, 'flat profile projection must remove a stale canonical encounter domain')
	assert_equal(replacement_projected.weaponskill_min_tp, 2000, 'replacement profile must own the projected WS minimum TP')
	assert_equal(replacement_projected.encounter_enabled, false, 'omitted replacement encounter must disable the stale encounter')
	local replacement_config = normalizer.normalize(replacement_projected, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	})
	assert_equal(replacement_config.combat.weaponskill.minimum_tp, 2000, 'replacement WS minimum TP must survive canonical normalization')
	assert_equal(replacement_config.encounter.enabled, false, 'stale encounter must remain disabled after canonical normalization')
	assert_equal(projected.targets[1], 'Apex Bat', 'projected add priority targets mismatch')
	assert_equal(projected.add_priority_names[1], 'Apex Bat', 'projected add priority compatibility names mismatch')
	assert_equal(projected.partner_names[1], 'Ponponponponpon', 'projected primary partner name mismatch')
	assert_equal(projected.partner_names[2], 'Nyoourke', 'projected secondary partner name mismatch')
	assert_equal(projected.partner_ids[1], 568177, 'projected primary partner id must resolve from durable name')
	assert_equal(projected.partner_ids[2], 558393, 'projected secondary partner id must resolve from durable name')
	assert_equal(projected.follow.partner.names[1], 'Ponponponponpon', 'projected nested primary partner name mismatch')
	assert_equal(projected.follow.partner.ids[1], 568177, 'projected nested primary partner id mismatch')

	local projected_snapshot = deep_clone(projected)
	local sync_target = deep_clone(flat)
	local sync_identity = sync_target
	local sync_ok, sync_err = active_config.sync_flat_settings_in_place(sync_target, projected)
	assert_true(sync_ok == true, 'syncing projected settings should succeed')
	assert_true(sync_target == sync_identity, 'sync should preserve target identity')
	assert_deep_equal(sync_target, projected_snapshot, 'sync should copy projected settings in place')
	assert_deep_equal(flat, flat_snapshot, 'projection and sync should not mutate source settings')

	local ui_fixture = load_lua_fixture('tests/replay/fixtures/shared/ui_authored_profile_v2_fixture.lua')
	local ui_fixture_snapshot = deep_clone(ui_fixture)
	local ui_profile = active_config.build_active_profile_from_v2_payload(ui_fixture, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	assert_equal(ui_profile.config.ownership.pause_automation_while_weakened, true, 'UI-authored recovery hold mismatch')
	assert_true(type(ui_profile) == 'table', 'active profile from v2 payload must be a table')
	assert_equal(ui_profile.version, 2, 'UI active profile version mismatch')
	assert_equal(ui_profile.profile.source, 'ui', 'UI active profile source mismatch')
	assert_equal(ui_profile.profile.character, 'Redrogue', 'UI active profile character mismatch')
	assert_equal(ui_profile.profile.main_job, 'PLD', 'UI active profile main job mismatch')
	assert_equal(ui_profile.profile.sub_job, 'WAR', 'UI active profile sub job mismatch')
	assert_equal(ui_profile.config.combat.weaponskill.primary, 'Savage Blade', 'UI active combat mismatch')
	assert_equal(ui_profile.config.combat.weaponskill.allow_aoe, false, 'UI active Smart WS AoE preference mismatch')
	assert_equal(ui_profile.config.combat.weaponskill.fast_skillchain, true, 'UI active Fast Skillchain preference mismatch')
	local legacy_ws_fixture = deep_clone(ui_fixture)
	legacy_ws_fixture.config.combat.weaponskill.minimum_tp = nil
	legacy_ws_fixture.config.combat.weaponskill.allow_aoe = nil
	legacy_ws_fixture.config.combat.weaponskill.fast_skillchain = nil
	legacy_ws_fixture.config.combat.weaponskill.wait_ignore_names = nil
	local legacy_ws_profile = active_config.build_active_profile_from_v2_payload(legacy_ws_fixture, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	assert_equal(legacy_ws_profile.config.combat.weaponskill.minimum_tp, 1000, 'legacy v2 profile must receive the Smart WS minimum TP compatibility default')
	assert_equal(legacy_ws_profile.config.combat.weaponskill.allow_aoe, true, 'legacy v2 profile must receive the Smart WS AoE compatibility default')
	assert_equal(legacy_ws_profile.config.combat.weaponskill.fast_skillchain, false, 'legacy v2 profile must receive the Fast Skillchain compatibility default')
	assert_deep_equal(legacy_ws_profile.config.combat.weaponskill.wait_ignore_names, {}, 'legacy v2 profile must receive the Smart WS wait-ignore compatibility default')
	assert_equal(ui_profile.config.movement.path.file_name, 'route-a', 'UI active path mismatch')
	assert_equal(ui_profile.config.follow.party.leader_name, 'Leader', 'UI active follow mismatch')
	assert_equal(ui_profile.config.follow.partner.puller_name, 'Niightsiide', 'UI active puller mismatch')
	assert_equal(ui_profile.config.combat.weaponskill.wait_ignore_names[1], 'Ally One', 'UI active wait ignore name mismatch')
	assert_equal(ui_profile.config.targeting.target_ignore_names[1], 'Mob One', 'UI active target ignore name mismatch')
	assert_equal(ui_profile.config.targeting.targets[1], 'Apex Bat', 'UI active add priority target mismatch')
	assert_equal(ui_profile.config.defensive.buffs.targeted[1].character, 'Terrasjr', 'UI active targeted buff character mismatch')
	assert_equal(ui_profile.config.defensive.buffs.targeted[1].buff, 'Honor March', 'UI active targeted buff name mismatch')
	assert_equal(ui_profile.config.defensive.na.limit_enabled, true, 'UI active status-removal limit mismatch')
	assert_equal(ui_profile.config.defensive.na.priority, 'Poison|Paralyze|Dia', 'UI active status-removal priority mismatch')
	assert_deep_equal(ui_fixture, ui_fixture_snapshot, 'building from payload must not mutate fixture')

	local ui_set_ok, ui_stored_profile = active_config.set_active_profile(ui_profile)
	assert_true(ui_set_ok == true, 'setting UI active profile should succeed')
	assert_true(ui_stored_profile == rawget(_G, 'UC_ACTIVE_PROFILE'), 'UI active profile should be stored in place')
	assert_equal(active_config.get_path('profile.source'), 'ui', 'active profile path access should reach metadata')
	assert_equal(active_config.get_path('config.movement.path.file_name'), 'route-a', 'active profile path access should reach config')

	local encounter_fixture = deep_clone(ui_fixture)
	encounter_fixture.config.encounter = {
		enabled = true,
		id = 'sortie_ghatjot',
		policy = {
			water_damage = 'enforce',
			water_skillchain = 'warn',
			repeat_action_wall = 'off',
		},
		tuning = {
			repeat_action_guard_s = 10.0,
		},
	}
	local encounter_profile = active_config.build_active_profile_from_v2_payload(encounter_fixture, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	assert_equal(encounter_profile.config.encounter.enabled, true, 'encounter domain enabled mismatch')
	assert_equal(encounter_profile.config.encounter.id, 'sortie_ghatjot', 'encounter domain ID mismatch')
	local encounter_projected = active_config.project_flat_settings(encounter_profile, {})
	assert_equal(encounter_projected.encounter_enabled, true, 'projected encounter enabled mismatch')
	assert_equal(encounter_projected.encounter_id, 'sortie_ghatjot', 'projected encounter ID mismatch')
	assert_equal(encounter_projected.encounter_water_skillchain, 'warn', 'projected encounter policy mismatch')
	assert_equal(encounter_projected.encounter_repeat_action_guard_s, 10.0, 'projected encounter tuning mismatch')
	local disabled_encounter_profile = active_config.build_active_profile_from_v2_payload(ui_fixture, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	local disabled_encounter_projected = active_config.project_flat_settings(disabled_encounter_profile, {
		encounter_enabled = true,
		encounter_id = 'sortie_dhartok',
	})
	assert_equal(disabled_encounter_projected.encounter_enabled, false, 'disabled encounter projection must clear stale enabled state')
	assert_equal(disabled_encounter_projected.encounter_id, 'sortie_ghatjot', 'disabled encounter projection identity mismatch')

	local formation_fixture = deep_clone(ui_fixture)
	formation_fixture.config.movement.formation = {
		enabled = true,
		encounter = 'lilith_easy',
		role = 'healer',
		tank_name = 'Terrasjr',
		required_party_names = { 'Terrasjr', 'Etamame' },
		capture_stable_s = 0.5,
		capture_tolerance = 0.1,
		safe_radius = 16,
		tank = {
			accept_radius = 1.5,
			return_radius = 3,
		},
		dps = {
			flank_angle_deg = 90,
			melee_radius = 3,
			position_tolerance = 1.5,
		},
		healer = {
			preferred_radius = 12,
			minimum_boss_distance = 8,
			maximum_party_range = 18,
			cone_half_angle_deg = 50,
			cone_safety_margin_deg = 15,
			sample_step_deg = 10,
		},
	}
	local formation_profile = active_config.build_active_profile_from_v2_payload(formation_fixture, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	local formation_projected = active_config.project_flat_settings(formation_profile, {})
	assert_equal(formation_profile.config.movement.formation.role, 'healer', 'formation role should remain durable')
	assert_equal(formation_projected.formation_enabled, true, 'enabled formation should qualify as a movement participant')
	assert_equal(formation_projected.formation_role, 'healer', 'formation role should project to flat runtime settings')
	assert_equal(formation_projected.formation_tank_name, 'Terrasjr', 'formation tank name should project to flat runtime settings')
	assert_equal(formation_projected.formation_required_party_names[2], 'Etamame', 'formation coverage members should project to flat runtime settings')
	assert_equal(formation_projected.formation_tank_return_radius, 3, 'formation tank radius should project to flat runtime settings')
	assert_equal(formation_projected.formation_dps_flank_angle_deg, 90, 'formation DPS angle should project to flat runtime settings')
	assert_equal(formation_projected.formation_healer_maximum_party_range, 18, 'formation healer range should project to flat runtime settings')

	local normalized = normalizer.normalize(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	assert_equal(normalized.profile.source, 'UC_SETTINGS', 'normalizer source mismatch')

	local migrated_profile, migrated_err = active_config.build_active_profile_from_v2_payload({
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Niightsiide',
			main_job = 'GEO',
			sub_job = 'RDM',
			source = 'ui',
		},
		config = {
			combat = {
				enabled = true,
			},
			defensive = {
				cure = {},
			},
			maintenance = {
				geo = {},
			},
		},
	}, {
		character = 'Niightsiide',
		main_job = 'GEO',
		sub_job = 'RDM',
		source = 'UC_PROFILE_V2',
	})
	assert_true(type(migrated_profile) == 'table', 'legacy GEO profile should receive new configuration defaults')
	assert_true(migrated_err == nil, 'legacy GEO profile migration should not report an error')
	assert_true(type(migrated_profile.config.combat.pulling) == 'table', 'legacy profile must receive normalized pulling configuration')
	assert_false(migrated_profile.config.combat.pulling.enabled, 'migrated pulling configuration must remain disabled')
	assert_true(type(migrated_profile.config.defensive.cure.curaga) == 'table', 'legacy profile must receive Curaga compatibility defaults')
	assert_false(migrated_profile.config.defensive.cure.curaga.enabled, 'legacy profile must leave Curaga disabled')
	assert_equal(migrated_profile.config.defensive.cure.curaga.min_targets, 3, 'legacy profile must receive the Curaga minimum target default')
	assert_true(type(migrated_profile.config.defensive.waltz) == 'table', 'legacy profile must receive Waltz compatibility defaults')
	assert_false(migrated_profile.config.defensive.waltz.enabled, 'legacy profile must leave Waltz disabled')
	assert_equal(migrated_profile.config.defensive.waltz.tp_reserve, 0, 'legacy profile must receive the Waltz TP reserve default')
	assert_equal(migrated_profile.config.defensive.waltz.divine_min_targets, 3, 'legacy profile must receive the Divine Waltz minimum target default')
	assert_true(type(migrated_profile.config.defensive.enemy_debuffs) == 'table', 'legacy profile must receive enemy debuff compatibility defaults')
	assert_false(migrated_profile.config.defensive.enemy_debuffs.enabled, 'legacy profile must leave enemy debuff maintenance disabled')
	assert_equal(migrated_profile.config.defensive.enemy_debuffs.list, '', 'legacy profile must receive an empty enemy debuff list')
	assert_true(type(migrated_profile.config.maintenance.geo) == 'table', 'legacy profile must receive normalized GEO configuration')
	assert_false(migrated_profile.config.maintenance.geo.enabled, 'migrated GEO configuration must remain disabled')
	assert_equal(migrated_profile.config.maintenance.geo.luopan.placement, 'target', 'migrated GEO placement must default to target')
	local migrated_projected, migrated_project_err = active_config.project_flat_settings(migrated_profile, {
		defensive_curaga_enabled = true,
		defensive_curaga_min_targets = 6,
		defensive_waltz_enabled = true,
		defensive_waltz_tp_reserve = 1000,
		defensive_divine_waltz_min_targets = 6,
		def_maintain_enemy_debuffs = true,
		defensive_enemy_debuffs = 'Distract',
	})
	assert_true(type(migrated_projected) == 'table', 'migrated GEO profile should project to runtime settings')
	assert_true(migrated_project_err == nil, 'migrated GEO profile projection should not report an error')
	assert_true(type(migrated_projected.camp_pulling) == 'table', 'migrated runtime settings must include camp pulling configuration')
	assert_true(type(migrated_projected.maintenance_geo) == 'table', 'migrated runtime settings must include GEO configuration')
	assert_false(migrated_projected.defensive_curaga_enabled, 'legacy profile projection must disable stale Curaga')
	assert_equal(migrated_projected.defensive_curaga_min_targets, 3, 'legacy profile projection must restore the Curaga minimum target default')
	assert_false(migrated_projected.defensive_waltz_enabled, 'legacy profile projection must disable stale Waltz')
	assert_equal(migrated_projected.defensive_waltz_tp_reserve, 0, 'legacy profile projection must restore the Waltz TP reserve default')
	assert_equal(migrated_projected.defensive_divine_waltz_min_targets, 3, 'legacy profile projection must restore the Divine Waltz minimum target default')
	assert_false(migrated_projected.def_maintain_enemy_debuffs, 'legacy profile projection must disable stale enemy debuff maintenance')
	assert_equal(migrated_projected.defensive_enemy_debuffs, '', 'legacy profile projection must clear a stale enemy debuff list')

	local invalid_enemy_debuffs_profile, invalid_enemy_debuffs_err = active_config.build_active_profile_from_v2_payload({
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Niightsiide',
			main_job = 'GEO',
			sub_job = 'RDM',
			source = 'ui',
		},
		config = {
			defensive = {
				enemy_debuffs = {
					enabled = 'false',
					list = '',
				},
			},
		},
	}, {
		character = 'Niightsiide',
		main_job = 'GEO',
		sub_job = 'RDM',
		source = 'UC_PROFILE_V2',
	})
	assert_true(invalid_enemy_debuffs_profile == nil, 'malformed enemy debuff configuration must fail profile activation')
	assert_true(type(invalid_enemy_debuffs_err) == 'string' and invalid_enemy_debuffs_err:find('config.defensive.enemy_debuffs.enabled must be a boolean', 1, true) ~= nil, 'malformed enemy debuff configuration must report the contract error')

	local invalid_waltz_profile, invalid_waltz_err = active_config.build_active_profile_from_v2_payload({
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Ponponponponpon',
			main_job = 'COR',
			sub_job = 'DNC',
			source = 'ui',
		},
		config = {
			defensive = {
				waltz = {
					enabled = false,
					tp_reserve = 5000,
					divine_min_targets = 3,
				},
			},
		},
	}, {
		character = 'Ponponponponpon',
		main_job = 'COR',
		sub_job = 'DNC',
		source = 'UC_PROFILE_V2',
	})
	assert_true(invalid_waltz_profile == nil, 'malformed Waltz configuration must fail profile activation')
	assert_true(type(invalid_waltz_err) == 'string' and invalid_waltz_err:find('config.defensive.waltz.tp_reserve must be an integer from 0 to 3000', 1, true) ~= nil, 'malformed Waltz configuration must report the contract error')

	local invalid_pulling_profile, invalid_pulling_err = active_config.build_active_profile_from_v2_payload({
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Niightsiide',
			main_job = 'GEO',
			sub_job = 'RDM',
			source = 'ui',
		},
		config = {
			combat = {
				pulling = 'invalid',
			},
		},
	}, {
		character = 'Niightsiide',
		main_job = 'GEO',
		sub_job = 'RDM',
		source = 'UC_PROFILE_V2',
	})
	assert_true(invalid_pulling_profile == nil, 'malformed pulling configuration must fail profile activation')
	assert_true(type(invalid_pulling_err) == 'string' and invalid_pulling_err:find('combat.pulling must be a table', 1, true) ~= nil, 'malformed pulling configuration must report the contract error')

	local bad_profile, bad_err = active_config.build_active_profile_from_v2_payload({ version = 1 }, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	assert_true(bad_profile == nil, 'invalid payload should fail to build active profile')
	assert_true(type(bad_err) == 'string' and bad_err ~= '', 'invalid payload should report an error')
	assert_false(sync_target == flat, 'sanity check for identity comparison')

	_G.UC_ACTIVE_PROFILE = previous_active_profile
	rawset(_G, 'windower', previous_windower)
	io.stdout:write('selftest_active_config: OK\n')
end

main()
