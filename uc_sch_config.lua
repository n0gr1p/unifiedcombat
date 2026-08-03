local capabilities = require('uc_sch_capabilities')

local M = {}

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar configuration must not contain cycles')
	end
	visited[value] = true
	local out = {}
	for key, inner in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner, visited)
	end
	visited[value] = nil
	return out
end

local function add_issue(result, code, path, message)
	result.valid = false
	result.errors[#result.errors + 1] = {
		code = code,
		path = path,
		message = message,
	}
end

local function allowed_key_set(keys)
	local out = {}
	for i = 1, #keys do
		out[keys[i]] = true
	end
	return out
end

local function reject_unknown_keys(result, value, path, keys)
	if type(value) ~= 'table' then
		return
	end
	local allowed = allowed_key_set(keys)
	for key in pairs(value) do
		if type(key) ~= 'string' or allowed[key] ~= true then
			add_issue(
				result,
				'sch_unknown_key',
				path,
				('%s contains unknown key %q.'):format(path, tostring(key))
			)
		end
	end
end

local function require_table(result, parent, key, path)
	local value = parent[key]
	if type(value) ~= 'table' then
		add_issue(result, 'sch_shape_invalid', path, path .. ' must be a table.')
		return nil
	end
	return value
end

local function require_boolean(result, parent, key, path)
	if type(parent[key]) ~= 'boolean' then
		add_issue(result, 'sch_shape_invalid', path, path .. ' must be boolean.')
		return false
	end
	return true
end

local function require_string(result, parent, key, path)
	if type(parent[key]) ~= 'string' or parent[key] == '' then
		add_issue(result, 'sch_shape_invalid', path, path .. ' must be a non-empty string.')
		return false
	end
	return true
end

local function require_integer(result, parent, key, path, minimum, maximum)
	local value = parent[key]
	if type(value) ~= 'number' or value % 1 ~= 0 or value < minimum or value > maximum then
		add_issue(
			result,
			'sch_shape_invalid',
			path,
			('%s must be an integer from %d to %d.'):format(path, minimum, maximum)
		)
		return false
	end
	return true
end

local function array_length(result, value, path)
	if type(value) ~= 'table' then
		add_issue(result, 'sch_shape_invalid', path, path .. ' must be an array.')
		return nil
	end
	local length = #value
	for key in pairs(value) do
		if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > length then
			add_issue(result, 'sch_shape_invalid', path, path .. ' must be a contiguous array.')
			return nil
		end
	end
	return length
end

local function require_exact_array(result, value, path, expected)
	local length = array_length(result, value, path)
	if length == nil then
		return false
	end
	if length ~= #expected then
		add_issue(result, 'sch_policy_unsupported', path, path .. ' must match the supported Phase 1 policy exactly.')
		return false
	end
	for i = 1, #expected do
		if value[i] ~= expected[i] then
			add_issue(result, 'sch_policy_unsupported', path, path .. ' must match the supported Phase 1 policy exactly.')
			return false
		end
	end
	return true
end

local function validate_empty_array(result, value, path)
	local length = array_length(result, value, path)
	if length ~= nil and length ~= 0 then
		add_issue(result, 'sch_deferred_feature_enabled', path, path .. ' must remain empty in Phase 1.')
	end
end

local function validate_disabled_feature(result, value, path)
	if require_boolean(result, value, 'enabled', path .. '.enabled') and value.enabled ~= false then
		add_issue(result, 'sch_deferred_feature_enabled', path .. '.enabled', path .. ' is not implemented in Phase 1.')
	end
end

function M.default_config()
	return {
		enabled = false,
		mode = 'support',
		arts = {
			default = 'light',
			minimum_commit_s = 12,
			emergency_off_art_casts = true,
		},
		sublimation = {
			enabled = false,
			activate_when_mpp_at_least = 70,
			release_when_mpp_at_most = 45,
			release_when_complete = false,
			minimum_hpp_to_activate = 75,
		},
		support = {
			regen = {
				enabled = false,
				spell = 'Regen V',
				recipients = { 'party' },
				stratagems = { 'Accession', 'Perpetuance' },
				minimum_coverage = 4,
				refresh_before_s = 25,
				unknown_existing_policy = 'wait_for_clear',
			},
			storms = {
				enabled = false,
				assignments = {},
				refresh_before_s = 30,
				unknown_existing_policy = 'wait_for_clear',
			},
			embrava = {
				enabled = false,
				manual_arm_required = true,
			},
		},
		defensive = {
			accession_cure = {
				enabled = false,
				minimum_members = 3,
				member_hpp_at_most = 75,
				minimum_total_missing_hp = 2500,
			},
			accession_status_removal = {
				enabled = false,
				minimum_members = 2,
			},
			rapture = {
				enabled = false,
				minimum_missing_hp = 1800,
			},
			penury = {
				enabled = false,
				maximum_mpp = 45,
			},
		},
		offense = {
			magic_burst = {
				enabled = false,
				minimum_mpp = 35,
				minimum_target_hpp = 10,
				spells = {},
			},
			skillchain = {
				enabled = false,
				allow_party_close = false,
				plans = {},
			},
		},
	}
