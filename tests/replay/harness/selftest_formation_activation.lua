local active_config = require('uc_active_config')
local formation_runtime = require('uc_formation_runtime')
local generic_runtime_factory = require('uc_generic_formation_runtime')
local profile_contract = require('uc_profile_contract')
local profile_v2 = require('uc_profile_v2')

local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_false(condition, message)
	if condition ~= false then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function generic_flat()
	return {
		domain_movement_enabled = true,
		encounter_enabled = true,
		encounter_id = 'sortie_ghatjot',
		encounter_water_damage = 'enforce',
		encounter_water_skillchain = 'enforce',
		encounter_repeat_action_wall = 'off',
		encounter_repeat_action_guard_s = 10,
		formation_enabled = true,
		formation_encounter = 'sortie_ghatjot',
		formation_mock_enabled = true,
		formation_mock_mob_name = 'Apex Crab',
		formation_placement_mode = 'polar_band',
		formation_anchor = 'boss',
		formation_anchor_member = '',
		formation_axis_type = 'boss_to_member',
		formation_axis_member = 'Reference',
		formation_preferred_radius = 3,
		formation_minimum_radius = 2,
		formation_maximum_radius = 4,
		formation_preferred_angle_deg = 180,
		formation_allowed_angle_half_width_deg = 45,
		formation_radius_step = 0.5,
		formation_angle_step_deg = 15,
		formation_hysteresis_start_distance = 1,
		formation_hysteresis_stop_distance = 0.5,
		formation_avoid_encounter_hazards = true,
		formation_hazard_margin = 0.25,
		formation_safe_origin_radius = 16,
		formation_minimum_boss_distance = 1,
		formation_maximum_boss_distance = 6,
		formation_maximum_party_range = 12,
		formation_required_party_names = { 'Reference' },
	}
end

local meta = {
	character = 'Tester',
	main_job = 'WAR',
	sub_job = 'SAM',
}
local durable = profile_v2.build_durable_config(generic_flat(), meta)
assert_equal(
	profile_contract.classify_profile_field('formation_placement_mode'),
	'profile_owned_by_ui',
	'generic formation flat fields must remain durable UI-owned settings'
)
local formation = durable.movement.formation
assert_equal(formation.encounter, 'sortie_ghatjot', 'generic durable encounter mismatch')
assert_true(formation.mock.enabled, 'generic durable mock enable mismatch')
assert_equal(formation.mock.mob_name, 'Apex Crab', 'generic durable mock name mismatch')
assert_equal(formation.placement.mode, 'polar_band', 'generic durable placement mode mismatch')
assert_equal(formation.placement.axis.member, 'Reference', 'generic durable axis member mismatch')
assert_equal(formation.hysteresis.stop_distance, 0.5, 'generic durable hysteresis mismatch')
assert_true(formation.constraints.avoid_encounter_hazards, 'generic durable hazard preference mismatch')
assert_equal(formation.constraints.required_party_names[1], 'Reference', 'generic durable party constraint mismatch')
assert_equal(formation.role, nil, 'generic durable formation must not contain role semantics')
assert_equal(formation.tank, nil, 'generic durable formation must not contain tank semantics')
assert_equal(formation.dps, nil, 'generic durable formation must not contain DPS semantics')
assert_equal(formation.healer, nil, 'generic durable formation must not contain healer semantics')

local projected, projection_error = active_config.project_flat_settings({
	version = 2,
	profile = {
		schema_version = 2,
		engine = 'UC',
		character = 'Tester',
		main_job = 'WAR',
		sub_job = 'SAM',
		source = 'selftest',
	},
	config = durable,
}, {})
assert_true(type(projected) == 'table', 'generic structured profile projection failed: ' .. tostring(projection_error))
assert_equal(projected.formation_placement_mode, 'polar_band', 'generic flat projection mode mismatch')
assert_true(projected.formation_mock_enabled, 'generic flat projection mock enable mismatch')
assert_equal(projected.formation_mock_mob_name, 'Apex Crab', 'generic flat projection mock name mismatch')
assert_equal(projected.formation_axis_member, 'Reference', 'generic flat projection axis member mismatch')
assert_equal(projected.formation_safe_origin_radius, 16, 'generic flat projection constraint mismatch')
local round_trip = profile_v2.build_durable_config(projected, meta)
local diff = profile_v2.diff_durable_config(durable, round_trip)
assert_equal(diff.count, 0, 'generic formation Profile V2 round-trip mismatch')

