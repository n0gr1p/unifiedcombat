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

local function assert_nil(value, message)
	if value ~= nil then
		error((message or 'value should be nil') .. ': actual=' .. tostring(value))
	end
end

local function assert_false(value, message)
	if value ~= false then
		error((message or 'value should be false') .. ': actual=' .. tostring(value))
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

local function make_fake_fs(initial_files, failures, initial_dirs)
	local dirs = {}
	if initial_dirs == nil then
		dirs['data/profiles_v2'] = true
	else
		dirs = deep_clone(initial_dirs)
	end
	local state = {
		files = deep_clone(initial_files or {}),
		dirs = dirs,
		failures = failures or {},
		rename_calls = {},
		remove_calls = {},
		open_calls = {},
		read_calls = {},
		load_calls = {},
		create_dir_calls = {},
		execute_calls = 0,
	}

	local deps = {}

	function deps.open(path, mode)
		state.open_calls[#state.open_calls + 1] = { path = path, mode = mode }
		local err = state.failures.open and state.failures.open[path]
		if err ~= nil then
			return nil, err
		end
		local handle = {
			closed = false,
			buffer = '',
		}
		function handle:write(content)
			local write_err = state.failures.write and state.failures.write[path]
			if write_err ~= nil then
				return nil, write_err
			end
			self.buffer = self.buffer .. tostring(content or '')
			return true
		end
		function handle:close()
			local close_err = state.failures.close and state.failures.close[path]
			if close_err ~= nil then
				return nil, close_err
			end
			self.closed = true
			state.files[path] = self.buffer
			return true
		end
		return handle
	end

	function deps.exists(path)
		local err = state.failures.exists and state.failures.exists[path]
		if err ~= nil then
			error(err)
		end
		return state.files[path] ~= nil
	end

	function deps.dir_exists(path)
		local err = state.failures.dir_exists and state.failures.dir_exists[path]
		if err ~= nil then
			error(err)
		end
		return state.dirs[path] == true
	end

	function deps.create_dir(path)
		state.create_dir_calls[#state.create_dir_calls + 1] = path
		local err = state.failures.create_dir and state.failures.create_dir[path]
		if err ~= nil then
			return nil, err
		end
		state.dirs[path] = true
		return true
	end

	function deps.rename(from_path, to_path)
		state.rename_calls[#state.rename_calls + 1] = { from_path = from_path, to_path = to_path }
		local key = from_path .. '->' .. to_path
		local err = state.failures.rename and state.failures.rename[key]
		if err ~= nil then
			return nil, err
		end
		if state.files[from_path] == nil then
			return nil, 'source missing'
		end
		if state.files[to_path] ~= nil then
			return nil, 'target exists'
		end
		state.files[to_path] = state.files[from_path]
		state.files[from_path] = nil
		return true
	end

	function deps.remove(path)
		state.remove_calls[#state.remove_calls + 1] = path
		local err = state.failures.remove and state.failures.remove[path]
		if err ~= nil then
			return nil, err
		end
		if state.files[path] == nil then
			return nil, 'missing'
		end
		state.files[path] = nil
		return true
	end

	function deps.read_all(path)
		state.read_calls[#state.read_calls + 1] = path
		local err = state.failures.read and state.failures.read[path]
		if err ~= nil then
			return nil, err
		end
		local content = state.files[path]
		if type(content) ~= 'string' or content == '' then
			return nil, 'missing'
		end
		return content
	end

	function deps.load_chunk(content, chunk_name)
		state.load_calls[#state.load_calls + 1] = { content = content, chunk_name = chunk_name }
		local err = state.failures.load and state.failures.load[content]
		if err ~= nil then
			return nil, err
		end
		return loadstring(content, chunk_name)
	end

	function deps.execute_chunk(chunk)
		state.execute_calls = state.execute_calls + 1
		return chunk()
	end

	return deps, state
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
	local addon_local_path = exporter.default_export_path({
		character = ' Red Rogue! ',
		main_job = 'pld',
		sub_job = 'war',
		addon_path = 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\',
	})
	assert_equal(addon_local_path, 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\data\\profiles_v2\\red_rogue_PLD_WAR.lua', 'addon-local export path mismatch')
	local durable_path = exporter.default_export_path({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	})

	local expected_serialized = exporter.serialize_structured_profile(profile)
	local durable_deps, durable_state = make_fake_fs()
	local durable_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, durable_deps)
	assert_true(durable_result.ok == true, 'durable export helper should report success')
	assert_equal(durable_result.path, durable_path, 'durable export helper path mismatch')
	assert_equal(durable_state.files[durable_path], expected_serialized, 'durable export helper should write serialized profile content')
	assert_nil(durable_state.files[durable_path .. '.tmp'], 'temp file should not remain after successful promote')
	assert_nil(durable_state.files[durable_path .. '.bak'], 'backup file should not remain after successful promote')

	local created_dir_path = exporter.default_export_path({
		character = 'Created',
		main_job = 'BRD',
		sub_job = 'WHM',
	})
	local create_dir_deps, create_dir_state = make_fake_fs(nil, nil, {})
	local create_dir_result = exporter.write_structured_profile_export(profile, {
		character = 'Created',
		main_job = 'BRD',
		sub_job = 'WHM',
	}, create_dir_deps)
	assert_true(create_dir_result.ok == true, 'missing output directory should be created for explicit export')
	assert_equal(create_dir_state.create_dir_calls[1], 'data/profiles_v2', 'export should create only the v2 profile directory')
	assert_equal(create_dir_state.files[created_dir_path], expected_serialized, 'export should write after creating the v2 profile directory')

	local dir_fail_deps = make_fake_fs(nil, {
		create_dir = {
			['data/profiles_v2'] = 'access denied',
		},
	}, {})
	local dir_fail_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, dir_fail_deps)
	assert_true(dir_fail_result.ok == false, 'directory create failure should report failure')
	assert_equal(dir_fail_result.stage, 'prepare_dir', 'directory failure stage mismatch')
	assert_equal(dir_fail_result.reason, 'output directory unavailable', 'directory failure reason mismatch')
	assert_equal(dir_fail_result.detail, 'access denied', 'directory failure detail mismatch')

	local open_fail_deps = make_fake_fs(nil, {
		open = {
			[durable_path .. '.tmp'] = 'permission denied',
		},
	})
	local open_fail_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, open_fail_deps)
	assert_true(open_fail_result.ok == false, 'temp open failure should report failure')
	assert_equal(open_fail_result.stage, 'open_temp', 'temp open failure stage mismatch')
	assert_equal(open_fail_result.reason, 'temp open failed', 'temp open failure reason mismatch')
	assert_equal(open_fail_result.detail, 'permission denied', 'temp open failure detail mismatch')

	local write_fail_deps, write_fail_state = make_fake_fs({
		[durable_path] = 'return { version = 2, preserved = true }\n',
	}, {
		write = {
			[durable_path .. '.tmp'] = 'disk full',
		},
	})
	local write_fail_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, write_fail_deps)
	assert_true(write_fail_result.ok == false, 'temp write failure should report failure')
	assert_equal(write_fail_result.stage, 'write_temp', 'temp write failure stage mismatch')
	assert_equal(write_fail_result.reason, 'temp write failed', 'temp write failure reason mismatch')
	assert_equal(write_fail_result.detail, 'disk full', 'temp write failure detail mismatch')
	assert_equal(write_fail_state.files[durable_path], 'return { version = 2, preserved = true }\n', 'temp write failure must preserve existing final file')
	assert_nil(write_fail_state.files[durable_path .. '.tmp'], 'temp write failure should clean temp file')

	local close_fail_deps, close_fail_state = make_fake_fs({
		[durable_path] = 'return { version = 2, preserved = true }\n',
	}, {
		close = {
			[durable_path .. '.tmp'] = 'close denied',
		},
	})
	local close_fail_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, close_fail_deps)
	assert_true(close_fail_result.ok == false, 'temp close failure should report failure')
	assert_equal(close_fail_result.stage, 'close_temp', 'temp close failure stage mismatch')
	assert_equal(close_fail_result.reason, 'temp close failed', 'temp close failure reason mismatch')
	assert_equal(close_fail_result.detail, 'close denied', 'temp close failure detail mismatch')
	assert_equal(close_fail_state.files[durable_path], 'return { version = 2, preserved = true }\n', 'temp close failure must preserve existing final file')

	local promote_fail_deps, promote_fail_state = make_fake_fs({
		[durable_path] = 'return { version = 2, preserved = true }\n',
	}, {
		rename = {
			[durable_path .. '.tmp->' .. durable_path] = 'rename blocked',
		},
	})
	local promote_fail_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, promote_fail_deps)
	assert_true(promote_fail_result.ok == false, 'promotion failure should report failure')
	assert_equal(promote_fail_result.stage, 'promote', 'promotion failure stage mismatch')
	assert_equal(promote_fail_result.reason, 'temp promote failed', 'promotion failure reason mismatch')
	assert_equal(promote_fail_result.detail, 'rename blocked', 'promotion failure detail mismatch')
	assert_true(promote_fail_result.restore_ok == true, 'promotion failure should restore existing final file when possible')
	assert_equal(promote_fail_state.files[durable_path], 'return { version = 2, preserved = true }\n', 'promotion failure should restore preserved final file')
	assert_nil(promote_fail_state.files[durable_path .. '.tmp'], 'promotion failure should clean temp file')
	assert_nil(promote_fail_state.files[durable_path .. '.bak'], 'promotion failure should clean backup file after restore')

	profile.self = profile
	local render_fail_result = exporter.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, durable_deps)
	profile.self = nil
	assert_true(render_fail_result.ok == false, 'serialization failure should report failure')
	assert_equal(render_fail_result.stage, 'render', 'serialization failure stage mismatch')
	assert_equal(render_fail_result.reason, 'serialization failed', 'serialization failure reason mismatch')

	local validate_settings_snapshot = {
		engine_enabled = true,
		weaponskill = 'Savage Blade',
	}
	_G.UC_SETTINGS = deep_clone(validate_settings_snapshot)

	local validate_ok_deps, validate_ok_state = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local validate_ok_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_ok_deps)
	assert_true(validate_ok_result.ok == true, 'structured profile validation should succeed for well-formed export')
	assert_equal(validate_ok_result.path, durable_path, 'structured profile validation path mismatch')
	assert_equal(#validate_ok_state.read_calls, 1, 'structured profile validation should read one file')
	assert_deep_equal(_G.UC_SETTINGS, validate_settings_snapshot, 'structured profile validation must not mutate UC_SETTINGS')

	local validate_read_fail_deps = make_fake_fs(nil, {
		read = {
			[durable_path] = 'missing',
		},
	})
	local validate_read_fail_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_read_fail_deps)
	assert_true(validate_read_fail_result.ok == false, 'structured profile validation should fail when file cannot be read')
	assert_equal(validate_read_fail_result.stage, 'read', 'structured profile read failure stage mismatch')

	local validate_not_table_deps = make_fake_fs({
		[durable_path] = 'return "not a table"\n',
	})
	local validate_not_table_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_not_table_deps)
	assert_true(validate_not_table_result.ok == false, 'structured profile validation should fail when file does not return a table')
	assert_equal(validate_not_table_result.stage, 'shape', 'structured profile non-table failure stage mismatch')

	local validate_bad_version_deps = make_fake_fs({
		[durable_path] = 'return { version = 1, profile = {}, config = {} }\n',
	})
	local validate_bad_version_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_bad_version_deps)
	assert_true(validate_bad_version_result.ok == false, 'structured profile validation should fail when version is not 2')
	assert_equal(validate_bad_version_result.reason, 'invalid version', 'structured profile invalid version reason mismatch')

	local validate_missing_profile_deps = make_fake_fs({
		[durable_path] = 'return { version = 2, config = {} }\n',
	})
	local validate_missing_profile_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_missing_profile_deps)
	assert_true(validate_missing_profile_result.ok == false, 'structured profile validation should fail when profile is missing')
	assert_equal(validate_missing_profile_result.reason, 'missing profile', 'structured profile missing profile reason mismatch')

	local validate_missing_config_deps = make_fake_fs({
		[durable_path] = 'return { version = 2, profile = {} }\n',
	})
	local validate_missing_config_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_missing_config_deps)
	assert_true(validate_missing_config_result.ok == false, 'structured profile validation should fail when config is missing')
	assert_equal(validate_missing_config_result.reason, 'missing config', 'structured profile missing config reason mismatch')
	assert_deep_equal(_G.UC_SETTINGS, validate_settings_snapshot, 'structured profile validation failures must not mutate UC_SETTINGS')

	local contract_fail_deps = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local contract_fail_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, function()
		return {
			ok = false,
			errors = { 'forced contract failure' },
		}
	end, contract_fail_deps)
	assert_true(contract_fail_result.ok == false, 'structured profile validation should report contract validation failure')
	assert_equal(contract_fail_result.stage, 'contract', 'contract validation failure stage mismatch')
	assert_equal(contract_fail_result.reason, 'contract failed', 'contract validation failure reason mismatch')
	assert_equal(contract_fail_result.error, 'forced contract failure', 'contract validation failure detail mismatch')

	local diff_ok_deps = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local diff_ok_result = exporter.diff_structured_profile_file_against_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, diff_ok_deps)
	assert_true(diff_ok_result.ok == true, 'structured profile diff should succeed for matching config')
	assert_equal(diff_ok_result.count, 0, 'structured profile diff should report zero differences for matching config')
	assert_equal(#diff_ok_result.differences, 0, 'structured profile diff details should be empty for matching config')

	local scalar_diff_payload = deep_clone(profile)
	scalar_diff_payload.profile.exported_at = '2099-01-01T00:00:00Z'
	scalar_diff_payload.config.combat.face = false
	local scalar_diff_deps = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(scalar_diff_payload),
	})
	local scalar_diff_result = exporter.diff_structured_profile_file_against_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, scalar_diff_deps)
	assert_true(scalar_diff_result.ok == true, 'structured profile diff should succeed for scalar difference payload')
	assert_equal(scalar_diff_result.count, 1, 'structured profile diff should report one changed scalar value')
	assert_equal(scalar_diff_result.differences[1], 'config.combat.face', 'structured profile diff scalar path mismatch')

	local nested_diff_payload = deep_clone(profile)
	nested_diff_payload.config.movement.spacing.band_max = 0.9
	local nested_diff_deps = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(nested_diff_payload),
	})
	local nested_diff_result = exporter.diff_structured_profile_file_against_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, nested_diff_deps)
	assert_true(nested_diff_result.ok == true, 'structured profile diff should succeed for nested difference payload')
	assert_equal(nested_diff_result.count, 1, 'structured profile diff should report one nested table difference')
	assert_equal(nested_diff_result.differences[1], 'config.movement.spacing.band_max', 'structured profile diff nested path mismatch')

	local missing_key_payload = deep_clone(profile)
	missing_key_payload.config.sleep.order = nil
	local missing_key_deps = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(missing_key_payload),
	})
	local missing_key_result = exporter.diff_structured_profile_file_against_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, missing_key_deps)
	assert_true(missing_key_result.ok == true, 'structured profile diff should succeed for missing key payload')
	assert_equal(missing_key_result.count, 1, 'structured profile diff should report one missing key difference')
	assert_equal(missing_key_result.differences[1], 'config.sleep.order', 'structured profile diff missing key path mismatch')

	local metadata_only_payload = deep_clone(profile)
	metadata_only_payload.profile.exported_at = '2100-12-31T23:59:59Z'
	metadata_only_payload.profile.profile_key = 'Other|Job|Pair'
	local metadata_only_deps = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(metadata_only_payload),
	})
	local metadata_only_result = exporter.diff_structured_profile_file_against_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, metadata_only_deps)
	assert_true(metadata_only_result.ok == true, 'structured profile diff should succeed for metadata-only payload')
	assert_equal(metadata_only_result.count, 0, 'structured profile diff should ignore profile metadata differences')

	local order_diff_left = {
		alpha = {
			x = 1,
			y = 2,
		},
		beta = true,
	}
	local order_diff_right = {
		beta = true,
		alpha = {
			y = 2,
			x = 1,
		},
	}
	local order_diff_result = exporter.diff_durable_config(order_diff_left, order_diff_right)
	assert_equal(order_diff_result.count, 0, 'structured profile diff should ignore table key order')

	local deterministic_left = {
		beta = {
			inner_b = 2,
			inner_a = 1,
		},
		alpha = true,
	}
	local deterministic_right = {
		beta = {
			inner_b = 3,
			inner_a = 0,
		},
		alpha = false,
	}
	local deterministic_first = exporter.diff_durable_config(deterministic_left, deterministic_right)
	local deterministic_second = exporter.diff_durable_config(deterministic_left, deterministic_right)
	assert_equal(deterministic_first.count, 3, 'structured profile diff deterministic count mismatch')
	assert_deep_equal(deterministic_first.differences, {
		'config.alpha',
		'config.beta.inner_a',
		'config.beta.inner_b',
	}, 'structured profile diff deterministic order mismatch')
	assert_deep_equal(deterministic_first.differences, deterministic_second.differences, 'structured profile diff should be deterministic')

	local diff_fail_result = exporter.diff_structured_profile_file_against_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_missing_config_deps)
	assert_true(diff_fail_result.ok == false, 'structured profile diff should fail cleanly when validation fails')
	assert_equal(diff_fail_result.reason, 'missing config', 'structured profile diff failure reason mismatch')
	assert_deep_equal(_G.UC_SETTINGS, validate_settings_snapshot, 'structured profile diff must not mutate UC_SETTINGS')

	local apply_fail_snapshot = deep_clone(validate_settings_snapshot)
	local apply_fail_deps = make_fake_fs({
		[durable_path] = 'return { version = 2, profile = {} }\n',
	})
	local apply_fail_result = exporter.apply_structured_profile_file_to_settings(_G.UC_SETTINGS, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, apply_fail_deps)
	assert_true(apply_fail_result.ok == false, 'structured profile apply should fail cleanly when validation fails')
	assert_equal(apply_fail_result.reason, 'missing config', 'structured profile apply validation failure reason mismatch')
	assert_deep_equal(_G.UC_SETTINGS, apply_fail_snapshot, 'structured profile apply validation failure must not mutate UC_SETTINGS')

	local no_diff_settings = deep_clone(flat)
	local no_diff_identity = no_diff_settings
	local no_diff_deps, no_diff_state = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local no_diff_apply_result = exporter.apply_structured_profile_file_to_settings(no_diff_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, no_diff_deps)
	assert_true(no_diff_apply_result.ok == true, 'structured profile apply should succeed for matching config')
	assert_equal(no_diff_apply_result.count, 0, 'structured profile apply should report zero differences for matching config')
	assert_true(no_diff_settings == no_diff_identity, 'structured profile apply helper must not replace settings table identity')
	assert_deep_equal(no_diff_settings, flat, 'structured profile apply helper should leave matching settings unchanged')
	assert_equal(#no_diff_state.open_calls, 0, 'structured profile apply should not write to disk on no-diff apply')
	assert_equal(#no_diff_state.rename_calls, 0, 'structured profile apply should not rename files on no-diff apply')

	local scalar_apply_payload = deep_clone(profile)
	scalar_apply_payload.config.combat.face = false
	local scalar_apply_deps, scalar_apply_state = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(scalar_apply_payload),
	})
	local scalar_apply_settings = deep_clone(flat)
	local scalar_apply_identity = scalar_apply_settings
	local scalar_apply_result = exporter.apply_structured_profile_file_to_settings(scalar_apply_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, scalar_apply_deps)
	assert_true(scalar_apply_result.ok == true, 'structured profile apply should succeed for scalar change')
	assert_equal(scalar_apply_result.count, 1, 'structured profile apply should report one scalar change')
	assert_true(scalar_apply_settings == scalar_apply_identity, 'structured profile apply should preserve settings table identity')
	assert_false(scalar_apply_result.candidate.face, 'structured profile apply candidate should update scalar runtime setting')
	assert_equal(scalar_apply_result.candidate.weaponskill, 'Savage Blade', 'structured profile apply candidate should preserve unrelated runtime setting values')
	assert_equal(#scalar_apply_state.open_calls, 0, 'structured profile apply should not write files on scalar apply')

	local nested_apply_payload = deep_clone(profile)
	nested_apply_payload.config.movement.path.file_name = 'route-b'
	nested_apply_payload.config.follow.partner.ids = { 99, 100 }
	local nested_apply_deps = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(nested_apply_payload),
	})
	local nested_apply_settings = deep_clone(flat)
	local nested_apply_result = exporter.apply_structured_profile_file_to_settings(nested_apply_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, nested_apply_deps)
	assert_true(nested_apply_result.ok == true, 'structured profile apply should succeed for nested change')
	assert_equal(nested_apply_result.candidate.path_file_name, 'route-b', 'structured profile apply should update nested movement runtime field')
	assert_equal(nested_apply_result.candidate.partner_ids[1], 99, 'structured profile apply should update nested partner id list')
	assert_equal(nested_apply_result.candidate.partner_id, 99, 'structured profile apply should sync primary partner legacy field')
	assert_equal(nested_apply_result.candidate.partner_id2, 100, 'structured profile apply should sync secondary partner legacy field')

	local metadata_apply_payload = deep_clone(profile)
	metadata_apply_payload.profile.character = 'SomeoneElse'
	metadata_apply_payload.profile.main_job = 'THF'
	metadata_apply_payload.profile.exported_at = '2101-01-01T00:00:00Z'
	local metadata_apply_deps = make_fake_fs({
		[durable_path] = exporter.serialize_structured_profile(metadata_apply_payload),
	})
	local metadata_apply_settings = deep_clone(flat)
	local metadata_apply_result = exporter.apply_structured_profile_file_to_settings(metadata_apply_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, metadata_apply_deps)
	assert_true(metadata_apply_result.ok == true, 'structured profile apply should succeed for metadata-only differences')
	assert_equal(metadata_apply_result.count, 0, 'structured profile apply should ignore profile metadata differences')
	assert_equal(exporter.diff_durable_config(exporter.build_durable_config(metadata_apply_result.candidate, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}), profile.config).count, 0, 'structured profile apply should ignore profile metadata changes')

	local conversion_fail_snapshot = deep_clone(flat)
	local conversion_fail_deps = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local conversion_fail_result = exporter.apply_structured_profile_file_to_settings(conversion_fail_snapshot, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, {
		read_all = conversion_fail_deps.read_all,
		load_chunk = conversion_fail_deps.load_chunk,
		execute_chunk = conversion_fail_deps.execute_chunk,
		build_durable_config = function()
			error('forced normalize failure')
		end,
		diff_durable_config = exporter.diff_durable_config,
	})
	assert_true(conversion_fail_result.ok == false, 'structured profile apply should fail on conversion helper failure')
	assert_equal(conversion_fail_result.stage, 'convert', 'structured profile apply conversion failure stage mismatch')
	assert_deep_equal(conversion_fail_snapshot, flat, 'structured profile apply conversion failure must not mutate settings')

	local file = io.open('UnifiedCombat.lua', 'r')
	assert_true(file ~= nil, 'unable to read UnifiedCombat.lua')
	local addon = file:read('*a')
	file:close()
	assert_contains(addon, "elseif a == 'profilev2' then", 'addon must route profilev2 command')
	assert_contains(addon, "//uc profilev2 export", 'addon must advertise profilev2 export help')
	assert_contains(addon, "//uc profilev2 validate", 'addon must advertise profilev2 validate help')
	assert_contains(addon, "//uc profilev2 diff", 'addon must advertise profilev2 diff help')
	assert_contains(addon, "//uc profilev2 apply", 'addon must advertise profilev2 apply help')
	assert_contains(addon, "uc_profile_v2_export.write_structured_profile_export(profile, meta)", 'addon must use structured profile export helper')
	assert_contains(addon, "uc_profile_v2_export.validate_structured_profile_file(meta, function(payload)", 'addon must use structured profile validate helper')
	assert_contains(addon, "uc_profile_v2_export.diff_structured_profile_file_against_settings(settings, meta, function(payload)", 'addon must use structured profile diff helper')
	assert_contains(addon, "uc_profile_v2_export.apply_structured_profile_file_to_settings(settings, meta, function(payload)", 'addon must use structured profile apply helper')
	assert_contains(addon, "UC profile v2 export failed: ", 'addon export failure chat must include reason')
	assert_contains(addon, "addon_path = uc_addon_path()", 'addon must resolve v2 profile files under the addon path')
	assert_not_contains(addon, 'UC profile v2 apply: ' .. "profile saved", 'structured profile apply path must not report v1 save behavior')
	assert_not_contains(addon, 'windower.add_to_chat(207, uc_profile_v2_export.serialize_structured_profile', 'addon must not dump structured profile contents to chat')

	local expected_config = build_expected_config()
	assert_true(deep_equal(profile.config, expected_config), 'exported config mismatch against expected durable domains')

	io.stdout:write('selftest_profile_v2_export: OK\n')
end

main()
