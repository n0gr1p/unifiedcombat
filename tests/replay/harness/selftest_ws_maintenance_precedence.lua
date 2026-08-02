local TEST_MODULE_NAMES = {
	'socket',
	'resources',
	'skills',
	'uc_ws_gate',
	'uc_ws_memory',
	'uc_ignore',
	'uc_target_ignore',
	'uc_partner_list',
	'uc_fight_leader',
	'uc_add_control',
	'uc_targeting_common',
	'uc_settarget',
	'uc_attack',
	'uc_path_hunter',
	'uc_camp_anchor',
	'uc_ability_pipeline',
	'unified_combat_core',
}
local saved_modules = {}
for _, module_name in ipairs(TEST_MODULE_NAMES) do
	saved_modules[module_name] = package.loaded[module_name]
end
local saved_socket = rawget(_G, 'socket')
local saved_windower = rawget(_G, 'windower')

package.loaded['socket'] = {
	gettime = function()
		return os.clock()
	end,
}
_G.socket = package.loaded['socket']

local function make_resource_list(rows)
	local list = rows or {}
	function list:with(field, value)
		for _, row in pairs(self) do
			if type(row) == 'table' and row[field] == value then
				return row
			end
		end
		return nil
	end
	return list
end

package.loaded['resources'] = {
	weapon_skills = make_resource_list({
		[10] = { id = 10, en = 'Test Continuation' },
	}),
	job_abilities = make_resource_list({
		[20] = { id = 20, en = 'Chivalry', recast_id = 20, targets = '{Self}' },
	}),
	spells = make_resource_list({}),
	buffs = {},
	items = {},
	monster_abilities = {},
}
package.loaded['skills'] = {
	weapon_skills = {
		[10] = { skillchain = { 'Transfixion' } },
	},
}
package.loaded['uc_ws_gate'] = {}
package.loaded['uc_ws_memory'] = {
	valid_ws_name = function(name)
		return name == 'Savage Blade'
			or name == 'Knights of Round'
			or name == 'Test Continuation'
	end,
}
package.loaded['uc_ignore'] = {
	is_name_blocked = function()
		return false
	end,
}
package.loaded['uc_target_ignore'] = {
	is_mob_blocked = function()
		return false
	end,
}
package.loaded['uc_partner_list'] = {
	as_ordered_ids = function()
		return {}
	end,
}
package.loaded['uc_fight_leader'] = {
	resolve_mid_override = function()
		return 0
	end,
}
package.loaded['uc_add_control'] = {
	enabled = function()
		return false
	end,
	pick = function()
		return 0
	end,
}
package.loaded['uc_targeting_common'] = {
	build_party_claims = function()
		return {}, {}
	end,
}
package.loaded['uc_settarget'] = {
	select_by_id = function()
		return true
	end,
}
package.loaded['uc_attack'] = {
	switch_target = function()
		return true
	end,
	engage_target = function()
		return true
	end,
}
package.loaded['uc_path_hunter'] = {
	matches_mob = function()
		return false
	end,
}
package.loaded['uc_camp_anchor'] = {
	resolve_current_anchor = function()
		return nil, 'CAMP_UNSET'
	end,
}
package.loaded['uc_ability_pipeline'] = nil
package.loaded['unified_combat_core'] = nil

local player = {
	id = 101,
	name = 'Terrasjr',
	status = 1,
	buffs = {},
	vitals = {
		tp = 1000,
		mp = 0,
		max_mp = 100,
	},
}
local ability_recasts = { [20] = 0 }
local dispatch_target = nil
local send_command_count = 0

windower = {
	addon_path = '',
	register_event = function()
	end,
	send_ipc_message = function()
	end,
	dir_exists = function()
		return true
	end,
	create_dir = function()
	end,
	send_command = function()
		send_command_count = send_command_count + 1
	end,
	ffxi = {
		get_player = function()
			return player
		end,
		get_abilities = function()
			return {
				job_abilities = { 20 },
				weapon_skills = { 10 },
			}
		end,
		get_ability_recasts = function()
			return ability_recasts
		end,
		get_items = function(bag, index)
			if bag == 'equipment' then
				return {
					main_bag = 0,
					main = 1,
					sub_bag = 0,
					sub = 2,
					range_bag = 0,
					range = 3,
				}
			end
			if bag == 0 and index then
				return { id = 0 }
			end
			error('unexpected get_items request')
		end,
		get_party = function()
			return {}
		end,
		get_mob_by_target = function()
			return nil
		end,
		get_mob_by_id = function(id)
			if dispatch_target and dispatch_target.id == id then
				return dispatch_target
			end
			return nil
		end,
		get_mob_by_index = function()
			return nil
		end,
		get_mob_array = function()
			return {}
		end,
		get_info = function()
			return { zone = 0 }
		end,
		run = function()
			return true
		end,
	},
}

