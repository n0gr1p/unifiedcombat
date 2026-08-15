local saved_windower = rawget(_G, 'windower')
local saved_resources = package.loaded.resources
local saved_active_config = package.loaded.uc_active_config
local saved_party_buff_tracker = package.loaded.uc_party_buff_tracker
local saved_encounter_runtime = package.loaded.uc_encounter_runtime
local saved_encounter_state = package.loaded.uc_encounter_state
local saved_encounter_policy = package.loaded.uc_encounter_policy
local saved_encounter_classifier = package.loaded.uc_encounter_action_classifier
local saved_skillchain_elements = package.loaded.uc_skillchain_elements
local saved_timeline_log = rawget(_G, 'UC_ACTION_TIMELINE_LOG')

local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local config = {
	enabled = true,
	id = 'sortie_dhartok',
	policy = {
		water_damage = 'warn',
		water_skillchain = 'enforce',
		repeat_action_wall = 'enforce',
	},
	tuning = {
		repeat_action_guard_s = 9.0,
	},
}
local mobs = {
	[1] = { id = 3001, name = 'Dhartok', x = -5, y = 8, z = 0, hpp = 100, status = 1 },
	[2] = { id = 4001, name = 'MemberA', x = 6, y = 7, z = 8, hpp = 100, status = 1 },
	[3] = { id = 4002, name = 'MemberB', x = 1, y = 2, z = 3, hpp = 100, status = 1 },
}
local mobs_by_id = {}
for _, mob in pairs(mobs) do
	mobs_by_id[mob.id] = mob
end

package.loaded.resources = {
	zones = {
		[133] = { en = "Outer Ra'Kaznar [U2]" },
	},
	buffs = {
		[101] = { en = 'Poison' },
		[102] = { en = 'Taint' },
	},
	elements = {
		[5] = { en = 'Water' },
	},
	spells = {
		[169] = { id = 169, en = 'Water', element = 5, skill = 36, type = 'BlackMagic' },
	},
	weapon_skills = {},
	job_abilities = {},
	monster_abilities = {
		[900] = { en = 'Cesspool' },
		[901] = { en = 'Fetid Eddies' },
		[902] = { en = 'Noyade' },
		[903] = { en = 'Auto Attack 1' },
	},
}
package.loaded.uc_active_config = {
	get_path = function(path)
		assert_equal(path, 'config.encounter', 'runtime config path mismatch')
		return config
	end,
}
package.loaded.uc_party_buff_tracker = {
	get = function(member_id)
		if tonumber(member_id) == 4002 then
			return { buffs = { 102 } }
		end
		return nil
	end,
}

_G.windower = {
	ffxi = {
		get_info = function()
			return { zone = 133 }
		end,
		get_mob_array = function()
			return mobs
		end,
		get_party = function()
			return {
				p0 = { mob = mobs_by_id[4001] },
				p1 = { mob = mobs_by_id[4002] },
			}
		end,
		get_player = function()
			return { id = 4001, buffs = { 101 } }
		end,
		get_mob_by_id = function(id)
			return mobs_by_id[tonumber(id)]
		end,
	},
}

local timeline_events = {}
_G.UC_ACTION_TIMELINE_LOG = function(event_code, fields)
	timeline_events[#timeline_events + 1] = {
		event_code = event_code,
		fields = fields,
	}
	return true
end

package.loaded.uc_encounter_runtime = nil
package.loaded.uc_encounter_state = nil
local runtime = require('uc_encounter_runtime')

local ok, reason = runtime.observe(10.0)
assert_true(ok, 'runtime should bind configured Dhartok')
assert_equal(reason, 'ORIGIN_CAPTURE_MISSED', 'runtime bind reason mismatch')
local snapshot = runtime.snapshot()
assert_equal(snapshot.resolved_id, 'sortie_dhartok', 'runtime resolved encounter mismatch')
assert_true(snapshot.status_context[1].poison, 'runtime local Poison observation missing')
assert_true(snapshot.status_context[2].taint, 'runtime party Taint observation missing')
assert_equal(snapshot.policy_modes.water_damage, 'warn', 'runtime policy override mismatch')
assert_equal(snapshot.tuning.repeat_action_guard_s, 9.0, 'runtime tuning override mismatch')

ok, reason = runtime.validate_proposal({ now = 10.1 }, {
	proposal_id = 'runtime-water-warn',
	provider = 'combat',
	action_type = 'spell',
	action_name = 'Water',
	target_kind = 'mob',
	target_id = 3001,
})
assert_true(ok, 'runtime warn policy must allow proposal')
assert_equal(reason, '', 'runtime warn policy reason mismatch')
assert_equal(runtime.snapshot().last_policy_violation.mode, 'warn', 'runtime warn diagnostic missing')

config.policy.water_damage = 'enforce'
runtime.observe(10.2)
ok, reason = runtime.validate_proposal({ now = 10.3 }, {
	proposal_id = 'runtime-water-enforce',
	provider = 'combat',
	action_type = 'spell',
	action_name = 'Water',
	target_kind = 'mob',
	target_id = 3001,
})
assert_equal(ok, false, 'runtime enforce policy must reject proposal')
assert_equal(reason, 'encounter_water_damage', 'runtime enforce rejection mismatch')
assert_equal(runtime.snapshot().last_policy_rejection.mode, 'enforce', 'runtime rejection diagnostic missing')

