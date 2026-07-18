local M = {}

function M.spell_known_flag(v)
	return v == true or v == 1 or v == 'true'
end

function M.job_id_by_short(deps, short_name)
	local j = deps.jobs:with('english_short', tostring(short_name or ''))
	return tonumber(j and j.id) or 0
end

function M.action_target_mode(deps, action_name, action_kind)
	local targets = nil
	if action_kind == 'spell' then
		local sp = deps.get_spell_resource(action_name)
		targets = sp and sp.targets or nil
	elseif action_kind == 'ja' then
		local ja = deps.get_ja_resource(action_name)
		targets = ja and ja.targets or nil
	end
	if type(targets) == 'number' then
		return targets == 1 and 'self_only' or 'normal'
	end
	if type(targets) == 'table' then
		local has_self = targets.Self == true or targets.self == true
		local has_other = targets.Player == true or targets.player == true
			or targets.Party == true or targets.party == true
			or targets.Ally == true or targets.ally == true
			or targets.Enemy == true or targets.enemy == true
		return (has_self and not has_other) and 'self_only' or 'normal'
	end
	targets = tostring(targets or '')
	local has_self = targets:find('Self', 1, true) ~= nil
	local has_other = targets:find('Player', 1, true) ~= nil or
		targets:find('Party', 1, true) ~= nil or
		targets:find('Ally', 1, true) ~= nil or
		targets:find('Enemy', 1, true) ~= nil
	if has_self and not has_other then
		return 'self_only'
	end
	return 'normal'
end

function M.action_status_id(deps, name)
	local sp = deps.get_spell_resource(name)
	if sp and type(sp.status) == 'number' then
		return sp.status
	end
	local ja = deps.get_ja_resource(name)
	if ja and type(ja.status) == 'number' then
		return ja.status
	end
	return nil
end

function M.action_duration_seconds(deps, name, default_seconds)
	local sp = deps.get_spell_resource(name)
	if sp and type(sp.duration) == 'number' and sp.duration > 0 then
		return sp.duration
	end
	return default_seconds
end

function M.action_effective_range(deps, raw_range)
	local r = tonumber(raw_range) or 0
	if r <= 0 then
		return 0
	end
	local m = deps.SCHED_RANGE_MULT[r]
	if m then
		return r * m
	end
	if r > 20 then
		return r * 0.01
	end
	return r
end

return M
