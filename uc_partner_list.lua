-- Ordered partner mob IDs (follow their targets for autotarget / sub). Mirrors uc_ignore list ops.

local M = {}

function M.as_ordered_ids(s)
	if not s or type(s.partner_ids) ~= 'table' then
		return {}
	end
	local out = {}
	for _, v in ipairs(s.partner_ids) do
		if type(v) == 'number' and v ~= 0 then
			out[#out + 1] = v
		end
	end
	if #out > 0 then
		return out
	end
	local keys = {}
	for k in pairs(s.partner_ids) do
		if type(k) == 'number' then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = s.partner_ids[k]
		if type(v) == 'number' and v ~= 0 then
			out[#out + 1] = v
		end
	end
	return out
end

function M.sync_legacy_partner_fields(s)
	if not s then
		return
	end
	local arr = M.as_ordered_ids(s)
	s.partner_id = arr[1] or 0
	s.partner_id2 = arr[2] or 0
	s.partner2 = (arr[2] or 0) ~= 0
end

function M.migrate_from_legacy(s)
	if not s then
		return
	end
	local arr = M.as_ordered_ids(s)
	if #arr > 0 then
		M.sync_legacy_partner_fields(s)
		return
	end
	local ids = {}
	if type(s.partner_id) == 'number' and s.partner_id ~= 0 then
		ids[#ids + 1] = s.partner_id
	end
	if type(s.partner_id2) == 'number' and s.partner_id2 ~= 0 and s.partner_id2 ~= s.partner_id then
		ids[#ids + 1] = s.partner_id2
	end
	if #ids > 0 then
		s.partner_ids = ids
	end
	M.sync_legacy_partner_fields(s)
end

function M.append_id(s, id)
	if not s or not id or id == 0 then
		return false, 'PARTNER_BAD_ID'
	end
	local arr = M.as_ordered_ids(s)
	for _, v in ipairs(arr) do
		if v == id then
			return true, 'PARTNER_ALREADY'
		end
	end
	arr[#arr + 1] = id
	s.partner_ids = arr
	M.sync_legacy_partner_fields(s)
	return true, ''
end

function M.remove_id(s, id)
	if not s or not id or id == 0 then
		return false, 'PARTNER_BAD_ID'
	end
	local arr = M.as_ordered_ids(s)
	local new = {}
	local found = false
	for _, v in ipairs(arr) do
		if v == id then
			found = true
		else
			new[#new + 1] = v
		end
	end
	if not found then
		return false, 'PARTNER_NOT_FOUND'
	end
	s.partner_ids = new
	M.sync_legacy_partner_fields(s)
	return true, ''
end

--- Preserve list order (slot 1 = sub, slot 2 = sub2 in melee).
function M.encode_for_ui(s, name_by_id_fn)
	local arr = M.as_ordered_ids(s)
	if #arr == 0 then
		return ''
	end
	local parts = {}
	for _, id in ipairs(arr) do
		local nm = '?'
		if type(name_by_id_fn) == 'function' then
			local ok, res = pcall(name_by_id_fn, id)
			if ok and type(res) == 'string' and res ~= '' then
				nm = res
			end
		end
		nm = nm:gsub(':', '_'):gsub('|', '_')
		parts[#parts + 1] = tostring(id) .. ':' .. nm
	end
	return table.concat(parts, '|')
end

return M
