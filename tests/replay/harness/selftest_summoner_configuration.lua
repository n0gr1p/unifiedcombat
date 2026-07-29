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
	for _, issue in ipairs(issues) do
		if issue.code == code then
			return issue
		end
	end
	return nil
end

local function valid_summoner_config()
	return {
		enabled = true,
		avatar = 'Ifrit',
		maintenance = {
			avatar_favor = true,
			ward = {
				enabled = true,
				action = 'Crimson Howl',
			},
		},
		pet_combat = {
			engage_on_combat_start = true,
			offensive_action = {
				enabled = true,
				action = 'Flaming Crush',
				usage = 'on_cooldown',
			},
		},
	}
end

local function main()
	package.loaded.uc_smn_capabilities = nil
	package.loaded.uc_smn_config = nil
	local capabilities = require('uc_smn_capabilities')
	local validator = require('uc_smn_config')
	local normalizer = require('uc_config_normalizer')
	local contract = require('uc_profile_contract')
	local active_config = require('uc_active_config')

	local catalog = capabilities.get()
	assert_equal(#catalog.avatar_order, 11, 'supported avatar count mismatch')
	assert_equal(capabilities.avatar('Ifrit').summon_spell_id, 298, 'Ifrit summon spell id mismatch')
	assert_equal(capabilities.action('Ifrit', 'ward', 'Crimson Howl').effect_id, 68, 'Crimson Howl effect mismatch')
	assert_equal(capabilities.action('Ifrit', 'rage', 'Flaming Crush').id, 550, 'Flaming Crush resource id mismatch')
	assert_true(capabilities.action('Garuda', 'rage', 'Flaming Crush') == nil, 'cross-avatar Rage must be incompatible')

	local missing = normalizer.normalize({}, { main_job = 'SMN' })
	assert_equal(missing.summoner.enabled, false, 'missing Summoner section must normalize disabled')
	assert_true(missing.summoner.avatar == nil, 'missing Summoner avatar must remain nil')
	assert_equal(missing.summoner.pet_combat.offensive_action.usage, 'on_cooldown', 'default Rage usage mismatch')
	assert_true(validator.validate(missing.summoner).valid, 'disabled Summoner configuration must be valid')
	local malformed_normalize_ok = pcall(function()
		normalizer.normalize({
			summoner = {
				enabled = false,
				maintenance = 'invalid',
				pet_combat = {},
			},
		}, { main_job = 'SMN' })
	end)
	assert_true(not malformed_normalize_ok, 'malformed nested Summoner configuration must fail normalization')
	local malformed_boolean_ok = pcall(function()
		local invalid = valid_summoner_config()
		invalid.maintenance.avatar_favor = 'true'
		normalizer.normalize({ summoner = invalid }, { main_job = 'SMN' })
	end)
	assert_true(not malformed_boolean_ok, 'nested Summoner booleans must not use coercion fallbacks')

	local flat = normalizer.normalize({
		summoner_enabled = true,
		summoner_avatar = 'Ifrit',
		summoner_avatar_favor = true,
		summoner_ward_enabled = true,
		summoner_ward_action = 'Crimson Howl',
		summoner_engage_on_combat_start = true,
		summoner_rage_enabled = true,
		summoner_rage_action = 'Flaming Crush',
		summoner_rage_usage = 'on_cooldown',
	}, { main_job = 'SMN' })
	local valid = validator.validate(flat.summoner)
	assert_true(valid.valid, 'valid Summoner configuration must validate')
	assert_true(valid.ward_valid, 'compatible Ward must validate')
	assert_true(valid.rage_valid, 'compatible Rage must validate')

	local no_avatar = valid_summoner_config()
	no_avatar.avatar = nil
	local no_avatar_result = validator.validate(no_avatar)
	assert_true(not no_avatar_result.valid, 'enabled Summoner configuration must require an avatar')
	assert_true(find_issue(no_avatar_result.errors, 'avatar_required') ~= nil, 'missing avatar diagnostic mismatch')

	local invalid_avatar = valid_summoner_config()
	invalid_avatar.avatar = 'NotAnAvatar'
	local invalid_avatar_result = validator.validate(invalid_avatar)
	assert_true(not invalid_avatar_result.valid, 'unsupported avatar must invalidate Summoner automation')
	assert_true(find_issue(invalid_avatar_result.errors, 'avatar_unsupported') ~= nil, 'unsupported avatar diagnostic mismatch')

	local malformed = validator.validate({
		enabled = false,
		maintenance = 'invalid',
		pet_combat = {},
	})
	assert_true(not malformed.valid, 'disabled malformed Summoner shape must fail validation')
	assert_true(find_issue(malformed.errors, 'summoner_shape_invalid') ~= nil, 'malformed shape diagnostic mismatch')

	local incompatible = valid_summoner_config()
	incompatible.avatar = 'Garuda'
	local incompatible_result = validator.validate(incompatible)
	assert_true(incompatible_result.valid, 'compatible desired avatar must remain globally valid')
	assert_true(not incompatible_result.ward_valid, 'incompatible Ward must be suppressed')
	assert_true(not incompatible_result.rage_valid, 'incompatible Rage must be suppressed')
	assert_equal(incompatible.maintenance.ward.action, 'Crimson Howl', 'invalid Ward value must be preserved')
	assert_equal(incompatible.pet_combat.offensive_action.action, 'Flaming Crush', 'invalid Rage value must be preserved')
	assert_true(find_issue(incompatible_result.warnings, 'ward_incompatible') ~= nil, 'incompatible Ward diagnostic mismatch')
	assert_true(find_issue(incompatible_result.warnings, 'rage_incompatible') ~= nil, 'incompatible Rage diagnostic mismatch')

	local payload = {
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Tester',
			main_job = 'SMN',
			sub_job = 'RDM',
		},
		config = {
			summoner = incompatible,
		},
	}
	local contract_result = contract.validate_structured_profile_config(payload)
	assert_true(contract_result.ok, 'isolated Summoner incompatibility must not invalidate the profile container')
	assert_true(contract_result.configuration_valid, 'valid desired avatar must keep the configuration globally valid')
	assert_true(not contract_result.summoner.ward_valid, 'contract must expose incompatible Ward state')
	assert_true(not contract_result.summoner.rage_valid, 'contract must expose incompatible Rage state')

	payload.config.summoner = no_avatar
	local no_avatar_contract = contract.validate_structured_profile_config(payload)
	assert_true(no_avatar_contract.ok, 'Summoner semantic failure must not disable unrelated profile domains')
	assert_true(not no_avatar_contract.configuration_valid, 'missing avatar must mark configuration invalid')

	local active_profile = active_config.build_active_profile_from_v2_payload({
		version = 2,
		profile = payload.profile,
		config = {
			summoner = valid_summoner_config(),
		},
	}, { main_job = 'SMN', sub_job = 'RDM' })
	local projected, projection_error = active_config.project_flat_settings(active_profile, {})
	assert_true(type(projected) == 'table', 'Summoner projection failed: ' .. tostring(projection_error))
	assert_equal(projected.summoner_enabled, true, 'projected enabled mismatch')
	assert_equal(projected.summoner_avatar, 'Ifrit', 'projected avatar mismatch')
	assert_equal(projected.summoner_ward_action, 'Crimson Howl', 'projected Ward mismatch')
	assert_equal(projected.summoner_rage_action, 'Flaming Crush', 'projected Rage mismatch')

	local round_trip = normalizer.normalize(projected, { main_job = 'SMN' })
	assert_equal(round_trip.summoner.avatar, 'Ifrit', 'round-trip avatar mismatch')
	assert_equal(round_trip.summoner.maintenance.ward.action, 'Crimson Howl', 'round-trip Ward mismatch')
	assert_equal(round_trip.summoner.pet_combat.offensive_action.action, 'Flaming Crush', 'round-trip Rage mismatch')

	print('selftest_summoner_configuration: OK')
end

main()
