local M = {}

local config_aliases = {
	['paralyze'] = 'paralysis',
	['petrify'] = 'petrification',
}

local function trim(value)
	return tostring(value or ''):match('^%s*(.-)%s*$')
end

function M.normalize_config_key(value)
	local key = trim(value):lower():gsub('%s+', '_')
	if key == 'blindness' then
		key = 'blind'
	end
	return config_aliases[key] or key
end

function M.parse_priority_list(raw, known_status_keys)
	local order = {}
	local rank_by_key = {}
	for token in (tostring(raw or '') .. '|'):gmatch('(.-)|') do
		local key = M.normalize_config_key(token)
		local known = type(known_status_keys) ~= 'table' or known_status_keys[key] == true
		if key ~= '' and known and rank_by_key[key] == nil then
			order[#order + 1] = key
			rank_by_key[key] = #order
		end
	end
	return {
		order = order,
		rank_by_key = rank_by_key,
	}
end

local function limited_candidate_better(candidate, current)
	if not current then
		return true
	end
	if candidate.status_rank ~= current.status_rank then
		return candidate.status_rank < current.status_rank
	end
	return candidate.prio < current.prio
end

function M.choose_status_removal(members, options, deps)
	options = type(options) == 'table' and options or {}
	deps = type(deps) == 'table' and deps or {}
	if options.enabled ~= true then
		return nil
	end

	local limited = options.limit_enabled == true
	local policy = M.parse_priority_list(options.priority, deps.known_status_keys)
	local selected = nil

	for _, member in ipairs(type(members) == 'table' and members or {}) do
		local spell_in_range = deps.in_party_cast_range(member)
		local alternative_in_range = type(deps.status_removal_alternative_in_range) == 'function'
			and deps.status_removal_alternative_in_range(member) == true
		if spell_in_range or alternative_in_range then
			local best = nil
			for _, buff_id in ipairs(type(member.buffs) == 'table' and member.buffs or {}) do
				local buff_res = deps.buffs and deps.buffs[buff_id] or nil
				local status_name = buff_res and buff_res.en or ''
				local spell = deps.debuff_map[status_name] or deps.debuff_spell_for_buff_id(buff_id)
				local status_key = deps.normalize_status_removal_key(buff_res, buff_id)
				local status_rank = limited and policy.rank_by_key[status_key] or nil
				if spell and (not limited or status_rank ~= nil) then
					local action_name = nil
					local action_kind = nil
					local action_detail = nil
					local ready = false
					local spell_blocked = type(deps.spell_status_removal_blocked) == 'function'
						and deps.spell_status_removal_blocked(member, buff_id, status_key, spell) == true
					if spell_in_range and not spell_blocked then
						ready = deps.action_ready(spell)
					end
					if ready then
						action_name = spell
						action_kind = 'spell'
					elseif type(deps.status_removal_alternative) == 'function' then
						local alternative = deps.status_removal_alternative(member, buff_id, status_key, spell)
						if type(alternative) == 'table' then
							action_name = tostring(alternative.action_name or '')
							action_kind = tostring(alternative.action_kind or '')
							action_detail = alternative
						end
					end
					if action_name ~= '' and (action_kind == 'spell' or action_kind == 'ja')
						and deps.attempt_allowed('debuff', member.name, action_name, options.now, 3) then
						local action_prio = deps.status_removal_priority[status_key] or 5
						local better = not best or action_prio < best.action_prio
						if limited then
							better = not best or status_rank < best.status_rank
						end
						if better then
							best = {
								action_name = action_name,
								action_kind = action_kind,
								spell = action_kind == 'spell' and action_name or nil,
								buff_id = buff_id,
								action_prio = action_prio,
								status_rank = status_rank,
								action_detail = action_detail,
							}
						end
					end
				end
			end

			if best then
				local member_prio = deps.member_priority(member)
				local candidate = {
					type = 'debuff',
					spell = best.spell,
					action_name = best.action_name,
					action_kind = best.action_kind,
					target = member,
					buff_id = best.buff_id,
					prio = deps.pri_default(member_prio, best.action_prio),
					na_limited = limited,
					status_rank = best.status_rank,
					action_detail = best.action_detail,
				}
				if (limited and limited_candidate_better(candidate, selected))
					or (not limited and (not selected or candidate.prio < selected.prio)) then
					selected = candidate
				end
			end
		end
	end

	return selected
end

local function cure_is_critical(cure_action, critical_hpp)
	if type(cure_action) ~= 'table' then
		return false
	end
	local target_hpp = tonumber(cure_action.lowest_covered_hpp)
		or tonumber(cure_action.target and cure_action.target.hpp)
		or 0
	return target_hpp > 0 and target_hpp <= (tonumber(critical_hpp) or 35)
end

function M.choose_defensive_action(candidates, critical_hpp)
	local c = type(candidates) == 'table' and candidates or {}
	local function action_name(action)
		return type(action) == 'table' and tostring(action.action_name or action.spell or '') or ''
	end
	local function is_majesty_action(action)
		return action_name(action):lower() == 'majesty'
	end

	if c.debuff and c.debuff.na_limited and c.cure and cure_is_critical(c.cure, critical_hpp) then
		return c.cure, 'BLOCK_DEFENSIVE_CURE'
	end
	if c.debuff and action_name(c.debuff) == 'Paralyna' and c.debuff.target and c.debuff.target.is_self then
		return c.debuff, 'BLOCK_DEFENSIVE_NA'
	end

	local majesty_action = nil
	if is_majesty_action(c.buff) then
		majesty_action = c.buff
	elseif is_majesty_action(c.overwrite) then
		majesty_action = c.overwrite
	end
	if majesty_action then
		return majesty_action, 'BLOCK_DEFENSIVE_MAJESTY'
	end
	if c.overwrite then
		return c.overwrite, 'BLOCK_DEFENSIVE_OVERWRITE'
	elseif c.cure then
		if c.debuff and c.debuff.na_limited then
			return c.debuff, 'BLOCK_DEFENSIVE_NA'
		end
		if c.debuff and ((c.debuff.prio + 2) < c.cure.prio) then
			return c.debuff, 'BLOCK_DEFENSIVE_NA'
		end
		return c.cure, 'BLOCK_DEFENSIVE_CURE'
	elseif c.debuff then
		if c.buff and (c.buff.prio < c.debuff.prio) then
			return c.buff, 'BLOCK_DEFENSIVE_BUFF'
		end
		return c.debuff, 'BLOCK_DEFENSIVE_NA'
	elseif c.buff then
		return c.buff, 'BLOCK_DEFENSIVE_BUFF'
	end
	return nil, nil
end

return M