local core = dofile('unified_combat_core.lua')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function install_active_resonance()
	local now = os.clock()
	core.resonating[9001] = {
		target_id = 9001,
		generation = 1,
		active_properties = { 'Compression' },
		chainbound_level = 0,
		source_action_id = 1,
		source_actor_id = 202,
		action_count = 1,
		earliest_close_at = now - 1,
		preferred_execute_at = now - 0.5,
		expires_at = now + 5,
		terminal = false,
		actor_expiry_overrides = {},
	}
end

local settings = {
	ability_active = true,
	abilities = { 'Chivalry' },
	weaponskill = 'Savage Blade',
	ws_mode = 'smart',
	weaponskill_min_tp = 1000,
	spam = false,
	solo = false,
	aftermath_enabled = false,
	aftermath_ws = 'Knights of Round',
}

local function select()
	install_active_resonance()
	return core.select_ws_plan_for_scheduler(settings, 9001)
end

local function test_chivalry_reserves_tp_across_ready_boundary()
	ability_recasts[20] = 0
	player.buffs = {}
	player.vitals.mp = 0
	player.vitals.tp = 1500
	local selection, reason = select()
	assert_equal(selection, nil, 'active resonance must not spend Chivalry-reserved TP')
	assert_equal(reason, 'CHIVALRY_HOLD_TP', 'Chivalry TP hold reason mismatch')

	player.vitals.tp = 2000
	selection, reason = select()
	assert_equal(selection, nil, 'ready Chivalry must suppress competing WS proposals')
	assert_equal(reason, 'CHIVALRY_READY', 'Chivalry ready reason mismatch')
end

local function test_aftermath_reserves_tp_and_dispatches_before_continuation()
	ability_recasts[20] = 30
	settings.weaponskill_min_tp = 2000
	settings.aftermath_enabled = true
	player.buffs = {}
	player.vitals.tp = 2500
	local selection, reason = select()
	assert_equal(selection, nil, 'active resonance must not spend aftermath-reserved TP')
	assert_equal(reason, 'AM_HOLD_TP', 'aftermath TP hold reason mismatch')

	player.vitals.tp = 3000
	selection, reason = select()
	assert_true(type(selection) == 'table', 'ready aftermath must produce a WS selection')
	assert_equal(reason, 'AM_READY', 'aftermath ready reason mismatch')
	assert_equal(selection.ws_name, 'Knights of Round', 'aftermath WS mismatch')
	assert_equal(selection.skillchain_plan, nil, 'aftermath maintenance must not be mislabeled as a continuation')
	assert_equal(selection.required_tp, 3000, 'aftermath dispatch requirement must remain 3000 TP')
	settings.weaponskill_min_tp = 1000
end

local function test_satisfied_maintenance_applies_minimum_tp_to_continuation()
	ability_recasts[20] = 30
	settings.weaponskill_min_tp = 2000
	settings.aftermath_enabled = true
	player.buffs = { 273 }
	player.vitals.tp = 1000
	local selection, reason = select()
	assert_equal(selection, nil, 'continuation must hold below configured minimum TP')
	assert_equal(reason, 'WS_MIN_TP_HOLD', 'continuation minimum TP hold reason mismatch')

	player.vitals.tp = 2000
	selection, reason = select()
	assert_true(type(selection) == 'table', 'satisfied maintenance must allow a continuation at configured minimum TP')
	assert_equal(reason, 'SC_READY', 'continuation reason mismatch after maintenance is satisfied')
	assert_true(type(selection.skillchain_plan) == 'table', 'continuation plan must remain structured')
	assert_equal(selection.ws_name, 'Test Continuation', 'continuation WS mismatch')
	assert_equal(selection.required_tp, 2000, 'continuation dispatch requirement must use configured minimum TP')
	settings.weaponskill_min_tp = 1000
end

local function test_ordinary_smart_ws_observes_minimum_tp()
	ability_recasts[20] = 30
	settings.ws_mode = 'smart'
	settings.spam = false
	settings.aftermath_enabled = false
	settings.weaponskill_min_tp = 2000
	player.buffs = {}
	core.resonating[9001] = nil
	player.vitals.tp = 1999
	local selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_equal(selection, nil, 'ordinary smart WS must hold below configured minimum TP')
	assert_equal(reason, 'WS_MIN_TP_HOLD', 'ordinary smart WS minimum TP hold reason mismatch')

	player.vitals.tp = 2000
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table', 'ordinary smart WS must select at configured minimum TP')
	assert_equal(reason, 'READY', 'ordinary smart WS ready reason mismatch')
	assert_equal(selection.required_tp, 2000, 'ordinary smart WS dispatch requirement mismatch')
	settings.weaponskill_min_tp = 1000
end

local function test_primary_only_ws_retains_base_tp_requirement()
	ability_recasts[20] = 30
	settings.ws_mode = 'primary_no_sc'
	settings.spam = false
	settings.aftermath_enabled = false
	settings.weaponskill_min_tp = 2000
	player.buffs = {}
	core.resonating[9001] = nil
	player.vitals.tp = 1000
	local selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table', 'primary-only WS must retain its existing 1000 TP eligibility')
	assert_equal(reason, 'WS_MODE_PRIMARY_ONLY_READY', 'primary-only WS ready reason mismatch')
	assert_equal(selection.required_tp, 1000, 'primary-only WS dispatch requirement must remain 1000 TP')
	settings.ws_mode = 'smart'
	settings.weaponskill_min_tp = 1000