end

local function validate_arts(result, config)
	local arts = require_table(result, config, 'arts', 'sch.arts')
	if arts == nil then return end
	reject_unknown_keys(result, arts, 'sch.arts', {
		'default', 'minimum_commit_s', 'emergency_off_art_casts',
	})
	if require_string(result, arts, 'default', 'sch.arts.default') and arts.default ~= 'light' then
		add_issue(result, 'sch_policy_unsupported', 'sch.arts.default', 'Phase 1 requires sch.arts.default = "light".')
	end
	require_integer(result, arts, 'minimum_commit_s', 'sch.arts.minimum_commit_s', 0, 120)
	require_boolean(result, arts, 'emergency_off_art_casts', 'sch.arts.emergency_off_art_casts')
end

local function validate_sublimation(result, config)
	local value = require_table(result, config, 'sublimation', 'sch.sublimation')
	if value == nil then return end
	reject_unknown_keys(result, value, 'sch.sublimation', {
		'enabled', 'activate_when_mpp_at_least', 'release_when_mpp_at_most',
		'release_when_complete', 'minimum_hpp_to_activate',
	})
	require_boolean(result, value, 'enabled', 'sch.sublimation.enabled')
	local activate_ok = require_integer(
		result, value, 'activate_when_mpp_at_least', 'sch.sublimation.activate_when_mpp_at_least', 0, 100
	)
	local release_ok = require_integer(
		result, value, 'release_when_mpp_at_most', 'sch.sublimation.release_when_mpp_at_most', 0, 100
	)
	require_boolean(result, value, 'release_when_complete', 'sch.sublimation.release_when_complete')
	require_integer(result, value, 'minimum_hpp_to_activate', 'sch.sublimation.minimum_hpp_to_activate', 1, 100)
	if activate_ok and release_ok and value.release_when_mpp_at_most >= value.activate_when_mpp_at_least then
		add_issue(
			result,
			'sch_threshold_conflict',
			'sch.sublimation',
			'sch.sublimation.release_when_mpp_at_most must be less than activate_when_mpp_at_least.'
		)
	end
end

local function validate_regen(result, support)
	local regen = require_table(result, support, 'regen', 'sch.support.regen')
	if regen == nil then return end
	reject_unknown_keys(result, regen, 'sch.support.regen', {
		'enabled', 'spell', 'recipients', 'stratagems', 'minimum_coverage',
		'refresh_before_s', 'unknown_existing_policy',
	})
	require_boolean(result, regen, 'enabled', 'sch.support.regen.enabled')
	if require_string(result, regen, 'spell', 'sch.support.regen.spell')
		and capabilities.regen_spell(regen.spell) == nil then
		add_issue(result, 'sch_regen_spell_unsupported', 'sch.support.regen.spell', 'Phase 1 supports exact spell "Regen V" only.')
	end
	require_exact_array(result, regen.recipients, 'sch.support.regen.recipients', { 'party' })
	require_exact_array(
		result,
		regen.stratagems,
		'sch.support.regen.stratagems',
		{ 'Accession', 'Perpetuance' }
	)
	require_integer(result, regen, 'minimum_coverage', 'sch.support.regen.minimum_coverage', 1, 6)
	require_integer(result, regen, 'refresh_before_s', 'sch.support.regen.refresh_before_s', 1, 300)
	if require_string(result, regen, 'unknown_existing_policy', 'sch.support.regen.unknown_existing_policy')
		and regen.unknown_existing_policy ~= 'wait_for_clear' then
		add_issue(
			result,
			'sch_policy_unsupported',
			'sch.support.regen.unknown_existing_policy',
			'Phase 1 supports unknown_existing_policy = "wait_for_clear" only.'
		)
	end
end

