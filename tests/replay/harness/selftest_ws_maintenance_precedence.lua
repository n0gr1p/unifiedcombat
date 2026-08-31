local TEST_MODULE_NAMES = {
	'socket',
	'resources',
	'skills',
	'uc_ws_gate',
	'uc_ws_memory',
	'uc_ws_selector',
	'data/ws_progression',
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

local actual_skills = dofile('skills.lua')
local function actual_ws_by_name(name)
	for _, skill in pairs(actual_skills.weapon_skills) do
		if skill.en == name then
			return skill
		end
	end
	return nil
end

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
		[10] = { id = 10, en = 'Test Single Continuation' },
		[11] = { id = 11, en = 'Test AoE Continuation' },
		[30] = { id = 30, en = 'Aeolian Edge' },
		[42] = { id = 42, en = 'Savage Blade' },
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
		[11] = { skillchain = { 'Transfixion' }, aoe = true },
		[30] = { aoe = true },
		[42] = {},
	},
}
package.loaded['uc_ws_gate'] = {}
package.loaded['uc_ws_memory'] = {
	valid_ws_name = function(name)
		return name == 'Savage Blade'
			or name == 'Knights of Round'
			or name == 'Aeolian Edge'
			or name == 'Test Single Continuation'
			or name == 'Test AoE Continuation'
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
local ipc_messages = {}
local learned_weapon_skills = { 10, 11, 30, 42 }

windower = {
	addon_path = '',
	register_event = function()
	end,
	send_ipc_message = function(message)
		ipc_messages[#ipc_messages + 1] = message
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
				weapon_skills = learned_weapon_skills,
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

local native_dofile = dofile
dofile = function(path)
	if tostring(path) == 'docs/aftermath_table.lua' then
		return {
			get_weapon_by_ws = function(ws_name)
				if ws_name ~= 'Knights of Round' and ws_name ~= 'Aeolian Edge' then
					return nil, nil
				end
				return 'Test Weapon', {
					minimum_aftermath_stage = 3,
					aftermath = {
						tp = {
							[3] = { buff_id = 273 },
						},
					},
				}
			end,
		}
	end
	return native_dofile(path)
end
local core = dofile('unified_combat_core.lua')
dofile = native_dofile

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_false(value, message)
	assert_equal(value, false, message)
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
	weaponskill_allow_aoe = true,
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
	assert_equal(selection.ws_name, 'Test Single Continuation', 'equal-rank continuation must use stable lower resource ID')
	assert_equal(selection.required_tp, 2000, 'continuation dispatch requirement must use configured minimum TP')
	settings.weaponskill_min_tp = 1000
end

local function test_aoe_metadata_classification()
	for _, name in ipairs({
		'Spinning Attack',
		'Cyclone',
		'Aeolian Edge',
		'Circle Blade',
		'Shockwave',
		'Fell Cleave',
		'Spinning Scythe',
		'Sonic Thrust',
		'Earth Crusher',
		'Cataclysm',
		'Glory Slash',
		'Uriel Blade',
	}) do
		local skill = actual_ws_by_name(name)
		assert_true(type(skill) == 'table', name .. ' metadata entry must exist')
		assert_equal(skill.aoe, true, name .. ' must be classified as AoE')
	end
	for _, name in ipairs({ 'Savage Blade', 'Tachi: Fudo', 'Shijin Spiral', 'Victory Smite' }) do
		local skill = actual_ws_by_name(name)
		assert_true(type(skill) == 'table', name .. ' metadata entry must exist')
		assert_true(skill.aoe ~= true, name .. ' must remain non-AoE')
	end
end

local function test_smart_continuation_candidate_filtering()
	ability_recasts[20] = 30
	settings.ws_mode = 'smart'
	settings.spam = false
	settings.solo = false
	settings.aftermath_enabled = false
	settings.weaponskill_min_tp = 1000
	player.buffs = {}
	player.vitals.tp = 1000
	learned_weapon_skills = { 10, 11, 30, 42 }

	settings.weaponskill_allow_aoe = true
	local selection, reason = select()
	assert_true(type(selection) == 'table', 'AoE-enabled Smart mode must retain continuation candidates')
	assert_equal(reason, 'SC_READY', 'AoE-enabled continuation reason mismatch')
	assert_equal(selection.ws_name, 'Test Single Continuation', 'AoE-enabled equal-rank candidates must use stable lower resource ID')

	settings.weaponskill_allow_aoe = false
	selection, reason = select()
	assert_true(type(selection) == 'table', 'single-target continuation must remain available when AoE is disabled')
	assert_equal(reason, 'SC_READY', 'single-target continuation reason mismatch')
	assert_equal(selection.ws_name, 'Test Single Continuation', 'AoE continuation must be filtered before planning')

	learned_weapon_skills = { 11 }
	selection, reason = select()
	assert_equal(selection, nil, 'AoE-only continuation set must not produce a Smart WS selection')
	assert_equal(reason, 'SC_NO_CONTINUATION', 'AoE-only continuation set must hold with the planner reason')

	learned_weapon_skills = { 10, 11, 30, 42 }
	settings.weaponskill_allow_aoe = true
end

local function test_smart_primary_and_aftermath_aoe_restriction()
	ability_recasts[20] = 30
	settings.ws_mode = 'smart'
	settings.spam = false
	settings.solo = false
	settings.aftermath_enabled = false
	settings.weaponskill_min_tp = 1000
	settings.weaponskill_allow_aoe = false
	player.buffs = {}
	player.vitals.tp = 1000
	core.resonating[9001] = nil

	settings.weaponskill = 'Aeolian Edge'
	local selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_equal(selection, nil, 'Smart AoE primary must not produce a proposal when disabled')
	assert_equal(reason, 'PRIMARY_WS_AOE_BLOCKED', 'Smart AoE primary block reason mismatch')

	settings.weaponskill = 'Savage Blade'
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table', 'Smart single-target primary must remain selectable')
	assert_equal(reason, 'READY', 'Smart single-target primary reason mismatch')
	assert_equal(selection.ws_name, 'Savage Blade', 'Smart mode without active resonance must use configured primary WS')
	assert_equal(selection.smart_aoe_guard, true, 'normal Smart proposals must carry the commit guard')

	settings.weaponskill_allow_aoe = true
	settings.weaponskill = 'Aeolian Edge'
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table', 'AoE-enabled Smart primary must retain existing READY behavior')
	assert_equal(reason, 'READY', 'AoE-enabled Smart primary reason mismatch')

	settings.weaponskill_allow_aoe = false
	settings.weaponskill = 'Savage Blade'
	settings.aftermath_enabled = true
	settings.aftermath_ws = 'Aeolian Edge'
	player.vitals.tp = 3000
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_equal(selection, nil, 'Smart aftermath maintenance must not select an AoE WS when disabled')
	assert_equal(reason, 'AFTERMATH_WS_AOE_BLOCKED', 'Smart aftermath AoE block reason mismatch')

	settings.aftermath_enabled = false
	settings.weaponskill_allow_aoe = true
	player.vitals.tp = 1000
end

local function test_aoe_restriction_scope_and_revalidation()
	ability_recasts[20] = 30
	settings.weaponskill = 'Aeolian Edge'
	settings.weaponskill_allow_aoe = false
	settings.aftermath_enabled = false
	settings.weaponskill_min_tp = 1000
	player.vitals.tp = 1000
	core.resonating[9001] = nil

	settings.ws_mode = 'primary_no_sc'
	settings.spam = false
	local selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table', 'primary_no_sc must remain outside the Smart AoE restriction')
	assert_equal(reason, 'WS_MODE_PRIMARY_ONLY_READY', 'primary_no_sc scope reason mismatch')
	assert_equal(selection.smart_aoe_guard, false, 'primary_no_sc proposal must not carry the Smart guard')

	settings.ws_mode = 'smart'
	settings.spam = true
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table', 'spam must remain outside the Smart AoE restriction')
	assert_equal(reason, 'READY_SPAM', 'spam scope reason mismatch')
	assert_equal(selection.smart_aoe_guard, false, 'spam proposal must not carry the Smart guard')

	local allowed, block_reason = core.revalidate_smart_ws_aoe(settings, 'Aeolian Edge')
	assert_equal(allowed, false, 'Smart AoE commit helper must reject a newly disabled AoE WS')
	assert_equal(block_reason, 'SMART_WS_AOE_BLOCKED', 'Smart AoE commit reason mismatch')
	allowed, block_reason = core.revalidate_skillchain_plan({ ws_id = 11 }, settings, 9001, 'Test AoE Continuation', 'test')
	assert_equal(allowed, false, 'stale Smart AoE continuation must fail revalidation')
	assert_equal(block_reason, 'SMART_WS_AOE_BLOCKED', 'stale continuation block reason mismatch')

	dispatch_target = {
		id = 9001,
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		distance = { sqrt = function() return 5 end },
	}
	local dispatch_plan = require('uc_scheduler_dispatch_plan')
	local ctx = { now = 1, tick = 1, settings = settings }
	local guarded = {
		proposal_id = 'guarded',
		action_name = 'Aeolian Edge',
		target_kind = 'mob',
		target_id = 9001,
		expires_at = 2,
		commit_deadline = 2,
		smart_aoe_guard = true,
	}
	local plan = dispatch_plan.p1_build_dispatch_plan({}, ctx, guarded, function(value) return value end)
	allowed, block_reason = dispatch_plan.p1_revalidate_plan_commit({}, ctx, guarded, plan, function(value) return value end, windower, core)
	assert_equal(allowed, false, 'stale Smart AoE primary proposal must fail scheduler commit')
	assert_equal(block_reason, 'SMART_WS_AOE_BLOCKED', 'stale primary commit reason mismatch')

	guarded.smart_aoe_guard = false
	plan = dispatch_plan.p1_build_dispatch_plan({}, ctx, guarded, function(value) return value end)
	allowed, block_reason = dispatch_plan.p1_revalidate_plan_commit({}, ctx, guarded, plan, function(value) return value end, windower, core)
	assert_equal(allowed, true, 'explicit/manual proposal without the Smart guard must remain unaffected')
	dispatch_target = nil

	settings.ws_mode = 'smart'
	settings.spam = false
	settings.weaponskill = 'Savage Blade'
	settings.weaponskill_allow_aoe = true
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

local function install_dispatch_target(target_id)
	dispatch_target = {
		id = target_id,
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		distance = {
			sqrt = function()
				return 3
			end,
		},
	}
end

local function skillchain_intent(target_id, ws_name, generation, source_actor_id, source_action_id, source_resource)
	return {
		kind = 'skillchain_continuation',
		target_id = target_id,
		ws_name = ws_name,
		resonance_generation = generation,
		source_actor_id = source_actor_id or 202,
		source_action_id = source_action_id or 42,
		source_resource = source_resource or 'weapon_skills',
	}
end

local function reset_ws_intent_test_state()
	core.reset_skillchain_state('ws_intent_selftest')
	ipc_messages = {}
end

local function install_high_level_skillchain_result(level, terminal)
	local now = os.clock()
	core.resonating[9001] = {
		target_id = 9001,
		generation = 9,
		active_properties = { level == 4 and 'Radiance' or 'Light' },
		chainbound_level = 0,
		source_action_id = 42,
		source_actor_id = 202,
		source_resource = 'weapon_skills',
		action_count = 3,
		result_level = level,
		earliest_close_at = now - 1,
		preferred_execute_at = now - 0.5,
		expires_at = now + 8,
		magic_burst_expires_at = now + 10,
		terminal = terminal == true,
		actor_expiry_overrides = {},
	}
end

local function test_fast_skillchain_restarts_only_after_terminal_result()
	reset_ws_intent_test_state()
	ability_recasts[20] = 30
	settings.ws_mode = 'smart'
	settings.spam = false
	settings.solo = false
	settings.aftermath_enabled = false
	settings.weaponskill = 'Savage Blade'
	settings.weaponskill_min_tp = 1000
	settings.fast_skillchain = false
	player.vitals.tp = 1000

	install_high_level_skillchain_result(3, false)
	local selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_equal(selection, nil, 'default level-3 behavior must preserve the burst window')
	assert_equal(reason, 'SC_NO_CONTINUATION', 'default level-3 hold reason mismatch')

	settings.fast_skillchain = true
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_equal(selection, nil,
		'Fast Skillchain must preserve continuation timing after a nonterminal level-3 result')
	assert_equal(reason, 'SC_NO_CONTINUATION', 'Fast Skillchain nonterminal level-3 hold reason mismatch')
	assert_true(core.resonating[9001] ~= nil,
		'Fast Skillchain must retain the nonterminal level-3 resonance for Double Light or Darkness')

	install_high_level_skillchain_result(4, true)
	settings.fast_skillchain = false
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_equal(selection, nil, 'default terminal-result behavior must preserve the burst window')
	assert_equal(reason, 'SC_TERMINAL', 'default terminal-result hold reason mismatch')

	settings.fast_skillchain = true
	selection, reason = core.select_ws_plan_for_scheduler(settings, 9001)
	assert_true(type(selection) == 'table',
		'Fast Skillchain must select a fresh opener after a confirmed terminal result')
	assert_equal(reason, 'READY', 'Fast Skillchain terminal-result opener reason mismatch')

	install_high_level_skillchain_result(4, true)
	dispatch_target = {
		id = 9001,
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		distance = { sqrt = function() return 5 end },
	}
	local sent, dispatch_reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, nil)
	assert_false(sent, 'Fast Skillchain opener must still enter WS intent arbitration')
	assert_equal(dispatch_reason, 'WS_INTENT_BROADCAST', 'Fast Skillchain arbitration reason mismatch')
	assert_true(core.resonating[9001] ~= nil,
		'arbitration must not clear the prior resonance before command dispatch')
	core.ws_intent_pending_ready_at = 0
	sent, dispatch_reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, nil)
	assert_true(sent, 'Fast Skillchain opener must dispatch after arbitration')
	assert_equal(dispatch_reason, 'WS_INTENT_SENT', 'Fast Skillchain dispatch reason mismatch')
	assert_equal(core.resonating[9001], nil,
		'Fast Skillchain must clear the prior resonance only after opener dispatch')

	dispatch_target = nil
	settings.fast_skillchain = false
	reset_ws_intent_test_state()
end

local function test_skillchain_intent_different_ws_same_resonance_conflicts_across_local_generations()
	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	local plan = skillchain_intent(9001, 'Savage Blade', 7)
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, plan)
	assert_false(sent, 'initial skillchain intent must wait for arbitration')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'initial skillchain intent reason')
	assert_true(tostring(ipc_messages[1] or ''):match('^ucws_intent|101|9001|Savage Blade|sc:202:weapon_skills:42|') ~= nil, 'skillchain IPC must include stable resonance identity')

	-- The remote client has a different local resonance_generation, but observed the same source action.
	core.on_ipc_message('ucws_intent|100|9001|Tachi: Kasha|sc:202:weapon_skills:42|1.000')
	assert_equal(core.ws_intent_remote_claim_id, 'sc:202:weapon_skills:42', 'remote stable resonance identity must be recorded')
	assert_equal(core.ws_intent_pending_target_id, 0, 'lower actor must clear a conflicting local generation claim')
	sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, plan)
	assert_false(sent, 'losing skillchain intent must not dispatch against the claimed generation')
	assert_equal(reason, 'WS_INTENT_COOLDOWN_LOST_TO:100', 'different WS must contend for the same generation')
