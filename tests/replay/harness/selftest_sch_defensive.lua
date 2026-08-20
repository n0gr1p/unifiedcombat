local function assert_true(value, message)
	if not value then error(message or 'assertion failed') end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected)
			.. ', actual=' .. tostring(actual))
	end
end

local function config_for(feature)
	local config = require('uc_sch_config').default_config().defensive
	config[feature].enabled = true
	return config
end

local function member(id, name, hp, max_hp, x, buffs)
	return {
		id = id,
		name = name,
		hp = hp,
		max_hp = max_hp,
		hpp = math.floor((hp / max_hp) * 100),
		x = x,
		y = 0,
		z = 0,
		coordinate_observed_at = 100,
		buffs = buffs or {},
		charmed = false,
	}
end

local function context(members)
	return {
		now = 100,
		player = {
			id = 1001,
			name = 'Scholar',
			vitals = { mp = 1000, max_mp = 1500, mpp = 66 },
		},
		party_members = members,
		party_generation = 1,
		defensive_enabled = true,
		critical_cure_present = false,
		critical_hpp = 35,
		area_mechanics = {
			confidence = 'confirmed',
			model_key = 'Accession|party',
			source = 'fixture:phase2_geometry',
			radius_yalms = 10,
			max_coordinate_age_s = 1,
			distance_metric = 'horizontal',
		},
		status_removal_for_buff = function(buff_id)
			if buff_id == 3 then
				return { buff_id = 3, spell = 'Poisona', status_key = 'poison', priority = 0 }
			end
			return nil
		end,
		spell_ready = function()
			return true, '', 'spell'
		end,
		select_cure_spell = function()
			return 'Cure IV', ''
		end,
	}
end

local function runtime_snapshot()
	return { stratagem = { confidence = 'confirmed', estimated_available = 5 } }
end

local function configure_runtime(runtime, config, members)
	runtime.reset('phase2_test', 200)
	runtime.configure(config, { main_job = 'SCH' }, 1, 200)
	runtime.observe_environment({
		engine_enabled = true,
		maintenance_enabled = true,
		defensive_enabled = true,
		main_job = 'SCH',
		player_hpp = 100,
		party_generation = 1,
		party_members = members,
	}, 200)
	runtime.observe_player_buffs({ 358 }, 200)
	runtime.observe_charge({
		available = 5,
		maximum = 5,
		recast_present = true,
		observed_recast = 0,
		confidence = 'confirmed',
		tabula_rasa_active = false,
		model_key = 'SCH|99|true|2100|231',
		decoder_source = 'fixture:phase2_charge',
		reason = '',
	}, 200)
end

local function main()
	package.loaded.uc_sch_defensive = nil
	package.loaded.uc_sch_runtime = nil
	local defensive = require('uc_sch_defensive')
	local runtime = require('uc_sch_runtime')

	local status_members = {
		member(1001, 'Scholar', 2000, 2000, 0, {}),
		member(1002, 'One', 2000, 2000, 2, { 3 }),
		member(1003, 'Two', 2000, 2000, 4, { 3 }),
	}
	local status = defensive.evaluate(
		config_for('accession_status_removal'),
		context(status_members),
		runtime_snapshot()
	)
	assert_equal(status.candidate.plan.purpose, 'accession_status_removal',
		'area status purpose mismatch')
	assert_equal(status.candidate.plan.spell, 'Poisona', 'area status spell mismatch')
	assert_equal(status.candidate.plan.required_addendum, 'white',
		'-na sequence must require Addendum White')
	assert_equal(#status.candidate.plan.expected_recipients, 2,
		'area status recipient count mismatch')

	local cure_members = {
		member(1001, 'Scholar', 1000, 2000, 0),
		member(1002, 'One', 1000, 2000, 2),
		member(1003, 'Two', 1000, 2000, 4),
		member(1004, 'Healthy', 2000, 2000, 6),
	}
	local cure = defensive.evaluate(
		config_for('accession_cure'),
		context(cure_members),
		runtime_snapshot()
	)
	assert_equal(cure.candidate.plan.purpose, 'accession_cure',
		'area cure purpose mismatch')
	assert_equal(cure.candidate.plan.spell, 'Cure IV', 'area cure spell mismatch')
	assert_equal(cure.candidate.plan.total_missing_hp, 3000,
		'area cure total missing HP mismatch')
	assert_equal(cure.candidate.plan.spell_mp_multiplier, 2.0,
		'Accession cure MP multiplier mismatch')

	local critical_ctx = context(cure_members)
	critical_ctx.critical_cure_present = true
	local critical = defensive.evaluate(
		config_for('accession_cure'), critical_ctx, runtime_snapshot()
	)
	assert_equal(critical.blocker, 'critical_direct_cure_required',
		'critical direct-cure preemption mismatch')

	local rapture_members = {
		member(1001, 'Scholar', 4000, 4000, 0),
		member(1002, 'Tank', 2100, 4000, 2),
	}
	local rapture = defensive.evaluate(
		config_for('rapture'), context(rapture_members), runtime_snapshot()
	)
	assert_equal(rapture.candidate.plan.purpose, 'rapture_cure',
		'Rapture purpose mismatch')
	assert_equal(rapture.candidate.plan.stratagems[1], 'Rapture',
		'Rapture stratagem mismatch')

	local penury_ctx = context(rapture_members)
	penury_ctx.player.vitals.mpp = 40
	local penury = defensive.evaluate(
		config_for('penury'), penury_ctx, runtime_snapshot()
	)
	assert_equal(penury.candidate.plan.purpose, 'penury_cure',
		'Penury purpose mismatch')
	assert_equal(penury.candidate.plan.spell_mp_multiplier, 0.5,
		'Penury MP multiplier mismatch')

	local full_config = require('uc_sch_config').default_config()
	full_config.enabled = true
	full_config.defensive.accession_cure.enabled = true
	configure_runtime(runtime, full_config, cure_members)
	local plan = cure.candidate.plan
	plan.id = 'phase2-accession-cure'
	plan.deadline = 230
	assert_true(runtime.start_sequence(plan, 200), 'Phase 2 sequence did not start')
	local accession = runtime.next_step(200.1)
	assert_equal(accession.provider, 'defensive_sch', 'Phase 2 provider mismatch')
	assert_equal(accession.action_name, 'Accession', 'Phase 2 first action mismatch')
	assert_true(runtime.note_dispatched(accession, 200.2), 'Accession dispatch failed')
	assert_true(runtime.observe_local_action({
		action_type = 'job_ability', action_name = 'Accession', success = true,
	}, 200.3), 'Accession result failed')
	runtime.observe_player_buffs({ 358, 366 }, 200.4)
	local spell = runtime.next_step(200.5)
	assert_equal(spell.action_name, 'Cure IV', 'Phase 2 cure action mismatch')
	assert_equal(spell.spell_mp_multiplier, 2.0, 'Phase 2 dispatch MP multiplier mismatch')
	assert_true(runtime.note_dispatched(spell, 200.6), 'Cure dispatch failed')
	assert_true(runtime.observe_local_action({
		action_type = 'spell',
		action_name = 'Cure IV',
		success = true,
		successful_recipients = {
			{ id = 1001, name = 'Scholar' },
			{ id = 1002, name = 'One' },
			{ id = 1003, name = 'Two' },
		},
	}, 201), 'Cure result failed')
	assert_equal(runtime.snapshot().last_sequence.result, 'complete',
		'Phase 2 sequence completion mismatch')
	assert_true(next(runtime.snapshot().owned_buffs) == nil,
		'cures must not create durable buff ownership')

	print('selftest_sch_defensive: OK')
end

main()