local function validate_storms(result, support)
	local storms = require_table(result, support, 'storms', 'sch.support.storms')
	if storms == nil then return end
	reject_unknown_keys(result, storms, 'sch.support.storms', {
		'enabled', 'assignments', 'refresh_before_s', 'unknown_existing_policy',
	})
	require_boolean(result, storms, 'enabled', 'sch.support.storms.enabled')
	require_integer(result, storms, 'refresh_before_s', 'sch.support.storms.refresh_before_s', 1, 300)
	if require_string(result, storms, 'unknown_existing_policy', 'sch.support.storms.unknown_existing_policy')
		and storms.unknown_existing_policy ~= 'wait_for_clear' then
		add_issue(
			result,
			'sch_policy_unsupported',
			'sch.support.storms.unknown_existing_policy',
			'Phase 1 supports unknown_existing_policy = "wait_for_clear" only.'
		)
	end
	local length = array_length(result, storms.assignments, 'sch.support.storms.assignments')
	if length == nil then return end
	local assigned_targets = {}
	for index = 1, length do
		local assignment = storms.assignments[index]
		local path = ('sch.support.storms.assignments[%d]'):format(index)
		if type(assignment) ~= 'table' then
			add_issue(result, 'sch_shape_invalid', path, path .. ' must be a table.')
		else
			reject_unknown_keys(result, assignment, path, { 'spell', 'targets' })
			if require_string(result, assignment, 'spell', path .. '.spell')
				and capabilities.storm_spell(assignment.spell) == nil then
				add_issue(result, 'sch_storm_spell_unsupported', path .. '.spell', ('Unknown Storm II spell %q.'):format(assignment.spell))
			end
			local target_count = array_length(result, assignment.targets, path .. '.targets')
			if target_count ~= nil then
				if target_count == 0 then
					add_issue(result, 'sch_shape_invalid', path .. '.targets', path .. '.targets must not be empty.')
				end
				for target_index = 1, target_count do
					local target_name = assignment.targets[target_index]
					local target_path = ('%s.targets[%d]'):format(path, target_index)
					if type(target_name) ~= 'string' or target_name == '' then
						add_issue(result, 'sch_shape_invalid', target_path, target_path .. ' must be a non-empty string.')
					else
						local key = target_name:lower()
						if assigned_targets[key] ~= nil then
							add_issue(
								result,
								'sch_duplicate_storm_target',
								target_path,
								('Storm target %q is assigned more than once.'):format(target_name)
							)
						else
							assigned_targets[key] = target_path
						end
					end
				end
			end
		end
	end
end

local function validate_support(result, config)
	local support = require_table(result, config, 'support', 'sch.support')
	if support == nil then return end
	reject_unknown_keys(result, support, 'sch.support', { 'regen', 'storms', 'embrava' })
	validate_regen(result, support)
	validate_storms(result, support)
	local embrava = require_table(result, support, 'embrava', 'sch.support.embrava')
	if embrava ~= nil then
		reject_unknown_keys(result, embrava, 'sch.support.embrava', { 'enabled', 'manual_arm_required' })
		validate_disabled_feature(result, embrava, 'sch.support.embrava')
		if require_boolean(result, embrava, 'manual_arm_required', 'sch.support.embrava.manual_arm_required')
			and embrava.manual_arm_required ~= true then
			add_issue(
				result,
				'sch_manual_arm_required',
				'sch.support.embrava.manual_arm_required',
				'Embrava requires manual_arm_required = true.'
			)
		end
	end
end

local function validate_defensive(result, config)
	local defensive = require_table(result, config, 'defensive', 'sch.defensive')
	if defensive == nil then return end
	reject_unknown_keys(result, defensive, 'sch.defensive', {
		'accession_cure', 'accession_status_removal', 'rapture', 'penury',
	})
	local accession_cure = require_table(result, defensive, 'accession_cure', 'sch.defensive.accession_cure')
	if accession_cure ~= nil then
		reject_unknown_keys(result, accession_cure, 'sch.defensive.accession_cure', {
			'enabled', 'minimum_members', 'member_hpp_at_most', 'minimum_total_missing_hp',
		})
		validate_disabled_feature(result, accession_cure, 'sch.defensive.accession_cure')
		require_integer(result, accession_cure, 'minimum_members', 'sch.defensive.accession_cure.minimum_members', 2, 6)
		require_integer(result, accession_cure, 'member_hpp_at_most', 'sch.defensive.accession_cure.member_hpp_at_most', 1, 99)
		require_integer(result, accession_cure, 'minimum_total_missing_hp', 'sch.defensive.accession_cure.minimum_total_missing_hp', 1, 99999)
	end
	local status = require_table(
		result, defensive, 'accession_status_removal', 'sch.defensive.accession_status_removal'
	)
	if status ~= nil then
		reject_unknown_keys(result, status, 'sch.defensive.accession_status_removal', { 'enabled', 'minimum_members' })
		validate_disabled_feature(result, status, 'sch.defensive.accession_status_removal')
		require_integer(result, status, 'minimum_members', 'sch.defensive.accession_status_removal.minimum_members', 2, 6)
	end
	local rapture = require_table(result, defensive, 'rapture', 'sch.defensive.rapture')
	if rapture ~= nil then
		reject_unknown_keys(result, rapture, 'sch.defensive.rapture', { 'enabled', 'minimum_missing_hp' })
		validate_disabled_feature(result, rapture, 'sch.defensive.rapture')
		require_integer(result, rapture, 'minimum_missing_hp', 'sch.defensive.rapture.minimum_missing_hp', 1, 99999)
	end
	local penury = require_table(result, defensive, 'penury', 'sch.defensive.penury')
	if penury ~= nil then
		reject_unknown_keys(result, penury, 'sch.defensive.penury', { 'enabled', 'maximum_mpp' })
		validate_disabled_feature(result, penury, 'sch.defensive.penury')
		require_integer(result, penury, 'maximum_mpp', 'sch.defensive.penury.maximum_mpp', 0, 100)
	end