end

local function test_aftermath_precedes_spam_until_buff_active()
	ability_recasts[20] = 30
	settings.spam = true
	settings.aftermath_enabled = true
	player.buffs = {}
	player.vitals.tp = 2500
	local selection, reason = select()
	assert_equal(selection, nil, 'spam must not spend aftermath-reserved TP')
	assert_equal(reason, 'AM_HOLD_TP', 'spam aftermath TP hold reason mismatch')

	player.vitals.tp = 3000
	selection, reason = select()
	assert_true(type(selection) == 'table', 'ready aftermath must take priority over spam')
	assert_equal(reason, 'AM_READY', 'spam aftermath ready reason mismatch')
	assert_equal(selection.ws_name, 'Knights of Round', 'spam aftermath WS mismatch')
	assert_equal(selection.skillchain_plan, nil, 'spam aftermath WS must not carry a skillchain plan')

	player.buffs = { 273 }
	player.vitals.tp = 1000
	selection, reason = select()
	assert_true(type(selection) == 'table', 'satisfied aftermath must restore spam selection')
	assert_equal(reason, 'READY_SPAM', 'spam must resume after aftermath is active')
	assert_equal(selection.ws_name, 'Savage Blade', 'restored spam must use the primary WS')
	assert_equal(selection.skillchain_plan, nil, 'restored spam WS must not carry a skillchain plan')
	settings.spam = false
end

local function test_spam_forces_primary_ws_across_active_resonance()
	ability_recasts[20] = 30
	settings.spam = true
	settings.aftermath_enabled = false
	player.buffs = {}
	player.vitals.tp = 1000
	local selection, reason = select()
	assert_true(type(selection) == 'table', 'spam must produce a primary WS selection')
	assert_equal(reason, 'READY_SPAM', 'spam primary WS reason mismatch')
	assert_equal(selection.ws_name, 'Savage Blade', 'spam must not select a skillchain continuation WS')
	assert_equal(selection.skillchain_plan, nil, 'spam primary WS must not carry a skillchain plan')
	settings.spam = false
end

local function test_spam_ws_observes_minimum_tp()
	ability_recasts[20] = 30
	settings.spam = true
	settings.aftermath_enabled = false
	settings.weaponskill_min_tp = 2000
	player.buffs = {}
	player.vitals.tp = 1999
	local selection, reason = select()
	assert_equal(selection, nil, 'spam WS must hold below configured minimum TP')
	assert_equal(reason, 'WS_MIN_TP_HOLD', 'spam WS minimum TP hold reason mismatch')

	player.vitals.tp = 2000
	selection, reason = select()
	assert_true(type(selection) == 'table', 'spam WS must select at configured minimum TP')
	assert_equal(reason, 'READY_SPAM', 'spam WS ready reason mismatch at configured minimum TP')
	assert_equal(selection.required_tp, 2000, 'spam WS dispatch requirement mismatch')
	settings.spam = false
	settings.weaponskill_min_tp = 1000
end

local function test_spam_ws_dispatch_rejects_out_of_range_target()
	dispatch_target = {
		id = 9001,
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		distance = {
			sqrt = function()
				return 5.51
			end,
		},
	}
	send_command_count = 0
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, {
		spam = true,
	}, nil)
	assert_equal(sent, false, 'spam WS dispatch must fail outside the WS range boundary')
	assert_equal(reason, 'WS_OUT_OF_RANGE', 'out-of-range WS dispatch reason mismatch')
	assert_equal(send_command_count, 0, 'out-of-range WS dispatch must not send a command')
	dispatch_target = nil
end

local function restore_test_environment()
	for _, module_name in ipairs(TEST_MODULE_NAMES) do
		package.loaded[module_name] = saved_modules[module_name]
	end
	_G.socket = saved_socket
	_G.windower = saved_windower
end

local function main()
	local ok, err = pcall(function()
	test_chivalry_reserves_tp_across_ready_boundary()
	test_aftermath_reserves_tp_and_dispatches_before_continuation()
	test_satisfied_maintenance_applies_minimum_tp_to_continuation()
	test_ordinary_smart_ws_observes_minimum_tp()
	test_primary_only_ws_retains_base_tp_requirement()
	test_aftermath_precedes_spam_until_buff_active()
	test_spam_forces_primary_ws_across_active_resonance()
	test_spam_ws_observes_minimum_tp()
	test_spam_ws_dispatch_rejects_out_of_range_target()
	end)
	restore_test_environment()
	if not ok then
		error(err, 0)
	end
	io.stdout:write('selftest_ws_maintenance_precedence: OK\n')
end

main()
