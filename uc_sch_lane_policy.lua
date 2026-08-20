local M = {}

local VALID_CLASSES = {
	none = true,
	planning = true,
	prepared_support = true,
	timed_combat = true,
	dispatched = true,
}

function M.decide(lane, proposal, critical_cure, hard_emergency)
	if type(lane) ~= 'table' then
		error('Scholar lane policy requires lane state')
	end
	if VALID_CLASSES[lane.class] ~= true then
		error('Scholar lane policy received an invalid lane class')
	end
	if type(lane.reserved) ~= 'boolean' then
		error('Scholar lane policy requires a boolean reserved state')
	end
	if type(lane.atomic) ~= 'boolean' then
		error('Scholar lane policy requires a boolean atomic state')
	end
	if type(proposal) ~= 'table' then
		error('Scholar lane policy requires a proposal')
	end
	if type(critical_cure) ~= 'boolean' then
		error('Scholar lane policy requires a boolean critical-cure classification')
	end
	if type(hard_emergency) ~= 'boolean' then
		error('Scholar lane policy requires a boolean hard-emergency classification')
	end
	if lane.reserved ~= true then
		return {
			allowed = true,
			preempt = false,
			reason = '',
		}
	end
	local provider = tostring(proposal.provider or '')
	if provider == 'maintenance_sch' or provider == 'defensive_sch' then
		return {
			allowed = true,
			preempt = false,
			reason = 'sch_sequence_owner',
		}
	end
	if lane.atomic then
		return {
			allowed = false,
			preempt = false,
			reason = 'sch_lane_atomic',
		}
	end
	if lane.class == 'dispatched' then
		return {
			allowed = true,
			preempt = false,
			reason = '',
		}
	end
	if hard_emergency then
		return {
			allowed = true,
			preempt = true,
			reason = 'hard_emergency_preemption',
		}
	end
	if critical_cure then
		return {
			allowed = true,
			preempt = true,
			reason = 'critical_cure_preemption',
		}
	end
	return {
		allowed = false,
		preempt = false,
		reason = 'sch_lane_' .. lane.class,
	}
end

function M.holds_movement_and_targeting(lane)
	if type(lane) ~= 'table' or VALID_CLASSES[lane.class] ~= true then
		error('Scholar lane movement policy requires valid lane state')
	end
	if type(lane.reserved) ~= 'boolean' then
		error('Scholar lane movement policy requires a boolean reserved state')
	end
	if type(lane.atomic) ~= 'boolean' then
		error('Scholar lane movement policy requires a boolean atomic state')
	end
	return lane.class == 'prepared_support' or lane.class == 'timed_combat'
end

return M
