local function assert_true(condition, message)
	if not condition then
		error(message or 'assertion failed')
	end
end

local function assert_contains(haystack, needle, message)
	assert_true(type(haystack) == 'string' and haystack:find(needle, 1, true) ~= nil, message or ('missing substring: ' .. tostring(needle)))
end

local function assert_not_contains(haystack, needle, message)
	assert_true(type(haystack) == 'string' and haystack:find(needle, 1, true) == nil, message or ('unexpected substring: ' .. tostring(needle)))
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

local function source_block(source, start_marker, end_marker)
	local start_pos = source:find(start_marker, 1, true)
	assert_true(start_pos ~= nil, 'missing source block start: ' .. tostring(start_marker))
	local end_pos = source:find(end_marker, start_pos + #start_marker, true)
	assert_true(end_pos ~= nil, 'missing source block end: ' .. tostring(end_marker))
	return source:sub(start_pos, end_pos - 1)
end

local function test_automatic_identity_lifecycle(addon)
	local transition = source_block(addon, 'local function uc_begin_profile_v2_identity_transition', 'local function uc_run_profile_v2_auto_reload')
	assert_contains(transition, "_G.UC_StopUnifiedEngine('profile_identity_change')", 'identity changes must stop the running engine')
	assert_contains(transition, 'uc_initialize_safe_profile_v2_identity', 'identity changes must publish safe defaults before resolution')
	assert_contains(transition, 'uc_queue_profile_v2_autoload(expected_main_job, resume_engine)', 'identity changes must queue the exact Profile V2 identity')
	assert_not_contains(transition, 'uc_load_profiles_for_character', 'identity changes must not read legacy profiles')
	assert_not_contains(transition, 'UC_StartUnifiedEngine', 'identity transition must not restart before Profile V2 resolution')

	local establish = source_block(addon, 'local function uc_establish_profile_v2_identity', 'local function uc_autoload_profile_v2_file')
	assert_contains(establish, 'uc_initialize_safe_profile_v2_identity', 'missing and invalid identities must begin from safe defaults')
	assert_contains(establish, "state = 'missing'", 'missing files must be reported distinctly')
	assert_contains(establish, "state = 'invalid'", 'invalid files must be reported distinctly')
	assert_contains(establish, 'uc_apply_profile_v2_file', 'valid files must use the shared Profile V2 apply path')
	assert_not_contains(establish, 'uc_load_profiles_for_character', 'Profile V2 establishment must never fall back to legacy profiles')

	local queued = source_block(addon, 'local function uc_run_queued_profile_v2_autoload', 'local function uc_begin_profile_v2_identity_transition')
	assert_contains(queued, 'uc_autoload_profile_v2_file()', 'queued startup and job transitions must resolve Profile V2 automatically')
	assert_contains(queued, 'uc_profile_v2_autoload_resume_engine', 'engine restart must be deferred until identity resolution completes')
	assert_contains(queued, 'uc_start_active_engine_if_running()', 'previously-running engines must restart after resolution')

	local load_event = source_block(addon, "windower.register_event('load'", "windower.register_event('login'")
	assert_contains(load_event, 'uc_begin_profile_v2_identity_transition()', 'load must automatically resolve Profile V2')
	assert_not_contains(load_event, 'uc_reload_startup_profile_once', 'load must not use the legacy startup loader')

	local login_start = addon:find("windower.register_event('login'", 1, true)
	assert_true(login_start ~= nil, 'missing login event')
	local login_event = addon:sub(login_start)
	assert_contains(login_event, 'uc_begin_profile_v2_identity_transition()', 'login must automatically resolve Profile V2')
	assert_not_contains(login_event, 'uc_reload_startup_profile_once', 'login must not use the legacy startup loader')

	local job_event = source_block(addon, "windower.register_event('job change'", "windower.register_event('zone change'")
	assert_contains(job_event, 'uc_begin_profile_v2_identity_transition(jname)', 'job/subjob changes must automatically resolve the exact Profile V2 identity')
	assert_not_contains(job_event, 'uc_reload_startup_profile_once', 'job changes must not use the legacy startup loader')
	assert_not_contains(job_event, 'UC_StartUnifiedEngine', 'job event must not restart the engine ahead of queued resolution')

	local prerender = source_block(addon, "windower.register_event('prerender'", "windower.register_event('job change'")
	local queued_pos = prerender:find('uc_run_queued_profile_v2_autoload()', 1, true)
	local recovery_pos = prerender:find('uc_update_recovery_hold()', 1, true)
	assert_true(queued_pos ~= nil and recovery_pos ~= nil and queued_pos < recovery_pos, 'Profile V2 identity must resolve before runtime recovery work')
end

local function test_unconditional_watcher(addon)
	local watcher = source_block(addon, 'local function uc_run_profile_v2_auto_reload', 'local function uc_normalize_targets')
	assert_contains(watcher, 'UC_PROFILE_V2_AUTO_RELOAD_POLL_SEC', 'watcher must poll continuously')
	assert_contains(watcher, 'UC_PROFILE_V2_AUTO_RELOAD_STABLE_SEC', 'watcher must debounce file writes')
	assert_contains(watcher, 'uc_profile_v2_content_hash', 'watcher must suppress unchanged content by hash')
	assert_contains(watcher, 'uc_apply_profile_v2_file', 'watcher must use the shared validated apply path')
	assert_contains(watcher, 'last_reported_hash', 'watcher must suppress duplicate invalid-content errors')
	assert_not_contains(watcher, 'profile_v2_auto_reload_on_change == true', 'watcher must not consult the removed lifecycle switch')
	assert_not_contains(watcher, 'profile_v2_autoload == true', 'watcher must not consult the removed lifecycle switch')
end

local function test_watcher_state_machine(addon)
	local watcher_source = source_block(addon, 'local function uc_run_profile_v2_auto_reload', 'local function uc_normalize_targets')
	local state = {
		now = 1.1,
		content = nil,
		apply_calls = 0,
		chats = {},
		settings = {
			value = 'last-known-good',
			profile_v2_autoload = false,
			profile_v2_auto_reload_on_change = false,
		},
	}
	local env = {
		UC_PROFILE_V2_AUTO_RELOAD_POLL_SEC = 1,
		UC_PROFILE_V2_AUTO_RELOAD_STABLE_SEC = 1,
		uc_profile_v2_auto_reload_last_checked_at = 0,
		uc_profile_v2_auto_reload_session_key = nil,
		uc_profile_v2_auto_reload_last_applied_session_key = nil,
		uc_profile_v2_auto_reload_last_applied_hash = nil,
		uc_profile_v2_auto_reload_last_reported_hash = nil,
		uc_profile_v2_auto_reload_pending_path = nil,
		uc_profile_v2_auto_reload_pending_hash = nil,
		uc_profile_v2_auto_reload_pending_seen_at = nil,
		uc_profile_v2_auto_reload_last_error = nil,
		UC_SETTINGS = state.settings,
		uc_now_s = function()
			return state.now
		end,
		uc_profile_v2_session_key = function(player)
			return player.name .. '|' .. player.main_job .. '|' .. player.sub_job
		end,
		uc_addon_path = function()
			return 'C:\\Addon'
		end,
		uc_profile_v2_file_path = function()
			return 'C:\\Addon\\data\\profiles_v2\\redrogue_PLD_WAR.lua'
		end,
		uc_profile_v2_read_file_content = function()
			if state.content == nil then
				return nil, 'missing file'
			end
			return state.content
		end,
		uc_profile_v2_content_hash = function(content)
			return content
		end,
		uc_validate_structured_profile_export = function()
			return { ok = true }
		end,
		uc_profile_v2 = {
			inspect_structured_profile_file_against_settings = function()
				return { ok = true, valid = true, count = 0, diff_count = 0 }
			end,
		},
		windower = {
			ffxi = {
				get_player = function()
					return { name = 'Redrogue', main_job = 'PLD', sub_job = 'WAR' }
				end,
			},
			add_to_chat = function(_, message)
				state.chats[#state.chats + 1] = message
			end,
		},
	}
	setmetatable(env, { __index = _G })
	env._G = env
	env.uc_profile_v2_auto_reload_reset = function()
		env.uc_profile_v2_auto_reload_pending_path = nil
		env.uc_profile_v2_auto_reload_pending_hash = nil
		env.uc_profile_v2_auto_reload_pending_seen_at = nil
		env.uc_profile_v2_auto_reload_session_key = nil
		env.uc_profile_v2_auto_reload_last_applied_session_key = nil
		env.uc_profile_v2_auto_reload_last_applied_hash = nil
		env.uc_profile_v2_auto_reload_last_reported_hash = nil
		env.uc_profile_v2_auto_reload_last_checked_at = 0
		env.uc_profile_v2_auto_reload_last_error = nil
	end
	env.uc_apply_profile_v2_file = function()
		state.apply_calls = state.apply_calls + 1
		if state.content == 'invalid' then
			return false, env.uc_profile_v2_file_path(), 'forced invalid profile'
		end
		state.settings.value = state.content
		return true, env.uc_profile_v2_file_path(), nil, 1
	end

	local chunk, load_err = loadstring(watcher_source .. '\nreturn uc_run_profile_v2_auto_reload', '@watcher_state_machine')
	assert_true(type(chunk) == 'function', 'failed to compile watcher: ' .. tostring(load_err))
	setfenv(chunk, env)
	local run = chunk()

	assert_true(run() == nil, 'missing Profile V2 must remain on safe current state')
	assert_true(state.settings.value == 'last-known-good', 'missing file must not mutate runtime config')

	state.now = 2.2
	state.content = 'first-write'
	assert_true(run() == nil and state.apply_calls == 0, 'file creation must enter debounce')
	state.now = 3.3
	state.content = 'rapid-replacement'
	assert_true(run() == nil and state.apply_calls == 0, 'rapid replacement must restart debounce')
	state.now = 4.4
	assert_true(run().ok == true and state.apply_calls == 1, 'stable replacement must apply once')
	assert_true(state.settings.value == 'rapid-replacement', 'stable replacement must become active')
	state.now = 5.5
	assert_true(run() == nil and state.apply_calls == 1, 'unchanged content must not reapply')

	state.now = 6.6
	state.content = 'invalid'
	assert_true(run() == nil, 'invalid edit must first debounce')
	state.now = 7.7
	local invalid_result = run()
	assert_true(type(invalid_result) == 'table' and invalid_result.ok == false, 'stable invalid edit must be rejected')
	assert_true(state.settings.value == 'rapid-replacement', 'invalid edit must preserve last-known-good runtime config')
	assert_true(#state.chats == 2, 'successful apply and first invalid content should each report once')
	state.now = 8.8
	assert_true(run() == nil and #state.chats == 2, 'unchanged invalid content must not repeat the error')

	state.now = 9.9
	state.content = 'corrected'
	assert_true(run() == nil, 'corrected content must debounce independently')
	state.now = 11.0
	assert_true(run().ok == true and state.apply_calls == 3, 'corrected stable content must apply automatically')
	assert_true(state.settings.value == 'corrected', 'corrected content must replace last-known-good config')
end

local function test_manual_commands_and_legacy_isolation(addon)
	local save = source_block(addon, 'local function uc_save_active_profile', 'local function uc_reload_active_profile')
	assert_contains(save, 'uc_write_profile_v2_export', '//uc save must use the Profile V2 export writer')
	assert_contains(addon, 'uc_profile_v2.write_structured_profile_export', 'Profile V2 export writer must preserve atomic-write behavior')
	assert_not_contains(save, 'uc_write_profiles_file', '//uc save must not write legacy profiles')

	local reload = source_block(addon, 'local function uc_reload_active_profile', 'local function uc_sleep_spell_list_lines')
	assert_contains(reload, 'uc_reload_profile_v2_for_current_identity', '//uc reload must be a manual Profile V2 recovery command')
	assert_not_contains(reload, 'uc_load_profiles_for_character', '//uc reload must not read legacy profiles')

	local load_calls = 0
	for _ in addon:gmatch('uc_load_profiles_for_character%s*%(') do
		load_calls = load_calls + 1
	end
	assert_true(load_calls == 1, 'legacy profile reader may remain defined for compatibility but must have no callers')

	local write_calls = 0
	for _ in addon:gmatch('uc_write_profiles_file%s*%(') do
		write_calls = write_calls + 1
	end
	assert_true(write_calls == 1, 'legacy profile writer may remain defined for compatibility but must have no callers')
end

local function test_ui_single_authority()
	local logic = read_file('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
	local activity = read_file('UnifiedCombatWinForms/MainForm.ActivityProfiles.cs')
	local writer = read_file('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
	local constants = read_file('UnifiedCombatWinForms/HubUiConstants.cs')
	assert_contains(logic, '"active_config"', 'editor initialization must come from runtime active config')
	assert_contains(logic, 'BuildEditorProfileFromRuntimeSession', 'runtime config must be converted into the editor model')
	assert_contains(logic, 'TrySaveStructuredProfileV2FromUi(sid, profile', 'durable Save must write Profile V2')
	assert_not_contains(logic, 'TrySaveProfileFromUi(', 'durable Save must not write per-identity UI JSON')
	assert_not_contains(logic, 'TryLoadProfileForSid(', 'editor must not load per-identity UI JSON as authority')
	assert_not_contains(activity, 'BuildUiFinalPath', 'activity deployment must not create per-identity UI JSON')
	assert_not_contains(activity, 'UiDestinationPath', 'activity deployment must target Profile V2 only')
	assert_not_contains(writer, 'profile_v2_autoload', 'writer must ignore removed lifecycle keys')
	assert_not_contains(writer, 'profile_v2_auto_reload_on_change', 'writer must ignore removed lifecycle keys')
	assert_not_contains(constants, 'ProfileLifecycleUiKeys', 'lifecycle controls must be absent from the WinForms UI')
end

local function test_bridge_publishes_runtime_config()
	local bridge = read_file('remote_bridge.lua')
	assert_contains(bridge, "require('uc_active_config')", 'bridge must project the canonical active profile')
	assert_contains(bridge, 'st.active_config = active_settings', 'bridge snapshots must expose active runtime config to the editor')
	assert_contains(bridge, 'json_encode_value', 'bridge JSON must encode the nested active config')
	local encoder_source = source_block(bridge, 'local function json_escape_simple', '\n\nlocal sock = nil')
	local chunk, load_err = loadstring(encoder_source .. '\nreturn json_encode_simple', '@bridge_active_config_json')
	assert_true(type(chunk) == 'function', 'failed to compile bridge JSON encoder: ' .. tostring(load_err))
	local encode = chunk()
	local encoded = encode({
		active_config = {
			enabled = true,
			abilities = { 'Provoke', 'Warcry' },
		},
	})
	assert_contains(encoded, '"active_config":{', 'bridge must encode active config as an object')
	assert_contains(encoded, '"abilities":["Provoke","Warcry"]', 'bridge must encode active-config arrays')
	assert_contains(encoded, '"enabled":true', 'bridge must encode active-config booleans')
end

local addon = read_file('UnifiedCombat.lua')
test_automatic_identity_lifecycle(addon)
test_unconditional_watcher(addon)
test_watcher_state_machine(addon)
test_manual_commands_and_legacy_isolation(addon)
test_ui_single_authority()
test_bridge_publishes_runtime_config()

io.stdout:write('selftest_profile_v2_autoload_lifecycle: OK\n')