end

local function test_established_remote_claim_is_not_preempted_by_lower_actor()
	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	core.on_ipc_message('ucws_intent|102|9001|Tachi: Kasha|sc:202:weapon_skills:42|1.000')
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, skillchain_intent(9001, 'Savage Blade', 7))
	assert_false(sent, 'lower actor must not preempt an established remote claim')
	assert_equal(reason, 'WS_INTENT_WAIT_REMOTE:102', 'established remote claim must win before a local pending claim exists')
	assert_equal(#ipc_messages, 0, 'waiting on an established remote claim must not broadcast a competing claim')
end

local function test_skillchain_intent_same_ws_contention_remains()
	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	local plan = skillchain_intent(9001, 'Savage Blade', 7)
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, plan)
	assert_false(sent, 'initial same-WS intent must wait for arbitration')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'initial same-WS intent reason')
	core.on_ipc_message('ucws_intent|100|9001|Savage Blade|sc:202:weapon_skills:42|1.000')
	sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, plan)
	assert_false(sent, 'same WS contenders must still arbitrate')
	assert_equal(reason, 'WS_INTENT_COOLDOWN_LOST_TO:100', 'same WS contention winner must remain lower actor ID')
end

local function test_skillchain_intent_lower_actor_keeps_the_generation_claim()
	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	local plan = skillchain_intent(9001, 'Savage Blade', 7)
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, plan)
	assert_false(sent, 'initial winner intent must wait for arbitration')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'initial winner intent reason')
	core.on_ipc_message('ucws_intent|102|9001|Tachi: Kasha|sc:202:weapon_skills:42|1.000')
	assert_equal(core.ws_intent_pending_target_id, 9001, 'lower actor must retain its conflicting generation claim')
	assert_equal(core.ws_intent_pending_claim_id, 'sc:202:weapon_skills:42', 'winner must retain the claimed resonance identity')
	assert_equal(core.ws_intent_loser_cooldown_until, 0, 'winner must not enter loser cooldown')
