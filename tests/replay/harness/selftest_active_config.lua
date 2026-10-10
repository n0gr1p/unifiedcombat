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

	local canonical = active_config.get_config()
	assert_equal(canonical.combat.weaponskill.primary, 'Savage Blade', 'canonical weaponskill mismatch')
	assert_equal(canonical.combat.weaponskill.allow_aoe, false, 'canonical Smart WS AoE preference mismatch')
	assert_equal(canonical.combat.weaponskill.fast_skillchain, true, 'canonical Fast Skillchain preference mismatch')
	assert_equal(canonical.combat.weaponskill.no_skillchain_targets[1], 'Gyre', 'canonical no-skillchain target mismatch')
	assert_equal(canonical.combat.weaponskill.skillchain_target, 'light', 'canonical skillchain target mismatch')
	assert_equal(canonical.sleep.order[1], 'Horde Lullaby II', 'canonical sleep order mismatch')
	assert_equal(canonical.sleep.max_target_range, 14.0, 'canonical sleep target range mismatch')
	assert_equal(canonical.defensive.cure.curaga.enabled, true, 'canonical Curaga enabled mismatch')
	assert_equal(canonical.defensive.cure.curaga.min_targets, 4, 'canonical Curaga minimum mismatch')
	assert_equal(canonical.defensive.waltz.enabled, true, 'canonical Waltz enabled mismatch')
	assert_equal(canonical.defensive.waltz.tp_reserve, 1000, 'canonical Waltz reserve mismatch')
	assert_equal(canonical.defensive.buffs.targeted[1].character, 'Terrasjr', 'canonical targeted buff character mismatch')
	assert_equal(canonical.defensive.enemy_debuffs.list, 'Dia III|Distract III', 'canonical enemy debuff list mismatch')
	assert_equal(canonical.combat.weaponskill.wait_ignore_names[1], 'Niightsiide', 'canonical wait-ignore name mismatch')
	assert_equal(canonical.ownership.pause_automation_while_weakened, true, 'canonical recovery hold mismatch')
	assert_equal(canonical.follow.fight.leader_name, 'Niightsiide', 'canonical fight leader name mismatch')
	assert_equal(canonical.follow.partner.puller_name, 'Niightsiide', 'canonical puller name mismatch')
	assert_equal(canonical.follow.partner.leash_source, 'player', 'canonical puller leash source mismatch')
	assert_equal(canonical.follow.partner.engage_range, 9.5, 'canonical puller engage range mismatch')
	assert_equal(canonical.follow.nyzul.coordinator_name, 'Redrogue', 'canonical Nyzul coordinator mismatch')
	assert_equal(canonical.follow.nyzul.anchor_name, 'Terrasjr', 'canonical Nyzul anchor mismatch')
	assert_equal(canonical.follow.partner.names[1], 'Ponponponponpon', 'canonical primary partner name mismatch')
	assert_equal(canonical.follow.partner.names[2], 'Nyoourke', 'canonical secondary partner name mismatch')
	assert_deep_equal(flat, flat_snapshot, 'canonical active-profile construction must not mutate source settings')

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
	assert_equal(encounter_profile.config.encounter.policy.water_skillchain, 'warn', 'canonical encounter policy mismatch')
	assert_equal(encounter_profile.config.encounter.tuning.repeat_action_guard_s, 10.0, 'canonical encounter tuning mismatch')
	local disabled_encounter_profile = active_config.build_active_profile_from_v2_payload(ui_fixture, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_PROFILE_V2',
	})
	assert_true(disabled_encounter_profile.config.encounter == nil, 'disabled optional encounter domain must remain absent canonically')

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
	assert_equal(formation_profile.config.movement.formation.role, 'healer', 'formation role should remain durable')
	assert_true(formation_profile.config.movement.formation.enabled, 'enabled formation should remain canonical')
	assert_equal(formation_profile.config.movement.formation.tank_name, 'Terrasjr', 'formation tank name should remain canonical')
	assert_equal(formation_profile.config.movement.formation.required_party_names[2], 'Etamame', 'formation coverage members should remain canonical')
	assert_equal(formation_profile.config.movement.formation.tank.return_radius, 3, 'formation tank radius should remain canonical')
	assert_equal(formation_profile.config.movement.formation.dps.flank_angle_deg, 90, 'formation DPS angle should remain canonical')
	assert_equal(formation_profile.config.movement.formation.healer.maximum_party_range, 18, 'formation healer range should remain canonical')

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
	assert_true(type(migrated_profile.config.combat.pulling) == 'table', 'migrated canonical config must include camp pulling configuration')
	assert_false(migrated_profile.config.defensive.cure.curaga.enabled, 'legacy profile canonical migration must disable Curaga')
	assert_equal(migrated_profile.config.defensive.cure.curaga.min_targets, 3, 'legacy profile canonical migration must restore the Curaga minimum target default')
	assert_false(migrated_profile.config.defensive.waltz.enabled, 'legacy profile canonical migration must disable Waltz')
	assert_equal(migrated_profile.config.defensive.waltz.tp_reserve, 0, 'legacy profile canonical migration must restore the Waltz TP reserve default')
	assert_false(migrated_profile.config.defensive.enemy_debuffs.enabled, 'legacy profile canonical migration must disable enemy debuff maintenance')
	assert_equal(migrated_profile.config.defensive.enemy_debuffs.list, '', 'legacy profile canonical migration must clear enemy debuff list')

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
