local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function resource_set(entries)
	local rows = entries or {}
	return setmetatable(rows, {
		__index = {
			with = function(self, key, value)
				for _, item in pairs(self) do
					if type(item) == 'table' and item[key] == value then
						return item
					end
				end
				return nil
			end,
		},
	})
end

local switch_calls = {}
local select_calls = {}
local engage_calls = 0
local disengage_calls = 0
local switch_result = true
local commit_valid = true

package.loaded.resources = {
	spells = resource_set({}),
	job_abilities = resource_set({}),
	buffs = resource_set({
		[2] = { id = 2, en = 'sleep' },
		[19] = { id = 19, en = 'sleep' },
	}),
}
package.loaded.uc_ability_pipeline = {
	collect_ordered = function()
		return {}
	end,
}
package.loaded.unified_combat_core = {
	on_action_message = function()
	end,
	add_control_enabled_for_scheduler = function()
		return false
	end,
	select_ws_plan_for_scheduler = function()
		return nil
	end,
	is_live_actionable_combat_target = function()
		return false
	end,
	select_pull_for_scheduler = function()
		return nil
	end,
	select_tank_enmity_for_scheduler = function()
		return nil
	end,
	select_target_for_scheduler = function()
		return nil
	end,
	revalidate_death_switch_for_scheduler = function()
		if commit_valid then
			return true, 'death_switch_valid'
		end
		return false, 'death_switch_destination_invalid'
	end,
}
package.loaded.uc_targeting_common = {
	build_friendly_claims = function()
		return {}, {}
	end,
	mob_targets_friendly_member = function()
		return false
	end,
}
package.loaded.uc_cor_maintenance = {
	propose = function()
		return nil
	end,
}
package.loaded.uc_settarget = {
	select_by_id = function(target_id)
		select_calls[#select_calls + 1] = target_id
		return true
	end,
}
package.loaded.uc_attack = {
	switch_target = function(target_id)
		switch_calls[#switch_calls + 1] = target_id
		return switch_result, switch_result and 'OK' or 'PACKET_INJECT_FAIL'
	end,
	engage_target = function()
		engage_calls = engage_calls + 1
		return true
	end,
	disengage = function()
		disengage_calls = disengage_calls + 1
		return true
	end,
}
package.loaded.uc_partner_list = {
	as_ordered_ids = function()
		return {}
	end,
}
package.loaded.uc_fight_leader = {
	leader_target_id = function()
		return 0
	end,
}
package.loaded.uc_hb_buff_maint = {}
package.loaded.uc_enemy_effect_tracker = {
	on_action = function()
		return {}
	end,
	on_action_message = function()
		return {}
	end,
	list_targets = function()
		return {}
	end,
	get_effects = function()
		return {}
	end,
}
package.loaded['lor/lor_packets'] = {}
package.loaded.json = {}
package.loaded.uc_tb_effect_table = {
	apply_from_action = function()
	end,
}
package.loaded.socket = {
	gettime = function()
		return _G.__TEST_NOW
	end,
}
_G.socket = package.loaded.socket

_G.__TEST_NOW = 100
_G.windower = {
	addon_path = 'C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\',
	add_to_chat = function()
	end,
	send_ipc_message = function()
	end,
	packets = {
		parse_action = function()
			return {}
		end,
	},
	ffxi = {
		get_player = function()
			return {
				id = 101,
				name = 'Self',
				status = 1,
				main_job_id = 1,
				sub_job_id = 2,
				main_job_level = 99,
				sub_job_level = 49,
				vitals = { mp = 500 },
				job_points = {},
				buffs = {},
			}
		end,
		get_mob_by_target = function()
			return { id = 700, name = 'Dead Incumbent', hpp = 0, spawn_type = 16 }
		end,
		get_mob_by_id = function(target_id)
			return { id = target_id, name = 'Replacement', hpp = 100, spawn_type = 16, valid_target = true }
		end,
		get_mob_by_index = function(target_index)
			return { id = target_index, name = 'Replacement', hpp = 100, spawn_type = 16, valid_target = true }
		end,
		get_mob_array = function()
			return {}
		end,
		get_party = function()
			return {}
		end,
		get_spells = function()
			return {}
		end,
		get_spell_recasts = function()
			return {}
		end,
		get_ability_recasts = function()
			return {}
		end,
		get_abilities = function()
			return { job_abilities = {} }
		end,
		get_mjob_data = function()
			return { spells = {} }
		end,
		get_sjob_data = function()
			return { spells = {} }
		end,
		get_info = function()
			return { zone = 0 }
		end,
	},
}

package.loaded.unified_scheduler = nil
local scheduler = require('unified_scheduler')
scheduler.action_timeline_log = function()
end
scheduler.p1_build_lock_summary = function()
	return ''
end
scheduler.p1_set_pending_globals = function()
end
scheduler.p1_maybe_release_stale_spell_lock_for_target_transition = function()
	return false
end

local function death_switch_proposal(target_id)
	return {
		proposal_id = 'target.death_switch.700.' .. tostring(target_id),
		family_id = 'target.acquire.primary',
		provider = 'target_control',
		action_type = 'target',
		action_name = 'death_switch',
		target_kind = 'mob',
		target_id = target_id,
		target_name = 'Replacement',
		priority_band = 148,
		urgency = 1.0,
		duplicate_suppression_key = 'target.death_switch:700:' .. tostring(target_id),
		detail = {
			add_control_retarget = false,
			death_switch = true,
			death_switch_incumbent_id = 700,
		},
	}
end

local proposal = death_switch_proposal(701)
local dispatched = scheduler.p1_dispatch_target_control(proposal, {
	now = 100,
	tick = 1,
	settings = { autotarget = true },
})
assert_true(dispatched, 'valid death switch must dispatch')
assert_equal(#switch_calls, 1, 'valid death switch must execute exactly one switch packet')
assert_equal(switch_calls[1], 701, 'switch executor target id')
assert_equal(#select_calls, 0, 'death switch must not call select-target preparation')
assert_equal(engage_calls, 0, 'death switch must not engage')
assert_equal(disengage_calls, 0, 'death switch must not disengage')
assert_true(scheduler.p1_duplicate_suppressed({ now = 100.1 }, proposal), 'successful death switch must be debounce-suppressed on repeated ticks')

commit_valid = false
local stale = death_switch_proposal(702)
dispatched = scheduler.p1_dispatch_target_control(stale, {
	now = 101,
	tick = 2,
	settings = { autotarget = true },
})
assert_equal(dispatched, false, 'commit-time rejection must discard stale death switch')
assert_equal(#switch_calls, 1, 'commit-time rejection must not execute switch packet')

commit_valid = true
switch_result = false
local failed = death_switch_proposal(703)
dispatched = scheduler.p1_dispatch_target_control(failed, {
	now = 102,
	tick = 3,
	settings = { autotarget = true },
})
assert_equal(dispatched, false, 'packet failure must report no dispatch')
assert_equal(#switch_calls, 2, 'packet failure must attempt only one packet')
assert_true(scheduler.p1_duplicate_suppressed({ now = 102.1 }, failed), 'packet failure must be debounce-suppressed')
assert_equal(#select_calls, 0, 'packet failure must not fall back to select target')
assert_equal(engage_calls, 0, 'packet failure must not fall back to engage')
assert_equal(disengage_calls, 0, 'packet failure must not fall back to disengage')

io.stdout:write('selftest_death_switch_dispatch: OK\n')