end

local function test_skillchain_intent_next_generation_is_not_blocked()
	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	local generation_seven = skillchain_intent(9001, 'Savage Blade', 7)
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, generation_seven)
	assert_false(sent, 'initial generation must wait for arbitration')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'initial generation reason')
	core.on_ipc_message('ucws_intent|100|9001|Tachi: Kasha|sc:202:weapon_skills:42|1.000')

	local generation_eight = skillchain_intent(9001, 'Savage Blade', 8, 202, 43)
	sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, generation_eight)
	assert_false(sent, 'next generation must start its own arbitration window')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'previous generation reservation must not block next generation')
	assert_equal(core.ws_intent_pending_claim_id, 'sc:202:weapon_skills:43', 'next resonance must own the new local claim')
end

local function test_skillchain_intent_different_targets_do_not_conflict()
	reset_ws_intent_test_state()
	core.on_ipc_message('ucws_intent|100|9001|Tachi: Kasha|sc:202:weapon_skills:42|1.000')
	install_dispatch_target(9002)
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9002, settings, skillchain_intent(9002, 'Savage Blade', 7))
	assert_false(sent, 'different target intent must start local arbitration')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'different targets must not conflict')
end

local function test_non_skillchain_primary_ws_arbitration_is_name_based()
	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	core.on_ipc_message('ucws_intent|100|9001|Tachi: Kasha|ws:Tachi: Kasha|1.000')
	local sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, nil)
	assert_false(sent, 'ordinary primary WS must start arbitration when remote WS differs')
	assert_equal(reason, 'WS_INTENT_BROADCAST', 'ordinary primary WS must retain name-based arbitration')

	reset_ws_intent_test_state()
	install_dispatch_target(9001)
	core.on_ipc_message('ucws_intent|100|9001|Savage Blade|ws:Savage Blade|1.000')
	sent, reason = core.try_dispatch_ws_with_intent('Savage Blade', 9001, settings, nil)
	assert_false(sent, 'ordinary same-WS primary contention must wait for remote')
	assert_equal(reason, 'WS_INTENT_WAIT_REMOTE:100', 'ordinary primary same-WS behavior must remain unchanged')
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
	test_aoe_metadata_classification()
	test_chivalry_reserves_tp_across_ready_boundary()
	test_aftermath_reserves_tp_and_dispatches_before_continuation()
	test_satisfied_maintenance_applies_minimum_tp_to_continuation()
	test_ordinary_smart_ws_observes_minimum_tp()
	test_primary_only_ws_retains_base_tp_requirement()
	test_aftermath_precedes_spam_until_buff_active()
	test_spam_forces_primary_ws_across_active_resonance()
	test_spam_ws_observes_minimum_tp()
	test_spam_ws_dispatch_rejects_out_of_range_target()
	test_fast_skillchain_restarts_only_after_terminal_result()
	test_skillchain_intent_different_ws_same_resonance_conflicts_across_local_generations()
	test_established_remote_claim_is_not_preempted_by_lower_actor()
	test_skillchain_intent_same_ws_contention_remains()
	test_skillchain_intent_lower_actor_keeps_the_generation_claim()
	test_skillchain_intent_next_generation_is_not_blocked()
	test_skillchain_intent_different_targets_do_not_conflict()
	test_non_skillchain_primary_ws_arbitration_is_name_based()
	test_smart_continuation_candidate_filtering()
	test_smart_primary_and_aftermath_aoe_restriction()
	test_aoe_restriction_scope_and_revalidation()
	end)
	restore_test_environment()
	if not ok then
		error(err, 0)
	end
	io.stdout:write('selftest_ws_maintenance_precedence: OK\n')
end

main()
