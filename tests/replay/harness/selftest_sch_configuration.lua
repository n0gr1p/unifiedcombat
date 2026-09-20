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

local function find_issue(issues, code)
	for i = 1, #issues do
		if issues[i].code == code then
			return issues[i]
		end
	end
	return nil
end

local function valid_config()
	local config = require('uc_sch_config').default_config()
	config.enabled = true
	config.sublimation.enabled = true
	config.support.regen.enabled = true
	config.support.storms.enabled = true
	config.support.storms.assignments = {
		{
			spell = 'Aurorastorm II',
			targets = { 'Redrogue', 'Terrasjr' },
		},
		{
			spell = 'Thunderstorm II',
			targets = { 'Nyoourke' },
		},
	}
	return config
end

local function main()
	package.loaded.uc_sch_capabilities = nil
	package.loaded.uc_sch_config = nil
	local capabilities = require('uc_sch_capabilities')
	local config_module = require('uc_sch_config')
	local normalizer = require('uc_config_normalizer')
	local active_config = require('uc_active_config')
	local contract = require('uc_profile_contract')
	local profile_v2 = require('uc_profile_v2')

	assert_equal(capabilities.JOB_ID, 20, 'SCH job id mismatch')
	assert_equal(capabilities.STRATAGEM_RECAST_ID, 231, 'stratagem recast id mismatch')
	assert_equal(capabilities.abilities.accession.id, 218, 'Accession id mismatch')
	assert_equal(capabilities.abilities.perpetuance.buff_id, 469, 'Perpetuance buff id mismatch')
	assert_equal(capabilities.abilities.addendum_white.recast_id, 231, 'Addendum recast id mismatch')
	assert_equal(capabilities.regen_spell('Regen V').status_id, 42, 'Regen V status mismatch')
	assert_equal(capabilities.accession_maintenance_spell('Phalanx').anchor_policy, 'self',
		'Phalanx maintenance anchor policy mismatch')
	assert_equal(capabilities.storm_spell('Aurorastorm II').status_id, 595, 'Aurorastorm II status mismatch')
	assert_equal(capabilities.accession_maintenance_spell('Aurorastorm II').status_id, 595,
		'Aurorastorm II must be available to Accession + Perpetuance maintenance')
	assert_equal(capabilities.accession_ownership_family('Aurorastorm II'), 'storm',
		'Accession Storm II must share storm ownership')
	assert_true(capabilities.storm_spell('Aurorastorm') == nil,
		'targeted Storm subsystem must remain Storm II-only')
	assert_equal(capabilities.accession_maintenance_spell('Aurorastorm').status_id, 184,
		'Storm I must be available to Accession + Perpetuance maintenance')
	assert_equal(capabilities.accession_maintenance_spell('Regen IV').status_id, 42,
		'Regen IV must be available to Accession + Perpetuance maintenance')
	assert_true(capabilities.accession_maintenance_spell('Haste') == nil,
		'Haste must remain excluded from Accession + Perpetuance maintenance')

	local missing = normalizer.normalize({}, { main_job = 'SCH' })
	assert_true(type(missing.sch) == 'table', 'missing Scholar section must create disabled canonical config')
	assert_equal(missing.sch.enabled, false, 'missing Scholar section must remain disabled')
	assert_equal(missing.sch.mode, 'support', 'default Scholar mode mismatch')
	assert_equal(missing.sch.support.regen.spells[1], 'Regen V', 'default maintenance spell mismatch')
	assert_true(config_module.validate(missing.sch, { main_job = 'SCH' }).valid, 'disabled default Scholar config must validate')

	local enabled = valid_config()
	local enabled_result = config_module.validate(enabled, { main_job = 'SCH' })
	assert_true(enabled_result.valid, 'valid enabled Scholar config must validate')
	assert_true(enabled_result.enabled, 'enabled Scholar result mismatch')

	local wrong_job = config_module.validate(enabled, { main_job = 'WHM' })
	assert_true(not wrong_job.valid, 'enabled Scholar config must reject non-SCH main job')
	assert_true(find_issue(wrong_job.errors, 'sch_main_job_required') ~= nil, 'wrong-job issue mismatch')

	local unknown = valid_config()
	unknown.runtime_state = {}
	local unknown_result = config_module.validate(unknown, { main_job = 'SCH' })
	assert_true(not unknown_result.valid, 'runtime-owned unknown key must fail validation')
	assert_true(find_issue(unknown_result.errors, 'sch_unknown_key') ~= nil, 'unknown-key issue mismatch')

	local malformed = valid_config()
	malformed.sublimation.enabled = 'true'
	assert_true(not config_module.validate(malformed, { main_job = 'SCH' }).valid, 'string boolean must fail validation')
	local malformed_normalize_ok = pcall(normalizer.normalize, { sch = malformed }, { main_job = 'SCH' })
	assert_true(not malformed_normalize_ok, 'normalizer must fail malformed Scholar booleans')

	local unsupported_mode = valid_config()
	unsupported_mode.mode = 'support_burst'
	local unsupported_mode_result = config_module.validate(unsupported_mode, { main_job = 'SCH' })
	assert_true(not unsupported_mode_result.valid, 'deferred Scholar mode must fail validation')
	assert_true(find_issue(unsupported_mode_result.errors, 'sch_mode_unsupported') ~= nil, 'mode issue mismatch')

	local expanded_maintenance = valid_config()
	expanded_maintenance.support.regen.spells = {
		'Protect IV', 'Shell III', 'Regen IV', 'Aurorastorm',
		'Animus Minuo', 'Invisible',
	}
	assert_true(config_module.validate(expanded_maintenance, { main_job = 'SCH' }).valid,
		'complete Accession + Perpetuance catalog must validate representative spells')

	local invalid_maintenance = valid_config()
	invalid_maintenance.support.regen.spells = { 'Haste' }
	local invalid_maintenance_result = config_module.validate(invalid_maintenance, { main_job = 'SCH' })
	assert_true(not invalid_maintenance_result.valid, 'Haste must not validate for Accession + Perpetuance')
	assert_true(find_issue(invalid_maintenance_result.errors, 'sch_accession_maintenance_spell_unsupported') ~= nil,
		'maintenance spell issue mismatch')

	local stackable_status_bars = valid_config()
	stackable_status_bars.support.regen.spells = { 'Barsleep', 'Barpoison' }
	assert_true(config_module.validate(stackable_status_bars, { main_job = 'SCH' }).valid,
		'status Barspells must remain independently maintainable')

	local stackable_animus = valid_config()
	stackable_animus.support.regen.spells = { 'Animus Augeo', 'Animus Minuo' }
	assert_true(config_module.validate(stackable_animus, { main_job = 'SCH' }).valid,
		'Animus spells must not be rejected as a configuration family conflict')

	local conflicting_buffs = valid_config()
	conflicting_buffs.support.regen.spells = { 'Enfire', 'Enwater' }
	local conflicting_buffs_result = config_module.validate(conflicting_buffs, { main_job = 'SCH' })
	assert_true(not conflicting_buffs_result.valid, 'mutually exclusive maintenance buffs must fail validation')
	assert_true(find_issue(conflicting_buffs_result.errors, 'sch_accession_maintenance_spell_conflict') ~= nil,
		'maintenance conflict issue mismatch')

	local storm_maintenance = valid_config()
	storm_maintenance.support.regen.spells = { 'Aurorastorm II' }
	assert_true(config_module.validate(storm_maintenance, { main_job = 'SCH' }).valid,
		'Storm II must validate in Accession + Perpetuance maintenance')

	local conflicting_storm_maintenance = valid_config()
	conflicting_storm_maintenance.support.regen.spells = { 'Aurorastorm II', 'Thunderstorm II' }
	local conflicting_storm_maintenance_result = config_module.validate(
		conflicting_storm_maintenance,
		{ main_job = 'SCH' }
	)
	assert_true(not conflicting_storm_maintenance_result.valid,
		'multiple Storm II maintenance spells must conflict')
	assert_true(find_issue(conflicting_storm_maintenance_result.errors,
		'sch_accession_maintenance_spell_conflict') ~= nil,
		'Storm II maintenance conflict issue mismatch')

	local invalid_stratagems = valid_config()
	invalid_stratagems.support.regen.stratagems = { 'Accession' }
	assert_true(
		not config_module.validate(invalid_stratagems, { main_job = 'SCH' }).valid,
		'partial Regen stratagem policy must fail validation'
	)

	local duplicate_target = valid_config()
	duplicate_target.support.storms.assignments[2].targets = { 'redrogue' }
	local duplicate_result = config_module.validate(duplicate_target, { main_job = 'SCH' })
	assert_true(not duplicate_result.valid, 'duplicate storm target must fail validation')
	assert_true(find_issue(duplicate_result.errors, 'sch_duplicate_storm_target') ~= nil, 'duplicate target issue mismatch')

	local unknown_storm = valid_config()
	unknown_storm.support.storms.assignments[1].spell = 'Aurorastorm'
	local unknown_storm_result = config_module.validate(unknown_storm, { main_job = 'SCH' })
	assert_true(not unknown_storm_result.valid, 'unknown Storm II spell must fail validation')
	assert_true(find_issue(unknown_storm_result.errors, 'sch_storm_spell_unsupported') ~= nil, 'storm issue mismatch')

	local unrestricted_release = valid_config()
	unrestricted_release.sublimation.release_when_mpp_at_most = 100
	assert_true(config_module.validate(unrestricted_release, { main_job = 'SCH' }).valid,
		'Sublimation release MPP must not be compared with an activation threshold')
	local legacy_sublimation = valid_config()
	legacy_sublimation.sublimation.activate_when_mpp_at_least = 95
	local legacy_copy, legacy_validation = config_module.copy_validated(
		legacy_sublimation,
		{ main_job = 'SCH' }
	)
	assert_true(legacy_validation.valid, 'legacy Sublimation activation MPP must be accepted during normalization')
	assert_true(legacy_copy.sublimation.activate_when_mpp_at_least == nil,
		'legacy Sublimation activation MPP must be discarded during normalization')

	local phase2 = valid_config()
	phase2.defensive.rapture.enabled = true
	assert_true(config_module.validate(phase2, { main_job = 'SCH' }).valid,
		'enabled Phase 2 defensive feature must validate')
	local deferred = valid_config()
	deferred.offense.magic_burst.enabled = true
	local deferred_result = config_module.validate(deferred, { main_job = 'SCH' })
	assert_true(not deferred_result.valid, 'enabled deferred feature must fail validation')
	assert_true(find_issue(deferred_result.errors, 'sch_deferred_feature_enabled') ~= nil, 'deferred issue mismatch')

	local normalized = normalizer.normalize({ sch = enabled }, { main_job = 'SCH' })
	assert_equal(normalized.sch.support.storms.assignments[1].spell, 'Aurorastorm II', 'nested normalization mismatch')
	assert_equal(normalized.sch.support.storms.assignments[2].targets[1], 'Nyoourke', 'nested target mismatch')

	local payload = {
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Tester',
			main_job = 'SCH',
			sub_job = 'RDM',
		},
		config = {
			sch = legacy_sublimation,
		},
	}
	local contract_result = contract.validate_structured_profile_config(payload)
	assert_true(contract_result.ok, 'Scholar payload must remain structurally valid')
	assert_true(contract_result.configuration_valid, 'valid Scholar config must keep configuration valid')
	assert_true(contract_result.sch.valid, 'contract must expose Scholar validation')

	local active_profile, active_error = active_config.build_active_profile_from_v2_payload(
		payload,
		{ main_job = 'SCH', sub_job = 'RDM' }
	)
	assert_true(type(active_profile) == 'table', 'Scholar active profile failed: ' .. tostring(active_error))
	local projected, projection_error = active_config.project_flat_settings(active_profile, {
		sch_sublimation_activate_when_mpp_at_least = 95,
	})
	assert_true(type(projected) == 'table', 'Scholar projection failed: ' .. tostring(projection_error))
	assert_true(type(projected.sch) == 'table', 'projected settings must carry exact nested Scholar config')
	assert_true(projected.sch.sublimation.activate_when_mpp_at_least == nil,
		'projected nested Scholar config must omit legacy activation MPP')
	assert_true(projected.sch_sublimation_activate_when_mpp_at_least == nil,
		'projected flat Scholar settings must omit legacy activation MPP')
	local legacy_apply_payload = profile_v2.build_structured_profile(
		normalizer.normalize({ sch = legacy_sublimation }, { main_job = 'SCH', sub_job = 'RDM' }),
		{
			character = 'Tester',
			main_job = 'SCH',
			sub_job = 'RDM',
			exported_at = '2026-08-20T00:00:00Z',
		}
	)
	legacy_apply_payload.config.sch.sublimation.activate_when_mpp_at_least = 95
	local legacy_apply = profile_v2.build_settings_candidate_from_structured_profile(
		{ sch_sublimation_activate_when_mpp_at_least = 95 },
		legacy_apply_payload,
		{ character = 'Tester', main_job = 'SCH', sub_job = 'RDM' }
	)
	assert_true(legacy_apply.ok == true,
		'legacy structured Scholar profile must load: ' .. tostring(legacy_apply.error))
	assert_equal(legacy_apply.diff_count, 0,
		'legacy activation MPP must not create a structured-profile conversion difference')
	assert_true(legacy_apply.candidate.sch_sublimation_activate_when_mpp_at_least == nil,
		'legacy structured profile apply must remove the flat activation MPP setting')
	assert_equal(projected.sch.support.regen.spells[1], 'Regen V', 'projected maintenance spell mismatch')
	assert_equal(projected.sch_accession_perpetuance_spells, 'Regen V',
		'projected maintenance spell list mismatch')
	assert_equal(projected.sch_enabled, true, 'projected Scholar enabled mismatch')
	assert_equal(projected.sch_arts_minimum_commit_s, 12, 'projected Scholar Arts commitment mismatch')
	assert_equal(projected.sch_regen_enabled, true, 'projected Scholar Regen enabled mismatch')
	assert_equal(projected.sch_regen_minimum_coverage, 4, 'projected Scholar Regen coverage mismatch')
	assert_equal(projected.sch_storms_enabled, true, 'projected Scholar storms enabled mismatch')
	assert_equal(
		projected.sch_storm_assignments,
		'Aurorastorm II:Redrogue,Terrasjr|Thunderstorm II:Nyoourke',
		'projected Scholar storm assignments mismatch'
	)
	assert_equal(projected.sch_sublimation_enabled, true, 'projected Scholar Sublimation enabled mismatch')
	assert_equal(projected.sch_sublimation_release_when_mpp_at_most, 45, 'projected Scholar release MPP mismatch')
	local round_trip = normalizer.normalize(projected, { main_job = 'SCH' })
	assert_equal(round_trip.sch.support.storms.assignments[1].targets[2], 'Terrasjr', 'Scholar round-trip mismatch')
	local exported = profile_v2.build_structured_profile({ sch = enabled }, {
		character = 'Tester',
		main_job = 'SCH',
		sub_job = 'RDM',
		exported_at = '2026-08-02T00:00:00Z',
	})
	assert_true(type(exported.config.sch) == 'table', 'SCH profile export must own config.sch')
	assert_equal(exported.config.sch.support.regen.spells[1], 'Regen V',
		'exported Scholar maintenance spell mismatch')
	local non_sch_export = profile_v2.build_structured_profile({}, {
		character = 'Tester',
		main_job = 'WHM',
		sub_job = 'RDM',
		exported_at = '2026-08-02T00:00:00Z',
	})
	assert_true(non_sch_export.config.sch == nil, 'non-SCH profile export must omit disabled config.sch')

	payload.profile.main_job = 'WHM'
	local wrong_job_contract = contract.validate_structured_profile_config(payload)
	assert_true(wrong_job_contract.ok, 'wrong-job Scholar payload must remain structurally valid')
	assert_true(not wrong_job_contract.configuration_valid, 'wrong-job Scholar config must be semantically invalid')
	local wrong_active, wrong_active_error = active_config.build_active_profile_from_v2_payload(
		payload,
		{ main_job = 'WHM', sub_job = 'RDM' }
	)
	assert_true(wrong_active == nil, 'active config must reject wrong-job Scholar automation')
	assert_true(type(wrong_active_error) == 'string' and wrong_active_error ~= '', 'active rejection must explain the failure')

	print('selftest_sch_configuration: OK')
end

main()
