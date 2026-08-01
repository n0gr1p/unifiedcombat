local numeric = require('uc_scheduler_numeric_utils')

local M = {}

function M.validate_identity(proposal)
	if type(proposal) ~= 'table' then
		return false, 'malformed'
	end
	if tostring(proposal.proposal_id or '') == '' or tostring(proposal.provider or '') == '' then
		return false, 'malformed'
	end
	return true, ''
end

function M.created_age(ctx, proposal)
	return numeric.p1_number(
		numeric.p1_number(ctx.now, 0) - numeric.p1_number(proposal.created_at, ctx.now),
		0
	)
end

function M.normalize_live_fields(ctx, proposal)
	local expires_at = numeric.p1_number(proposal.expires_at, ctx.now + 0.40)
	if expires_at <= ctx.now then
		return false, 'expired'
	end
	proposal.expires_at = expires_at
	proposal.commit_deadline = numeric.p1_number(proposal.commit_deadline, ctx.now + 0.25)
	proposal.priority_band = math.floor(numeric.p1_number(proposal.priority_band, 0))
	proposal.urgency = numeric.p1_clamp_urgency(proposal.urgency)
	return true, ''
end

function M.priority_bypasses_engage(proposal, engage_bypass_band)
	if type(proposal) ~= 'table' or type(proposal.priority_band) ~= 'number' then
		return false
	end
	return proposal.priority_band >= engage_bypass_band
end

return M
