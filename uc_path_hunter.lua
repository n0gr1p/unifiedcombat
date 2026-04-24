local mod = {}

local function trim(s)
	if not s then
		return ''
	end
	return tostring(s):match('^%s*(.-)%s*$') or ''
end

function mod.as_ordered_names(settings)
	local out = {}
	if type(settings) ~= 'table' then
		return out
	end
	if type(settings.path_hunter_targets) ~= 'table' then
		settings.path_hunter_targets = {}
	end
	for _, n in ipairs(settings.path_hunter_targets) do
		local t = trim(n)
		if t ~= '' then
			out[#out + 1] = t
		end
	end
	settings.path_hunter_targets = out
	return out
end

function mod.append_name(settings, name)
	if type(settings) ~= 'table' then
		return false, 'PATH_HUNTER_NO_SETTINGS'
	end
	local nm = trim(name)
	if nm == '' then
		return false, 'PATH_HUNTER_EMPTY_NAME'
	end
	local arr = mod.as_ordered_names(settings)
	local want = nm:lower()
	for _, v in ipairs(arr) do
		if v:lower() == want then
			return false, 'PATH_HUNTER_ALREADY'
		end
	end
	arr[#arr + 1] = nm
	settings.path_hunter_targets = arr
	return true
end

function mod.remove_index(settings, idx)
	if type(settings) ~= 'table' then
		return false, 'PATH_HUNTER_NO_SETTINGS'
	end
	local arr = mod.as_ordered_names(settings)
	local i = tonumber(idx)
	if not i then
		return false, 'PATH_HUNTER_BAD_INDEX'
	end
	i = math.floor(i + 0.5)
	if i < 1 or i > #arr then
		return false, 'PATH_HUNTER_BAD_INDEX'
	end
	table.remove(arr, i)
	settings.path_hunter_targets = arr
	return true
end

function mod.encode_for_ui(settings)
	local arr = mod.as_ordered_names(settings)
	local out = {}
	for i, name in ipairs(arr) do
		out[#out + 1] = tostring(i) .. ':' .. tostring(name)
	end
	return table.concat(out, '|')
end

function mod.matches_mob(settings, mob_name)
	local name = trim(mob_name):lower()
	if name == '' then
		return false
	end
	local arr = mod.as_ordered_names(settings)
	if #arr == 0 then
		return false
	end
	for _, token in ipairs(arr) do
		local t = tostring(token):lower()
		-- Fuzzy substring match, e.g. "elemental" matches "Wind Elemental".
		if t ~= '' and name:find(t, 1, true) then
			return true
		end
	end
	return false
end

return mod
