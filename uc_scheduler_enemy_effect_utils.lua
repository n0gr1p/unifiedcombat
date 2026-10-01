local M = {}

local status_key_by_buff_id = {
	[3] = 'poison',
	[4] = 'paralysis',
	[5] = 'blind',
	[6] = 'silence',
	[7] = 'petrification',
	[8] = 'disease',
	[9] = 'curse',
	[31] = 'plague',
}

local status_key_aliases = {
	blindness = 'blind',
	petrify = 'petrification',
	petrified = 'petrification',
}

function M.normalize_status_removal_key(buff_res, buff_id)
	local en = tostring((buff_res and buff_res.en) or ''):match('^%s*(.-)%s*
function M.danger_weight_to_priority(w)
	local n = tonumber(w) or 0
	if n <= 1 then
		return 72
	elseif n == 2 then
		return 76
	elseif n == 3 then
		return 82
	elseif n == 4 then
		return 88
	end
	return 94
end

function M.enemy_dispel_claim_valid(claim_id, party_claim_set)
	local cid = tonumber(claim_id) or 0
	return cid > 0 and type(party_claim_set) == 'table' and party_claim_set[cid] == true
end

function M.enemy_effect_log_label(deps, effect_id)
	local eid = tonumber(effect_id) or 0
	if eid <= 0 then
		return ('id:%d'):format(eid)
	end
	local buffs = deps and deps.buffs or nil
	local buff = buffs and buffs[eid] or nil
	local name = tostring((buff and buff.en) or '')
	if name == '' then
		return ('id:%d'):format(eid)
	end
	return ('%s(%d)'):format(name, eid)
end

return M
)
	if en == '' then
		return status_key_by_buff_id[tonumber(buff_id) or 0] or ''
	end
	local key = en:lower():gsub('%s+', '_')
	return status_key_aliases[key] or key
end

function M.danger_weight_to_priority(w)
	local n = tonumber(w) or 0
	if n <= 1 then
		return 72
	elseif n == 2 then
		return 76
	elseif n == 3 then
		return 82
	elseif n == 4 then
		return 88
	end
	return 94
end

function M.enemy_dispel_claim_valid(claim_id, party_claim_set)
	local cid = tonumber(claim_id) or 0
	return cid > 0 and type(party_claim_set) == 'table' and party_claim_set[cid] == true
end

function M.enemy_effect_log_label(deps, effect_id)
	local eid = tonumber(effect_id) or 0
	if eid <= 0 then
		return ('id:%d'):format(eid)
	end
	local buffs = deps and deps.buffs or nil
	local buff = buffs and buffs[eid] or nil
	local name = tostring((buff and buff.en) or '')
	if name == '' then
		return ('id:%d'):format(eid)
	end
	return ('%s(%d)'):format(name, eid)
end

return M
