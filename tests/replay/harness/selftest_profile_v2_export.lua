local function assert_true(condition, message)
	if not condition then
		error(message or 'assertion failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values are not equal') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function assert_contains(haystack, needle, message)
	assert_true(type(haystack) == 'string' and haystack:find(needle, 1, true) ~= nil, message or ('missing substring: ' .. tostring(needle)))
end

local function assert_not_contains(haystack, needle, message)
	assert_true(type(haystack) == 'string' and haystack:find(needle, 1, true) == nil, message or ('unexpected substring: ' .. tostring(needle)))
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

local function build_flat_settings()
	return {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		show_ingame_ui = true,
		engine_enabled = true,
		weaponskill_active = true,
		weaponskill = 'Savage Blade',
		ws_mode = 'smart',
		aftermath_enabled = true,
		aftermath_ws = 'Atonement',
		autotarget = true,
		spam = true,
		closer = true,
		manual = false,
		prime = false,
		static = false,
		face = true,
		ability_active = true,
		abilities = { 'Sentinel', 'Rampart' },
		tank = true,
		tank_enmity_actions = { 'Provoke', 'Flash' },
		defensive_enabled = true,
		defensive_provider = 'internal',
		defensive_cure_enabled = true,
		def_heal_min_tier_cure = 3,
		def_heal_max_tier_cure = 4,
		def_heal_min_missing_hp = 250,
		def_heal_ignore_trusts = true,
		defensive_doom_water = true,
		defensive_na_enabled = true,
		defensive_buff_enabled = true,
		defensive_buffs = 'Barspell',
		defensive_critical_hpp = 35,
		defensive_medium_hpp = 55,
		move = true,
		spacing = true,
		spacing_band_min = -0.9,
		spacing_band_max = 0.4,
		path_follow_enabled = true,
		path_file_name = 'route-a',
		path_points = { '1,2,3' },
		party_follow = true,
		party_follow_leader_name = 'Leader',
		party_follow_min = 1,
		party_follow_max = 25,
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
		cor_roll_1 = 'Chaos Roll',
		cor_roll_2 = 'Samurai Roll',
		sub = true,
		hunter = true,
		legacy_flag = true,
		profiles = {
			UC = {
				PLD = {
					marker = true,
				},
			},
		},
	}
end

