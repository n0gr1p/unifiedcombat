local ws_progression = require('data/ws_progression')

local M = {}

function M.progression_score(ws_id_or_name)
	return ws_progression.score(ws_id_or_name)
end

local function validate_candidate(candidate)
	if type(candidate) ~= 'table' then
		error('weapon-skill selector candidate must be a table')
	end
	if type(candidate.ws_name) ~= 'string' or candidate.ws_name == '' then
		error('weapon-skill selector candidate requires ws_name')
	end
	if type(candidate.ws_id) ~= 'number' then
		error('weapon-skill selector candidate requires numeric ws_id')
	end
	if type(candidate.path_rank) ~= 'number' then
		error('weapon-skill selector candidate requires numeric path_rank')
	end
	if type(candidate.skillchain_level) ~= 'number' then
		error('weapon-skill selector candidate requires numeric skillchain_level')
	end
	if type(candidate.progression_score) ~= 'number' then
		error('weapon-skill selector candidate requires numeric progression_score')
	end
end

function M.is_better(candidate, incumbent, configured_primary)
	validate_candidate(candidate)
	if incumbent == nil then
		return true
	end
	validate_candidate(incumbent)

	if candidate.path_rank ~= incumbent.path_rank then
		return candidate.path_rank > incumbent.path_rank
	end
	if candidate.skillchain_level ~= incumbent.skillchain_level then
		return candidate.skillchain_level > incumbent.skillchain_level
	end
	if candidate.progression_score ~= incumbent.progression_score then
		return candidate.progression_score > incumbent.progression_score
	end

	local primary = tostring(configured_primary or '')
	local candidate_is_primary = primary ~= '' and candidate.ws_name == primary
	local incumbent_is_primary = primary ~= '' and incumbent.ws_name == primary
	if candidate_is_primary ~= incumbent_is_primary then
		return candidate_is_primary
	end

	return candidate.ws_id < incumbent.ws_id
end

function M.select(candidates, configured_primary)
	if type(candidates) ~= 'table' then
		error('weapon-skill selector candidates must be a table')
	end
	local chosen = nil
	for i = 1, #candidates do
		if M.is_better(candidates[i], chosen, configured_primary) then
			chosen = candidates[i]
		end
	end
	return chosen
end

return M
