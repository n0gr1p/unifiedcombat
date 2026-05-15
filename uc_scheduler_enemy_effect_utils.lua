local M = {}

function M.normalize_status_removal_key(buff_res)
	local en = tostring((buff_res and buff_res.en) or '')
	if en == '' then
		return ''
	end
	local key = en:lower():gsub('%s+', '_')
	if key == 'blindness' then
		return 'blind'
	end
	return key
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
