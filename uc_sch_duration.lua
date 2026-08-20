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

local function require_supported_spell(family, spell)
	if family == 'accession_maintenance' then
		if capabilities.accession_maintenance_spell(spell) == nil then
			error('Scholar duration Accession maintenance spell is unsupported')
		end
		return
	end
	if family == 'storm' then
		if capabilities.storm_spell(spell) == nil then
			error('Scholar duration storm spell is unsupported')
		end
		return
	end
	error('Scholar duration family is unsupported')
end

local function validated_modifiers(modifiers)
	require_table(modifiers, 'Scholar duration applied_modifiers')
	local out = {}
	local seen = {}
	for i = 1, #modifiers do
		local modifier = require_non_empty_string(
			modifiers[i],
			'Scholar duration applied modifier'
		)
		if seen[modifier] then
			error('Scholar duration applied modifiers must be unique')
		end
		seen[modifier] = true
		out[i] = modifier
	end
	for key in pairs(modifiers) do
		if type(key) ~= 'number' or key < 1 or key > #modifiers or key % 1 ~= 0 then
			error('Scholar duration applied_modifiers must be a contiguous array')
		end
	end
	return out
end

function M.model_key(family, spell, applied_modifiers)
	require_non_empty_string(family, 'Scholar duration family')
	require_non_empty_string(spell, 'Scholar duration spell')
	require_supported_spell(family, spell)
	local modifiers = validated_modifiers(applied_modifiers)
	return table.concat({ family, spell, table.concat(modifiers, ',') }, '|'), modifiers
end

function M.production_evidence(family, spell, applied_modifiers)
	local model_key = M.model_key(family, spell, applied_modifiers)
	if model_key == 'accession_maintenance|Regen V|Accession,Perpetuance' then
		return {
			confidence = 'confirmed',
			model_key = model_key,
			duration_s = 440,
			source = 'sch_capture:Nyoourke_solo_phase1_20260820T104827Z',
		}
	end
	return {
		confidence = 'unknown',
		reason = 'duration_not_captured_for_exact_effect',
	}
end

function M.estimate(input)
	require_table(input, 'Scholar duration input')
	local cast_at = require_finite_number(input.cast_at, 'Scholar duration cast_at')
	if cast_at < 0 then
		error('Scholar duration cast_at must be non-negative')
	end
	local model_key, modifiers = M.model_key(
		input.family,
		input.spell,
		input.applied_modifiers
	)
	local evidence = require_table(input.evidence, 'Scholar duration evidence')
	if evidence.confidence == 'unknown' then
		local reason = require_non_empty_string(
			evidence.reason,
			'Scholar unknown duration reason'
		)
		if evidence.model_key ~= nil
			or evidence.duration_s ~= nil
			or evidence.source ~= nil then
			error('Scholar unknown duration evidence must not claim model data')
		end
		return {
			duration_confidence = 'unknown',
			duration_s = 0,
			estimated_expires_at = 0,
			duration_reason = reason,
			duration_source = '',
			duration_model_key = model_key,
			applied_modifiers = modifiers,
		}
	end
	if evidence.confidence ~= 'confirmed' then
		error('Scholar duration evidence confidence must be unknown or confirmed')
	end
	if evidence.model_key ~= model_key then
		error('Scholar duration evidence model_key does not match the exact effect')
	end
	local duration_s = require_finite_number(
		evidence.duration_s,
		'Scholar confirmed duration_s'
	)
	if duration_s <= 0 then
		error('Scholar confirmed duration_s must be positive')
	end
	local source = require_non_empty_string(
		evidence.source,
		'Scholar confirmed duration source'
	)
	if evidence.reason ~= nil then
		error('Scholar confirmed duration evidence must not include an unknown reason')
	end
	return {
		duration_confidence = 'confirmed',
		duration_s = duration_s,
		estimated_expires_at = cast_at + duration_s,
		duration_reason = '',
		duration_source = source,
		duration_model_key = model_key,
		applied_modifiers = modifiers,
	}
end

return M
