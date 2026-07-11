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
		autotarget = true,
		spam = true,
		closer = true,
		manual = false,
		prime = false,
		static = false,
		face = true,
		defensive_enabled = true,
		defensive_cure_enabled = true,
		def_heal_min_tier_cure = 3,
		def_heal_max_tier_cure = 4,
		def_heal_min_missing_hp = 250,
		def_heal_ignore_trusts = true,
		defensive_targeted_buffs = 'Terrasjr:Honor March|Nyoourke:Valor Minuet V',
		move = true,
		spacing = true,
		path_follow_enabled = true,
		path_file_name = 'route-a',
		path_points = { '1,2,3' },
		party_follow = true,
		party_follow_leader_name = 'Leader',
		puller = true,
		puller_name = 'Niightsiide',
		wait_ignore_names = { 'Niightsiide' },
		target_ignore_names = { 'Ignore Me' },
		add_control = true,
		add_priority_names = { 'Apex Bat' },
		sleep = true,
		sleepspells = { 'Horde Lullaby II' },
		spell_active = true,
		spell = 'Dia',
		debug = true,
		log_def_sched = true,
		domain_combat_enabled = true,
		domain_defensive_enabled = true,
		domain_movement_enabled = true,
		domain_maintenance_enabled = true,
		domain_follow_enabled = true,
		scheduler_dark_launch_combat = true,
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
	assert_equal(active_profile.config.follow.partner.puller_name, 'Niightsiide', 'active puller name mismatch')
	assert_equal(active_profile.config.follow.partner.puller_id, 0, 'active puller id should remain runtime-owned in the durable active profile')
	assert_equal(active_profile.config.targeting.target_ignore_names[1], 'Ignore Me', 'active target ignore names mismatch')
	assert_equal(active_profile.config.maintenance.enabled, true, 'active maintenance domain mismatch')
	assert_equal(active_profile.config.legacy.hunter, true, 'active legacy hunter mismatch')
	assert_deep_equal(flat, flat_snapshot, 'building active profile must not mutate input settings')

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
	assert_equal(projected.sleep, true, 'projected sleep mismatch')
	assert_equal(projected.sleepspell, 'Horde Lullaby II', 'projected sleep mirror mismatch')
	assert_equal(projected.sleepspells[1], 'Horde Lullaby II', 'projected sleep list mismatch')
	assert_equal(projected.defensive_targeted_buffs, 'Terrasjr:Honor March|Nyoourke:Valor Minuet V', 'projected targeted buff mirror mismatch')
	assert_equal(projected.wait_ignore_names[1], 'Niightsiide', 'projected wait ignore names mismatch')
	assert_equal(projected.ignore[1], 77, 'projected compatibility ignore id mismatch')
	assert_equal(projected.puller_name, 'Niightsiide', 'projected puller name mismatch')
	assert_equal(projected.puller_id, 77, 'projected puller id should resolve from puller name')
	assert_equal(projected.follow.partner.puller_name, 'Niightsiide', 'projected nested puller name mismatch')
	assert_equal(projected.follow.partner.puller_id, 77, 'projected nested puller id mismatch')
	assert_true(type(projected.partner_ids) == 'table' and #projected.partner_ids == 0, 'projected compatibility table should keep empty partner ids as an empty list')

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
	assert_true(type(ui_profile) == 'table', 'active profile from v2 payload must be a table')
	assert_equal(ui_profile.version, 2, 'UI active profile version mismatch')
	assert_equal(ui_profile.profile.source, 'ui', 'UI active profile source mismatch')
	assert_equal(ui_profile.profile.character, 'Redrogue', 'UI active profile character mismatch')
	assert_equal(ui_profile.profile.main_job, 'PLD', 'UI active profile main job mismatch')
	assert_equal(ui_profile.profile.sub_job, 'WAR', 'UI active profile sub job mismatch')
	assert_equal(ui_profile.config.combat.weaponskill.primary, 'Savage Blade', 'UI active combat mismatch')
	assert_equal(ui_profile.config.movement.path.file_name, 'route-a', 'UI active path mismatch')
	assert_equal(ui_profile.config.follow.party.leader_name, 'Leader', 'UI active follow mismatch')
	assert_equal(ui_profile.config.follow.partner.puller_name, 'Niightsiide', 'UI active puller mismatch')
	assert_equal(ui_profile.config.combat.weaponskill.wait_ignore_names[1], 'Ally One', 'UI active wait ignore name mismatch')
	assert_equal(ui_profile.config.targeting.target_ignore_names[1], 'Mob One', 'UI active target ignore name mismatch')
	assert_equal(ui_profile.config.defensive.buffs.targeted[1].character, 'Terrasjr', 'UI active targeted buff character mismatch')
	assert_equal(ui_profile.config.defensive.buffs.targeted[1].buff, 'Honor March', 'UI active targeted buff name mismatch')
	assert_deep_equal(ui_fixture, ui_fixture_snapshot, 'building from payload must not mutate fixture')

	local ui_set_ok, ui_stored_profile = active_config.set_active_profile(ui_profile)
	assert_true(ui_set_ok == true, 'setting UI active profile should succeed')
	assert_true(ui_stored_profile == rawget(_G, 'UC_ACTIVE_PROFILE'), 'UI active profile should be stored in place')
	assert_equal(active_config.get_path('profile.source'), 'ui', 'active profile path access should reach metadata')
	assert_equal(active_config.get_path('config.movement.path.file_name'), 'route-a', 'active profile path access should reach config')

	local normalized = normalizer.normalize(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	assert_equal(normalized.profile.source, 'UC_SETTINGS', 'normalizer source mismatch')

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
