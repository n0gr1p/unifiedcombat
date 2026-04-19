-- Shared ignore-list helpers: profiles may store a plain array or a Windower list (append/contains).

local M = {}

function M.has_id(s, id)
	if not s or id == nil or id == 0 then
		return false
	end
	local ig = s.ignore
	if type(ig) ~= 'table' then
		return false
	end
	if type(ig.contains) == 'function' then
		local ok, res = pcall(function()
			return ig:contains(id)
		end)
		if ok then
			return res == true
		end
	end
	if ig[id] ~= nil then
		return true
	end
	for _, v in pairs(ig) do
		if v == id then
			return true
		end
	end
	return false
end

function M.append_id(s, id)
	if not s or not id or id == 0 then
		return false, 'IGNORE_BAD_ID'
	end
	if M.has_id(s, id) then
		return true, 'IGNORE_ALREADY'
	end
	local ig = s.ignore
	if type(ig) ~= 'table' then
		s.ignore = { id }
		return true, ''
	end
	if type(ig.append) == 'function' then
		ig:append(id)
		return true, ''
	end
	table.insert(ig, id)
	return true, ''
end

function M.remove_id(s, id)
	if not s or not id or id == 0 then
		return false, 'IGNORE_BAD_ID'
	end
	local ig = s.ignore
	if type(ig) ~= 'table' then
		return false, 'IGNORE_EMPTY'
	end
	local found = false
	local new = {}
	for _, v in pairs(ig) do
		if type(v) == 'number' and v ~= 0 then
			if v == id then
				found = true
			else
				new[#new + 1] = v
			end
		end
	end
	if not found then
		return false, 'IGNORE_NOT_FOUND'
	end
	s.ignore = new
	return true, ''
end

--- Build "id:name|id:name" for remote UI (name from resolver or "?").
function M.encode_for_ui(s, name_by_id_fn)
	local ig = s and s.ignore
	if type(ig) ~= 'table' then
		return ''
	end
	local parts = {}
	local seen = {}
	for _, v in pairs(ig) do
		if type(v) == 'number' and v ~= 0 and not seen[v] then
			seen[v] = true
			local nm = '?'
			if type(name_by_id_fn) == 'function' then
				local ok, res = pcall(name_by_id_fn, v)
				if ok and type(res) == 'string' and res ~= '' then
					nm = res
				end
			end
			nm = nm:gsub(':', '_'):gsub('|', '_')
			parts[#parts + 1] = tostring(v) .. ':' .. nm
		end
	end
	table.sort(parts)
	return table.concat(parts, '|')
end

return M
