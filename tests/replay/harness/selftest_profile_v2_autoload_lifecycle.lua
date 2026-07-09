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

	local block = extract_source_block(
		addon,
		'local uc_sync_table_in_place',
		'\n\nlocal function uc_read_profiles_file'
	)

	local chunk_source = table.concat({
		block,
		'',
		'return {',
		'  startup_reload = uc_reload_startup_profile_once,',
		'  queue = uc_queue_profile_v2_autoload,',
		'  run = uc_run_queued_profile_v2_autoload,',
		'  autoload = uc_autoload_profile_v2_file,',
		'}',
	}, '\n')

	local env = {
		_G = _G,
		uc_now_s = function()
			return 123.5
		end,
		uc_addon_path = function()
			return 'C:\\Addon'
		end,
		uc_validate_structured_profile_export = function()
			return {
				ok = true,
			}
		end,
		uc_profile_v2 = {
			autoload_structured_profile_file_to_settings = function(current_settings, meta)
				state.autoload_calls = state.autoload_calls + 1
				state.settings_identity = current_settings
				current_settings.profile_v2_autoload = true
				current_settings.engine_enabled = false
				current_settings.cor_roll_1 = 'Chaos Roll'
				current_settings.cor_roll_2 = 'Ninja Roll'
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
					},
				}
				_G.UC_ACTIVE_PROFILE = state.active_profile
				return deep_clone(autoload_result)
			end,
		},
		uc_update_profile_v2_contract_status = function(context)
			state.status_calls = state.status_calls + 1
			state.status_context = context
			return deep_clone(status_result)
		end,
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
		autoload_calls = 0,
		status_calls = 0,
		start_calls = 0,
		chats = {},
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
		reload_calls = 0,
		reload_job = nil,
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
	assert_equal(success_state.autoload_calls, 1, 'autoload should run exactly once for the session')
	assert_equal(success_state.status_calls, 1, 'autoload should compute a post-apply status check')
	assert_equal(success_state.settings_identity, success_state.settings, 'autoload must preserve _G.UC_SETTINGS identity')
	assert_true(_G.UC_ACTIVE_PROFILE == success_state.active_profile, 'autoload must update _G.UC_ACTIVE_PROFILE')
	assert_equal(success_state.settings.profile_v2_autoload, true, 'autoload must preserve the autoload flag in settings')
	assert_equal(success_state.settings.engine_enabled, false, 'autoload must not enable the engine')
	assert_equal(success_state.start_calls, 0, 'autoload runner must not start the engine')
	assert_chat_contains(success_state, 'UC profile v2 autoload: applied', 'successful autoload should report applied when post-apply diff is zero')
	assert_true(success_scope.startup_reload() ~= nil, 'post-autoload startup reload should be ignored for the same session')
	assert_equal(success_state.reload_calls, 1, 'post-autoload startup reload must not run twice for the same session')
	local active_config = require('uc_active_config')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_1'), 'Chaos Roll', 'autoloaded active config roll 1 mismatch')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_2'), 'Ninja Roll', 'autoloaded active config roll 2 mismatch')
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
