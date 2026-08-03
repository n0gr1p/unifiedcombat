local capabilities = require('uc_sch_capabilities')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_non_empty_string(value, name)
	if type(value) ~= 'string' or value == '' then
		error(name .. ' must be a non-empty string')
	end
	return value
end

local function require_finite_number(value, name)
	if type(value) ~= 'number'
		or value ~= value
		or value == math.huge
		or value == -math.huge then
		error(name .. ' must be a finite number')
	end
	return value
end

local function require_non_negative_integer(value, name)
	local number_value = require_finite_number(value, name)
	if number_value < 0 or number_value % 1 ~= 0 then
		error(name .. ' must be a non-negative integer')
	end
	return number_value
end

function M.model_key(main_job_level, job_points_present, job_points_spent)
	local level = require_non_negative_integer(
		main_job_level,
		'Scholar charge main_job_level'
	)
	if level == 0 then
		error('Scholar charge main_job_level must be positive')
	end
	if type(job_points_present) ~= 'boolean' then
		error('Scholar charge job_points_present must be a boolean')
	end
	local spent = require_non_negative_integer(
		job_points_spent,
		'Scholar charge job_points_spent'
	)
	return table.concat({
		capabilities.JOB_SHORT_NAME,
		tostring(level),
		tostring(job_points_present),
		tostring(spent),
		tostring(capabilities.STRATAGEM_RECAST_ID),
	}, '|')
end

function M.production_catalog(main_job_level, job_points_present, job_points_spent)
	return {
		confidence = 'unknown',
		model_key = M.model_key(main_job_level, job_points_present, job_points_spent),
		reason = 'phase0_charge_mapping_unvalidated',
	}
end

local function validated_input(input)
	require_table(input, 'Scholar charge input')
	local model_key = M.model_key(
		input.main_job_level,
		input.job_points_present,
		input.job_points_spent
	)
	if type(input.recast_present) ~= 'boolean' then
		error('Scholar charge recast_present must be a boolean')
	end
	local observed_recast = input.observed_recast
	if input.recast_present then
		observed_recast = require_finite_number(
			observed_recast,
			'Scholar charge observed_recast'
		)
		if observed_recast < 0 then
			error('Scholar charge observed_recast must be non-negative')
		end
	elseif observed_recast ~= nil then
		error('Scholar charge observed_recast must be nil when recast data is absent')
	end
	if type(input.tabula_rasa_active) ~= 'boolean' then
		error('Scholar charge tabula_rasa_active must be a boolean')
	end
	return model_key, observed_recast
end

local function unknown_result(input, model_key, observed_recast, reason, source)
	local decoder_source = ''
	if source ~= nil then
		decoder_source = require_non_empty_string(source, 'Scholar charge decoder source')
	end
	return {
		available = 0,
		maximum = 0,
		recast_present = input.recast_present,
		observed_recast = observed_recast,
		confidence = 'unknown',
		tabula_rasa_active = input.tabula_rasa_active,
		model_key = model_key,
		decoder_source = decoder_source,
		reason = reason,
	}
end

local function validated_catalog(catalog, model_key)
	require_table(catalog, 'Scholar charge catalog')
	if catalog.model_key ~= model_key then
		error('Scholar charge catalog model_key does not match player progression')
	end
	if catalog.confidence == 'unknown' then
		local reason = require_non_empty_string(
			catalog.reason,
			'Scholar unknown charge reason'
		)
		local prohibited = {
			'source',
			'encoding',
			'maximum_charges',
			'recharge_interval_s',
			'recast_unit_scale',
			'boundary_tolerance_s',
			'tabula_rasa_policy',
		}
		for i = 1, #prohibited do
			if catalog[prohibited[i]] ~= nil then
				error('Scholar unknown charge catalog must not claim decoder parameters')
			end
		end
		return {
			confidence = 'unknown',
			reason = reason,
		}
	end
	if catalog.confidence ~= 'confirmed' then
		error('Scholar charge catalog confidence must be unknown or confirmed')
	end
	if catalog.reason ~= nil then
		error('Scholar confirmed charge catalog must not include an unknown reason')
	end
	if catalog.encoding ~= 'time_until_full' then
		error('Scholar confirmed charge encoding must be time_until_full')
	end
	local maximum = require_non_negative_integer(
		catalog.maximum_charges,
		'Scholar charge maximum_charges'
	)
	if maximum == 0 then
		error('Scholar charge maximum_charges must be positive')
	end
	local interval = require_finite_number(
		catalog.recharge_interval_s,
		'Scholar charge recharge_interval_s'
	)
	if interval <= 0 then
		error('Scholar charge recharge_interval_s must be positive')
	end
	local scale = require_finite_number(
		catalog.recast_unit_scale,
		'Scholar charge recast_unit_scale'
	)
	if scale <= 0 then
		error('Scholar charge recast_unit_scale must be positive')
	end
	local tolerance = require_finite_number(
		catalog.boundary_tolerance_s,
		'Scholar charge boundary_tolerance_s'
	)
	if tolerance < 0 or tolerance >= interval then
		error('Scholar charge boundary_tolerance_s must be non-negative and below the interval')
	end
	local tabula_policy = catalog.tabula_rasa_policy
	if tabula_policy ~= 'force_maximum'
		and tabula_policy ~= 'use_recast'
		and tabula_policy ~= 'unknown' then
		error('Scholar charge tabula_rasa_policy is invalid')
	end
	return {
		confidence = 'confirmed',
		source = require_non_empty_string(catalog.source, 'Scholar charge catalog source'),
		maximum = maximum,
		interval = interval,
		scale = scale,
		tolerance = tolerance,
		tabula_policy = tabula_policy,
	}
end

function M.decode(input, catalog)
	local model_key, observed_recast = validated_input(input)
	local model = validated_catalog(catalog, model_key)
	if input.job_points_present ~= true then
		return unknown_result(
			input,
			model_key,
			observed_recast,
			'job_points_unobserved',
			model.source
		)
	end
	if input.recast_present ~= true then
		return unknown_result(
			input,
			model_key,
			observed_recast,
			'recast_unavailable',
			model.source
		)
	end
	if model.confidence ~= 'confirmed' then
		return unknown_result(
			input,
			model_key,
			observed_recast,
			model.reason,
			nil
		)
	end
	if input.tabula_rasa_active and model.tabula_policy == 'unknown' then
		return unknown_result(
			input,
			model_key,
			observed_recast,
			'tabula_rasa_charge_semantics_unvalidated',
			model.source
		)
	end
	local available
	if input.tabula_rasa_active and model.tabula_policy == 'force_maximum' then
		available = model.maximum
	else
		local debt_seconds = observed_recast * model.scale
		local maximum_debt = model.maximum * model.interval
		if debt_seconds > maximum_debt + model.tolerance then
			return unknown_result(
				input,
				model_key,
				observed_recast,
				'recast_outside_confirmed_model',
				model.source
			)
		end
		local adjusted_debt = math.max(0, debt_seconds - model.tolerance)
		local missing_charges = math.ceil(adjusted_debt / model.interval)
		available = model.maximum - missing_charges
	end
	return {
		available = available,
		maximum = model.maximum,
		recast_present = true,
		observed_recast = observed_recast,
		confidence = 'confirmed',
		tabula_rasa_active = input.tabula_rasa_active,
		model_key = model_key,
		decoder_source = model.source,
		reason = '',
	}
end

return M
