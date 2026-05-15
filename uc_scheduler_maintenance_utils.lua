local M = {}

function M.set_has(settbl, v)
	if type(settbl) ~= 'table' then
		return false
	end
	if type(settbl.contains) == 'function' then
		return settbl:contains(v)
	end
	return settbl[v] == true
end

function M.dedupe_numeric_ids(ids)
	local out, seen = {}, {}
	for _, v in ipairs(ids or {}) do
		local n = tonumber(v) or 0
		if n > 0 and not seen[n] then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	return out
end

function M.split_actions(raw)
	local function norm(s)
		return require('uc_scheduler_text_utils').decode_json_escapes(tostring(s or ''))
			:gsub('[\226\128\153\226\128\152`´]', "'")
			:gsub('%s+', ' ')
			:gsub('^%s+', '')
			:gsub('%s+$', '')
	end
	local out = {}
	if type(raw) == 'table' then
		for _, v in ipairs(raw) do
			if v and v ~= '' then
				local n = require('uc_scheduler_text_utils').normalize_action_name_like_healbot(norm(v))
				if n ~= '' then
					out[#out + 1] = n
				end
			end
		end
		return out
	end
	for token in tostring(raw or ''):gmatch('[^|,]+') do
		local t = require('uc_scheduler_text_utils').normalize_action_name_like_healbot(norm(token))
		if t ~= '' then
			out[#out + 1] = t
		end
	end
	return out
end

function M.canon_name(s)
	return require('uc_scheduler_text_utils').decode_json_escapes(tostring(s or ''))
		:gsub('[\226\128\153\226\128\152`´]', "'")
		:gsub('%s+', ' ')
		:gsub('^%s+', '')
		:gsub('%s+$', '')
end

function M.count_matching_buffs(buff_list, id_set)
	if type(buff_list) ~= 'table' or type(id_set) ~= 'table' then
		return 0
	end
	local c = 0
	for _, id in ipairs(buff_list) do
		if id_set[id] then
			c = c + 1
		end
	end
	return c
end

function M.count_buff_occurrences(buffs)
	local out = {}
	for _, bid in ipairs(buffs or {}) do
		out[bid] = (out[bid] or 0) + 1
	end
	return out
end

return M
