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

local function logs_contain(logs, needle)
	for i = 1, #logs do
		if logs[i]:find(needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function base_config()
	local config = require('uc_sch_config').default_config()
	config.enabled = true
	return config
end

local function runtime_snapshot(art, charge_confidence, charges)
	return {
		eligibility = 'eligible',
		active_sequence = nil,
		arts = { observed = art },
		stratagem = {
			confidence = charge_confidence,
			estimated_available = charges,
			recast_present = true,
			observed_recast = 0,
			model_key = 'SCH|99|true|2100|231',
			decoder_source = charge_confidence == 'confirmed'
				and 'fixture:confirmed_charge_state' or '',
		},
		environment = { party_generation = 7 },
		sublimation = { observed = 'none' },
		owned_buffs = {},
	}
end

local function dispatch_and_confirm_ja(runtime, step, action_buffs, at)
	local dispatched, dispatch_reason = runtime.note_dispatched(step, at)
	assert_true(dispatched, 'Scholar JA dispatch failed: ' .. tostring(dispatch_reason))
	local observed, observation_reason = runtime.observe_local_action({
		action_type = 'job_ability',
		action_name = step.action_name,
		success = true,
	}, at + 0.1)
	assert_true(observed, 'Scholar JA observation failed: ' .. tostring(observation_reason))
	runtime.observe_player_buffs(action_buffs, at + 0.2)
end

local function player()
	return {
		id = 1001,
		name = 'Scholar',
		main_job = 'SCH',
		main_job_level = 99,
		job_points = {
			sch = { jp_spent = 2100 },
		},
		buffs = { 358 },
		vitals = {
			hp = 2000,
			hpp = 100,
			mp = 1000,
			max_mp = 1500,
			mpp = 66,
		},
	}
end

local function members()
	return {
		{ id = 1001, name = 'Scholar', hpp = 100, x = 1, y = 2, z = 3, coordinate_observed_at = 100, buffs = { 358 } },
		{ id = 1002, name = 'Nyoourke', hpp = 100, x = 2, y = 2, z = 3, coordinate_observed_at = 100, buffs = {} },
		{ id = 1003, name = 'Redrogue', hpp = 100, x = 3, y = 2, z = 3, coordinate_observed_at = 100, buffs = { 590 } },
	}
end

local function unknown_area_mechanics()
	return {
		confidence = 'unknown',
		model_key = 'Accession|party',
		reason = 'fixture_accession_geometry_unvalidated',
	}
end

local function sublimation_safety(critical_defensive_present, dangerous_local_pressure_present)
	return {
		confidence = 'confirmed',
		model_key = 'scheduler_support_safety|v1',
		source = 'fixture:existing_scheduler_signals',
		critical_defensive_present = critical_defensive_present,
		dangerous_local_pressure_present = dangerous_local_pressure_present,
	}
end

local function sublimation_context(test_player, recast, safety, release_mechanics, ready)
	return {
		now = 100,
		player = test_player,
		party_members = members(),
		ability_recasts_present = true,
		ability_recasts = { [228] = 0, [234] = recast },
		sublimation_safety = safety,
		sublimation_release_mechanics = release_mechanics,
		action_ready = ready,
		action_readiness_source = 'unified_scheduler:action_ready',
	}
end

local function sublimation_ready()
	return true, '', 'ja'
end

local function maintenance_spell_ready()
	return true, '', 'spell'
end

local function main()
	package.loaded.uc_sch_maintenance = nil
	package.loaded.uc_provider_sch_maintenance = nil
	package.loaded.uc_sch_runtime = nil
	local maintenance = require('uc_sch_maintenance')
	local provider_module = require('uc_provider_sch_maintenance')
	local runtime = require('uc_sch_runtime')

	local arts_config = base_config()
	local arts_result = maintenance.evaluate(arts_config, {
		now = 100,
		player = player(),
		party_members = members(),
		ability_recasts_present = true,
		ability_recasts = { [228] = 0 },
		action_readiness_source = 'fixture:scheduler_action_ready',
		action_ready = function(action_name, target_id)
			assert_equal(action_name, 'Light Arts', 'Arts readiness action mismatch')
			assert_equal(target_id, 1001, 'Arts readiness target mismatch')
			return true, '', 'ja'
		end,
	}, runtime_snapshot('none', 'unknown', 0))
	assert_equal(arts_result.candidate.action_name, 'Light Arts', 'missing Arts candidate mismatch')
	assert_true(arts_result.candidate.observe_only == nil, 'Arts candidate must be executable')
	assert_equal(arts_result.arts.plan.purpose, 'ensure_light_arts', 'Arts plan purpose mismatch')
	assert_equal(arts_result.arts.plan.expected_buff_id, 358, 'Arts expected buff mismatch')
	assert_equal(arts_result.arts.plan.recast_id, 228, 'Arts recast id mismatch')
	assert_equal(arts_result.arts.plan.readiness_source, 'fixture:scheduler_action_ready',
		'Arts readiness source mismatch')
	assert_true(arts_result.candidate.plan == arts_result.arts.plan,
		'Arts candidate must carry the exact plan')
	local unknown_arts_result = maintenance.evaluate(arts_config, {
		now = 100,
		player = player(),
		party_members = members(),
	}, runtime_snapshot('unknown', 'unknown', 0))
	assert_true(unknown_arts_result.candidate == nil,
		'unknown Arts state must not authorize Light Arts')
	assert_equal(unknown_arts_result.first_blocker, 'arts_state_unknown',
		'unknown Arts blocker mismatch')
	local arts_recast_result = maintenance.evaluate(arts_config, {
		now = 100,
		player = player(),
		party_members = members(),
		ability_recasts_present = true,
		ability_recasts = { [228] = 12 },
		action_readiness_source = 'fixture:scheduler_action_ready',
		action_ready = function()
			error('Light Arts action_ready must not run while recast is unavailable')
		end,
	}, runtime_snapshot('dark', 'unknown', 0))
	assert_equal(arts_recast_result.first_blocker, 'arts_recast_unavailable',
		'Light Arts recast blocker mismatch')

	local storm_config = base_config()
	storm_config.support.storms.enabled = true
	storm_config.support.storms.assignments = {
		{ spell = 'Thunderstorm II', targets = { 'Nyoourke' } },
	}
	local storm_result = maintenance.evaluate(storm_config, {
		now = 100,
		player = player(),
		party_members = members(),
	}, runtime_snapshot('light', 'unknown', 0))
	assert_equal(storm_result.candidate.action_name, 'Thunderstorm II', 'missing storm candidate mismatch')
	assert_equal(storm_result.candidate.target_id, 1002, 'storm target mismatch')
	assert_true(storm_result.candidate.observe_only == nil, 'storm candidate must be executable')
	assert_equal(storm_result.storms.plan.purpose, 'targeted_storm', 'storm plan purpose mismatch')
	assert_equal(storm_result.storms.plan.party_generation, 7, 'storm plan party generation mismatch')
	assert_equal(storm_result.storms.plan.expected_recipients[1].id, 1002,
		'storm plan exact recipient mismatch')
	assert_equal(storm_result.storms.plan.duration_confidence, 'unknown',
		'unvalidated storm duration must remain unknown')
	assert_equal(storm_result.storms.plan.duration_model_key, 'storm|Thunderstorm II|',
		'storm duration model key mismatch')
	assert_true(storm_result.candidate.plan == storm_result.storms.plan,
		'storm candidate must carry the selected exact plan')
	local unknown_arts_storm = maintenance.evaluate(storm_config, {
		now = 100,
		player = player(),
		party_members = members(),
	}, runtime_snapshot('unknown', 'unknown', 0))
	assert_true(unknown_arts_storm.candidate == nil,
		'unknown Arts state must suppress an otherwise actionable storm')
	assert_equal(unknown_arts_storm.first_blocker, 'arts_state_unknown',
		'unknown Arts must remain the first storm-plan blocker')
	assert_equal(unknown_arts_storm.storms.plan.spell, 'Thunderstorm II',
		'blocked Arts state must preserve downstream storm diagnostics')
	local storm_without_arts = maintenance.evaluate(storm_config, {
		now = 100,
		player = player(),
		party_members = members(),
		ability_recasts_present = true,
		ability_recasts = { [228] = 0 },
		action_readiness_source = 'fixture:scheduler_action_ready',
		action_ready = function()
			return true, '', 'ja'
		end,
	}, runtime_snapshot('none', 'unknown', 0))
	assert_equal(storm_without_arts.candidate.action_name, 'Light Arts',
		'Light Arts must retain priority over an actionable storm')
	assert_equal(storm_without_arts.storms.plan.spell, 'Thunderstorm II',
		'storm diagnostics must retain the exact downstream plan while Arts is missing')

	local exact_members = members()
	exact_members[2].buffs = { 593 }
	local unowned_exact_result = maintenance.evaluate(storm_config, {
		now = 100,
		player = player(),
		party_members = exact_members,
	}, runtime_snapshot('light', 'unknown', 0))
	assert_true(unowned_exact_result.candidate == nil,
		'unowned exact storm must suppress an overwrite')
	assert_equal(unowned_exact_result.storms.assignments[1].state, 'blocked',
		'unowned exact storm state mismatch')
	assert_equal(unowned_exact_result.storms.assignments[1].ownership, 'unowned',
		'unowned exact storm ownership mismatch')
	assert_equal(unowned_exact_result.first_blocker, 'unowned_storm_wait_for_clear',
		'unowned exact storm blocker mismatch')

	local owned_exact_snapshot = runtime_snapshot('light', 'unknown', 0)
	owned_exact_snapshot.owned_buffs[1002] = {
		storm = {
			exact_spell = 'Thunderstorm II',
			status_id = 593,
			presence = 'present',
		},
	}
	local owned_exact_result = maintenance.evaluate(storm_config, {
		now = 100,
		player = player(),
		party_members = exact_members,
	}, owned_exact_snapshot)
	assert_true(owned_exact_result.candidate == nil,
		'confirmed owned exact storm must suppress an action')
	assert_equal(owned_exact_result.storms.assignments[1].state, 'satisfied_owned_present',
		'owned exact storm state mismatch')
	assert_equal(owned_exact_result.storms.assignments[1].ownership, 'confirmed',
		'owned exact storm ownership mismatch')

	local other_members = members()
	other_members[2].buffs = { 590 }
	local other_result = maintenance.evaluate(storm_config, {
		now = 100,
		player = player(),
		party_members = other_members,
	}, runtime_snapshot('light', 'unknown', 0))
	assert_true(other_result.candidate == nil, 'unowned other storm must not be overwritten')
	assert_equal(other_result.first_blocker, 'unowned_storm_wait_for_clear', 'storm ownership blocker mismatch')

	local invalid_storm_members = members()
	invalid_storm_members[2].hpp = '100'
	local invalid_storm_ok = pcall(maintenance.evaluate, storm_config, {
		now = 100,
		player = player(),
		party_members = invalid_storm_members,
	}, runtime_snapshot('light', 'unknown', 0))
	assert_true(not invalid_storm_ok, 'storm party evidence must reject coerced HPP values')

	local sublimation_config = base_config()
	sublimation_config.sublimation.enabled = true
	local activation_player = player()
	activation_player.vitals.mpp = 10
	activation_player.vitals.mp = 150
	local activation_snapshot = runtime_snapshot('light', 'unknown', 0)
	activation_snapshot.sublimation.observed = 'none'
	local activation_result = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			activation_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		activation_snapshot
	)
	assert_equal(activation_result.sublimation.state, 'actionable',
		'Sublimation activation state mismatch')
	assert_equal(activation_result.candidate.action_name, 'Sublimation',
		'Sublimation activation candidate mismatch')
	assert_equal(activation_result.sublimation.plan.purpose, 'sublimation_activate',
		'Sublimation activation plan purpose mismatch')
	assert_equal(activation_result.sublimation.plan.safety_source,
		'fixture:existing_scheduler_signals', 'Sublimation safety evidence mismatch')
	assert_equal(activation_result.sublimation.plan.observed_recast, 0,
		'Sublimation activation recast evidence mismatch')
	assert_equal(activation_result.sublimation.plan.readiness_source,
		'unified_scheduler:action_ready', 'Sublimation readiness source mismatch')
	assert_true(activation_result.sublimation.plan.missing_mp == nil,
		'Sublimation activation plan must not depend on current MP capacity')
	assert_true(activation_result.candidate.observe_only == nil,
		'Sublimation activation candidate must be executable')

	local low_hp_player = player()
	low_hp_player.vitals.hpp = 60
	low_hp_player.vitals.mpp = 100
	low_hp_player.vitals.mp = low_hp_player.vitals.max_mp
	local low_hp_activation = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			low_hp_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		activation_snapshot
	)
	assert_equal(low_hp_activation.sublimation.state, 'no_transition_required',
		'Sublimation activation must remain gated by minimum HPP')
	assert_true(low_hp_activation.candidate == nil,
		'low HPP must suppress Sublimation activation even at full MP')

	local unsafe_activation = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			activation_player,
			0,
			sublimation_safety(true, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		activation_snapshot
	)
	assert_equal(unsafe_activation.sublimation.blocker, 'sublimation_critical_defensive_pending',
		'critical defense must block Sublimation activation')
	local pressured_activation = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			activation_player,
			0,
			sublimation_safety(false, true),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		activation_snapshot
	)
	assert_equal(pressured_activation.sublimation.blocker, 'sublimation_dangerous_local_pressure',
		'hard emergency pressure must block Sublimation activation')
	local recast_activation = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			activation_player,
			12,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		activation_snapshot
	)
	assert_equal(recast_activation.sublimation.blocker, 'sublimation_recast_unavailable',
		'Sublimation recast blocker mismatch')
	local unavailable_activation = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			activation_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			function()
				return false, 'BLOCK_DEFENSIVE_JA_NOT_OWNED', 'ja'
			end
		),
		activation_snapshot
	)
	assert_equal(unavailable_activation.sublimation.blocker,
		'sublimation_action_unavailable:BLOCK_DEFENSIVE_JA_NOT_OWNED',
		'unlearned Sublimation blocker mismatch')
	local unknown_safety_context = sublimation_context(
		activation_player,
		0,
		{
			confidence = 'unknown',
			reason = 'scheduler_safety_unavailable',
		},
		require('uc_sch_sublimation').production_release_mechanics(),
		sublimation_ready
	)
	local unknown_safety_activation = maintenance.evaluate(
		sublimation_config,
		unknown_safety_context,
		activation_snapshot
	)
	assert_equal(unknown_safety_activation.sublimation.blocker, 'scheduler_safety_unavailable',
		'unknown Sublimation safety must block activation')

	local release_player = player()
	release_player.vitals.mpp = 40
	release_player.vitals.mp = 600
	local release_snapshot = runtime_snapshot('light', 'unknown', 0)
	release_snapshot.sublimation.observed = 'complete'
	local unknown_release = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			release_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		release_snapshot
	)
	assert_equal(unknown_release.sublimation.blocker, '',
		'captured Sublimation release capacity must authorize release')
	assert_equal(unknown_release.candidate.action_name, 'Sublimation',
		'captured Sublimation release candidate mismatch')
	assert_equal(unknown_release.sublimation.plan.minimum_missing_mp, 332,
		'captured Sublimation release capacity mismatch')
	local confirmed_release_mechanics = {
		confidence = 'confirmed',
		model_key = 'Sublimation|release_capacity',
		source = 'fixture:validated_release_capacity',
		minimum_missing_mp = 300,
	}
	local ready_release = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			release_player,
			0,
			sublimation_safety(false, false),
			confirmed_release_mechanics,
			sublimation_ready
		),
		release_snapshot
	)
	assert_equal(ready_release.sublimation.state, 'actionable',
		'Sublimation release state mismatch')
	assert_equal(ready_release.sublimation.plan.purpose, 'sublimation_release',
		'Sublimation release plan purpose mismatch')
	assert_equal(ready_release.sublimation.plan.release_capacity_model_key,
		'Sublimation|release_capacity', 'Sublimation release capacity model mismatch')
	assert_equal(ready_release.sublimation.plan.missing_mp, 900,
		'Sublimation release missing MP mismatch')

	local partial_release_snapshot = runtime_snapshot('light', 'unknown', 0)
	partial_release_snapshot.sublimation.observed = 'activated'
	local partial_release = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			release_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		partial_release_snapshot
	)
	assert_equal(partial_release.sublimation.plan.purpose, 'sublimation_release',
		'charging Sublimation must permit partial release at low MP')

	local banked_player = player()
	banked_player.vitals.mpp = 80
	banked_player.vitals.mp = 600
	local banked_release = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			banked_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		release_snapshot
	)
	assert_equal(banked_release.sublimation.state, 'no_transition_required',
		'complete Sublimation must remain banked above the release threshold')
	assert_true(banked_release.candidate == nil,
		'banked complete Sublimation must not request release')

	local immediate_config = base_config()
	immediate_config.sublimation.enabled = true
	immediate_config.sublimation.release_when_complete = true
	local immediate_release = maintenance.evaluate(
		immediate_config,
		sublimation_context(
			banked_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		release_snapshot
	)
	assert_equal(immediate_release.sublimation.plan.purpose, 'sublimation_release',
		'complete Sublimation must release immediately when configured')
	assert_equal(immediate_release.sublimation.plan.minimum_missing_mp, 332,
		'immediate complete release must retain the production capacity guard')

	local arts_before_sublimation = runtime_snapshot('none', 'unknown', 0)
	arts_before_sublimation.sublimation.observed = 'none'
	local arts_priority_result = maintenance.evaluate(
		sublimation_config,
		sublimation_context(
			activation_player,
			0,
			sublimation_safety(false, false),
			require('uc_sch_sublimation').production_release_mechanics(),
			sublimation_ready
		),
		arts_before_sublimation
	)
	assert_equal(arts_priority_result.candidate.action_name, 'Light Arts',
		'Light Arts must retain priority over Sublimation activation')
	assert_equal(arts_priority_result.sublimation.plan.purpose, 'sublimation_activate',
		'Sublimation plan must remain visible while Arts has priority')

	local regen_config = base_config()
	regen_config.support.regen.enabled = true
	local regen_result = maintenance.evaluate(regen_config, {
		now = 100,
		player = player(),
		party_members = members(),
		area_mechanics = unknown_area_mechanics(),
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'unknown', 0))
	assert_equal(regen_result.regen.blocker, 'charge_confidence_unknown', 'unknown charge Regen blocker mismatch')
	local geometry_result = maintenance.evaluate(regen_config, {
		now = 100,
		player = player(),
		party_members = members(),
		area_mechanics = unknown_area_mechanics(),
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_equal(geometry_result.regen.blocker, 'accession_geometry_unvalidated', 'geometry gate mismatch')
	local unknown_members = members()
	unknown_members[2].buffs = nil
	local unknown_result = maintenance.evaluate(regen_config, {
		now = 100,
		player = player(),
		party_members = unknown_members,
		area_mechanics = unknown_area_mechanics(),
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_equal(unknown_result.regen.blocker, 'party_buff_state_unknown', 'unknown party buff blocker mismatch')
	assert_equal(geometry_result.regen.geometry.blocker, 'accession_geometry_unvalidated',
		'observe-only geometry diagnostic mismatch')
	local unowned_members = members()
	unowned_members[1].buffs = { 42, 358 }
	local unowned_result = maintenance.evaluate(regen_config, {
		now = 100,
		player = player(),
		party_members = unowned_members,
		area_mechanics = unknown_area_mechanics(),
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_equal(unowned_result.regen.unowned_existing_recipient_ids[1], 1001,
		'unowned existing Regen recipient mismatch')

	local ready_config = base_config()
	ready_config.support.regen.enabled = true
	ready_config.support.regen.minimum_coverage = 3
	local ready_result = maintenance.evaluate(ready_config, {
		now = 100,
		player = player(),
		party_members = members(),
		area_mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:confirmed_accession_geometry',
			radius_yalms = 1,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_equal(ready_result.regen.state, 'actionable', 'ready Regen plan state mismatch')
	assert_equal(ready_result.candidate.action_name, 'Accession', 'ready Regen candidate mismatch')
	assert_equal(ready_result.regen.plan.anchor_id, 1002, 'ready Regen anchor mismatch')
	assert_equal(#ready_result.regen.plan.expected_recipients, 3,
		'ready Regen expected coverage mismatch')
	assert_equal(ready_result.regen.plan.geometry_source,
		'fixture:confirmed_accession_geometry', 'ready Regen geometry source mismatch')
	assert_true(ready_result.candidate.observe_only == nil, 'ready Regen candidate must be executable')

	local accession_storm_config = base_config()
	accession_storm_config.support.regen.enabled = true
	accession_storm_config.support.regen.spells = { 'Aurorastorm II' }
	accession_storm_config.support.regen.minimum_coverage = 3
	local accession_storm_members = members()
	accession_storm_members[3].buffs = {}
	local accession_storm_result = maintenance.evaluate(accession_storm_config, {
		now = 100,
		player = player(),
		party_members = accession_storm_members,
		area_mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:confirmed_accession_geometry',
			radius_yalms = 4,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_equal(accession_storm_result.candidate.action_name, 'Accession',
		'Accession Storm II must prepare Accession first')
	assert_equal(accession_storm_result.regen.plan.spell, 'Aurorastorm II',
		'Accession Storm II plan spell mismatch')
	assert_equal(accession_storm_result.regen.plan.buff_family, 'storm',
		'Accession Storm II must use storm ownership')
	assert_equal(accession_storm_result.regen.plan.stratagems[1], 'Accession',
		'Accession Storm II first stratagem mismatch')
	assert_equal(accession_storm_result.regen.plan.stratagems[2], 'Perpetuance',
		'Accession Storm II second stratagem mismatch')
	assert_equal(#accession_storm_result.regen.plan.expected_recipients, 3,
		'Accession Storm II expected coverage mismatch')

	local conflicting_storm_members = members()
	conflicting_storm_members[2].buffs = { 590 }
	conflicting_storm_members[3].buffs = {}
	local conflicting_storm_result = maintenance.evaluate(accession_storm_config, {
		now = 100,
		player = player(),
		party_members = conflicting_storm_members,
		area_mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:confirmed_accession_geometry',
			radius_yalms = 4,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_true(conflicting_storm_result.candidate == nil,
		'Accession Storm II must not overwrite an unowned conflicting Storm')
	assert_equal(conflicting_storm_result.regen.blocker, 'accession_no_safe_anchor',
		'Accession Storm II conflicting Storm blocker mismatch')

	local list_config = base_config()
	list_config.support.regen.enabled = true
	list_config.support.regen.spells = { 'Regen V', 'Phalanx' }
	list_config.support.regen.minimum_coverage = 3
	local list_members = members()
	local list_snapshot = runtime_snapshot('light', 'confirmed', 2)
	for i = 1, #list_members do
		list_members[i].buffs[#list_members[i].buffs + 1] = 42
		list_snapshot.owned_buffs[list_members[i].id] = {
			accession_42 = {
				exact_spell = 'Regen V',
				status_id = 42,
				presence = 'present',
			},
		}
	end
	local list_result = maintenance.evaluate(list_config, {
		now = 100,
		player = player(),
		party_members = list_members,
		area_mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:confirmed_accession_geometry',
			radius_yalms = 4,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
		spell_ready = maintenance_spell_ready,
	}, list_snapshot)
	assert_equal(list_result.regen.spell, 'Phalanx',
		'ordered maintenance list must advance past satisfied Regen V')
	assert_equal(list_result.regen.plan.anchor_id, 1001,
		'self-target Accession maintenance must anchor on the Scholar')
	assert_equal(list_result.regen.plan.buff_family, 'accession_116',
		'Phalanx ownership family mismatch')
	assert_true(list_result.regen.plan.atomic,
		'Accession and Perpetuance maintenance chain must be atomic')

	local blocked_list_members = members()
	blocked_list_members[1].buffs[#blocked_list_members[1].buffs + 1] = 42
	local blocked_list_result = maintenance.evaluate(list_config, {
		now = 100,
		player = player(),
		party_members = blocked_list_members,
		area_mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:confirmed_accession_geometry',
			radius_yalms = 4,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
		spell_ready = maintenance_spell_ready,
	}, runtime_snapshot('light', 'confirmed', 2))
	assert_equal(blocked_list_result.regen.spells[1].blocker, 'coverage_below_minimum',
		'partially unowned Regen must retain its overwrite-safety blocker')
	assert_equal(blocked_list_result.regen.spell, 'Phalanx',
		'a blocked earlier maintenance spell must not starve a later actionable spell')
	assert_equal(blocked_list_result.regen.active_spell, 'Phalanx',
		'ordered maintenance list must expose the selected later actionable spell')

	local provider_config = storm_config
	local provider_player = player()
	local provider_members = members()
	local logs = {}
	local use_confirmed_planning_evidence = false
	local ignore_trusts_enabled = false
	local provider = provider_module.new({
		capture = require('uc_sch_capture').new(),
		runtime = runtime,
		get_party_members = function()
			return provider_members
		end,
		resolve_spell_name = function(id)
			if id == 504 then
				return 'Regen V'
			end
			return nil
		end,
		resolve_ability_name = function(id)
			if id == 218 then
				return 'Accession'
			end
			return nil
		end,
		get_action_result_catalog = function(action_type, action_name)
			return {
				confidence = 'confirmed',
				model_key = action_type .. '|' .. action_name,
				source = 'fixture:provider_action_results',
				rules = {
					{ message_id = 101, param = 'any', outcome = 'success' },
					{ message_id = 230, param = 'any', outcome = 'success' },
				},
			}
		end,
		get_charge_catalog = function(main_job_level, job_points_present, job_points_spent)
			if use_confirmed_planning_evidence then
				return {
					confidence = 'confirmed',
					model_key = 'SCH|99|true|2100|231',
					source = 'fixture:provider_confirmed_charge_model',
					encoding = 'time_until_full',
					maximum_charges = 5,
					recharge_interval_s = 30,
					recast_unit_scale = 1,
					boundary_tolerance_s = 0,
					tabula_rasa_policy = 'use_recast',
				}
			end
			return require('uc_sch_charge_model').production_catalog(
				main_job_level,
				job_points_present,
				job_points_spent
			)
		end,
		get_area_mechanics = function()
			if use_confirmed_planning_evidence then
				return {
					confidence = 'confirmed',
					model_key = 'Accession|party',
					source = 'fixture:provider_confirmed_accession_geometry',
					radius_yalms = 1,
					max_coordinate_age_s = 1,
					distance_metric = 'horizontal',
				}
			end
			return unknown_area_mechanics()
		end,
		action_ready = function(action_name, target_id)
			assert_true(action_name == 'Sublimation' or action_name == 'Light Arts',
				'provider readiness action mismatch')
			assert_equal(target_id, provider_player.id, 'provider readiness target mismatch')
			return true, '', 'ja'
		end,
		sch_spell_ready = function()
			return true, '', 'spell'
		end,
		select_cure_spell = function()
			return 'Cure IV', ''
		end,
		status_removal_for_buff = function()
			return nil
		end,
		is_critical_defensive = function()
			return false
		end,
		get_sublimation_safety = function()
			return {
				confidence = 'confirmed',
				model_key = 'scheduler_support_safety|v1',
				source = 'fixture:provider_scheduler_safety',
				critical_defensive_present = false,
				dangerous_local_pressure_present = false,
			}
		end,
		get_sublimation_release_mechanics = function()
			return require('uc_sch_sublimation').production_release_mechanics()
		end,
		ignore_trusts = function()
			return ignore_trusts_enabled
		end,
		routine_priority = 75,
		prepared_priority = 150,
		defensive_priority = 145,
		log = function(message)
			logs[#logs + 1] = message
		end,
	})
	runtime.reset('provider_test', 100)
	local out = {}
	local emitted = provider.collect({
		now = 100,
		settings = { sch = provider_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 17 },
	}, out)
	assert_true(emitted == true, 'live provider must report its emitted proposal')
	assert_equal(#out, 1, 'live provider must append one scheduler proposal')
	local status = provider.status_snapshot()
	assert_equal(status.mode, 'live', 'provider mode mismatch')
	assert_equal(status.proposals_emitted, 1, 'provider emitted-count mismatch')
	assert_equal(out[1].action_name, 'Thunderstorm II', 'provider live proposal action mismatch')
	assert_equal(out[1].priority_band, 75, 'provider routine priority mismatch')
	assert_equal(status.candidate.action_name, 'Thunderstorm II', 'provider observed candidate mismatch')
	assert_equal(status.storms.plan.purpose, 'targeted_storm', 'provider storm plan purpose mismatch')
	assert_equal(status.storms.plan.target_id, 1002, 'provider storm plan target mismatch')
	assert_equal(status.storms.plan.expected_recipients[1].id, 1002,
		'provider storm plan exact recipient mismatch')
	assert_true(status.candidate.plan ~= nil, 'provider storm candidate must expose its exact plan')
	assert_equal(status.runtime.stratagem.confidence, 'confirmed',
		'provider must consume captured charge evidence')
	assert_equal(status.runtime.stratagem.estimated_available, 4,
		'provider captured charge count mismatch')
	assert_equal(status.runtime.stratagem.observed_recast, 17, 'provider raw recast observation mismatch')
	assert_equal(status.party_generation, 1, 'provider party generation mismatch')
	assert_equal(status.runtime.environment.party_generation, 1, 'runtime party generation mismatch')
	assert_true(#logs >= 2, 'provider initial diagnostic log count mismatch')
	assert_true(logs_contain(logs, 'SCH_CHARGE_OBSERVATION'),
		'provider initial charge diagnostic mismatch')
	assert_true(logs_contain(logs, 'SCH_OBSERVE'), 'provider observation diagnostic mismatch')
	assert_equal(status.job_points_spent, 2100, 'provider job-point status mismatch')
	local status_lines = provider.status_lines(100)
	assert_true(status_lines[2]:find('jp_spent=2100', 1, true) ~= nil,
		'provider status lines must include job-point context')
	local trace_armed, trace_message = provider.arm_trace_once(100.5)
	assert_true(trace_armed, 'one-shot trace failed to arm: ' .. tostring(trace_message))
	assert_true(not provider.arm_trace_once(100.6), 'already armed trace must reject duplicate arm')
	local traced_out = {}
	provider.collect({
		now = 101,
		settings = { sch = provider_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 16 },
	}, traced_out)
	assert_equal(#traced_out, 1, 'trace evaluation must retain the live proposal')
	assert_true(provider.status_snapshot().trace_armed, 'trace must wait for a relevant local action')
	provider.observe_action({
		actor_id = provider_player.id,
		category = 6,
		param = 218,
		targets = {
			{ id = provider_player.id, actions = { { message = 101, param = 218 } } },
		},
	}, provider_player.id, 101.2)
	provider.observe_action_message({
		actor_id = provider_player.id,
		target_id = provider_player.id,
		message_id = 101,
		param_1 = 218,
		_uc_source = 'raw_029',
	}, provider_player.id, 101.3)
	provider.collect({
		now = 104,
		settings = { sch = provider_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 16 },
	}, traced_out)
	local traced_status = provider.status_snapshot()
	assert_true(not traced_status.trace_armed, 'one-shot trace must disarm after transaction settlement')
	assert_equal(traced_status.last_trace.focus_action_name, 'Accession', 'trace focus action mismatch')
	assert_equal(traced_status.last_trace.terminal_reason, 'settled', 'trace terminal reason mismatch')
	assert_true(#traced_status.last_trace.events >= 5, 'transaction trace must retain raw evidence')
	assert_equal(traced_status.last_trace.events[2].party[1].coordinate_observed_at, 101,
		'provider trace must use the timestamped Scholar party snapshot')
	assert_true(logs_contain(logs, 'SCH_TRACE_COMPLETE'), 'one-shot trace completion log mismatch')

	local owned_state = runtime._test_state()
	owned_state.owned_buffs[1002] = {
		storm = {
			status_id = 593,
			presence = 'unknown',
			last_observed_at = 0,
		},
	}
	provider_members[2].buffs = { 593 }
	provider.collect({
		now = 105,
		settings = { sch = provider_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 15 },
	}, traced_out)
	assert_equal(runtime.snapshot().owned_buffs[1002].storm.presence, 'present',
		'provider must reconcile owned party buff presence')
	assert_equal(provider.status_snapshot().party_generation, 1,
		'vital and buff changes must not increment party generation')
	provider_members[3] = nil
	provider.collect({
		now = 106,
		settings = { sch = provider_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 14 },
	}, traced_out)
	assert_equal(provider.status_snapshot().party_generation, 2,
		'party membership change must increment provider generation')

	runtime.reset('provider_action_result_test', 200)
	runtime.configure(regen_config, { main_job = 'SCH' }, 1, 200)
	runtime.observe_environment({
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		main_job = 'SCH',
		player_hpp = 100,
		party_generation = 2,
		party_members = provider_members,
	}, 200)
	runtime.observe_player_buffs({ 358 }, 200)
	runtime.observe_charge({
		available = 2,
		maximum = 5,
		recast_present = true,
		observed_recast = 0,
		confidence = 'confirmed',
		tabula_rasa_active = false,
		model_key = 'SCH|99|true|2100|231',
		decoder_source = 'fixture:provider_confirmed_charge_state',
		reason = '',
	}, 200)
	assert_true(runtime.start_sequence({
		id = 'provider-result',
		purpose = 'party_accession_maintenance',
		domain = 'maintenance',
		required_art = 'light',
		required_addendum = nil,
		stratagems = { 'Accession', 'Perpetuance' },
		atomic = true,
		spell = 'Regen V',
		buff_family = 'accession_42',
		duration_family = 'accession_maintenance',
		spell_mp_multiplier = 2.0,
		anchor_id = 1001,
		anchor_name = 'Scholar',
		expected_recipients = {
			{ id = 1001, name = 'Scholar' },
			{ id = 1002, name = 'Nyoourke' },
		},
		party_generation = 2,
		deadline = 230,
	}, 200), 'provider result sequence start failed')
	local provider_accession = runtime.next_step(200.1)
	dispatch_and_confirm_ja(runtime, provider_accession, { 358, 366 }, 200.2)
	local provider_perpetuance = runtime.next_step(200.5)
	dispatch_and_confirm_ja(runtime, provider_perpetuance, { 358, 366, 469 }, 200.6)
	local provider_spell = runtime.next_step(200.9)
	assert_true(runtime.note_dispatched(provider_spell, 201), 'provider result spell dispatch failed')
	provider.observe_action({
		actor_id = provider_player.id,
		category = 4,
		param = 504,
		targets = {
			{ id = 1001, actions = { { message = 230, param = 42 } } },
			{ id = 1002, actions = { { message = 230, param = 42 } } },
		},
	}, provider_player.id, 203)
	assert_equal(runtime.snapshot().last_sequence.result, 'complete',
		'classified provider result must complete the reducer transaction')
	assert_equal(provider.status_snapshot().last_action_result.outcome, 'success',
		'provider action-result diagnostic mismatch')
	assert_equal(runtime.snapshot().owned_buffs[1002].accession_42.exact_spell, 'Regen V',
		'provider result must record classified successful ownership')

	use_confirmed_planning_evidence = true
	local trust_party_config = base_config()
	trust_party_config.support.regen.enabled = true
	trust_party_config.support.regen.spells = { 'Regen V' }
	trust_party_config.support.regen.minimum_coverage = 4
	provider_members = {
		{ id = 1001, name = 'Scholar', hpp = 100, x = 0, y = 0, z = 0, buffs = { 358 }, is_npc = false },
		{ id = 1002, name = 'Player2', hpp = 100, x = 0.1, y = 0, z = 0, buffs = {}, is_npc = false },
		{ id = 1003, name = 'Player3', hpp = 100, x = 0.2, y = 0, z = 0, buffs = {}, is_npc = false },
		{ id = 1004, name = 'Player4', hpp = 100, x = 0.3, y = 0, z = 0, buffs = {}, is_npc = false },
		{ id = 1005, name = 'Player5', hpp = 100, x = 0.4, y = 0, z = 0, buffs = {}, is_npc = false },
		{ id = 1006, name = 'Trust', hpp = 100, x = 0.5, y = 0, z = 0, buffs = nil, is_npc = true },
	}
	ignore_trusts_enabled = true
	provider_player.buffs = { 358 }
	runtime.reset('provider_ignore_trusts_regen', 239)
	local trust_party_out = {}
	provider.collect({
		now = 240,
		settings = { sch = trust_party_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 0 },
	}, trust_party_out)
	local trust_party_status = provider.status_snapshot()
	assert_equal(#trust_party_out, 1,
		'ignore trusts must allow observable player maintenance to emit')
	assert_equal(trust_party_out[1].action_name, 'Accession',
		'five missing players plus one ignored trust must prepare Accession')
	assert_equal(#trust_party_status.regen.plan.expected_recipients, 5,
		'ignored trust must not enter the Accession recipient plan')
	assert_equal(#trust_party_status.runtime.environment.party_members, 5,
		'ignored trust must not enter Scholar runtime party state')
	ignore_trusts_enabled = false
	provider_members = members()
	runtime.reset('observe_only_ready_plan', 249)
	local ready_out = {}
	provider.collect({
		now = 250,
		settings = { sch = ready_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 0 },
	}, ready_out)
	local ready_status = provider.status_snapshot()
	assert_equal(#ready_out, 1, 'ready Regen plan must emit one live proposal')
	assert_equal(ready_out[1].action_name, 'Accession', 'live Regen first step mismatch')
	assert_true(type(ready_out[1].detail.sch_step) == 'table',
		'live Regen proposal must carry its exact runtime step')
	assert_equal(ready_status.candidate.action_name, 'Accession',
		'provider ready Regen candidate mismatch')
	assert_equal(ready_status.regen.plan.anchor_id, 1002,
		'provider ready Regen anchor mismatch')
	assert_equal(ready_status.runtime.stratagem.confidence, 'confirmed',
		'provider confirmed fixture charge model mismatch')
	assert_equal(ready_status.proposals_emitted, 1,
		'provider ready Regen proposal count mismatch')
	local ready_status_lines = provider.status_lines(250)
	assert_true(ready_status_lines[6]:find(
		'plan=Regen V/1002 expected=1001,1002,1003 charge_model=SCH|99|true|2100|231',
		1,
		true
	) ~= nil, 'provider status must expose the complete observe-only Regen plan')

	provider_player.buffs = { 358 }
	provider_player.vitals.mpp = 80
	provider_player.vitals.mp = 1200
	provider_player.vitals.max_mp = 1500
	runtime.reset('observe_only_sublimation_activation', 259)
	local sublimation_out = {}
	provider.collect({
		now = 260,
		settings = { sch = sublimation_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 0, [234] = 0 },
	}, sublimation_out)
	local sublimation_status = provider.status_snapshot()
	assert_equal(#sublimation_out, 1,
		'ready Sublimation activation must emit one live proposal')
	assert_equal(sublimation_out[1].action_type, 'ja',
		'live Sublimation scheduler action type mismatch')
	assert_equal(sublimation_status.candidate.action_name, 'Sublimation',
		'provider Sublimation candidate mismatch')
	assert_equal(sublimation_status.sublimation.plan.purpose, 'sublimation_activate',
		'provider Sublimation plan purpose mismatch')
	assert_equal(sublimation_status.sublimation.plan.safety_source,
		'fixture:provider_scheduler_safety', 'provider Sublimation safety source mismatch')
	assert_equal(sublimation_status.proposals_emitted, 1,
		'provider ready Sublimation proposal count mismatch')
	local sublimation_status_lines = provider.status_lines(260)
	assert_true(sublimation_status_lines[8]:find(
		'plan=sublimation_activate recast=234/0 readiness=unified_scheduler:action_ready',
		1,
		true
	) ~= nil, 'provider status must expose the complete Sublimation activation plan')

	provider_player.buffs = {}
	runtime.reset('observe_only_light_arts', 269)
	local arts_out = {}
	provider.collect({
		now = 270,
		settings = { sch = arts_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [228] = 0, [231] = 0 },
	}, arts_out)
	local arts_status = provider.status_snapshot()
	assert_equal(#arts_out, 1, 'ready Light Arts plan must emit one live proposal')
	assert_equal(arts_out[1].action_name, 'Light Arts', 'live Light Arts proposal mismatch')
	assert_equal(arts_status.candidate.action_name, 'Light Arts',
		'provider Light Arts candidate mismatch')
	assert_equal(arts_status.arts.plan.purpose, 'ensure_light_arts',
		'provider Light Arts plan purpose mismatch')
	assert_equal(arts_status.arts.plan.recast_id, 228,
		'provider Light Arts recast id mismatch')
	assert_equal(arts_status.proposals_emitted, 1,
		'provider ready Light Arts proposal count mismatch')
	local arts_status_lines = provider.status_lines(270)
	assert_true(arts_status_lines[3]:find(
		'plan=ensure_light_arts recast=228/0 readiness=unified_scheduler:action_ready',
		1,
		true
	) ~= nil, 'provider status must expose the complete Light Arts plan')

	local defensive_config = base_config()
	defensive_config.defensive.accession_cure.enabled = true
	provider_members = members()
	for i = 1, #provider_members do
		provider_members[i].hp = 1000
		provider_members[i].max_hp = 2000
		provider_members[i].hpp = 50
		provider_members[i].buffs = {}
	end
	provider_player.buffs = { 358 }
	runtime.reset('provider_phase2_accession_cure', 279)
	local defensive_out = {}
	provider.collect({
		now = 280,
		settings = { sch = defensive_config, defensive_critical_hpp = 35 },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [231] = 0 },
	}, defensive_out)
	local defensive_status = provider.status_snapshot()
	assert_equal(#defensive_out, 1, 'Phase 2 provider must emit one live proposal')
	assert_equal(defensive_out[1].provider, 'defensive_sch',
		'Phase 2 provider route mismatch')
	assert_equal(defensive_out[1].action_name, 'Accession',
		'Phase 2 first action mismatch')
	assert_equal(defensive_out[1].priority_band, 145,
		'Phase 2 defensive priority mismatch')
	assert_equal(defensive_status.defensive.candidate.plan.purpose, 'accession_cure',
		'Phase 2 provider plan mismatch')
	assert_equal(defensive_status.defensive.candidate.plan.spell_mp_multiplier, 2.0,
		'Phase 2 provider MP adjustment mismatch')
	runtime.reset('provider_test_cleanup', 281)

	provider_members = members()
	table.remove(provider_members, 1)
	provider_player.buffs = { 358 }
	runtime.reset('provider_inconsistent_party_snapshot', 289)
	local inconsistent_party_out = {}
	local inconsistent_party_emitted = provider.collect({
		now = 290,
		settings = { sch = arts_config },
		player = provider_player,
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		ability_recasts_present = true,
		ability_recasts = { [228] = 0, [231] = 0 },
	}, inconsistent_party_out)
	local inconsistent_party_status = provider.status_snapshot()
	assert_true(inconsistent_party_emitted == false,
		'inconsistent party snapshot must not emit a Scholar proposal')
	assert_equal(#inconsistent_party_out, 0,
		'inconsistent party snapshot must leave the proposal set unchanged')
	assert_equal(inconsistent_party_status.first_blocker, 'party_snapshot_inconsistent',
		'missing player party snapshot blocker mismatch')
	assert_true(logs_contain(logs, 'blocker=party_snapshot_inconsistent'),
		'inconsistent party snapshot blocker must be observable')

	print('selftest_sch_maintenance: OK')
end

main()