ok, reason = runtime.on_action({
	actor_id = 3001,
	category = 11,
	param = 900,
	targets = { { id = 4001, actions = {} } },
}, 11.0)
assert_true(ok, 'runtime should resolve Cesspool resource')
assert_equal(reason, 'CESSPOOL_TELEMETRY_STARTED', 'runtime Cesspool reason mismatch')
assert_equal(timeline_events[#timeline_events - 1].event_code, 'ENCOUNTER_RAW_ABILITY_CANDIDATE', 'raw capture event missing')
assert_equal(timeline_events[#timeline_events - 1].fields.actor_name, 'Dhartok', 'raw capture actor mismatch')
assert_equal(timeline_events[#timeline_events - 1].fields.zone_id, 133, 'raw capture zone id mismatch')
assert_equal(timeline_events[#timeline_events - 1].fields.zone_name, "Outer Ra'Kaznar [U2]", 'raw capture zone name mismatch')
assert_equal(timeline_events[#timeline_events - 1].fields.target_count, 1, 'raw capture target count mismatch')
assert_true(
	timeline_events[#timeline_events - 1].fields.targets_summary:find('id=4001', 1, true) ~= nil,
	'raw capture target summary missing id'
)

runtime.on_action({
	actor_id = 3001,
	category = 11,
	param = 903,
	targets = { { id = 4001, actions = {} } },
}, 11.5)
assert_equal(runtime.snapshot().cesspool.pair_index, 0, 'runtime auto attack advanced Cesspool pairing')

runtime.on_action({
	actor_id = 3001,
	category = 11,
	param = 901,
	targets = { { id = 4001, actions = {} } },
}, 12.0)
ok, reason = runtime.on_action({
	actor_id = 3001,
	category = 11,
	param = 902,
	targets = { { id = 4001, actions = {} } },
}, 13.0)
assert_true(ok, 'runtime should observe second TP completion')
assert_equal(reason, 'HAZARD_ACTIVATED', 'runtime hazard activation reason mismatch')

ok, reason = runtime.observe_action_result({
	action_class = 'bp',
	action_key = '777',
	action_name = 'Test Pact',
	actor_id = 5001,
	target_id = 3001,
	observed_at = 14.0,
	success = true,
})
assert_true(ok, 'runtime should record successful Blood Pact')
assert_equal(reason, 'ACTION_SUCCESS_OBSERVED', 'runtime BP result reason mismatch')

snapshot = runtime.snapshot()
assert_equal(#snapshot.hazard_candidates, 1, 'runtime hazard candidate count mismatch')
assert_equal(snapshot.hazard_candidates[1].target_id, 4001, 'runtime hazard target mismatch')
assert_equal(#snapshot.active_hazards, 1, 'runtime active hazard count mismatch')
assert_equal(snapshot.active_hazards[1].avoid_radius, 3.0, 'runtime active hazard radius mismatch')
assert_true(snapshot.recent_repeat_actions['bp:777'] ~= nil, 'runtime BP timestamp missing')
assert_true(#runtime.status_lines() >= 9, 'runtime diagnostics should expose detailed status')

ok, reason = runtime.observe_boss_defeat(3001)
assert_true(ok, 'runtime should reset on matching boss death message')
assert_equal(reason, 'BOSS_DEFEATED', 'runtime boss death reason mismatch')
assert_equal(runtime.snapshot().last_reset_reason, 'boss_defeated_action_message', 'runtime boss death reset mismatch')

runtime.reset('test_complete')

config.enabled = false
runtime.observe(20.0)
local raw_count = #timeline_events
ok, reason = runtime.on_action({
	actor_id = 3001,
	category = 11,
	param = 900,
	targets = {
		{
			id = 4001,
			actions = {
				{ message = 101, param = 202, reaction = 3, animation = 4, effect = 5, stagger = 6 },
			},
		},
	},
}, 21.0)
assert_equal(ok, false, 'disabled encounter state must not observe raw candidate as active state')
assert_equal(reason, 'ENCOUNTER_UNRESOLVED', 'disabled raw capture state reason mismatch')
assert_equal(#timeline_events, raw_count + 1, 'disabled encounter must still emit one raw capture event')
assert_equal(timeline_events[#timeline_events].event_code, 'ENCOUNTER_RAW_ABILITY_CANDIDATE', 'disabled raw event mismatch')
assert_true(
	timeline_events[#timeline_events].fields.actions_summary:find('message=101', 1, true) ~= nil,
	'disabled raw capture action details missing'
)

raw_count = #timeline_events
ok, reason = runtime.observe_action_result({
	action_class = 'ws',
	action_key = '42',
	action_name = 'Test WS',
	actor_id = 5001,
	target_id = 3001,
	observed_at = 22.0,
	success = true,
})
assert_equal(ok, false, 'disabled encounter state must not store raw action result candidate')
assert_equal(reason, 'DHARTOK_UNRESOLVED', 'disabled raw action result state reason mismatch')
assert_equal(#timeline_events, raw_count + 1, 'disabled encounter must emit one raw action result event')
assert_equal(
	timeline_events[#timeline_events].event_code,
	'ENCOUNTER_RAW_ACTION_RESULT_CANDIDATE',
	'disabled raw action result event mismatch'
)
assert_equal(timeline_events[#timeline_events].fields.success, true, 'raw action result success mismatch')

package.loaded.uc_encounter_runtime = saved_encounter_runtime
package.loaded.uc_encounter_state = saved_encounter_state
package.loaded.uc_encounter_policy = saved_encounter_policy
package.loaded.uc_encounter_action_classifier = saved_encounter_classifier
package.loaded.uc_skillchain_elements = saved_skillchain_elements
package.loaded.resources = saved_resources
package.loaded.uc_active_config = saved_active_config
package.loaded.uc_party_buff_tracker = saved_party_buff_tracker
_G.windower = saved_windower
_G.UC_ACTION_TIMELINE_LOG = saved_timeline_log

io.stdout:write('selftest_encounter_runtime: OK\n')
