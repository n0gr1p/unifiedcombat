local M = {}

function M.p1_format_top3(scheduler, ranked, p1_number)
	local parts = {}
	local count = math.min(3, #ranked)
	for i = 1, count do
		local p = ranked[i]
		parts[#parts + 1] = ('%d)%s %.2f %s'):format(i, tostring(p.provider or ''), p1_number(p._score, 0), tostring(p.action_name or ''))
	end
	return table.concat(parts, ' | ')
end

function M.p1_format_top3_verbose(scheduler, ranked, p1_number)
	local parts = {}
	local count = math.min(3, #ranked)
	for i = 1, count do
		local p = ranked[i]
		local sp = p._score_parts or {}
		parts[#parts + 1] = ('%d)%s score=%.2f pb=%s u=%.2f st=%.2f sk=%.2f rp=%.2f %s'):format(
			i,
			tostring(p.provider or ''),
			p1_number(p._score, 0),
			tostring(sp.priority_band or ''),
			p1_number(sp.urgency_bonus, 0),
			p1_number(sp.starvation_bonus, 0),
			p1_number(sp.sticky_bonus, 0),
			p1_number(sp.risk_penalty, 0),
			tostring(p.action_name or '')
		)
	end
	return table.concat(parts, ' | ')
end

function M.p1_format_topn_lines(scheduler, ranked, n, p1_number)
	local out = {}
	local count = math.min(tonumber(n) or 5, #ranked)
	for i = 1, count do
		local p = ranked[i]
		local sp = p._score_parts or {}
		out[#out + 1] = ('%d) %.2f %s/%s %s u=%.2f rp=%.2f'):format(
			i,
			p1_number(p._score, 0),
			tostring(p.provider or ''),
			tostring(p.family_id or ''),
			tostring(p.action_name or ''),
			p1_number(sp.urgency_bonus, 0),
			p1_number(sp.risk_penalty, 0)
		)
	end
	return out
end

function M.p1_capture_topn_items(scheduler, ranked, n, p1_number)
	local out = {}
	local count = math.min(tonumber(n) or 5, #ranked)
	for i = 1, count do
		local p = ranked[i]
		local sp = p._score_parts or {}
		out[#out + 1] = {
			idx = i,
			score = p1_number(p._score, 0),
			provider = tostring(p.provider or ''),
			family = tostring(p.family_id or ''),
			action = tostring(p.action_name or ''),
			urgency_bonus = p1_number(sp.urgency_bonus, 0),
			risk_penalty = p1_number(sp.risk_penalty, 0),
		}
	end
	return out
end

function M.p1_reject_top(scheduler, reject_counts, proposal_count)
	if proposal_count <= 0 then
		return 'no_proposals'
	end
	local best_reason, best_count = '', -1
	for reason, count in pairs(reject_counts) do
		if count > best_count then
			best_reason = tostring(reason or '')
			best_count = count
		end
	end
	if best_count < 0 then
		return ''
	end
	return ('%s:%d'):format(best_reason, best_count)
end

return M
