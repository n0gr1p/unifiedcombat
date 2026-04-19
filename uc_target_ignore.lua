-- Name-based list: autotarget / fight-leader never pick mobs whose name matches (case-insensitive).

local M = {}

local function trim(s)
	if not s then
		return ''
	end
	return tostring(s):match('^%s*(.-)%s*$') or ''
end

local function lower(s)
	return trim(s):lower()
end

function M.as_ordered_names(s)
	if not s or type(s.target_ignore_names) ~= 'table' then
		return {}
	end
	local t = s.target_ignore_names
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

function M.is_mob_blocked(s, mob)
	if not s or not mob then
		return false
	end
	local nm = mob.name
	if type(nm) ~= 'string' then
		return false
	end
	local ml = lower(nm)
	if ml == '' then
		return false
	end
	for _, entry in ipairs(M.as_ordered_names(s)) do
		if lower(entry) == ml then
			return true
		end
	end
	return false
end

function M.append_name(s, name)
	local n = trim(name)
	if not s or n == '' then
		return false, 'TARGET_IGNORE_BAD_NAME'
	end
	local nl = n:lower()
	local arr = M.as_ordered_names(s)
	for _, e in ipairs(arr) do
		if e:lower() == nl then
			return true, 'TARGET_IGNORE_ALREADY'
		end
	end
	arr[#arr + 1] = n
	s.target_ignore_names = arr
	return true, ''
end

function M.remove_index(s, idx)
	if not s or type(idx) ~= 'number' or idx < 1 or idx ~= math.floor(idx) then
		return false, 'TARGET_IGNORE_BAD_INDEX'
	end
	local arr = M.as_ordered_names(s)
	if idx > #arr then
		return false, 'TARGET_IGNORE_NOT_FOUND'
	end
	local new = {}
	for i, v in ipairs(arr) do
		if i ~= idx then
			new[#new + 1] = v
		end
	end
	s.target_ignore_names = new
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