end

local function validate_offense(result, config)
	local offense = require_table(result, config, 'offense', 'sch.offense')
	if offense == nil then return end
	reject_unknown_keys(result, offense, 'sch.offense', { 'magic_burst', 'skillchain' })
	local burst = require_table(result, offense, 'magic_burst', 'sch.offense.magic_burst')
	if burst ~= nil then
		reject_unknown_keys(result, burst, 'sch.offense.magic_burst', {
			'enabled', 'minimum_mpp', 'minimum_target_hpp', 'spells',
		})
		validate_disabled_feature(result, burst, 'sch.offense.magic_burst')
		require_integer(result, burst, 'minimum_mpp', 'sch.offense.magic_burst.minimum_mpp', 0, 100)
		require_integer(result, burst, 'minimum_target_hpp', 'sch.offense.magic_burst.minimum_target_hpp', 1, 100)
		validate_empty_array(result, burst.spells, 'sch.offense.magic_burst.spells')
	end
	local skillchain = require_table(result, offense, 'skillchain', 'sch.offense.skillchain')
	if skillchain ~= nil then
		reject_unknown_keys(result, skillchain, 'sch.offense.skillchain', {
			'enabled', 'allow_party_close', 'plans',
		})
		validate_disabled_feature(result, skillchain, 'sch.offense.skillchain')
		if require_boolean(result, skillchain, 'allow_party_close', 'sch.offense.skillchain.allow_party_close')
			and skillchain.allow_party_close ~= false then
			add_issue(
				result,
				'sch_deferred_feature_enabled',
				'sch.offense.skillchain.allow_party_close',
				'allow_party_close is not implemented in Phase 1.'
			)
		end
		validate_empty_array(result, skillchain.plans, 'sch.offense.skillchain.plans')
	end
end

function M.validate(config, meta)
	local result = {
		enabled = false,
		valid = true,
		errors = {},
		warnings = {},
	}
	if config == nil then
		return result
	end
	if type(config) ~= 'table' then
		add_issue(result, 'sch_not_table', 'sch', 'Scholar configuration must be a table.')
		return result
	end
	reject_unknown_keys(result, config, 'sch', {
		'enabled', 'mode', 'arts', 'sublimation', 'support', 'defensive', 'offense',
	})
	require_boolean(result, config, 'enabled', 'sch.enabled')
	if require_string(result, config, 'mode', 'sch.mode') and config.mode ~= 'support' then
		add_issue(result, 'sch_mode_unsupported', 'sch.mode', 'Phase 1 supports sch.mode = "support" only.')
	end
	validate_arts(result, config)
	validate_sublimation(result, config)
	validate_support(result, config)
	validate_defensive(result, config)
	validate_offense(result, config)
	result.enabled = config.enabled == true
	if result.enabled and type(meta) == 'table' then
		local main_job = tostring(meta.main_job or meta.job or ''):upper()
		if main_job ~= '' and main_job ~= 'UNKNOWN' and main_job ~= capabilities.JOB_SHORT_NAME then
			add_issue(
				result,
				'sch_main_job_required',
				'profile.main_job',
				('Scholar automation requires main job SCH, not %s.'):format(main_job)
			)
		end
	end
	return result
end

function M.copy_validated(config, meta)
	local validation = M.validate(config, meta)
	if not validation.valid then
		local first = validation.errors[1]
		error(first and first.message or 'Scholar configuration is invalid')
	end
	if config == nil then
		return M.default_config(), validation
	end
	return clone_value(config), validation
end

return M