local boss_heading_flat = generic_flat()
boss_heading_flat.formation_axis_type = 'boss_heading'
boss_heading_flat.formation_axis_member = ''
local boss_heading_durable = profile_v2.build_durable_config(boss_heading_flat, meta)
assert_equal(
	boss_heading_durable.movement.formation.placement.axis.type,
	'boss_heading',
	'boss heading axis must be durable'
)
assert_equal(
	boss_heading_durable.movement.formation.placement.axis.member,
	nil,
	'boss heading axis must not acquire member semantics'
)
local boss_heading_projected, boss_heading_projection_error = active_config.project_flat_settings({
	version = 2,
	profile = {
		schema_version = 2,
		engine = 'UC',
		character = 'Tester',
		main_job = 'WAR',
		sub_job = 'SAM',
		source = 'selftest',
	},
	config = boss_heading_durable,
}, {})
assert_true(
	type(boss_heading_projected) == 'table',
	'boss heading structured profile projection failed: ' .. tostring(boss_heading_projection_error)
)
assert_equal(boss_heading_projected.formation_axis_type, 'boss_heading', 'boss heading flat projection mismatch')
assert_equal(boss_heading_projected.formation_axis_member, nil, 'boss heading flat projection must omit axis member')
local boss_heading_round_trip = profile_v2.build_durable_config(boss_heading_projected, meta)
assert_equal(
	profile_v2.diff_durable_config(boss_heading_durable, boss_heading_round_trip).count,
	0,
	'boss heading Profile V2 round-trip mismatch'
)

local disabled_mock_flat = generic_flat()
disabled_mock_flat.formation_mock_enabled = false
local disabled_mock_durable = profile_v2.build_durable_config(disabled_mock_flat, meta)
assert_equal(disabled_mock_durable.movement.formation.mock, nil, 'disabled mock config must remain optional')
local invalid_mock_flat = generic_flat()
invalid_mock_flat.formation_mock_mob_name = ''
local invalid_mock_ok, invalid_mock_error = pcall(profile_v2.build_durable_config, invalid_mock_flat, meta)
assert_false(invalid_mock_ok, 'enabled mock without a mob name must fail normalization')
assert_true(
	tostring(invalid_mock_error):find('mock requires mob_name', 1, true) ~= nil,
	'enabled mock missing-name validation reason mismatch'
)

