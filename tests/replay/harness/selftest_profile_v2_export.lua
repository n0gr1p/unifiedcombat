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

local function read_file(path)
	local file, err = io.open(path, 'r')
	if not file then
		error('unable to read ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local content = file:read('*a')
	file:close()
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

local function extract_source_block(source, start_marker, end_marker)
	local start_pos = source:find(start_marker, 1, true)
	assert_true(start_pos ~= nil, 'missing source block start: ' .. tostring(start_marker))
	local end_pos = source:find(end_marker, start_pos + #start_marker, true)
	assert_true(end_pos ~= nil, 'missing source block end: ' .. tostring(end_marker))
	return source:sub(start_pos, end_pos - 1)
end

local function assert_non_cor_missing_cor_round_trip(profile_v2, contract, make_fake_fs_fn, flat, profile, main_job, sub_job)
	local case = {
		profile = deep_clone(profile),
		settings = deep_clone(flat),
	}
	case.settings_identity = case.settings
	case.profile.main_job = main_job
	case.profile.sub_job = sub_job
	case.profile.config.maintenance.cor = nil
	assert_nil(case.profile.config.maintenance.cor, tostring(main_job) .. ' structured profile should omit maintenance.cor when it is non-applicable')
	assert_true(contract.validate_structured_profile_config(case.profile).ok == true, tostring(main_job) .. ' structured profile missing maintenance.cor should validate')
	case.path = profile_v2.default_export_path({
		character = 'Redrogue',
		main_job = main_job,
		sub_job = sub_job,
	})
	case.deps, case.state = make_fake_fs_fn({
		[case.path] = profile_v2.serialize_structured_profile(case.profile),
	})
	case.status = profile_v2.inspect_structured_profile_status(case.settings, {
		character = 'Redrogue',
		main_job = main_job,
		sub_job = sub_job,
	}, contract.validate_structured_profile_config, case.deps)
	assert_equal(case.status.state, 'valid_match', tostring(main_job) .. ' structured profile missing maintenance.cor should still match runtime')
	assert_equal(case.status.valid, true, tostring(main_job) .. ' structured profile missing maintenance.cor should validate')
	assert_equal(case.status.diff_count, 0, tostring(main_job) .. ' structured profile missing maintenance.cor should report zero differences')
	assert_equal(case.status.reason, 'runtime matches file', tostring(main_job) .. ' structured profile missing maintenance.cor match reason mismatch')
	assert_equal(case.status.path, case.path, tostring(main_job) .. ' structured profile missing maintenance.cor path mismatch')
	assert_true(case.status.first_difference == nil, tostring(main_job) .. ' structured profile missing maintenance.cor should not expose a first difference')
	assert_true(case.settings == case.settings_identity, tostring(main_job) .. ' structured profile status must preserve settings table identity')
	case.apply_settings = deep_clone(flat)
	case.apply_identity = case.apply_settings
	case.apply = profile_v2.apply_structured_profile_file_to_settings(case.apply_settings, {
		character = 'Redrogue',
		main_job = main_job,
		sub_job = sub_job,
	}, contract.validate_structured_profile_config, case.deps)
	assert_true(case.apply.ok == true, tostring(main_job) .. ' structured profile missing maintenance.cor should apply cleanly')
	assert_equal(case.apply.count, 0, tostring(main_job) .. ' structured profile missing maintenance.cor should report zero differences on apply')
	assert_equal(case.apply.diff_count, 0, tostring(main_job) .. ' structured profile missing maintenance.cor apply diff_count mismatch')
	assert_true(case.apply_settings == case.apply_identity, tostring(main_job) .. ' structured profile missing maintenance.cor apply must preserve settings identity')
	assert_deep_equal(case.apply_settings, flat, tostring(main_job) .. ' structured profile missing maintenance.cor apply should leave matching settings unchanged')
	assert_equal(#case.state.open_calls, 0, tostring(main_job) .. ' structured profile missing maintenance.cor status should not write files')
	assert_equal(#case.state.rename_calls, 0, tostring(main_job) .. ' structured profile missing maintenance.cor status should not rename files')
end

local function assert_non_cor_blank_cor_round_trip(profile_v2, contract, make_fake_fs_fn, flat, profile)
	local blank_cor = deep_clone(profile)
	blank_cor.main_job = 'PLD'
	blank_cor.sub_job = 'RDM'
	blank_cor.config.maintenance.cor = {
		roll_1 = '',
		roll_2 = '',
		crooked_roll_slot = 0,
		elevens = false,
		luzaf_range_override = false,
		range_selected = '',
		range_require_ids = {},
	}
	assert_true(contract.validate_structured_profile_config(blank_cor).ok == true, 'non-COR structured profile with blank maintenance.cor should validate')
	local blank_cor_path = profile_v2.default_export_path({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'RDM',
	})
	local blank_cor_deps = make_fake_fs_fn({
		[blank_cor_path] = profile_v2.serialize_structured_profile(blank_cor),
	})
	local blank_cor_status = profile_v2.inspect_structured_profile_status(deep_clone(flat), {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'RDM',
	}, contract.validate_structured_profile_config, blank_cor_deps)
	assert_equal(blank_cor_status.state, 'valid_match', 'non-COR structured profile with blank maintenance.cor should match runtime')
	assert_equal(blank_cor_status.diff_count, 0, 'non-COR structured profile with blank maintenance.cor should report zero differences')
	assert_equal(blank_cor_status.reason, 'runtime matches file', 'non-COR structured profile with blank maintenance.cor reason mismatch')
	local blank_cor_apply_settings = deep_clone(flat)
	local blank_cor_apply = profile_v2.apply_structured_profile_file_to_settings(blank_cor_apply_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'RDM',
	}, contract.validate_structured_profile_config, blank_cor_deps)
	assert_true(blank_cor_apply.ok == true, 'non-COR structured profile with blank maintenance.cor should apply cleanly')
	assert_equal(blank_cor_apply.diff_count, 0, 'non-COR structured profile with blank maintenance.cor apply diff count mismatch')
end

local function load_profile_v2_apply_from_addon(addon_source, exporter_stub, validator_stub)
	local apply_block = extract_source_block(
		addon_source,
		"local uc_sync_table_in_place\nlocal uc_normalize_settings_table",
		"\n\nlocal function uc_read_profiles_file"
	)
	local normalize_block = extract_source_block(
		addon_source,
		"uc_normalize_settings_table = function(s)",
		"\n\nlocal function uc_normalize_active_settings"
	)
	local chunk_source = table.concat({
		apply_block,
		'',
		normalize_block,
		'',
		'return uc_apply_profile_v2_file',
	}, '\n')
	local env = {
		_G = _G,
		res = {
			jobs = {
				with = function()
					return { english_short = 'PLD' }
				end,
			},
		},
		uc_normalize_abilities = function()
		end,
		uc_normalize_targets = function()
		end,
		uc_normalize_ws_for_engine = function()
		end,
		uc_normalize_sleep_spell_list = function()
		end,
		uc_normalize_domain_settings = function()
		end,
		uc_partner_list = {
			migrate_from_legacy = function()
			end,
			sync_legacy_partner_fields = function()
			end,
		},
		uc_profile_v2 = {
			apply_structured_profile_file_to_settings = exporter_stub,
		},
		uc_active_config = require('uc_active_config'),
		uc_profile_v2_file_path = function()
			return 'data/profiles_v2/test.lua'
		end,
		uc_validate_structured_profile_export = function(payload)
			if type(validator_stub) == 'function' then
				return validator_stub(payload)
			end
			return {
				ok = true,
			}
		end,
		windower = {
			ffxi = {
				get_player = function()
					return { main_job = 'PLD' }
				end,
			},
		},
	}
	setmetatable(env, { __index = _G })
	local chunk, load_err = loadstring(chunk_source, '@selftest_profile_v2_apply_scope.lua')
	assert_true(type(chunk) == 'function', 'unable to load extracted profilev2 apply helper: ' .. tostring(load_err))
	setfenv(chunk, env)
	local apply_fn = chunk()
	assert_true(type(apply_fn) == 'function', 'extracted profilev2 apply helper must be callable')
	return apply_fn
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

local function run_profile_v2_autoload_selftest(profile_v2, active_config, contract, flat, durable_path)
	local previous_start_engine = rawget(_G, 'Start_Engine')
	_G.Start_Engine = false

	local profile_meta = {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		profile_key = 'Redrogue|PLD|WAR',
		exported_at = '2026-06-29T18:00:00Z',
	}

	local disabled_payload = profile_v2.build_structured_profile(flat, profile_meta)
	disabled_payload.config.ownership.profile_v2_autoload = nil
	local disabled_deps, disabled_state = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(disabled_payload),
	})
	local disabled_settings = deep_clone(flat)
	local disabled_snapshot = deep_clone(disabled_settings)
	local disabled_active = active_config.build_active_profile_from_settings(disabled_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	_G.UC_ACTIVE_PROFILE = disabled_active
	local disabled_active_identity = rawget(_G, 'UC_ACTIVE_PROFILE')
	local disabled_active_snapshot = deep_clone(rawget(_G, 'UC_ACTIVE_PROFILE'))
	local disabled_settings_identity = disabled_settings
	local disabled_result = profile_v2.autoload_structured_profile_file_to_settings(
		disabled_settings,
		{
			character = 'Redrogue',
			main_job = 'PLD',
			sub_job = 'WAR',
		},
		contract.validate_structured_profile_config,
		disabled_deps
	)
	assert_true(disabled_result == nil, 'autoload should stay disabled when the flag is missing')
	assert_true(disabled_settings == disabled_settings_identity, 'disabled autoload must preserve settings table identity')
	assert_deep_equal(disabled_settings, disabled_snapshot, 'disabled autoload must not mutate settings')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == disabled_active_identity, 'disabled autoload must not mutate active profile identity')
	assert_deep_equal(rawget(_G, 'UC_ACTIVE_PROFILE'), disabled_active_snapshot, 'disabled autoload must not mutate active profile values')
	assert_equal(#disabled_state.read_calls, 1, 'disabled autoload should only inspect the file')
	assert_equal(#disabled_state.open_calls, 0, 'disabled autoload must not write files')
	assert_true(_G.Start_Engine == false, 'disabled autoload must not start the engine')

	local enabled_payload = profile_v2.build_structured_profile(flat, profile_meta)
	enabled_payload.config.ownership.profile_v2_autoload = true
	local enabled_deps, enabled_state = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(enabled_payload),
	})
	local enabled_settings = deep_clone(flat)
	local enabled_snapshot = deep_clone(enabled_settings)
	local enabled_expected = deep_clone(enabled_snapshot)
	enabled_expected.profile_v2_autoload = true
	local enabled_active = active_config.build_active_profile_from_settings(enabled_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	_G.UC_ACTIVE_PROFILE = enabled_active
	local enabled_active_identity = rawget(_G, 'UC_ACTIVE_PROFILE')
	local enabled_settings_identity = enabled_settings
	local enabled_result = profile_v2.autoload_structured_profile_file_to_settings(
		enabled_settings,
		{
			character = 'Redrogue',
			main_job = 'PLD',
			sub_job = 'WAR',
		},
		contract.validate_structured_profile_config,
		enabled_deps
	)
	assert_true(type(enabled_result) == 'table', 'enabled autoload should return a result')
	assert_true(enabled_result.ok == true, 'enabled autoload should apply successfully')
	assert_true(enabled_result.autoload == true, 'enabled autoload should mark the result as autoload')
	assert_equal(enabled_result.count, 0, 'enabled autoload should report no config differences for matching files')
	assert_true(enabled_settings == enabled_settings_identity, 'enabled autoload must preserve settings table identity')
	assert_deep_equal(enabled_settings, enabled_expected, 'enabled autoload must update settings values in place')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == enabled_active_identity, 'enabled autoload must preserve active profile table identity')
	assert_true(type(enabled_result.active_profile) == 'table', 'enabled autoload must return an active profile')
	assert_true(_G.UC_ACTIVE_PROFILE.config.ownership.profile_v2_autoload == true, 'enabled autoload must update the active profile')
	assert_true(enabled_settings.profile_v2_autoload == true, 'enabled autoload must project the flag into flat settings')
	assert_true(enabled_result.candidate.profile_v2_autoload == true, 'enabled autoload must build a candidate with the flag projected')
	assert_equal(#enabled_state.read_calls, 2, 'enabled autoload should inspect and then apply the file')
	assert_equal(#enabled_state.open_calls, 0, 'enabled autoload must not write files')
	assert_true(_G.Start_Engine == false, 'enabled autoload must not start the engine')

	local invalid_deps, invalid_state = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(enabled_payload),
	})
	local invalid_settings = deep_clone(flat)
	local invalid_snapshot = deep_clone(invalid_settings)
	local invalid_settings_identity = invalid_settings
	local invalid_active = active_config.build_active_profile_from_settings(invalid_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	_G.UC_ACTIVE_PROFILE = invalid_active
	local invalid_active_identity = rawget(_G, 'UC_ACTIVE_PROFILE')
	local invalid_active_snapshot = deep_clone(rawget(_G, 'UC_ACTIVE_PROFILE'))
	local invalid_result = profile_v2.autoload_structured_profile_file_to_settings(
		invalid_settings,
		{
			character = 'Redrogue',
			main_job = 'PLD',
			sub_job = 'WAR',
		},
		function()
			return {
				ok = false,
				errors = { 'forced validation failure' },
			}
		end,
		invalid_deps
	)
	assert_true(type(invalid_result) == 'table', 'invalid autoload should return a failure result')
	assert_true(invalid_result.ok == false, 'invalid autoload should fail cleanly')
	assert_equal(invalid_result.error, 'forced validation failure', 'invalid autoload failure reason mismatch')
	assert_true(invalid_settings == invalid_settings_identity, 'invalid autoload must preserve settings identity')
	assert_deep_equal(invalid_settings, invalid_snapshot, 'invalid autoload must not mutate settings')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == invalid_active_identity, 'invalid autoload must preserve active profile identity')
	assert_deep_equal(rawget(_G, 'UC_ACTIVE_PROFILE'), invalid_active_snapshot, 'invalid autoload must not mutate active profile values')
	assert_equal(#invalid_state.read_calls, 2, 'invalid autoload should inspect and then attempt apply')
	assert_equal(#invalid_state.open_calls, 0, 'invalid autoload must not write files')
	assert_true(_G.Start_Engine == false, 'invalid autoload must not start the engine')

	if previous_start_engine == nil then
		_G.Start_Engine = nil
	else
		_G.Start_Engine = previous_start_engine
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
		defensive_targeted_buffs = 'Terrasjr:Honor March|Nyoourke:Valor Minuet V',
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
		puller = true,
		puller_name = 'Niightsiide',
		wait_ignore_names = { 'Ally One', 'Ally Two' },
		target_ignore_names = { 'Mob One', 'Mob Two' },
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
		profile_v2_autoload = true,
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
				wait_ignore_names = { 'Ally One', 'Ally Two' },
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
				targeted = {
					{ character = 'Terrasjr', buff = 'Honor March' },
					{ character = 'Nyoourke', buff = 'Valor Minuet V' },
				},
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
				puller = true,
				puller_name = 'Niightsiide',
				puller_distance_only = false,
			},
		},
		targeting = {
			add_control = true,
			legacy_slots = {},
			targets = {},
			targetability = {
				enabled = false,
				action = '',
			},
			target_ignore_names = { 'Mob One', 'Mob Two' },
		},
		tank = {
			enabled = true,
			enmity = {
				actions = { 'Provoke', 'Flash' },
			},
		},
		spells = {
			enabled = true,
			configured = 'Dia',
			dd2_slots = {},
		},
		maintenance = {
			enabled = true,
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
			profile_v2_autoload = true,
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
	local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	package.loaded['uc_profile_v2'] = nil
	package.loaded['uc_profile_v2_export'] = nil
	package.loaded['uc_active_config'] = nil
	package.loaded['uc_config_normalizer'] = nil
	package.loaded['uc_profile_contract'] = nil
	local profile_v2 = require('uc_profile_v2')
	local exporter = require('uc_profile_v2_export')
	local active_config = require('uc_active_config')
	local normalizer = require('uc_config_normalizer')
	local contract = require('uc_profile_contract')
	assert_true(type(profile_v2) == 'table', 'neutral profile v2 helper must load')
	assert_true(exporter == profile_v2, 'compatibility shim must return the canonical profile v2 helper module')

	local flat = build_flat_settings()
	local flat_snapshot = deep_clone(flat)
	local profile = profile_v2.build_structured_profile(flat, {
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
	assert_equal(profile.config.combat.weaponskill.primary, 'Savage Blade', 'combat domain mismatch')
	assert_true(profile.config.maintenance.cor == nil, 'non-COR structured profile must omit maintenance.cor')
	assert_equal(profile.config.legacy.hunter, true, 'legacy domain mismatch')
	assert_true(profile.config.targeting.add_priority_names == nil, 'exported config must not include durable add priority names')
	assert_true(profile.config.command == nil, 'exported config must not include engine runtime state')
	assert_true(profile.config.sleep == nil, 'exported config must not include sleep domain')
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
	assert_equal(normalized.maintenance.cor.roll_2, '', 'round-tripped normalized non-COR maintenance mismatch')
	assert_equal(normalized.legacy.hunter, true, 'round-tripped normalized legacy mismatch')

	local cor_roundtrip = {
		profile = profile_v2.build_structured_profile(flat, {
			character = 'Redrogue',
			main_job = 'COR',
			sub_job = 'WAR',
			profile_key = 'Redrogue|COR|WAR',
			exported_at = '2026-06-29T18:00:00Z',
		}),
	}
	assert_equal(cor_roundtrip.profile.config.maintenance.cor.roll_1, 'Chaos Roll', 'COR structured profile maintenance mismatch')
	assert_equal(cor_roundtrip.profile.config.maintenance.cor.roll_2, 'Samurai Roll', 'COR structured profile maintenance mismatch')
	cor_roundtrip.serialized = exporter.serialize_structured_profile(cor_roundtrip.profile)
	cor_roundtrip.chunk, cor_roundtrip.load_err = loadstring(cor_roundtrip.serialized)
	assert_true(type(cor_roundtrip.chunk) == 'function', 'serialized COR structured profile must load as Lua: ' .. tostring(cor_roundtrip.load_err))
	cor_roundtrip.ok_load, cor_roundtrip.loaded = pcall(cor_roundtrip.chunk)
	assert_true(cor_roundtrip.ok_load == true, 'serialized COR structured profile chunk should execute')
	assert_true(type(cor_roundtrip.loaded) == 'table', 'serialized COR structured profile must return a table')
	assert_deep_equal(cor_roundtrip.loaded, cor_roundtrip.profile, 'serialized COR structured profile should round-trip cleanly')

	local defaults = exporter.build_structured_profile(nil, nil)
	assert_equal(defaults.profile.character, 'unknown', 'nil settings character default mismatch')
	assert_equal(defaults.profile.main_job, 'UNKNOWN', 'nil settings main job default mismatch')
	assert_equal(defaults.profile.sub_job, 'UNKNOWN', 'nil settings sub job default mismatch')
	assert_equal(defaults.profile.source, 'exported_from_v1_settings', 'nil settings source default mismatch')
	assert_equal(defaults.config.combat.enabled, true, 'nil settings combat default mismatch')
	assert_equal(defaults.config.debug.enabled, false, 'nil settings debug default mismatch')

	local path = profile_v2.default_export_path({
		character = ' Red Rogue! ',
		main_job = 'pld',
		sub_job = 'war',
	})
	assert_equal(path, 'data/profiles_v2/red_rogue_PLD_WAR.lua', 'export path mismatch')
	assert_equal(profile_v2.default_export_path(nil), 'data/profiles_v2/unknown_UNKNOWN_UNKNOWN.lua', 'nil export path mismatch')
	local addon_local_path = profile_v2.default_export_path({
		character = ' Red Rogue! ',
		main_job = 'pld',
		sub_job = 'war',
		addon_path = 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\',
	})
	assert_equal(addon_local_path, 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\data\\profiles_v2\\red_rogue_PLD_WAR.lua', 'addon-local export path mismatch')
	local durable_path = profile_v2.default_export_path({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	})

	local expected_serialized = profile_v2.serialize_structured_profile(profile)
	local ui_fixture_path = 'tests/replay/fixtures/shared/ui_authored_profile_v2_fixture.lua'
	local ui_fixture_content = read_file(ui_fixture_path)
	local ui_fixture_payload = load_lua_fixture(ui_fixture_path)
	assert_equal(ui_fixture_payload.profile.source, 'ui', 'UI-authored fixture source metadata mismatch')
	assert_nil(ui_fixture_payload.profile.exported_at, 'UI-authored fixture should omit exported_at metadata')
	assert_nil(ui_fixture_payload.profile.profile_key, 'UI-authored fixture should omit profile_key metadata')
	assert_equal(ui_fixture_payload.config.combat.weaponskill.wait_ignore_names[1], 'Ally One', 'UI-authored fixture wait ignore name mismatch')
	assert_equal(ui_fixture_payload.config.follow.partner.puller_name, 'Niightsiide', 'UI-authored fixture puller name mismatch')
	assert_equal(ui_fixture_payload.config.targeting.target_ignore_names[1], 'Mob One', 'UI-authored fixture target ignore name mismatch')
	local durable_deps, durable_state = make_fake_fs()
	local durable_result = profile_v2.write_structured_profile_export(profile, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, durable_deps)
	assert_true(durable_result.ok == true, 'durable export helper should report success')
	assert_equal(durable_result.path, durable_path, 'durable export helper path mismatch')
	assert_equal(durable_state.files[durable_path], expected_serialized, 'durable export helper should write serialized profile content')
	assert_nil(durable_state.files[durable_path .. '.tmp'], 'temp file should not remain after successful promote')
	assert_nil(durable_state.files[durable_path .. '.bak'], 'backup file should not remain after successful promote')

	local created_dir_path = profile_v2.default_export_path({
		character = 'Created',
		main_job = 'BRD',
		sub_job = 'WHM',
	})
	local create_dir_deps, create_dir_state = make_fake_fs(nil, nil, {})
	local create_dir_result = profile_v2.write_structured_profile_export(profile, {
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

	local ui_fixture_validate_result = exporter.validate_structured_profile_file({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({
		[durable_path] = ui_fixture_content,
	}))
	assert_true(ui_fixture_validate_result.ok == true, 'UI-authored structured profile fixture should validate successfully')
	assert_equal(ui_fixture_validate_result.payload.profile.source, 'ui', 'UI-authored structured profile validation must preserve source metadata')
	assert_nil(ui_fixture_validate_result.payload.profile.exported_at, 'UI-authored structured profile validation must not require exported_at metadata')
	assert_nil(ui_fixture_validate_result.payload.profile.profile_key, 'UI-authored structured profile validation must not require profile_key metadata')

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
	assert_equal(validate_read_fail_result.error, 'missing', 'structured profile read failure error mismatch')

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
	assert_equal(diff_ok_result.diff_count, 0, 'structured profile diff diff_count mismatch for matching config')
	assert_true(diff_ok_result.first_difference == nil, 'structured profile diff first difference should be nil for matching config')
	assert_equal(#diff_ok_result.differences, 0, 'structured profile diff details should be empty for matching config')

	local ui_fixture_match_flat = deep_clone(flat)
	ui_fixture_match_flat.puller = true
	ui_fixture_match_flat.puller_name = 'Niightsiide'
	local ui_fixture_diff_ok_result = exporter.diff_structured_profile_file_against_settings(ui_fixture_match_flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({
		[durable_path] = ui_fixture_content,
	}))
	assert_true(ui_fixture_diff_ok_result.ok == true, 'UI-authored structured profile fixture should diff successfully against matching runtime settings')
	assert_equal(ui_fixture_diff_ok_result.count, 0, 'UI-authored structured profile fixture should report zero differences for matching runtime settings')
	assert_equal(ui_fixture_diff_ok_result.payload.profile.source, 'ui', 'UI-authored structured profile diff must preserve source metadata')

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
	assert_equal(scalar_diff_result.diff_count, 1, 'structured profile diff diff_count mismatch for scalar difference payload')
	assert_equal(scalar_diff_result.differences[1], 'config.combat.face', 'structured profile diff scalar path mismatch')
	assert_true(type(scalar_diff_result.first_difference) == 'table', 'structured profile diff scalar first difference should be structured')
	assert_equal(scalar_diff_result.first_difference.path, 'config.combat.face', 'structured profile diff scalar first difference path mismatch')
	assert_equal(scalar_diff_result.first_difference.file_value, false, 'structured profile diff scalar file-side value mismatch')
	assert_equal(scalar_diff_result.first_difference.runtime_value, true, 'structured profile diff scalar runtime-side value mismatch')
	assert_equal(scalar_diff_result.first_difference.file_type, 'boolean', 'structured profile diff scalar file-side type mismatch')
	assert_equal(scalar_diff_result.first_difference.runtime_type, 'boolean', 'structured profile diff scalar runtime-side type mismatch')

	local ui_fixture_diff_settings = deep_clone(flat)
	ui_fixture_diff_settings.puller = true
	ui_fixture_diff_settings.puller_name = 'Niightsiide'
	ui_fixture_diff_settings.face = false
	local ui_fixture_diff_snapshot = deep_clone(ui_fixture_diff_settings)
	local ui_fixture_scalar_diff_result = exporter.diff_structured_profile_file_against_settings(ui_fixture_diff_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({
		[durable_path] = ui_fixture_content,
	}))
	assert_true(ui_fixture_scalar_diff_result.ok == true, 'UI-authored structured profile fixture should diff successfully against mismatching runtime settings')
	assert_equal(ui_fixture_scalar_diff_result.count, 1, 'UI-authored structured profile fixture should report one deterministic difference')
	assert_equal(ui_fixture_scalar_diff_result.diff_count, 1, 'UI-authored structured profile fixture diff_count mismatch')
	assert_equal(ui_fixture_scalar_diff_result.differences[1], 'config.combat.face', 'UI-authored structured profile fixture diff path mismatch')
	assert_true(type(ui_fixture_scalar_diff_result.first_difference) == 'table', 'UI-authored structured profile fixture first difference should be structured')
	assert_equal(ui_fixture_scalar_diff_result.first_difference.path, 'config.combat.face', 'UI-authored structured profile fixture first difference path mismatch')
	assert_equal(ui_fixture_scalar_diff_result.first_difference.file_value, true, 'UI-authored structured profile fixture file-side value mismatch')
	assert_equal(ui_fixture_scalar_diff_result.first_difference.runtime_value, false, 'UI-authored structured profile fixture runtime-side value mismatch')
	assert_deep_equal(ui_fixture_diff_settings, ui_fixture_diff_snapshot, 'UI-authored structured profile diff must not mutate runtime settings')

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
	assert_equal(nested_diff_result.diff_count, 1, 'structured profile diff nested diff_count mismatch')
	assert_equal(nested_diff_result.differences[1], 'config.movement.spacing.band_max', 'structured profile diff nested path mismatch')
	assert_true(type(nested_diff_result.first_difference) == 'table', 'structured profile diff nested first difference should be structured')
	assert_equal(nested_diff_result.first_difference.path, 'config.movement.spacing.band_max', 'structured profile diff nested first difference path mismatch')

	local missing_key_payload = deep_clone(profile)
	missing_key_payload.config.targeting.targets = nil
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
	assert_equal(missing_key_result.differences[1], 'config.targeting.targets', 'structured profile diff missing key path mismatch')

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

	local status_read_fail_snapshot = deep_clone(flat)
	local status_read_fail_result = exporter.inspect_structured_profile_file_against_settings(status_read_fail_snapshot, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({
	}, {
		read = {
			[durable_path] = 'missing',
		},
	}))
	assert_true(status_read_fail_result.ok == false, 'structured profile status should fail cleanly when the file cannot be read')
	assert_equal(status_read_fail_result.stage, 'read', 'structured profile status read failure stage mismatch')
	assert_equal(status_read_fail_result.error, 'missing', 'structured profile status read failure error mismatch')
	assert_deep_equal(status_read_fail_snapshot, flat, 'structured profile status read failure must not mutate settings')

	local status_invalid_snapshot = deep_clone(flat)
	local status_invalid_result = exporter.inspect_structured_profile_file_against_settings(status_invalid_snapshot, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_bad_version_deps)
	assert_true(status_invalid_result.ok == false, 'structured profile status should fail cleanly on invalid file content')
	assert_equal(status_invalid_result.stage, 'shape', 'structured profile status invalid-file stage mismatch')
	assert_equal(status_invalid_result.error, 'structured profile version must be 2', 'structured profile status invalid-file error mismatch')
	assert_deep_equal(status_invalid_snapshot, flat, 'structured profile status invalid-file failure must not mutate settings')

	local status_match_settings = deep_clone(flat)
	local status_match_snapshot = deep_clone(status_match_settings)
	local status_match_deps = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local status_match_result = exporter.inspect_structured_profile_file_against_settings(status_match_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, status_match_deps)
	assert_true(status_match_result.ok == true, 'structured profile status should succeed for matching config')
	assert_equal(status_match_result.count, 0, 'structured profile status should report zero differences for matching config')
	assert_deep_equal(status_match_settings, status_match_snapshot, 'structured profile status matching config must not mutate settings')

	local ui_fixture_status_settings = deep_clone(flat)
	local ui_fixture_status_snapshot = deep_clone(ui_fixture_status_settings)
	local ui_fixture_status_result = exporter.inspect_structured_profile_file_against_settings(ui_fixture_status_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({
		[durable_path] = ui_fixture_content,
	}))
	assert_true(ui_fixture_status_result.ok == true, 'UI-authored structured profile fixture should be inspectable by the status helper')
	assert_equal(ui_fixture_status_result.count, 0, 'UI-authored structured profile fixture status should report zero differences for matching runtime settings')
	assert_equal(ui_fixture_status_result.payload.profile.source, 'ui', 'UI-authored structured profile status must preserve source metadata')
	assert_deep_equal(ui_fixture_status_settings, ui_fixture_status_snapshot, 'UI-authored structured profile status must not mutate runtime settings')

	local status_diff_payload = deep_clone(profile)
	status_diff_payload.config.combat.face = false
	local status_diff_settings = deep_clone(flat)
	local status_diff_snapshot = deep_clone(status_diff_settings)
	local status_diff_deps = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(status_diff_payload),
	})
	local status_diff_result = exporter.inspect_structured_profile_file_against_settings(status_diff_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, status_diff_deps)
	assert_true(status_diff_result.ok == true, 'structured profile status should succeed for diffable valid config')
	assert_equal(status_diff_result.count, 1, 'structured profile status should report one config difference')
	assert_deep_equal(status_diff_settings, status_diff_snapshot, 'structured profile status diff inspection must not mutate settings')

	local v2_status_missing = profile_v2.inspect_structured_profile_status(status_diff_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({}))
	assert_equal(v2_status_missing.state, 'missing', 'structured profile v2 status missing state mismatch')
	assert_equal(v2_status_missing.valid, false, 'structured profile v2 status missing validity mismatch')
	assert_equal(v2_status_missing.diff_count, 0, 'structured profile v2 status missing diff count mismatch')
	assert_equal(v2_status_missing.reason, 'missing file', 'structured profile v2 status missing reason mismatch')
	assert_equal(v2_status_missing.path, durable_path, 'structured profile v2 status missing path mismatch')

	local v2_status_invalid = profile_v2.inspect_structured_profile_status(status_diff_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, validate_bad_version_deps)
	assert_equal(v2_status_invalid.state, 'invalid', 'structured profile v2 status invalid state mismatch')
	assert_equal(v2_status_invalid.valid, false, 'structured profile v2 status invalid validity mismatch')
	assert_equal(v2_status_invalid.diff_count, 0, 'structured profile v2 status invalid diff count mismatch')
	assert_equal(v2_status_invalid.reason, 'structured profile version must be 2', 'structured profile v2 status invalid reason mismatch')
	assert_equal(v2_status_invalid.path, durable_path, 'structured profile v2 status invalid path mismatch')

	local v2_status_match_settings = deep_clone(flat)
	local v2_status_match_snapshot = deep_clone(v2_status_match_settings)
	local v2_status_match_deps, v2_status_match_state = make_fake_fs({
		[durable_path] = expected_serialized,
	})
	local v2_status_match = profile_v2.inspect_structured_profile_status(v2_status_match_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, v2_status_match_deps)
	assert_equal(v2_status_match.state, 'valid_match', 'structured profile v2 status matching state mismatch')
	assert_equal(v2_status_match.valid, true, 'structured profile v2 status matching validity mismatch')
	assert_equal(v2_status_match.diff_count, 0, 'structured profile v2 status matching diff count mismatch')
	assert_equal(v2_status_match.reason, 'runtime matches file', 'structured profile v2 status matching reason mismatch')
	assert_equal(v2_status_match.path, durable_path, 'structured profile v2 status matching path mismatch')
	assert_equal(v2_status_match.character, 'Redrogue', 'structured profile v2 status matching character mismatch')
	assert_equal(v2_status_match.main_job, 'PLD', 'structured profile v2 status matching main job mismatch')
	assert_equal(v2_status_match.sub_job, 'WAR', 'structured profile v2 status matching sub job mismatch')
	assert_deep_equal(v2_status_match_settings, v2_status_match_snapshot, 'structured profile v2 status matching must not mutate settings')
	assert_equal(#v2_status_match_state.rename_calls, 0, 'structured profile v2 status must not write to disk')
	assert_equal(#v2_status_match_state.create_dir_calls, 0, 'structured profile v2 status must not create directories')

	local v2_status_diff_settings = deep_clone(flat)
	local v2_status_diff_snapshot = deep_clone(v2_status_diff_settings)
	local v2_status_diff_payload = deep_clone(profile)
	v2_status_diff_payload.config.combat.face = false
	local v2_status_diff_deps = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(v2_status_diff_payload),
	})
	local v2_status_diff = profile_v2.inspect_structured_profile_status(v2_status_diff_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, v2_status_diff_deps)
	assert_equal(v2_status_diff.state, 'valid_diff', 'structured profile v2 status differing state mismatch')
	assert_equal(v2_status_diff.valid, true, 'structured profile v2 status differing validity mismatch')
	assert_equal(v2_status_diff.diff_count, 1, 'structured profile v2 status differing diff count mismatch')
	assert_equal(v2_status_diff.reason, 'runtime differs from file', 'structured profile v2 status differing reason mismatch')
	assert_equal(v2_status_diff.path, durable_path, 'structured profile v2 status differing path mismatch')
	assert_true(type(v2_status_diff.first_difference) == 'table', 'structured profile v2 status differing should expose first difference detail')
	assert_equal(v2_status_diff.first_difference.path, 'config.combat.face', 'structured profile v2 status differing first difference path mismatch')
	assert_equal(v2_status_diff.first_difference.file_value, false, 'structured profile v2 status differing file-side value mismatch')
	assert_equal(v2_status_diff.first_difference.runtime_value, true, 'structured profile v2 status differing runtime-side value mismatch')
	assert_equal(v2_status_diff.first_difference.file_type, 'boolean', 'structured profile v2 status differing file-side type mismatch')
	assert_equal(v2_status_diff.first_difference.runtime_type, 'boolean', 'structured profile v2 status differing runtime-side type mismatch')
	assert_equal(v2_status_diff.diff_details[1].path, 'config.combat.face', 'structured profile v2 status differing diff details path mismatch')
	local v2_status_diff_lines, v2_status_diff_lines_err = profile_v2.format_structured_profile_diff_detail_lines(v2_status_diff, 2)
	assert_true(type(v2_status_diff_lines) == 'table', 'structured profile v2 status differing should format diff detail lines')
	assert_nil(v2_status_diff_lines_err, 'structured profile v2 status differing should not error when formatting diff detail lines')
	assert_equal(v2_status_diff_lines[1], 'UC profile v2 diff detail: 1 config differences', 'structured profile v2 status differing diff detail header mismatch')
	assert_contains(v2_status_diff_lines[2], 'config.combat.face: file=false [boolean] runtime=true [boolean]', 'structured profile v2 status differing diff detail line mismatch')
	assert_deep_equal(v2_status_diff_settings, v2_status_diff_snapshot, 'structured profile v2 status differing must not mutate settings')

	local v2_fixture_status_settings = deep_clone(flat)
	local v2_fixture_status_snapshot = deep_clone(v2_fixture_status_settings)
	local v2_fixture_status = profile_v2.inspect_structured_profile_status(v2_fixture_status_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, make_fake_fs({
		[durable_path] = ui_fixture_content,
	}))
	assert_equal(v2_fixture_status.state, 'valid_match', 'UI-authored structured profile status state mismatch')
	assert_equal(v2_fixture_status.valid, true, 'UI-authored structured profile status validity mismatch')
	assert_equal(v2_fixture_status.diff_count, 0, 'UI-authored structured profile status diff count mismatch')
	assert_equal(v2_fixture_status.reason, 'runtime matches file', 'UI-authored structured profile status reason mismatch')
	assert_equal(v2_fixture_status.path, durable_path, 'UI-authored structured profile status path mismatch')
	assert_equal(v2_fixture_status.source, 'ui', 'UI-authored structured profile status source mismatch')
	assert_equal(v2_fixture_status.character, 'Redrogue', 'UI-authored structured profile status character mismatch')
	assert_equal(v2_fixture_status.main_job, 'PLD', 'UI-authored structured profile status main job mismatch')
	assert_equal(v2_fixture_status.sub_job, 'WAR', 'UI-authored structured profile status sub job mismatch')
	assert_deep_equal(v2_fixture_status_settings, v2_fixture_status_snapshot, 'UI-authored structured profile status must not mutate settings')
	assert_non_cor_missing_cor_round_trip(profile_v2, contract, make_fake_fs, flat, profile, 'BRD', 'WHM')
	assert_non_cor_missing_cor_round_trip(profile_v2, contract, make_fake_fs, flat, profile, 'PLD', 'RDM')
	assert_non_cor_missing_cor_round_trip(profile_v2, contract, make_fake_fs, flat, profile, 'SAM', 'DRG')
	assert_non_cor_missing_cor_round_trip(profile_v2, contract, make_fake_fs, flat, profile, 'GEO', 'WHM')
	assert_non_cor_blank_cor_round_trip(profile_v2, contract, make_fake_fs, flat, profile)

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

	local legacy_mirror_current = deep_clone(profile.config)
	legacy_mirror_current.abilities.legacy_slots = { 'Hagakure', 'Meditate' }
	legacy_mirror_current.follow.party.leader_id = 1234
	legacy_mirror_current.follow.fight.leader_id = 5678
	legacy_mirror_current.targeting.legacy_slots = { 'apex bats' }
	local legacy_mirror_diff = profile_v2.diff_durable_config(legacy_mirror_current, profile.config)
	assert_equal(legacy_mirror_diff.count, 0, 'durable diff should ignore legacy ability, follow id, and targeting slot mirrors')

	local runtime_engine_current = deep_clone(profile.config)
	local runtime_engine_target = deep_clone(profile.config)
	runtime_engine_current.command = { engine_enabled_default = false }
	runtime_engine_target.command = { engine_enabled_default = true }
	local runtime_engine_diff = profile_v2.diff_durable_config(runtime_engine_current, runtime_engine_target)
	assert_equal(runtime_engine_diff.count, 0, 'durable diff should ignore engine runtime mirrors')

	local path_file_runtime_current = deep_clone(ui_fixture_payload.config)
	local path_file_runtime_target = deep_clone(ui_fixture_payload.config)
	path_file_runtime_current.movement.path.file_name = 'runtime-selected-route.lua'
	path_file_runtime_target.movement.path.file_name = ''
	local path_file_runtime_diff = profile_v2.diff_durable_config(path_file_runtime_current, path_file_runtime_target)
	assert_equal(path_file_runtime_diff.count, 0, 'durable diff should ignore movement path filename runtime mirrors')

	local path_gate_current = deep_clone(ui_fixture_payload.config)
	local path_gate_target = deep_clone(ui_fixture_payload.config)
	path_gate_target.movement.path.party_gate_yalms = path_gate_target.movement.path.party_gate_yalms + 1
	local path_gate_diff = profile_v2.diff_durable_config(path_gate_current, path_gate_target)
	assert_equal(path_gate_diff.count, 1, 'durable diff should still detect durable movement path changes')
	assert_equal(path_gate_diff.first_difference.path, 'config.movement.path.party_gate_yalms', 'durable diff should report the durable movement path field path')

	local ui_fixture_reload_settings = deep_clone(flat)
	ui_fixture_reload_settings.face = false
	local ui_fixture_reload_identity = ui_fixture_reload_settings
	local ui_fixture_reload_deps, ui_fixture_reload_state = make_fake_fs({
		[durable_path] = ui_fixture_content,
	})
	local ui_fixture_reload_result = exporter.apply_structured_profile_file_to_settings(ui_fixture_reload_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, ui_fixture_reload_deps)
	assert_true(ui_fixture_reload_result.ok == true, 'UI-authored structured profile fixture should be consumable by the reload/apply helper')
	assert_equal(ui_fixture_reload_result.count, 1, 'UI-authored structured profile reload/apply helper should report one config difference')
	assert_equal(ui_fixture_reload_result.diff_count, 1, 'UI-authored structured profile reload/apply helper diff_count mismatch')
	assert_true(ui_fixture_reload_settings == ui_fixture_reload_identity, 'UI-authored structured profile reload/apply helper must preserve settings table identity')
	assert_true(ui_fixture_reload_result.candidate.face, 'UI-authored structured profile reload/apply helper should restore runtime values without addon-export metadata')
	assert_equal(ui_fixture_reload_result.payload.profile.source, 'ui', 'UI-authored structured profile reload/apply helper must preserve source metadata')
	assert_nil(ui_fixture_reload_result.payload.profile.exported_at, 'UI-authored structured profile reload/apply helper must not require exported_at metadata')
	assert_nil(ui_fixture_reload_result.payload.profile.profile_key, 'UI-authored structured profile reload/apply helper must not require profile_key metadata')
	assert_true(type(ui_fixture_reload_result.first_difference) == 'table', 'UI-authored structured profile reload/apply helper should expose first difference detail')
	assert_equal(ui_fixture_reload_result.first_difference.path, 'config.combat.face', 'UI-authored structured profile reload/apply helper first difference path mismatch')
	assert_equal(ui_fixture_reload_result.first_difference.file_value, true, 'UI-authored structured profile reload/apply helper file-side value mismatch')
	assert_equal(ui_fixture_reload_result.first_difference.runtime_value, false, 'UI-authored structured profile reload/apply helper runtime-side value mismatch')
	assert_equal(ui_fixture_reload_result.first_difference.file_type, 'boolean', 'UI-authored structured profile reload/apply helper file-side type mismatch')
	assert_equal(ui_fixture_reload_result.first_difference.runtime_type, 'boolean', 'UI-authored structured profile reload/apply helper runtime-side type mismatch')
	assert_equal(ui_fixture_reload_result.details[1].path, 'config.combat.face', 'UI-authored structured profile reload/apply helper diff details path mismatch')
	local ui_fixture_reload_lines, ui_fixture_reload_lines_err = profile_v2.format_structured_profile_diff_detail_lines(ui_fixture_reload_result, 3)
	assert_true(type(ui_fixture_reload_lines) == 'table', 'UI-authored structured profile reload/apply helper should format diff detail lines')
	assert_nil(ui_fixture_reload_lines_err, 'UI-authored structured profile reload/apply helper should not error when formatting diff detail lines')
	assert_equal(ui_fixture_reload_lines[1], 'UC profile v2 diff detail: 1 config differences', 'UI-authored structured profile reload/apply helper diff detail header mismatch')
	assert_contains(ui_fixture_reload_lines[2], 'config.combat.face: file=true [boolean] runtime=false [boolean]', 'UI-authored structured profile reload/apply helper diff detail line mismatch')
	assert_equal(#ui_fixture_reload_state.open_calls, 0, 'UI-authored structured profile reload/apply helper should not write files')
	assert_equal(#ui_fixture_reload_state.rename_calls, 0, 'UI-authored structured profile reload/apply helper should not rename files')

	local scalar_apply_payload = deep_clone(profile)
	scalar_apply_payload.config.combat.face = false
	local scalar_apply_deps, scalar_apply_state = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(scalar_apply_payload),
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
		[durable_path] = profile_v2.serialize_structured_profile(nested_apply_payload),
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
		[durable_path] = profile_v2.serialize_structured_profile(metadata_apply_payload),
	})
	local metadata_apply_settings = deep_clone(flat)
	local metadata_apply_result = exporter.apply_structured_profile_file_to_settings(metadata_apply_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, contract.validate_structured_profile_config, metadata_apply_deps)
	assert_true(metadata_apply_result.ok == true, 'structured profile apply should succeed for metadata-only differences')
	assert_equal(metadata_apply_result.count, 0, 'structured profile apply should ignore profile metadata differences')
	assert_equal(profile_v2.diff_durable_config(profile_v2.build_durable_config(metadata_apply_result.candidate, {
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

	local addon = read_file('UnifiedCombat.lua')
	assert_contains(addon, "elseif a == 'profilev2' then", 'addon must route profilev2 command')
	assert_contains(addon, "//uc profilev2 export", 'addon must advertise profilev2 export help')
	assert_contains(addon, "//uc profilev2 validate", 'addon must advertise profilev2 validate help')
	assert_contains(addon, "//uc profilev2 diff", 'addon must advertise profilev2 diff help')
	assert_contains(addon, "//uc profilev2 diff detail", 'addon must advertise profilev2 diff detail help')
	assert_contains(addon, "//uc profilev2 status", 'addon must advertise profilev2 status help')
	assert_contains(addon, "//uc profilev2 apply", 'addon must advertise profilev2 apply help')
	assert_contains(addon, "//uc profilev2 reload", 'addon must advertise profilev2 reload help')
	assert_contains(addon, "local uc_profile_v2 = require('uc_profile_v2')", 'addon must require the canonical profile v2 helper')
	assert_contains(addon, "local uc_active_config = require('uc_active_config')", 'addon must require the active config helper')
	assert_contains(addon, "uc_profile_v2.write_structured_profile_export(profile, meta)", 'addon must use structured profile export helper')
	assert_contains(addon, "uc_profile_v2.validate_structured_profile_file(meta, function(payload)", 'addon must use structured profile validate helper')
	assert_contains(addon, "uc_profile_v2.diff_structured_profile_file_against_settings(settings, meta, function(payload)", 'addon must use structured profile diff helper')
	assert_contains(addon, "uc_profile_v2.format_structured_profile_diff_detail_lines(diff_result, 5)", 'addon must format structured diff detail lines')
	assert_contains(addon, "uc_profile_v2.inspect_structured_profile_file_against_settings(settings, meta, function(payload)", 'addon must use structured profile status helper')
	assert_contains(addon, "uc_update_profile_v2_contract_status(context)", 'addon must build profile v2 status snapshots')
	assert_contains(addon, "profile_v2 = uc_update_profile_v2_contract_status(context)", 'addon config status snapshot must include profile v2 status')
	assert_contains(addon, "uc_profile_v2.apply_structured_profile_file_to_settings(settings, meta, function(payload)", 'addon must use structured profile apply helper')
	assert_contains(addon, "uc_active_config.set_active_profile(result.active_profile)", 'addon apply path must publish the active profile')
	assert_contains(addon, "uc_active_config.sync_flat_settings_in_place(settings, result.candidate)", 'addon apply path must project into flat settings through active config')
	assert_contains(addon, "UC profile v2 status: valid, runtime matches file", 'addon must report matching status tersely')
	assert_contains(addon, "UC profile v2 status: valid, ", 'addon must report differing status tersely')
	assert_contains(addon, "UC profile v2 status: invalid: ", 'addon must report invalid status tersely')
	assert_contains(addon, "UC profile v2 reload failed: ", 'addon must report reload failures tersely')
	assert_contains(addon, "UC profile v2 reload: no config differences", 'addon must report no-diff reload tersely')
	assert_contains(addon, "UC profile v2 reload: ", 'addon must report applied reload tersely')
	assert_contains(addon, "UC profile v2 autoload warning: ", 'addon must report post-apply autoload diff warnings tersely')
	assert_contains(addon, "UC profile v2 autoload: applied", 'addon must report autoload success tersely')
	assert_contains(addon, "UC profile v2 autoload: no config differences", 'addon must report no-diff autoload tersely')
	assert_contains(addon, "UC profile v2 autoload failed: ", 'addon must report autoload failures tersely')
	assert_contains(addon, "local uc_profile_v2_autoload_pending_key = nil", 'addon must track pending profilev2 autoload sessions')
	assert_contains(addon, "local function uc_queue_profile_v2_autoload()", 'addon must queue profilev2 autoload after startup hooks')
	assert_contains(addon, "local function uc_run_queued_profile_v2_autoload()", 'addon must run queued profilev2 autoload once per session')
	assert_contains(addon, "uc_queue_profile_v2_autoload()", 'addon must queue profilev2 autoload from startup hooks')
	assert_contains(addon, "uc_run_queued_profile_v2_autoload()", 'addon must run queued profilev2 autoload from prerender')
	assert_contains(addon, "uc_profile_v2.validate_structured_profile_file(meta, function(payload)", 'addon autoload must validate the structured file before applying')
	assert_contains(addon, "uc_apply_profile_v2_file(", 'addon autoload must use the shared apply path')
	assert_contains(addon, "local detail_mode = args[3] and tostring(args[3]):lower() == 'detail'", 'addon must recognize the diff detail command')
	assert_contains(addon, "local ok_reload, _, reload_err, reload_count = uc_apply_profile_v2_file(", 'addon reload command must use the shared apply path')
	assert_contains(addon, "local uc_sync_table_in_place", 'addon apply helper must keep sync helper scoped locally')
	assert_contains(addon, "local uc_normalize_settings_table", 'addon apply helper must keep normalize helper scoped locally')
	assert_contains(addon, "uc_sync_table_in_place = function(dst, src)", 'addon apply helper must bind sync helper before use')
	assert_contains(addon, "uc_normalize_settings_table = function(s)", 'addon apply helper must bind normalize helper before use')
	assert_contains(addon, "UC profile v2 export failed: ", 'addon export failure chat must include reason')
	assert_contains(addon, "addon_path = uc_addon_path()", 'addon must resolve v2 profile files under the addon path')
	assert_not_contains(addon, 'UC profile v2 apply: ' .. "profile saved", 'structured profile apply path must not report v1 save behavior')
	assert_not_contains(addon, 'windower.add_to_chat(207, uc_profile_v2.serialize_structured_profile', 'addon must not dump structured profile contents to chat')

	local previous_global_uc_normalize_settings_table = rawget(_G, 'UC_normalize_settings_table')
	local previous_global_uc_normalize_settings_table_lower = rawget(_G, 'uc_normalize_settings_table')
	local previous_global_uc_sync_table_in_place = rawget(_G, 'uc_sync_table_in_place')
	_G.UC_normalize_settings_table = nil
	_G.uc_normalize_settings_table = nil
	_G.uc_sync_table_in_place = nil

	local live_apply_payload = deep_clone(profile)
	live_apply_payload.config.combat.face = false
	live_apply_payload.config.follow.partner.ids = { 99, 100 }
	local live_apply_deps = make_fake_fs({
		[durable_path] = profile_v2.serialize_structured_profile(live_apply_payload),
	})
	local live_apply_active_seed = active_config.build_active_profile_from_settings(flat, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	local live_apply = load_profile_v2_apply_from_addon(
		addon,
		function(settings, meta, validator)
			return profile_v2.apply_structured_profile_file_to_settings(settings, meta, validator, live_apply_deps)
		end,
		contract.validate_structured_profile_config
	)
	local live_apply_settings = deep_clone(flat)
	local live_apply_identity = live_apply_settings
	_G.UC_ACTIVE_PROFILE = live_apply_active_seed
	local live_apply_active_identity = rawget(_G, 'UC_ACTIVE_PROFILE')
	local ok_live_apply, live_apply_path, live_apply_err, live_apply_count = live_apply({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, live_apply_settings)
	assert_true(ok_live_apply == true, 'live profilev2 apply should succeed without global normalizer helpers')
	assert_equal(live_apply_path, durable_path, 'live profilev2 apply path mismatch')
	assert_nil(live_apply_err, 'live profilev2 apply should not report an error')
	assert_true(type(live_apply_count) == 'number' and live_apply_count > 0, 'live profilev2 apply should report applied differences')
	assert_true(live_apply_settings == live_apply_identity, 'live profilev2 apply must preserve settings table identity')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE') == live_apply_active_identity, 'live profilev2 apply must preserve active profile table identity')
	assert_equal(_G.UC_ACTIVE_PROFILE.profile.source, live_apply_payload.profile.source, 'live profilev2 apply must preserve profile source metadata')
	assert_false(live_apply_settings.face, 'live profilev2 apply should update runtime scalar values')
	assert_equal(live_apply_settings.partner_ids[1], 99, 'live profilev2 apply should update partner id list')
	assert_equal(live_apply_settings.partner_id, 99, 'live profilev2 apply should sync primary partner legacy field')
	assert_equal(live_apply_settings.partner_id2, 100, 'live profilev2 apply should sync secondary partner legacy field')

	local live_validation_failure_apply = load_profile_v2_apply_from_addon(addon, function()
		return {
			ok = false,
			path = durable_path,
			error = 'missing config',
		}
	end)
	local live_validation_failure_settings = deep_clone(flat)
	local live_validation_failure_snapshot = deep_clone(live_validation_failure_settings)
	local live_validation_failure_active = active_config.build_active_profile_from_settings(live_validation_failure_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	_G.UC_ACTIVE_PROFILE = live_validation_failure_active
	local live_validation_failure_active_snapshot = deep_clone(rawget(_G, 'UC_ACTIVE_PROFILE'))
	local ok_validation_failure, _, validation_failure_err = live_validation_failure_apply({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, live_validation_failure_settings)
	assert_true(ok_validation_failure == false, 'live profilev2 apply should fail cleanly on validation failure')
	assert_equal(validation_failure_err, 'missing config', 'live profilev2 apply validation failure reason mismatch')
	assert_deep_equal(live_validation_failure_settings, live_validation_failure_snapshot, 'live profilev2 apply validation failure must not mutate settings')
	assert_deep_equal(rawget(_G, 'UC_ACTIVE_PROFILE'), live_validation_failure_active_snapshot, 'live profilev2 apply validation failure must not mutate active profile')

	local live_conversion_failure_apply = load_profile_v2_apply_from_addon(addon, function()
		return {
			ok = false,
			path = durable_path,
			error = 'forced normalize failure',
		}
	end)
	local live_conversion_failure_settings = deep_clone(flat)
	local live_conversion_failure_snapshot = deep_clone(live_conversion_failure_settings)
	local live_conversion_failure_active = active_config.build_active_profile_from_settings(live_conversion_failure_settings, {
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
		source = 'UC_SETTINGS',
	})
	_G.UC_ACTIVE_PROFILE = live_conversion_failure_active
	local live_conversion_failure_active_snapshot = deep_clone(rawget(_G, 'UC_ACTIVE_PROFILE'))
	local ok_conversion_failure, _, conversion_failure_err = live_conversion_failure_apply({
		character = 'Redrogue',
		main_job = 'PLD',
		sub_job = 'WAR',
	}, live_conversion_failure_settings)
	assert_true(ok_conversion_failure == false, 'live profilev2 apply should fail cleanly on conversion failure')
	assert_equal(conversion_failure_err, 'forced normalize failure', 'live profilev2 apply conversion failure reason mismatch')
	assert_deep_equal(live_conversion_failure_settings, live_conversion_failure_snapshot, 'live profilev2 apply conversion failure must not mutate settings')
	assert_deep_equal(rawget(_G, 'UC_ACTIVE_PROFILE'), live_conversion_failure_active_snapshot, 'live profilev2 apply conversion failure must not mutate active profile')

	run_profile_v2_autoload_selftest(profile_v2, active_config, contract, flat, durable_path)

	_G.UC_normalize_settings_table = previous_global_uc_normalize_settings_table
	_G.uc_normalize_settings_table = previous_global_uc_normalize_settings_table_lower
	_G.uc_sync_table_in_place = previous_global_uc_sync_table_in_place
	_G.UC_ACTIVE_PROFILE = previous_active_profile

	local expected_config = build_expected_config()
	assert_true(deep_equal(profile.config, expected_config), 'exported config mismatch against expected durable domains')

	io.stdout:write('selftest_profile_v2_export: OK\n')
end

main()