local function build_expected_config()
	return {
		ui = {
			show_ingame_ui = true,
		},
		command = {
			engine_enabled_default = true,
		},
		combat = {
			enabled = true,
			autotarget = true,
			spam = true,
			closer = true,
			manual = false,
			prime = false,
			static = false,
			face = true,
			weaponskill = {
				enabled = true,
				primary = 'Savage Blade',
				mode = 'smart',
				aftermath_enabled = true,
				aftermath_ws = 'Atonement',
			},
		},
		abilities = {
			enabled = true,
			configured = { 'Sentinel', 'Rampart' },
			legacy_slots = {},
			wsabilities = {},
		},
		defensive = {
			enabled = true,
			provider = 'internal',
			cure = {
				enabled = true,
				min_tier = 3,
				max_tier = 4,
				min_missing_hp = 250,
				ignore_trusts = true,
			},
			doom = {
				holy_water_enabled = true,
			},
			na = {
				enabled = true,
			},
			enemy_buffs = {
				remove = false,
			},
			buffs = {
				enabled = true,
				self_only = true,
				list = 'Barspell',
				overwrite_enabled = false,
				overwrite_interval = 150,
			},
			thresholds = {
				critical_hpp = 35,
				medium_hpp = 55,
			},
		},
		movement = {
			enabled = true,
			move = true,
			spacing = {
				enabled = true,
				band_min = -0.9,
				band_max = 0.4,
				model_size_floor = 0.9,
				use_prediction = true,
				lookahead_s = 0.25,
				repel_hold_ticks = 5,
				overlap_deadband = 0.10,
				repel_weight = 0.35,
				band_deadband = 0.20,
			},
			path = {
				recording = false,
				follow_enabled = true,
				file_name = 'route-a',
				route_type = 'unknown',
				distance_to_start = 0,
				points = { '1,2,3' },
				party_gate_yalms = 3.0,
				resume_index_window = 12,
				hunter_targets = {},
				hunter_max_z_delta = 2.0,
				hunter_max_target_range = 20.0,
				hunter_claim_timeout_s = 4.0,
				hunter_ignore_cooldown_s = 20.0,
				pull_action_type = 'ja',
				pull_action_name = '',
			},
		},
		follow = {
			enabled = true,
			party = {
				enabled = true,
				leader_id = 0,
				leader_name = 'Leader',
				min = 1,
				max = 25,
			},
			fight = {
				leader = false,
				leader_id = 0,
				min = 3.0,
				hold_s = 8.0,
			},
			partner = {
				enabled = false,
				secondary_enabled = false,
				ids = {},
				puller = false,
				puller_id = 0,
				puller_distance_only = false,
			},
		},
		targeting = {
			add_control = true,
			add_priority_names = { 'Apex Bat' },
			legacy_slots = {},
			targets = {},
			targetability = {
				enabled = false,
				action = '',
			},
			ignore = {},
			target_ignore_names = {},
		},
		tank = {
			enabled = true,
			enmity = {
				actions = { 'Provoke', 'Flash' },
			},
		},
		sleep = {
			enabled = true,
			order = { 'Horde Lullaby II' },
			legacy_primary = 'Horde Lullaby II',
		},
		spells = {
			enabled = true,
			configured = 'Dia',
			dd2_slots = {},
		},
		maintenance = {
			enabled = true,
			cor = {
				roll_1 = 'Chaos Roll',
				roll_2 = 'Samurai Roll',
				crooked_roll_slot = 0,
				elevens = false,
				luzaf_range_override = false,
				range_selected = '',
				range_require_ids = {},
			},
			brd = {},
			geo = {},
		},
		debug = {
			enabled = true,
			combat_sched = false,
			ja_sched = false,
			ja_debug = false,
			def_sched = true,
			tank_sched = false,
		},
		ownership = {
			domain_combat_enabled = true,
			domain_defensive_enabled = true,
			domain_movement_enabled = true,
			domain_maintenance_enabled = true,
			domain_follow_enabled = true,
			scheduler_dark_launch_combat = true,
			scheduler_dark_launch_defensive = false,
			scheduler_dark_launch_movement = false,
			scheduler_dark_launch_maintenance = false,
		},
		legacy = {
			sub = true,
			sub2 = false,
			solo = false,
			aeonic = false,
			color = false,
			command = false,
			hunter = true,
			profiles = {
				UC = {
					PLD = {
						marker = true,
					},
				},
			},
		},
	}
end

