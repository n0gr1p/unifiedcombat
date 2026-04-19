-- Ordered mob names for fight-adds: first entry = highest priority. Case-insensitive exact name match.
-- Empty list → add pick uses only distance / tank-hpp tiebreaks (legacy behavior).

local M = {}

local function trim(s)
	if not s then
		return ''
	end
	return tostring(s):match('^%s*(.-)%s*$') or ''
end

function M.as_ordered_names(s)
	if not s or type(s.add_priority_names) ~= 'table' then
		return {}
	end
	local t = s.add_priority_names
	local out = {}
	for i = 1, #t do
		local v = t[i]
		if type(v) == 'string' then
			local n = trim(v)
			if n ~= '' then
				out[#out + 1] = n
			end
		end
	end
	return out
end

--- @return integer|nil  nil when list empty (no priority layer); else 1..#list for first matching name, #list+1 if unmatched
function M.rank_for_mob_name(s, mob_name)
	local list = M.as_ordered_names(s)
	if #list == 0 then
		return nil
	end
	if type(mob_name) ~= 'string' then
		return #list + 1
	end
	local ml = trim(mob_name):lower()
	if ml == '' then
		return #list + 1
	end
	for i, entry in ipairs(list) do
		if trim(entry):lower() == ml then
			return i
		end
	end
	return #list + 1
end

function M.append_name(s, name)
	local n = trim(name)
	if not s or n == '' then
		return false, 'ADD_PRIORITY_BAD_NAME'
	end
	local nl = n:lower()
	local arr = M.as_ordered_names(s)
	for _, e in ipairs(arr) do
		if e:lower() == nl then
			return false, 'ADD_PRIORITY_ALREADY'
		end
	end
	arr[#arr + 1] = n
	s.add_priority_names = arr
	return true, ''
end

function M.remove_index(s, idx)
	if not s or type(idx) ~= 'number' or idx < 1 or idx ~= math.floor(idx) then
		return false, 'ADD_PRIORITY_BAD_INDEX'
	end
	local arr = M.as_ordered_names(s)
	if idx > #arr then
		return false, 'ADD_PRIORITY_NOT_FOUND'
	end
	local new = {}
	for i, v in ipairs(arr) do
		if i ~= idx then
			new[#new + 1] = v
		end
	end
	s.add_priority_names = new
	return true, ''
end

--- Swap entry at idx with idx+delta (delta -1 = up toward top priority, +1 = down).
function M.move_index(s, idx, delta)
	if not s or type(idx) ~= 'number' or idx < 1 or idx ~= math.floor(idx) then
		return false, 'ADD_PRIORITY_BAD_INDEX'
	end
	if type(delta) ~= 'number' or (delta ~= -1 and delta ~= 1) then
		return false, 'ADD_PRIORITY_BAD_DELTA'
	end
	local arr = M.as_ordered_names(s)
	local j = idx + delta
	if idx > #arr or j < 1 or j > #arr then
		return false, 'ADD_PRIORITY_BAD_MOVE'
	end
	arr[idx], arr[j] = arr[j], arr[idx]
	s.add_priority_names = arr
	return true, ''
end

function M.encode_for_ui(s)
	local arr = M.as_ordered_names(s)
	if #arr == 0 then
		return ''
	end
	local parts = {}
	for i, nm in ipairs(arr) do
		local esc = nm:gsub(':', '_'):gsub('|', '_')
		parts[#parts + 1] = tostring(i) .. ':' .. esc
	end
	return table.concat(parts, '|')
end

return M
