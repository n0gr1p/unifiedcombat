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

local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local content = fh:read('*a')
	fh:close()
	return content
end

local function extract_source_block(source, start_marker, end_marker)
	local start_pos = source:find(start_marker, 1, true)
	assert_true(start_pos ~= nil, 'missing source block start: ' .. tostring(start_marker))
	local end_pos = source:find(end_marker, start_pos + #start_marker, true)
	assert_true(end_pos ~= nil, 'missing source block end: ' .. tostring(end_marker))
	return source:sub(start_pos, end_pos - 1)
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

local function load_autoload_scope(state, status_result, autoload_result)
	local addon = read_file('UnifiedCombat.lua')
	assert_contains(addon, 'local function uc_queue_profile_v2_autoload()', 'addon must define the queued autoload helper')
	assert_contains(addon, 'local function uc_run_queued_profile_v2_autoload()', 'addon must define the queued autoload runner')
	assert_contains(addon, 'local function uc_run_profile_v2_auto_reload()', 'addon must define the file-change auto-reload runner')

	local block = extract_source_block(
		addon,
		'local uc_sync_table_in_place',
		'\n\nlocal function uc_sleep_spell_list_lines'
	)

	local chunk_source = table.concat({
		block,
		'',
		'return {',
		'  startup_reload = uc_reload_startup_profile_once,',
		'  reload = uc_reload_active_profile,',
		'  queue = uc_queue_profile_v2_autoload,',
		'  run = uc_run_queued_profile_v2_autoload,',
		'  auto_reload = uc_run_profile_v2_auto_reload,',
		'  auto_reload_status = uc_profile_v2_auto_reload_status,',
		'  autoload = uc_autoload_profile_v2_file,',
		'}',
	}, '\n')

	local env = {
		_G = _G,
		uc_now_s = function()
			return state.now
		end,
		uc_active_config = require('uc_active_config'),
		uc_partner_list = {
			migrate_from_legacy = function()
			end,
			sync_legacy_partner_fields = function()
			end,
		},
		uc_addon_path = function()
			return 'C:\\Addon'
		end,
		uc_profile_v2_file_path = function()
			return 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua'
		end,
		uc_validate_structured_profile_export = function()
			return {
				ok = true,
			}
		end,
		uc_update_config_contract_status = function()
			return {
				ok = true,
			}
		end,
		uc_profile_v2 = {
			validate_structured_profile_file = function(meta)
				state.validate_calls = state.validate_calls + 1
				if type(state.validate_result) == 'table' then
					return deep_clone(state.validate_result)
				end
				return {
					ok = true,
					payload = {
						config = {
							ownership = {
								profile_v2_autoload = true,
								profile_v2_auto_reload_on_change = true,
							},
						},
					},
				}
			end,
			apply_structured_profile_file_to_settings = function(current_settings, meta)
				if type(state.apply_result) == 'table' then
					return deep_clone(state.apply_result)
				end
				state.autoload_calls = state.autoload_calls + 1
				state.settings_identity = current_settings
				local auto_reload_enabled = state.auto_reload_enabled_after_apply
				if auto_reload_enabled == nil then
					auto_reload_enabled = current_settings.profile_v2_auto_reload_on_change == true
				end
				current_settings.profile_v2_autoload = true
				current_settings.engine_enabled = false
				current_settings.profile_v2_auto_reload_on_change = auto_reload_enabled == true
				current_settings.cor_roll_1 = 'Chaos Roll'
				current_settings.cor_roll_2 = 'Ninja Roll'
				current_settings.defensive_targeted_buffs = 'Terrasjr:Honor March'
				current_settings.cor_crooked_roll_slot = 0
				current_settings.cor_elevens = false
				current_settings.cor_luzaf_range_override = false
				current_settings.cor_roll_range_require_ids = {}
				state.active_profile = {
					version = 2,
					profile = {
						character = meta.character,
						main_job = meta.main_job,
						sub_job = meta.sub_job,
						source = 'UC_PROFILE_V2',
					},
					config = {
						ownership = {
							profile_v2_autoload = true,
							profile_v2_auto_reload_on_change = current_settings.profile_v2_auto_reload_on_change == true,
						},
						maintenance = {
							cor = {
								roll_1 = 'Chaos Roll',
								roll_2 = 'Ninja Roll',
								crooked_roll_slot = 0,
								elevens = false,
								luzaf_range_override = false,
								range_require_ids = {},
							},
						},
						defensive = {
							buffs = {
								targeted = {
									{ character = 'Terrasjr', buff = 'Honor March' },
								},
							},
						},
					},
				}
				_G.UC_ACTIVE_PROFILE = state.active_profile
				return {
					ok = true,
					path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
					stage = 'done',
					active_profile = state.active_profile,
					candidate = current_settings,
					projected_settings = current_settings,
					candidate_config = state.active_profile.config,
					count = autoload_result.count,
					diff_count = autoload_result.diff_count,
					differences = deep_clone(autoload_result.differences or {}),
					details = deep_clone(autoload_result.details or {}),
					diff_details = deep_clone(autoload_result.diff_details or {}),
					first_difference = deep_clone(autoload_result.first_difference),
				}
			end,
			inspect_structured_profile_file_against_settings = function(settings, meta)
				state.status_calls = state.status_calls + 1
				state.status_context = {
					settings = settings,
					meta = meta,
				}
				return deep_clone(state.status_result)
			end,
		},
		files = {
			exists = function(path)
				return state.files[path] ~= nil
			end,
			read = function(path)
				state.read_calls[#state.read_calls + 1] = path
				return state.files[path]
			end,
		},
		uc_update_profile_v2_contract_status = function(context)
			state.status_calls = state.status_calls + 1
			state.status_context = context
			return deep_clone(status_result)
		end,
		io = {
			open = function(path, mode)
				state.read_calls[#state.read_calls + 1] = path
				local content = state.files[path]
				if type(content) ~= 'string' then
					return nil, 'missing'
				end
				local consumed = false
				return {
					read = function(_, read_mode)
						if consumed then
							return nil
						end
						consumed = true
						if read_mode ~= nil and read_mode ~= '*' and read_mode ~= '*a' then
							return content
						end
						return content
					end,
					close = function()
						return true
					end,
				}
			end,
		},
		windower = {
			ffxi = {
				get_player = function()
					return state.player
				end,
			},
			add_to_chat = function(_, message)
				state.chats[#state.chats + 1] = tostring(message)
			end,
		},
	}
	setmetatable(env, { __index = _G })

	local chunk, load_err = loadstring(chunk_source, '@selftest_profile_v2_autoload_scope.lua')
	assert_true(type(chunk) == 'function', 'unable to load extracted autoload helpers: ' .. tostring(load_err))
	setfenv(chunk, env)
	local scope = chunk()
	assert_true(type(scope) == 'table', 'extracted autoload scope must return a table')
	return scope
end

local function make_state()
	return {
		validate_calls = 0,
		autoload_calls = 0,
		status_calls = 0,
		start_calls = 0,
		reload_calls = 0,
		reload_job = nil,
		chats = {},
		read_calls = {},
		files = {},
		now = 123.5,
		player = {
			name = 'Terrasjr',
			main_job = 'PLD',
			sub_job = 'RDM',
		},
		settings = {
			engine_enabled = false,
			profile_v2_autoload = false,
		},
		active_profile = nil,
		settings_identity = nil,
		status_context = nil,
		validate_result = nil,
		status_result = {
			ok = true,
			valid = true,
			diff_count = 0,
			count = 0,
			first_difference = nil,
			path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
		},
	}
end

local function assert_chat_contains(state, needle, message)
	local joined = table.concat(state.chats, '\n')
	assert_contains(joined, needle, message)
end

local function main()
	local previous_settings = rawget(_G, 'UC_SETTINGS')
	local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	local previous_reload_active_profile = rawget(_G, 'UC_ReloadActiveProfile')

	local success_state = make_state()
	_G.UC_SETTINGS = success_state.settings
	_G.UC_ACTIVE_PROFILE = {
		version = 2,
		profile = {
			character = 'Terrasjr',
			main_job = 'PLD',
			sub_job = 'RDM',
			source = 'seed',
		},
		config = {
			ownership = {},
		},
	}
	rawset(_G, 'UC_ReloadActiveProfile', function(job_for_defaults)
		success_state.reload_calls = success_state.reload_calls + 1
		success_state.reload_job = job_for_defaults
		success_state.active_profile = {
			version = 2,
			profile = {
				character = success_state.player.name,
				main_job = success_state.player.main_job,
				sub_job = success_state.player.sub_job,
				source = 'legacy',
			},
			config = {
				maintenance = {
					cor = {
						roll_1 = 'Corsair\'s Roll',
						roll_2 = 'Ninja Roll',
						crooked_roll_slot = 0,
						elevens = false,
						luzaf_range_override = false,
						range_require_ids = {},
					},
				},
			},
		}
		_G.UC_ACTIVE_PROFILE = success_state.active_profile
		return true
	end)

	local success_scope = load_autoload_scope(
		success_state,
		{
			valid = true,
			diff_count = 0,
			first_difference = nil,
		},
		{
			ok = true,
			count = 12,
			diff_count = 12,
			first_difference = {
				path = 'config.defensive.thresholds.critical_hpp',
			},
		}
	)

	assert_true(success_scope.queue() == 'Terrasjr|PLD|RDM', 'queued autoload should record the session key')
	assert_true(success_scope.queue() == 'Terrasjr|PLD|RDM', 'duplicate queue requests should return the same session key')
	assert_equal(success_state.autoload_calls, 0, 'queued autoload must not run before the startup runner fires')
	assert_equal(success_state.status_calls, 0, 'queued autoload must not inspect status before the startup runner fires')
	assert_true(success_scope.startup_reload() ~= nil, 'startup reload should run once before autoload')
	assert_equal(success_state.reload_calls, 1, 'startup reload should call the legacy bootstrap path once')
	assert_true(success_scope.startup_reload() ~= nil, 'duplicate startup reloads should be ignored for the same session')
	assert_equal(success_state.reload_calls, 1, 'duplicate startup reloads must not run twice for the same session')
	assert_true(success_scope.run() ~= nil, 'startup runner should execute the queued autoload')
	assert_equal(success_state.validate_calls, 1, 'autoload should validate the profile once before apply')
	assert_equal(success_state.autoload_calls, 1, 'autoload should run exactly once for the session')
	assert_equal(success_state.status_calls, 1, 'autoload should compute a post-apply status check')
	assert_equal(success_state.settings_identity, success_state.settings, 'autoload must preserve _G.UC_SETTINGS identity')
	assert_true(_G.UC_ACTIVE_PROFILE == success_state.active_profile, 'autoload must update _G.UC_ACTIVE_PROFILE')
	assert_equal(success_state.settings.profile_v2_autoload, true, 'autoload must preserve the autoload flag in settings')
	assert_equal(success_state.settings.engine_enabled, false, 'autoload must not enable the engine')
	assert_equal(success_state.settings.cor_roll_1, 'Chaos Roll', 'autoload must preserve COR roll 1 in settings')
	assert_equal(success_state.settings.cor_roll_2, 'Ninja Roll', 'autoload must preserve COR roll 2 in settings')
	assert_equal(success_state.settings.defensive_targeted_buffs, 'Terrasjr:Honor March', 'autoload must preserve targeted buffs in settings')
	assert_equal(success_state.start_calls, 0, 'autoload runner must not start the engine')
	assert_chat_contains(success_state, 'UC profile v2 autoload: applied', 'successful autoload should report applied when post-apply diff is zero')
	assert_true(success_scope.startup_reload() ~= nil, 'post-autoload startup reload should be ignored for the same session')
	assert_equal(success_state.reload_calls, 1, 'post-autoload startup reload must not run twice for the same session')
	local active_config = require('uc_active_config')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_1'), 'Chaos Roll', 'autoloaded active config roll 1 mismatch')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_2'), 'Ninja Roll', 'autoloaded active config roll 2 mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].character, 'Terrasjr', 'autoloaded active config targeted buff character mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].buff, 'Honor March', 'autoloaded active config targeted buff name mismatch')
	assert_true(success_scope.reload('PLD') ~= nil, 'post-autoload legacy reload guard should still return the player')
	assert_equal(success_state.settings.cor_roll_1, 'Chaos Roll', 'post-autoload reload must preserve COR roll 1 in settings')
	assert_equal(success_state.settings.cor_roll_2, 'Ninja Roll', 'post-autoload reload must preserve COR roll 2 in settings')
	assert_equal(success_state.settings.defensive_targeted_buffs, 'Terrasjr:Honor March', 'post-autoload reload must preserve targeted buffs in settings')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_1'), 'Chaos Roll', 'post-autoload reload must preserve active config roll 1')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_2'), 'Ninja Roll', 'post-autoload reload must preserve active config roll 2')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].character, 'Terrasjr', 'post-autoload reload must preserve active targeted buff character')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].buff, 'Honor March', 'post-autoload reload must preserve active targeted buff name')
	local previous_windower = rawget(_G, 'windower')
	rawset(_G, 'windower', {
		ffxi = {
			get_player = function()
				return {
					main_job = 'COR',
					sub_job = 'WAR',
					status = 0,
					buffs = {},
				}
			end,
			get_ability_recasts = function()
				return {}
			end,
			get_items = function()
				return { enabled = false }
			end,
			get_mob_by_id = function()
				return nil
			end,
		},
	})
	local active_cor = dofile('uc_cor_maintenance.lua')
	local cor_action = active_cor.propose({
		cor_roll_1 = 'Corsair\'s Roll',
		cor_roll_2 = 'Samurai Roll',
		cor_crooked_roll_slot = 0,
		cor_elevens = false,
		cor_luzaf_range_override = false,
		cor_roll_range_require_ids = {},
		abilities = {},
	})
	assert_true(type(cor_action) == 'table', 'post-autoload COR maintenance should still produce an action')
	assert_equal(cor_action.action_name, 'Chaos Roll', 'autoloaded COR rolls must survive the startup reload guard')
	rawset(_G, 'windower', previous_windower)

	assert_true(success_scope.run() == nil, 'duplicate startup runner calls must not rerun the same session')
	assert_equal(success_state.autoload_calls, 1, 'duplicate startup runner calls must not reapply the same session')
	rawset(_G, 'UC_ReloadActiveProfile', previous_reload_active_profile)

	local auto_reload_state = make_state()
	auto_reload_state.settings.profile_v2_auto_reload_on_change = true
	auto_reload_state.status_result = {
		ok = true,
		valid = true,
		diff_count = 0,
		count = 0,
		first_difference = nil,
		path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
	}
	local auto_reload_scope = load_autoload_scope(
		auto_reload_state,
		auto_reload_state.status_result,
		{
			ok = true,
			count = 7,
			diff_count = 7,
			first_difference = {
				path = 'config.defensive.thresholds.critical_hpp',
			},
		}
	)
	_G.UC_SETTINGS = auto_reload_state.settings
	_G.UC_ACTIVE_PROFILE = {
		version = 2,
		profile = {
			character = 'Terrasjr',
			main_job = 'PLD',
			sub_job = 'RDM',
			source = 'UC_PROFILE_V2',
		},
		config = {
			ownership = {
				profile_v2_auto_reload_on_change = true,
			},
		},
	}
	auto_reload_state.files['C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua'] = 'return { version = 2, config = { defensive = { thresholds = { critical_hpp = 35 } } } }'
	assert_true(auto_reload_scope.auto_reload() == nil, 'first auto-reload poll should only arm the stable snapshot')
	assert_equal(#auto_reload_state.read_calls, 1, 'auto-reload must read the active file once on the first poll')
	auto_reload_state.now = auto_reload_state.now + 3.5
	auto_reload_state.files['C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua'] = 'return { version = 2, config = { defensive = { thresholds = { critical_hpp = 30 } } } }'
	assert_true(auto_reload_scope.auto_reload() == nil, 'second auto-reload poll should record the changed file before applying')
	auto_reload_state.now = auto_reload_state.now + 3.5
	local auto_reload_settings_identity = auto_reload_state.settings
	local auto_reload_result = auto_reload_scope.auto_reload()
	assert_true(type(auto_reload_result) == 'table' and auto_reload_result.ok == true, 'stable file change should auto-reload successfully')
	assert_equal(auto_reload_state.settings_identity, auto_reload_settings_identity, 'auto-reload must preserve _G.UC_SETTINGS identity')
	assert_equal(auto_reload_state.settings.engine_enabled, false, 'auto-reload must not enable the engine')
	assert_equal(auto_reload_state.settings.profile_v2_auto_reload_on_change, true, 'auto-reload must preserve the auto-reload flag in settings')
	assert_equal(auto_reload_state.status_calls, 1, 'auto-reload should perform a post-apply status check')
	local auto_reload_status = auto_reload_scope.auto_reload_status()
	assert_true(type(auto_reload_status) == 'table', 'auto-reload status helper should return a table')
	assert_equal(auto_reload_status.enabled, true, 'auto-reload status should report enabled')
	assert_equal(auto_reload_status.last_error, nil, 'auto-reload status should clear last error on success')
	assert_true(auto_reload_status.path ~= nil, 'auto-reload status should report the watched path')
	assert_chat_contains(auto_reload_state, 'UC profile v2 auto-reload: applied', 'successful auto-reload should report applied when post-apply diff is zero')
	assert_true(auto_reload_scope.auto_reload() == nil, 'no-op auto-reload poll should not reapply an unchanged file')
	assert_equal(auto_reload_state.autoload_calls, 1, 'no-op auto-reload poll must not apply an unchanged file twice')

	local disable_reload_state = make_state()
	disable_reload_state.settings.profile_v2_auto_reload_on_change = true
	disable_reload_state.auto_reload_enabled_after_apply = false
	disable_reload_state.status_result = {
		ok = true,
		valid = true,
		diff_count = 0,
		count = 0,
		first_difference = nil,
		path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
	}
	local disable_reload_scope = load_autoload_scope(
		disable_reload_state,
		disable_reload_state.status_result,
		{
			ok = true,
			count = 0,
			diff_count = 0,
			first_difference = nil,
		}
	)
	_G.UC_SETTINGS = disable_reload_state.settings
	_G.UC_ACTIVE_PROFILE = {
		version = 2,
		profile = {
			character = 'Terrasjr',
			main_job = 'PLD',
			sub_job = 'RDM',
			source = 'UC_PROFILE_V2',
		},
		config = {
			ownership = {
				profile_v2_auto_reload_on_change = true,
			},
		},
	}
	disable_reload_state.files['C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua'] = 'return { version = 2, config = { ownership = { profile_v2_auto_reload_on_change = false }, defensive = { thresholds = { critical_hpp = 35 } } } }'
	assert_true(disable_reload_scope.auto_reload() == nil, 'disabled auto-reload should arm on the first poll')
	disable_reload_state.now = disable_reload_state.now + 3.5
	disable_reload_state.files['C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua'] = 'return { version = 2, config = { ownership = { profile_v2_auto_reload_on_change = false }, defensive = { thresholds = { critical_hpp = 30 } } } }'
	assert_true(disable_reload_scope.auto_reload() == nil, 'disabled auto-reload should record the changed file before applying')
	disable_reload_state.now = disable_reload_state.now + 3.5
	local disable_reload_result = disable_reload_scope.auto_reload()
	assert_true(type(disable_reload_result) == 'table' and disable_reload_result.ok == true, 'disabled auto-reload should still apply successfully')
	assert_equal(disable_reload_state.settings.profile_v2_auto_reload_on_change, false, 'disabled auto-reload must clear the flag in settings')
	assert_true(rawget(_G, 'UC_ACTIVE_PROFILE').config.ownership.profile_v2_auto_reload_on_change == nil, 'disabled auto-reload must omit the durable ownership flag')
	local disable_reload_status = disable_reload_scope.auto_reload_status()
	assert_true(type(disable_reload_status) == 'table', 'disabled auto-reload status should return a table')
	assert_equal(disable_reload_status.enabled, false, 'disabled auto-reload status should report disabled')
	assert_equal(disable_reload_state.status_calls, 2, 'disabled auto-reload should perform a post-apply status check and a status query')
	local disable_reload_reads_before = #disable_reload_state.read_calls
	disable_reload_state.now = disable_reload_state.now + 3.5
	assert_true(disable_reload_scope.auto_reload() == nil, 'disabled auto-reload should stop polling after the disabled flag is applied')
	assert_equal(#disable_reload_state.read_calls, disable_reload_reads_before, 'disabled auto-reload must stop reading the file after the flag is cleared')

	local invalid_reload_state = make_state()
	invalid_reload_state.settings.profile_v2_auto_reload_on_change = true
	invalid_reload_state.validate_result = {
		ok = false,
		path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
		stage = 'load',
		error = 'parse failed',
		reason = 'parse failed',
	}
	invalid_reload_state.apply_result = {
		ok = false,
		path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
		stage = 'apply',
		error = 'parse failed',
		reason = 'parse failed',
		count = 0,
		diff_count = 0,
	}
	invalid_reload_state.status_result = {
		ok = false,
		valid = false,
		diff_count = 1,
		count = 1,
		first_difference = {
			path = 'config.defensive.buffs.overwrite_interval',
		},
		path = 'C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua',
	}
	local invalid_reload_scope = load_autoload_scope(
		invalid_reload_state,
		invalid_reload_state.status_result,
		{
			ok = true,
			count = 3,
			diff_count = 3,
			first_difference = {
				path = 'config.defensive.buffs.overwrite_interval',
			},
		}
	)
	_G.UC_SETTINGS = invalid_reload_state.settings
	_G.UC_ACTIVE_PROFILE = {
		version = 2,
		profile = {
			character = 'Terrasjr',
			main_job = 'PLD',
			sub_job = 'RDM',
			source = 'UC_PROFILE_V2',
		},
		config = {
			ownership = {
				profile_v2_auto_reload_on_change = true,
			},
		},
	}
	invalid_reload_state.files['C:\\Addon\\data\\profiles_v2\\terrassjr_PLD_RDM.lua'] = 'return { version = 2, config = { bad = true } }'
	assert_true(invalid_reload_scope.auto_reload() == nil, 'invalid auto-reload should arm on the first poll')
	invalid_reload_state.now = invalid_reload_state.now + 3.5
	local invalid_reload_result = invalid_reload_scope.auto_reload()
	assert_true(type(invalid_reload_result) == 'table' and invalid_reload_result.ok == false, 'invalid auto-reload should fail without mutating runtime')
	assert_equal(invalid_reload_state.autoload_calls, 0, 'invalid auto-reload must not apply runtime changes')
	assert_equal(invalid_reload_state.settings.engine_enabled, false, 'invalid auto-reload must not mutate engine state')
	assert_equal(invalid_reload_state.settings.profile_v2_auto_reload_on_change, true, 'invalid auto-reload must preserve the flag in settings')
	assert_chat_contains(invalid_reload_state, 'UC profile v2 auto-reload failed: ', 'invalid auto-reload should report a concise warning')

	local warning_state = make_state()
	_G.UC_SETTINGS = warning_state.settings
	_G.UC_ACTIVE_PROFILE = {
		version = 2,
		profile = {
			character = 'Terrasjr',
			main_job = 'PLD',
			sub_job = 'RDM',
			source = 'seed',
		},
		config = {
			ownership = {},
		},
	}

	local warning_scope = load_autoload_scope(
		warning_state,
		{
			valid = true,
			diff_count = 12,
			first_difference = {
				path = 'config.defensive.thresholds.critical_hpp',
			},
		},
		{
			ok = true,
			count = 12,
			diff_count = 12,
			first_difference = {
				path = 'config.defensive.thresholds.critical_hpp',
			},
		}
	)

	assert_true(warning_scope.queue() == 'Terrasjr|PLD|RDM', 'warning case should still queue the session')
	assert_true(warning_scope.run() ~= nil, 'warning case should still execute once')
	assert_equal(warning_state.autoload_calls, 1, 'warning case should apply once')
	assert_equal(warning_state.status_calls, 1, 'warning case should compute one post-apply status check')
	assert_chat_contains(warning_state, 'UC profile v2 autoload warning: config.defensive.thresholds.critical_hpp', 'nonzero post-autoload diff should warn with the first diff path')
	assert_true(table.concat(warning_state.chats, '\n'):find('UC profile v2 autoload: applied', 1, true) == nil, 'warning case must not report success')
	assert_equal(warning_state.settings, warning_state.settings_identity, 'warning case must preserve _G.UC_SETTINGS identity')
	assert_equal(warning_state.settings.engine_enabled, false, 'warning case must not enable the engine')
	assert_equal(warning_state.start_calls, 0, 'warning case must not start the engine')

	_G.UC_SETTINGS = previous_settings
	_G.UC_ACTIVE_PROFILE = previous_active_profile
	rawset(_G, 'UC_ReloadActiveProfile', previous_reload_active_profile)
	io.stdout:write('selftest_profile_v2_autoload_lifecycle: OK\n')
end

main()
