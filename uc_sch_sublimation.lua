local M = {}

M.SAFETY_MODEL_KEY = 'scheduler_support_safety|v1'
M.RELEASE_MODEL_KEY = 'Sublimation|release_capacity'

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

function M.scheduler_safety(input)
	input = require_table(input, 'Scholar scheduler safety input')
	local proposals = require_table(
		input.proposals,
		'Scholar scheduler safety proposals'
	)
	if type(input.is_critical_defensive) ~= 'function' then
		error('Scholar scheduler safety critical classifier must be a function')
	end
	if type(input.player_doom_present) ~= 'boolean' then
		error('Scholar scheduler safety Doom signal must be boolean')
	end
	if type(input.defensive_evidence_current) ~= 'boolean' then
		error('Scholar scheduler defensive-evidence freshness must be boolean')
	end
	local source = require_non_empty_string(
		input.source,
		'Scholar scheduler safety source'
	)
	for key in pairs(proposals) do
		if type(key) ~= 'number' or key < 1 or key > #proposals or key % 1 ~= 0 then
			error('Scholar scheduler safety proposals must be a contiguous array')
		end
	end
	for i = 1, #proposals do
		if type(proposals[i]) ~= 'table' then
			error('Scholar scheduler safety proposal must be a table')
		end
	end
	if not input.defensive_evidence_current then
		return {
			confidence = 'unknown',
			reason = 'scheduler_defensive_evidence_not_current',
		}
	end
	local critical_defensive_present = false
	local dangerous_local_pressure_present = input.player_doom_present
	for i = 1, #proposals do
		local proposal = proposals[i]
		local critical = input.is_critical_defensive(proposal)
		if type(critical) ~= 'boolean' then
			error('Scholar scheduler safety critical classifier must return a boolean')
		end
		if critical then
			critical_defensive_present = true
		end
		if proposal.provider == 'charm_sleeper' then
			dangerous_local_pressure_present = true
		end
	end
	return {
		confidence = 'confirmed',
		model_key = M.SAFETY_MODEL_KEY,
		source = source,
		critical_defensive_present = critical_defensive_present,
		dangerous_local_pressure_present = dangerous_local_pressure_present,
	}
end

function M.validate_safety(evidence)
	evidence = require_table(evidence, 'Scholar Sublimation safety evidence')
	if evidence.confidence == 'unknown' then
		local reason = require_non_empty_string(
			evidence.reason,
			'Scholar unknown Sublimation safety reason'
		)
		if evidence.model_key ~= nil
			or evidence.source ~= nil
			or evidence.critical_defensive_present ~= nil
			or evidence.dangerous_local_pressure_present ~= nil then
			error('Scholar unknown Sublimation safety must not claim model data')
		end
		return {
			confidence = 'unknown',
			reason = reason,
			model_key = '',
			source = '',
			critical_defensive_present = false,
			dangerous_local_pressure_present = false,
		}
	end
	if evidence.confidence ~= 'confirmed' then
		error('Scholar Sublimation safety confidence must be unknown or confirmed')
	end
	if evidence.model_key ~= M.SAFETY_MODEL_KEY then
		error('Scholar Sublimation safety model key mismatch')
	end
	local source = require_non_empty_string(
		evidence.source,
		'Scholar confirmed Sublimation safety source'
	)
	if type(evidence.critical_defensive_present) ~= 'boolean'
		or type(evidence.dangerous_local_pressure_present) ~= 'boolean' then
		error('Scholar confirmed Sublimation safety signals must be boolean')
	end
	if evidence.reason ~= nil then
		error('Scholar confirmed Sublimation safety must not include an unknown reason')
	end
	return {
		confidence = 'confirmed',
		reason = '',
		model_key = M.SAFETY_MODEL_KEY,
		source = source,
		critical_defensive_present = evidence.critical_defensive_present,
		dangerous_local_pressure_present = evidence.dangerous_local_pressure_present,
	}
end

function M.production_release_mechanics()
	return {
		confidence = 'unknown',
		reason = 'phase0_sublimation_release_capacity_unvalidated',
	}
end

function M.evaluate_release_capacity(input, mechanics)
	input = require_table(input, 'Scholar Sublimation release-capacity input')
	local mp = require_finite_number(input.mp, 'Scholar Sublimation current MP')
	local max_mp = require_finite_number(input.max_mp, 'Scholar Sublimation maximum MP')
	if max_mp <= 0 or mp < 0 or mp > max_mp then
		error('Scholar Sublimation MP values are inconsistent')
	end
	mechanics = require_table(mechanics, 'Scholar Sublimation release mechanics')
	if mechanics.confidence == 'unknown' then
		local reason = require_non_empty_string(
			mechanics.reason,
			'Scholar unknown Sublimation release reason'
		)
		if mechanics.model_key ~= nil
			or mechanics.source ~= nil
			or mechanics.minimum_missing_mp ~= nil then
			error('Scholar unknown Sublimation release mechanics must not claim model data')
		end
		return {
			state = 'blocked',
			blocker = reason,
			missing_mp = max_mp - mp,
			model_key = '',
			source = '',
			minimum_missing_mp = 0,
		}
	end
	if mechanics.confidence ~= 'confirmed' then
		error('Scholar Sublimation release confidence must be unknown or confirmed')
	end
	if mechanics.model_key ~= M.RELEASE_MODEL_KEY then
		error('Scholar Sublimation release model key mismatch')
	end
	local source = require_non_empty_string(
		mechanics.source,
		'Scholar confirmed Sublimation release source'
	)
	local minimum_missing_mp = require_finite_number(
		mechanics.minimum_missing_mp,
		'Scholar Sublimation minimum missing MP'
	)
	if minimum_missing_mp <= 0 then
		error('Scholar Sublimation minimum missing MP must be positive')
	end
	if mechanics.reason ~= nil then
		error('Scholar confirmed Sublimation release mechanics must not include an unknown reason')
	end
	local missing_mp = max_mp - mp
	return {
		state = missing_mp >= minimum_missing_mp and 'ready' or 'blocked',
		blocker = missing_mp >= minimum_missing_mp
			and '' or 'sublimation_release_capacity_below_minimum',
		missing_mp = missing_mp,
		model_key = M.RELEASE_MODEL_KEY,
		source = source,
		minimum_missing_mp = minimum_missing_mp,
	}
end

return M