local function main()
	package.loaded['uc_profile_v2_export'] = nil
	package.loaded['uc_config_normalizer'] = nil
	package.loaded['uc_profile_contract'] = nil
	local exporter = require('uc_profile_v2_export')
	local normalizer = require('uc_config_normalizer')
	local contract = require('uc_profile_contract')

	local flat = build_flat_settings()
	local flat_snapshot = deep_clone(flat)
	local profile = exporter.build_structured_profile(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		profile_key = 'Redrogue|PLD|WAR',
		exported_at = '2026-06-29T18:00:00Z',
	})
	assert_deep_equal(flat, flat_snapshot, 'structured export must not mutate input settings')
	assert_equal(profile.version, 2, 'structured profile version mismatch')
	assert_equal(profile.profile.schema_version, 2, 'structured profile schema version mismatch')
	assert_equal(profile.profile.engine, 'UC', 'structured profile engine mismatch')
	assert_equal(profile.profile.character, 'Redrogue', 'structured profile character mismatch')
	assert_equal(profile.profile.main_job, 'PLD', 'structured profile main job mismatch')
	assert_equal(profile.profile.sub_job, 'WAR', 'structured profile sub job mismatch')
	assert_equal(profile.profile.source, 'exported_from_v1_settings', 'structured profile source mismatch')
	assert_equal(profile.profile.exported_at, '2026-06-29T18:00:00Z', 'structured profile export time mismatch')
	assert_equal(profile.profile.profile_key, 'Redrogue|PLD|WAR', 'structured profile key mismatch')
	assert_equal(profile.config.ui.show_ingame_ui, true, 'ui domain mismatch')
	assert_equal(profile.config.command.engine_enabled_default, true, 'command domain mismatch')
	assert_equal(profile.config.combat.weaponskill.primary, 'Savage Blade', 'combat domain mismatch')
	assert_equal(profile.config.maintenance.cor.roll_1, 'Chaos Roll', 'maintenance domain mismatch')
	assert_equal(profile.config.legacy.hunter, true, 'legacy domain mismatch')
	assert_true(profile.config.profile == nil, 'exported config must not include profile metadata')
	assert_true(profile.config.scheduler_action_state == nil, 'exported config must not include runtime scheduler state')
	assert_true(profile.config.pending_state == nil, 'exported config must not include pending state')
	assert_true(profile.config.current_selected_action == nil, 'exported config must not include current action state')
	assert_true(profile.config.current_target == nil, 'exported config must not include current target state')
	assert_true(profile.config.party_snapshot == nil, 'exported config must not include party snapshots')
	assert_true(profile.config.mob_snapshot == nil, 'exported config must not include mob snapshots')
	assert_true(profile.config.config_contract_status == nil, 'exported config must not include config status')
	assert_true(profile.config.uc_settings == nil, 'exported config must not include settings alias')

	local contract_result = contract.validate_structured_profile_config(profile)
	assert_true(contract_result.ok == true, 'structured profile export should validate')

	local serialized = exporter.serialize_structured_profile(profile)
	local chunk, load_err = loadstring(serialized)
	assert_true(type(chunk) == 'function', 'serialized structured profile must load as Lua: ' .. tostring(load_err))
	local ok_load, loaded = pcall(chunk)
	assert_true(ok_load == true, 'serialized structured profile chunk should execute')
	assert_true(type(loaded) == 'table', 'serialized structured profile must return a table')
	assert_deep_equal(loaded, profile, 'serialized structured profile should round-trip cleanly')

	local normalized = normalizer.normalize(loaded, {
		character = loaded.profile.character,
		main_job = loaded.profile.main_job,
		sub_job = loaded.profile.sub_job,
		source = loaded.profile.source,
	})
	assert_equal(normalized.profile.character, 'Redrogue', 'round-tripped normalized character mismatch')
	assert_equal(normalized.combat.weaponskill.primary, 'Savage Blade', 'round-tripped normalized combat mismatch')
	assert_equal(normalized.maintenance.cor.roll_2, 'Samurai Roll', 'round-tripped normalized maintenance mismatch')
	assert_equal(normalized.legacy.hunter, true, 'round-tripped normalized legacy mismatch')

	local defaults = exporter.build_structured_profile(nil, nil)
	assert_equal(defaults.profile.character, 'unknown', 'nil settings character default mismatch')
	assert_equal(defaults.profile.main_job, 'UNKNOWN', 'nil settings main job default mismatch')
	assert_equal(defaults.profile.sub_job, 'UNKNOWN', 'nil settings sub job default mismatch')
	assert_equal(defaults.profile.source, 'exported_from_v1_settings', 'nil settings source default mismatch')
	assert_equal(defaults.config.combat.enabled, true, 'nil settings combat default mismatch')
	assert_equal(defaults.config.debug.enabled, false, 'nil settings debug default mismatch')

	local path = exporter.default_export_path({
		character = ' Red Rogue! ',
		main_job = 'pld',
		sub_job = 'war',
	})
	assert_equal(path, 'data/profiles_v2/red_rogue_PLD_WAR.lua', 'export path mismatch')
	assert_equal(exporter.default_export_path(nil), 'data/profiles_v2/unknown_UNKNOWN_UNKNOWN.lua', 'nil export path mismatch')

	local file = io.open('UnifiedCombat.lua', 'r')
	assert_true(file ~= nil, 'unable to read UnifiedCombat.lua')
	local addon = file:read('*a')
	file:close()
	assert_contains(addon, "elseif a == 'profilev2' then", 'addon must route profilev2 command')
	assert_contains(addon, "//uc profilev2 export", 'addon must advertise profilev2 export help')
	assert_not_contains(addon, 'windower.add_to_chat(207, uc_profile_v2_export.serialize_structured_profile', 'addon must not dump structured profile contents to chat')

	local expected_config = build_expected_config()
	assert_true(deep_equal(profile.config, expected_config), 'exported config mismatch against expected durable domains')

	io.stdout:write('selftest_profile_v2_export: OK\n')
end

main()
