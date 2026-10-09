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
	assert_true(type(chunk) == 'function', 'failed to load fixture ' .. tostring(path) .. ': ' .. tostring(err))
	local ok, payload = pcall(chunk)
	assert_true(ok == true, 'fixture execution failed for ' .. tostring(path) .. ': ' .. tostring(payload))
	assert_true(type(payload) == 'table', 'fixture must return a table: ' .. tostring(path))
	return payload
end

local function extract_source_block(source, start_marker, end_marker)
	local start_pos = source:find(start_marker, 1, true)
	assert_true(start_pos ~= nil, 'missing source block start: ' .. tostring(start_marker))
	local end_pos = source:find(end_marker, start_pos + #start_marker, true)
	assert_true(end_pos ~= nil, 'missing source block end: ' .. tostring(end_marker))
	return source:sub(start_pos, end_pos - 1)
end

local function make_fake_fs(initial_files)
	local state = {
		files = deep_clone(initial_files or {}),
		read_calls = {},
	}

	local deps = {}

	function deps.read_all(path)
		state.read_calls[#state.read_calls + 1] = path
		local content = state.files[path]
		if type(content) ~= 'string' or content == '' then
			return nil, 'missing'
		end
		return content
	end

	function deps.exists(path)
		return state.files[path] ~= nil
	end

	function deps.open(path, mode)
		local existing = state.files[path]
		local handle = {}
		local buffer = ''
		function handle:write(content)
			buffer = buffer .. tostring(content or '')
			return true
		end
		function handle:close()
			if mode == 'r' and type(existing) == 'string' then
				return true
			end
			state.files[path] = buffer
			return true
		end
		return handle
	end

	function deps.load_chunk(content, chunk_name)
		return loadstring(content, chunk_name)
	end

	function deps.execute_chunk(chunk)
		return chunk()
	end

	return deps, state
end

local function make_meta(main_job, sub_job)
	return {
		character = 'Redrogue',
		main_job = main_job,
		sub_job = sub_job,
		profile_key = 'Redrogue|' .. main_job .. '|' .. sub_job,
		addon_path = 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat',
	}
end

local function make_non_cor_payload()
	local payload = load_lua_fixture('tests/replay/fixtures/shared/ui_authored_profile_v2_fixture.lua')
	payload.profile.main_job = 'PLD'
	payload.profile.sub_job = 'WAR'
	payload.config.maintenance.cor = nil
	return payload
end

local function make_fight_leader_payload(leader_name)
	local payload = load_lua_fixture('tests/replay/fixtures/shared/ui_authored_profile_v2_fixture.lua')
	payload.profile.main_job = 'PLD'
	payload.profile.sub_job = 'WAR'
	payload.config.maintenance.cor = nil
	payload.config.follow.fight.leader = false
	payload.config.follow.fight.leader_name = leader_name
	return payload
end

local function make_cor_payload()
	local payload = load_lua_fixture('tests/replay/fixtures/shared/ui_authored_profile_v2_fixture.lua')
	payload.profile.main_job = 'COR'
	payload.profile.sub_job = 'BRD'
	payload.config.maintenance.cor = {
		roll_1 = 'Chaos Roll',
		roll_2 = 'Samurai Roll',
		crooked_roll_slot = 0,
		elevens = false,
		luzaf_range_override = false,
		range_require_ids = {},
	}
	return payload
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
		weaponskill_min_tp = 2000,
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
		defensive_na_limit_enabled = true,
		defensive_na_priority = 'Poison|Paralyze|Dia',
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
		fight_leader = true,
		fight_leader_selected = 'Niightsiide',
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
		profile_v2_autoload = true,
		profile_v2_auto_reload_on_change = true,
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

local function make_autoload_deps(payload)
	local path = 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\data\\profiles_v2\\Redrogue_COR_BRD.lua'
	local serialized = require('uc_profile_v2').serialize_structured_profile(payload)
	local deps, state = make_fake_fs({
		[path] = serialized,
	})
	state.path = path
	return deps, state
end

local function main()
	local addon = read_file('UnifiedCombat.lua')
	local parity = read_file('UnifiedCombatWinForms\\MainForm.ParityLogic.cs')
	local main_form = read_file('UnifiedCombatWinForms\\MainForm.cs')
	local bridge = read_file('remote_bridge.lua')
	local profile_v2 = require('uc_profile_v2')
	local active_config = require('uc_active_config')
	local contract = require('uc_profile_contract')
	local previous_windower = rawget(_G, 'windower')

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

	local ok, err = pcall(function()

	assert_contains(addon, 'local ok_apply, path, apply_err, apply_count = uc_apply_profile_v2_file(', 'manual profilev2 apply must use the shared apply helper')
	assert_contains(addon, 'local ok_reload, _, reload_err, reload_count = uc_apply_profile_v2_file(', 'manual profilev2 reload must use the shared apply helper')
	assert_contains(addon, 'uc_begin_profile_v2_identity_transition()', 'startup hooks must begin exact-identity resolution')
	assert_contains(addon, 'uc_run_queued_profile_v2_autoload()', 'autoload must run from the queued helper')
	assert_contains(addon, 'local function uc_run_profile_v2_auto_reload()', 'auto-reload must define its polling helper')
	assert_contains(addon, 'uc_run_profile_v2_auto_reload()', 'auto-reload must run from prerender')
	assert_contains(addon, 'local function uc_profile_v2_auto_reload_status(', 'auto-reload diagnostics must expose a status helper')
	assert_contains(addon, '//uc profilev2 autoreload status', 'auto-reload diagnostics command must be documented')
	assert_contains(addon, "_G.UC_StopUnifiedEngine('profile_identity_change')", 'identity transition must stop automation before resolution')
	assert_contains(addon, "state = 'missing'", 'identity transition must distinguish a missing Profile V2')
	assert_not_contains(extract_source_block(addon, 'local function uc_reload_active_profile(', '\n\nlocal function uc_sleep_spell_list_lines'), 'uc_load_profiles_for_character(', 'runtime reload must not read legacy profiles')
	assert_contains(addon, 'UC profile v2 autoload: applied', 'autoload success text must remain tied to post-apply zero diff')
	assert_contains(addon, 'UC profile v2 autoload: no config differences', 'autoload zero-diff success text must remain available')
	assert_contains(addon, 'UC profile v2 autoload warning: ', 'autoload warning text must remain available for nonzero diffs')

	local save_remote_block = extract_source_block(parity, '    private void SaveRemote()', '    private void ToggleEngine()')
	assert_not_contains(save_remote_block, 'TrySaveProfileFromUi(sid, profile', 'UI save must not write per-identity UI JSON')
	assert_contains(save_remote_block, 'TrySaveStructuredProfileV2FromUi(sid, profile, out var v2Error)', 'UI save must still write the v2 profile file')
	assert_contains(save_remote_block, 'SetProfileSaveStatus("Mirror: Profile V2 saved")', 'UI save must report Profile V2 success')
	assert_contains(save_remote_block, '_suppressUiSaveOutbound = true;', 'UI save must suppress outbound runtime mirroring')
	assert_contains(save_remote_block, '_suppressUiSaveOutbound = false;', 'UI save must restore outbound mirroring')
	assert_not_contains(save_remote_block, 'PushFullFormState(sid);', 'UI save must not push a runtime form-state mutation')

	local runtime_gate_block = extract_source_block(main_form, '    private static bool IsRuntimeSessionOutboundOp(string op)', '    private void Forward(string sid, Dictionary<string, object?> msg)')
	assert_contains(runtime_gate_block, 'start_engine', 'runtime gate must still allow explicit runtime engine commands')
	assert_contains(runtime_gate_block, 'stop_engine', 'runtime gate must still allow explicit runtime engine commands')
	assert_contains(runtime_gate_block, 'addon_reload', 'runtime gate must still allow explicit runtime reload commands')
	assert_contains(runtime_gate_block, 'request_state', 'runtime gate must still allow runtime state requests')
	assert_contains(runtime_gate_block, 'request_options', 'runtime gate must still allow runtime option requests')

	local forward_block = extract_source_block(main_form, '    private void Forward(string sid, Dictionary<string, object?> msg)', '    private void ApplyMirrorLine(string line)')
	assert_contains(forward_block, 'IsRuntimeSessionOutboundOp(op)', 'forward must gate live outbound traffic to runtime/session ops only')

	assert_not_contains(bridge, "op == 'save'", 'bridge must not define a save runtime op')
	assert_not_contains(bridge, 'UC_SaveActiveProfile()', 'bridge must not call the addon save helper')

	local fixture = make_non_cor_payload()
	local meta = make_meta(fixture.profile.main_job, fixture.profile.sub_job)
	local deps_missing_cor, state_missing_cor = make_fake_fs({
		[profile_v2.default_export_path(meta)] = profile_v2.serialize_structured_profile(fixture),
	})
	local active_profile, active_err = active_config.build_active_profile_from_v2_payload(fixture, meta)
	assert_true(type(active_profile) == 'table', 'structured payload should build an active profile')
	assert_nil(active_err, 'structured payload should build without error')
	assert_nil(active_profile.config.ownership.profile_v2_auto_reload_on_change, 'structured active profile must ignore the legacy auto-reload flag')

	local projected, project_err = active_config.project_flat_settings(active_profile, build_flat_settings())
	assert_true(type(projected) == 'table', 'structured payload should project into flat settings')
	assert_nil(project_err, 'structured payload should project without error')
	assert_equal(projected.puller_name, 'Niightsiide', 'puller_name must remain durable in the projected settings')
	assert_equal(projected.puller_id, 77, 'puller_name must resolve to the live runtime id when projected')
	assert_equal(projected.fight_leader_name, 'Niightsiide', 'fight leader name must remain durable in the projected settings')
	assert_equal(projected.fight_leader_id, 77, 'fight leader name must resolve to the live runtime id when projected')
	assert_equal(projected.fight_leader_selected, 'Niightsiide', 'fight leader selected name must be projected for the UI')
	assert_equal(projected.follow.fight.leader_name, 'Niightsiide', 'nested fight leader name must remain durable in the projected settings')
	assert_equal(projected.follow.fight.leader_id, 77, 'nested fight leader id must resolve to the live runtime id when projected')
	assert_equal(projected.follow.fight.leader_selected, 'Niightsiide', 'nested fight leader selected name must be projected for the UI')
	assert_equal(projected.targets[1], 'Apex Bat', 'add priority targets must remain durable in the projected settings')
	assert_equal(projected.add_priority_names[1], 'Apex Bat', 'add priority compatibility names must be projected for runtime consumers')
	assert_equal(projected.follow.party.leader_name, 'Leader', 'party follow leader name must remain durable in the projected settings')
	assert_equal(projected.wait_ignore_names[1], 'Ally One', 'wait ignore names must remain durable in the projected settings')
	assert_equal(projected.ignore[1], nil, 'wait ignore names should not invent runtime ids when they are not resolvable')
	assert_nil(projected.profile_v2_auto_reload_on_change, 'legacy auto-reload flag must not project into runtime settings')
	assert_equal(projected.aftermath_ws, 'Atonement', 'weaponskill aftermath ws must round-trip')
	assert_equal(projected.weaponskill_min_tp, 2000, 'weaponskill minimum TP must round-trip')
	assert_equal(projected.defensive_overwrite_interval, 150, 'defensive overwrite interval must round-trip')
	assert_equal(projected.defensive_critical_hpp, 35, 'defensive critical threshold must round-trip')
	assert_equal(projected.defensive_medium_hpp, 55, 'defensive medium threshold must round-trip')
	assert_equal(projected.defensive_na_limit_enabled, true, 'status-removal limit must round-trip')
	assert_equal(projected.defensive_na_priority, 'Poison|Paralyze|Dia', 'status-removal priority must round-trip')
	assert_equal(projected.defensive_targeted_buffs, 'Terrasjr:Honor March|Nyoourke:Valor Minuet V', 'targeted defensive buffs must round-trip')

	local enabled_mismatch_payload = make_fight_leader_payload('Terrasjr')
	enabled_mismatch_payload.config.follow.fight.leader = true
	local enabled_mismatch_meta = make_meta(enabled_mismatch_payload.profile.main_job, enabled_mismatch_payload.profile.sub_job)
	local enabled_mismatch_path = profile_v2.default_export_path(enabled_mismatch_meta)
	local enabled_mismatch_deps = make_fake_fs({
		[enabled_mismatch_path] = profile_v2.serialize_structured_profile(enabled_mismatch_payload),
	})
	local enabled_mismatch_status = profile_v2.inspect_structured_profile_status(deep_clone(projected), enabled_mismatch_meta, contract.validate_structured_profile_config, enabled_mismatch_deps)
	assert_true(enabled_mismatch_status.valid == true, 'enabled fight leader mismatch case must validate')
	assert_true(enabled_mismatch_status.diff_count > 0, 'enabled fight leader mismatch case must report a real difference')
	assert_equal(enabled_mismatch_status.first_difference.path, 'config.follow.fight.leader_name', 'enabled fight leader mismatch path mismatch')

	local base_settings = build_flat_settings()
	local non_cor_apply = profile_v2.apply_structured_profile_file_to_settings(deep_clone(base_settings), meta, contract.validate_structured_profile_config, deps_missing_cor)
	assert_true(type(non_cor_apply) == 'table' and non_cor_apply.ok == true, 'non-COR profile must apply cleanly before drift checks')
	local non_cor_current = non_cor_apply.candidate_config
	assert_true(type(non_cor_current) == 'table', 'non-COR apply must return canonical current config')
	assert_true(non_cor_apply.candidate == nil, 'non-COR apply must not build a flat settings candidate')
	local disabled_settings = deep_clone(non_cor_current)
	if type(disabled_settings.follow) == 'table' and type(disabled_settings.follow.fight) == 'table' then
		disabled_settings.follow.fight.leader = false
		disabled_settings.follow.fight.leader_name = 'Terrasjr'
	end
	local disabled_cases = {
		{
			label = 'omitted',
			payload = make_fight_leader_payload(nil),
		},
		{
			label = 'empty',
			payload = make_fight_leader_payload(''),
		},
		{
			label = 'stale',
			payload = make_fight_leader_payload('Terrasjr'),
		},
	}
	for i = 1, #disabled_cases do
		local case = disabled_cases[i]
		local case_meta = make_meta(case.payload.profile.main_job, case.payload.profile.sub_job)
		local case_path = profile_v2.default_export_path(case_meta)
		local case_deps = make_fake_fs({
			[case_path] = profile_v2.serialize_structured_profile(case.payload),
		})
		local case_status = profile_v2.inspect_structured_profile_status_against_config(disabled_settings, case_meta, contract.validate_structured_profile_config, case_deps)
		assert_true(case_status.valid == true, 'disabled fight leader ' .. case.label .. ' case must validate')
		assert_equal(case_status.diff_count, 0, 'disabled fight leader ' .. case.label .. ' case must report zero differences')
		assert_equal(case_status.reason, 'runtime matches file', 'disabled fight leader ' .. case.label .. ' case reason mismatch')
		local case_apply = profile_v2.apply_structured_profile_file_to_active_config(deep_clone(disabled_settings), case_meta, contract.validate_structured_profile_config, case_deps)
		assert_true(case_apply.ok == true, 'disabled fight leader ' .. case.label .. ' case must apply cleanly')
		assert_equal(case_apply.count, 0, 'disabled fight leader ' .. case.label .. ' case must apply with zero diffs')
		local case_autoload = profile_v2.autoload_structured_profile_file_to_settings(deep_clone(disabled_settings), case_meta, contract.validate_structured_profile_config, case_deps)
		assert_true(type(case_autoload) == 'table' and case_autoload.ok == true, 'disabled fight leader ' .. case.label .. ' case must autoload cleanly')
		assert_equal(case_autoload.count, 0, 'disabled fight leader ' .. case.label .. ' case must autoload with zero diffs')
	end

	local unset_puller_payload = deep_clone(fixture)
	unset_puller_payload.config.follow.partner.puller = false
	unset_puller_payload.config.follow.partner.puller_name = nil
	local unset_puller_meta = make_meta(unset_puller_payload.profile.main_job, unset_puller_payload.profile.sub_job)
	local unset_puller_path = profile_v2.default_export_path(unset_puller_meta)
	local unset_puller_deps = make_fake_fs({
		[unset_puller_path] = profile_v2.serialize_structured_profile(unset_puller_payload),
	})
	local unset_puller_settings = deep_clone(non_cor_current)
	if type(unset_puller_settings.follow) == 'table' and type(unset_puller_settings.follow.partner) == 'table' then
		unset_puller_settings.follow.partner.puller = false
		unset_puller_settings.follow.partner.puller_name = nil
	end
	assert_nil(unset_puller_settings.follow.partner.puller_name, 'blank puller name must be omitted from durable config')
	local unset_puller_status = profile_v2.inspect_structured_profile_status_against_config(unset_puller_settings, unset_puller_meta, contract.validate_structured_profile_config, unset_puller_deps)
	assert_true(unset_puller_status.valid == true, 'omitted puller name profile must validate')
	assert_equal(unset_puller_status.diff_count, 0, 'omitted puller name profile must report zero differences')
	local unset_puller_apply = profile_v2.apply_structured_profile_file_to_active_config(deep_clone(unset_puller_settings), unset_puller_meta, contract.validate_structured_profile_config, unset_puller_deps)
	assert_true(unset_puller_apply.ok == true, 'omitted puller name profile must apply cleanly')
	assert_equal(unset_puller_apply.count, 0, 'omitted puller name profile must apply with zero diffs')
	local unset_puller_autoload = profile_v2.autoload_structured_profile_file_to_settings(deep_clone(unset_puller_settings), unset_puller_meta, contract.validate_structured_profile_config, unset_puller_deps)
	assert_true(type(unset_puller_autoload) == 'table' and unset_puller_autoload.ok == true, 'omitted puller name profile must autoload cleanly')
	assert_equal(unset_puller_autoload.count, 0, 'omitted puller name profile must autoload with zero diffs')

	local runtime_only = deep_clone(projected)
	runtime_only.engine_enabled = true
	runtime_only.party_follow_id = 101
	runtime_only.fight_leader_id = 202
	runtime_only.puller_id = 303
	runtime_only.path_file_name = 'different-route'
	local runtime_status = profile_v2.inspect_structured_profile_status(runtime_only, meta, contract.validate_structured_profile_config, deps_missing_cor)
	assert_true(runtime_status.valid == true, 'runtime-owned mirrors must not invalidate the structured profile')
	assert_equal(runtime_status.diff_count, 0, 'runtime-owned mirrors must stay out of durable drift')

	local validate_missing_cor = contract.validate_structured_profile_config(fixture)
	assert_true(validate_missing_cor.ok == true, 'non-COR profile missing maintenance.cor must validate')
	local status_missing_cor = profile_v2.inspect_structured_profile_status_against_config(non_cor_current, meta, contract.validate_structured_profile_config, deps_missing_cor)
	assert_true(status_missing_cor.valid == true, 'non-COR status with missing maintenance.cor must validate')
	assert_equal(status_missing_cor.diff_count, 0, 'non-COR status with missing maintenance.cor must be clean')
	assert_equal(status_missing_cor.reason, 'runtime matches file', 'non-COR status with missing maintenance.cor reason mismatch')
	local apply_missing_cor = profile_v2.apply_structured_profile_file_to_active_config(deep_clone(non_cor_current), meta, contract.validate_structured_profile_config, deps_missing_cor)
	assert_true(apply_missing_cor.ok == true, 'non-COR apply with missing maintenance.cor must succeed')
	assert_equal(apply_missing_cor.count, 0, 'non-COR apply with missing maintenance.cor must report zero diffs')
	local autoload_missing_cor = profile_v2.autoload_structured_profile_file_to_settings(deep_clone(non_cor_current), meta, contract.validate_structured_profile_config, deps_missing_cor)
	assert_true(type(autoload_missing_cor) == 'table' and autoload_missing_cor.ok == true, 'non-COR autoload with missing maintenance.cor must succeed')
	assert_equal(autoload_missing_cor.count, 0, 'non-COR autoload with missing maintenance.cor must report zero diffs')
	assert_true(#state_missing_cor.read_calls >= 2, 'non-COR profile must validate and apply the expected file path')
	assert_equal(state_missing_cor.read_calls[1], profile_v2.default_export_path(meta), 'non-COR profile must read the expected file path')

	local empty_brd_payload = deep_clone(fixture)
	empty_brd_payload.profile.main_job = 'BRD'
	empty_brd_payload.profile.sub_job = 'WHM'
	empty_brd_payload.config.maintenance.brd = {}
	local empty_brd_meta = make_meta('BRD', 'WHM')
	local empty_brd_deps = make_fake_fs({
		[profile_v2.default_export_path(empty_brd_meta)] = profile_v2.serialize_structured_profile(empty_brd_payload),
	})
	local empty_brd_apply = profile_v2.apply_structured_profile_file_to_settings(build_flat_settings(), empty_brd_meta, contract.validate_structured_profile_config, empty_brd_deps)
	assert_true(type(empty_brd_apply) == 'table' and empty_brd_apply.ok == true, 'legacy empty BRD maintenance section must apply cleanly')
	local empty_brd_status = profile_v2.inspect_structured_profile_status_against_config(empty_brd_apply.candidate_config, empty_brd_meta, contract.validate_structured_profile_config, empty_brd_deps)
	assert_true(empty_brd_status.valid == true, 'legacy empty BRD maintenance section must remain valid after apply')
	assert_equal(empty_brd_status.diff_count, 0, 'legacy empty BRD maintenance section must match the post-apply runtime')
	local empty_brd_autoload = profile_v2.autoload_structured_profile_file_to_settings(build_flat_settings(), empty_brd_meta, contract.validate_structured_profile_config, empty_brd_deps)
	assert_true(type(empty_brd_autoload) == 'table' and empty_brd_autoload.ok == true, 'legacy empty BRD maintenance section must autoload cleanly')

	local legacy_enabled_brd_payload = deep_clone(fixture)
	legacy_enabled_brd_payload.profile.main_job = 'BRD'
	legacy_enabled_brd_payload.profile.sub_job = 'WHM'
	legacy_enabled_brd_payload.config.maintenance.brd = {
		enabled = true,
		songs = { 'Honor March', 'Victory March' },
		dummy_songs = {},
		use_nitro = false,
		use_clarion_call = false,
		use_marcato = false,
		marcato_song = '',
	}
	local legacy_enabled_brd_deps = make_fake_fs({
		[profile_v2.default_export_path(empty_brd_meta)] = profile_v2.serialize_structured_profile(legacy_enabled_brd_payload),
	})
	local legacy_enabled_brd_apply = profile_v2.apply_structured_profile_file_to_settings(build_flat_settings(), empty_brd_meta, contract.validate_structured_profile_config, legacy_enabled_brd_deps)
	assert_true(type(legacy_enabled_brd_apply) == 'table' and legacy_enabled_brd_apply.ok == true, 'legacy enabled BRD maintenance must tolerate newly added optional durable fields')
	assert_equal(legacy_enabled_brd_apply.candidate_config.maintenance.brd.recovery_range_yalms, 9.9, 'legacy enabled BRD maintenance must receive the recovery range migration default')

	local cor_payload = make_cor_payload()
	local cor_meta = make_meta(cor_payload.profile.main_job, cor_payload.profile.sub_job)
	local cor_active, cor_err = active_config.build_active_profile_from_v2_payload(cor_payload, cor_meta)
	assert_true(type(cor_active) == 'table', 'COR payload should build an active profile')
	assert_nil(cor_err, 'COR payload should build without error')
	local cor_base_settings = build_flat_settings()
	cor_base_settings.main_job = 'COR'
	cor_base_settings.sub_job = 'BRD'
	local cor_projected, cor_project_err = active_config.project_flat_settings(cor_active, cor_base_settings)
	assert_true(type(cor_projected) == 'table', 'COR payload should project into flat settings')
	assert_nil(cor_project_err, 'COR payload should project without error')
	assert_equal(cor_projected.cor_roll_1, 'Chaos Roll', 'COR roll 1 must remain durable')
	assert_equal(cor_projected.cor_roll_2, 'Samurai Roll', 'COR roll 2 must remain durable')
	assert_equal(cor_projected.puller_name, 'Niightsiide', 'durable puller name must remain present for COR profiles too')
	assert_equal(cor_projected.aftermath_ws, 'Atonement', 'combat aftermath ws must remain durable')
	assert_equal(cor_projected.defensive_overwrite_interval, 150, 'defensive overwrite interval must remain durable for COR profiles')
	assert_equal(cor_projected.defensive_targeted_buffs, 'Terrasjr:Honor March|Nyoourke:Valor Minuet V', 'BRD targeted buffs must remain durable for COR profiles')

	end)
	rawset(_G, 'windower', previous_windower)
	if not ok then
		error(err)
	end

	io.stdout:write('selftest_profile_v2_source_of_truth_contract: OK\n')
end

main()