local intents = {}
local dispatcher = {
	dispatch_intent = function(intent, deps)
		intents[#intents + 1] = intent
		if intent.kind == 'run' then
			deps.run(intent.run_x, intent.run_y)
		elseif intent.kind == 'run_stop' then
			deps.run(false)
		else
			error('unexpected formation intent: ' .. tostring(intent.kind))
		end
		return { ok = true, executed = true, reason = 'executed' }
	end,
}
local generic_runtime = generic_runtime_factory.build({
	solver = require('uc_generic_formation'),
	dispatcher = dispatcher,
	run = function() end,
	source_prefix = 'formation_activation_test',
})
local selected_config = {
	enabled = true,
	encounter = 'sortie_ghatjot',
	mock = { enabled = false, mob_name = '' },
	placement = {
		mode = 'radial_band',
		anchor = 'boss',
		preferred_radius = 2,
		minimum_radius = 2,
		maximum_radius = 2,
		radius_step = 1,
		angle_step_deg = 90,
	},
	hysteresis = {
		start_distance = 0.5,
		stop_distance = 0.25,
	},
	constraints = {
		avoid_encounter_hazards = true,
		hazard_margin = 0.5,
		safe_origin_radius = 1,
	},
}
local encounter_snapshot = {
	enabled = true,
	configured_id = 'sortie_ghatjot',
	resolved_id = 'sortie_ghatjot',
	phase = 'active',
	error = '',
	boss = { id = 900, name = 'Ghatjot', x = 0, y = 0, hpp = 100, status = 1 },
	origin = { x = 0, y = 0 },
	hazard_candidates = {
		{ x = 10, y = 10, source = 'untrusted_test_candidate' },
	},
}
local lilith_observe_calls = 0
local lilith_run_calls = 0
local published = nil
local encounter_snapshot_calls = 0
local mock_observe_calls = 0
local mock_reset_calls = 0
local mock_snapshot = {
	enabled = true,
	configured_id = 'sortie_ghatjot',
	resolved_id = 'sortie_ghatjot',
	phase = 'active',
	error = '',
	mock = true,
	mock_mob_name = 'Apex Crab',
	boss = { id = 901, name = 'Apex Crab', x = 5, y = 0, hpp = 100, status = 1 },
	origin = { x = 5, y = 0 },
}
local runtime = formation_runtime.build({
	get_config = function()
		return selected_config
	end,
	encounter_runtime = {
		snapshot = function()
			encounter_snapshot_calls = encounter_snapshot_calls + 1
			return encounter_snapshot
		end,
	},
	encounter_registry = {
		get = function(encounter_id)
			if encounter_id == 'sortie_ghatjot' or encounter_id == 'sortie_dhartok' then
				return { id = encounter_id }
			end
			return nil
		end,
	},
	lilith_runtime = {
		observe = function()
			lilith_observe_calls = lilith_observe_calls + 1
			return { legacy = true }
		end,
		run_tick = function(observation)
			lilith_run_calls = lilith_run_calls + 1
			assert_true(observation.legacy, 'Lilith selector must preserve compatibility observation')
			return true, 'FORMATION_TANK_RETURN', true
		end,
		stop = function(reason)
			return false, reason
		end,
		reset = function() end,
	},
	generic_runtime = generic_runtime,
	mock_runtime = {
		observe = function(_, config)
			mock_observe_calls = mock_observe_calls + 1
			assert_equal(config.encounter, 'sortie_ghatjot', 'mock encounter identity mismatch')
			assert_equal(config.mob_name, 'Apex Crab', 'mock target name mismatch')
			return mock_snapshot
		end,
		reset = function()
			mock_reset_calls = mock_reset_calls + 1
			return true
		end,
	},
	get_me = function()
		return { id = 1, name = 'Me', x = 0, y = 0 }
	end,
	get_party_members = function()
		return {
			{ id = 1, name = 'Me', x = 0, y = 0 },
			{ id = 2, name = 'Reference', x = 4, y = 0 },
		}, ''
	end,
	publish_status = function(value)
		published = value
	end,
})

local observation = runtime.observe(10)
local acted, reason, owns = runtime.run_tick(observation)
assert_false(acted, 'unsatisfied generic formation must not dispatch a guessed move')
assert_equal(reason, 'FORMATION_UNSATISFIED', 'unsatisfied generic formation reason mismatch')
assert_true(owns, 'unsatisfied enabled generic formation must retain scheduler movement ownership')
assert_equal(#intents, 0, 'untrusted hazard candidates and unsatisfied geometry must not dispatch movement')
assert_equal(published.active_hazard_count, 0, 'Dhartok/Ghatjot hazard candidates must not become active constraints')

selected_config.constraints.safe_origin_radius = nil
observation = runtime.observe(10.5)
acted, reason, owns = runtime.run_tick(observation)
assert_true(acted, 'satisfied generic activation path must dispatch through the generic runtime')
assert_equal(reason, 'FORMATION_REPOSITION', 'generic activation movement reason mismatch')
assert_true(owns, 'moving generic formation must own scheduler movement')
assert_equal(#intents, 1, 'generic activation must emit exactly one dispatcher-backed movement intent')
assert_equal(intents[1].kind, 'run', 'generic activation must use the existing run intent')
assert_equal(intents[1].source, 'formation_activation_test:run_heading', 'generic activation dispatcher source mismatch')

local live_snapshot_calls = encounter_snapshot_calls
selected_config.mock = { enabled = true, mob_name = 'Apex Crab' }
mock_snapshot.boss.status = 0
observation = runtime.observe(10.7)
acted, reason, owns = runtime.run_tick(observation)
assert_true(acted, 'idle mock boss must stop a prior formation vector')
assert_equal(reason, 'FORMATION_WAITING_FOR_ENGAGE', 'idle mock boss engagement gate mismatch')
assert_true(owns, 'idle mock boss stop must retain ownership for the stop dispatch')
assert_equal(encounter_snapshot_calls, live_snapshot_calls, 'mock formation must not read live encounter-policy state')
assert_equal(mock_observe_calls, 1, 'mock formation observation count mismatch')

observation = runtime.observe(10.75)
acted, reason, owns = runtime.run_tick(observation)
assert_false(acted, 'idle mock boss must remain stationary after the stop dispatch')
assert_equal(reason, 'FORMATION_WAITING_FOR_ENGAGE', 'steady idle mock reason mismatch')
assert_false(owns, 'steady idle mock must release formation ownership')

mock_snapshot.boss.status = 1
observation = runtime.observe(10.8)
acted, reason, owns = runtime.run_tick(observation)
assert_true(acted, 'engaged mock boss must drive generic formation')
assert_equal(reason, 'FORMATION_REPOSITION', 'engaged mock formation reason mismatch')
assert_true(owns, 'engaged mock formation must own scheduler movement')
assert_equal(published.source, 'mock', 'formation diagnostics must identify mock source')
assert_equal(published.mock_mob_name, 'Apex Crab', 'formation diagnostics mock target mismatch')
assert_equal(encounter_snapshot_calls, live_snapshot_calls, 'mock execution must remain isolated from encounter state')

selected_config.enabled = false
observation = runtime.observe(11)
acted, reason, owns = runtime.run_tick(observation)
assert_false(acted, 'disabled generic formation must not act')
assert_equal(reason, 'FORMATION_DISABLED', 'disabled generic formation reason mismatch')
assert_false(owns, 'disabled generic formation must not own scheduler movement')
assert_equal(mock_reset_calls, 1, 'disabling mock formation must reset transient mock state')

selected_config = {
	enabled = true,
	encounter = 'lilith_easy',
}
observation = runtime.observe(12)
acted, reason, owns = runtime.run_tick(observation)
assert_true(acted, 'Lilith compatibility runtime result must be preserved')
assert_equal(reason, 'FORMATION_TANK_RETURN', 'Lilith compatibility reason mismatch')
assert_true(owns, 'Lilith compatibility runtime must retain movement ownership')
assert_equal(lilith_observe_calls, 1, 'Lilith compatibility observe call count mismatch')
assert_equal(lilith_run_calls, 1, 'Lilith compatibility run call count mismatch')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'rb'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
local coordinator_start = assert(scheduler_source:find('local function run_movement_coordinator_tick()', 1, true))
local coordinator_end = assert(scheduler_source:find('function scheduler.p1_pick_preemptive_engage', coordinator_start, true))
local coordinator = scheduler_source:sub(coordinator_start, coordinator_end)
local nyzul_at = assert(coordinator:find("nyzul_runtime.is_movement_held()", 1, true))
local camp_at = assert(coordinator:find("movement_reserved(camp_pulling_config())", 1, true))
local observe_at = assert(coordinator:find('formation_runtime.observe(now)', 1, true))
local reaction_at = assert(coordinator:find("formation_runtime.stop('FORMATION_REACTION_HOLD')", 1, true))
local cast_at = assert(coordinator:find("formation_runtime.stop('FORMATION_CAST_FREEZE_PREP')", 1, true))
local formation_at = assert(coordinator:find('formation_runtime.run_tick(formation_observation)', 1, true))
assert_true(nyzul_at < observe_at, 'Nyzul movement ownership must remain above formation')
assert_true(camp_at < observe_at, 'camp-puller movement ownership must remain above formation')
assert_true(reaction_at < formation_at, 'reaction holds must remain above formation execution')
assert_true(cast_at < formation_at, 'cast freezes must remain above formation execution')
assert_true(
	coordinator:find("UC_MOVEMENT_OWNER = 'scheduler_formation'", formation_at, true) ~= nil,
	'scheduler formation ownership publication must remain in the existing coordinator path'
)
local doom_at = assert(scheduler_source:find('local doom_blocked, doom_reason = try_doom_water_emergency(s)', 1, true))
local movement_at = assert(scheduler_source:find('move_acted, move_reason = run_movement_coordinator_tick()', doom_at, true))
assert_true(doom_at < movement_at, 'Doom handling must remain above the movement coordinator')

local addon_file = assert(io.open('UnifiedCombat.lua', 'rb'))
local addon_source = addon_file:read('*a')
addon_file:close()
local combat_participant_start = assert(addon_source:find('local function uc_is_combat_participant', 1, true))
local combat_participant_end = assert(addon_source:find('local function uc_is_defensive_participant', combat_participant_start, true))
local combat_participant_source = addon_source:sub(combat_participant_start, combat_participant_end)
assert_true(
	combat_participant_source:find('uc_truthy(st.formation_enabled)', 1, true) ~= nil,
	'enabled formation must remain eligible when the local character is engaged'
)

io.stdout:write('selftest_formation_activation: OK\n')
