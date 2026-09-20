-- Exact, case-insensitive mob-name deny list for weapon skills that would create a skillchain.
-- This is intentionally a no-op for targets not listed in weaponskill_no_skillchain_targets.

local M = {}

local function trim(value)
	if value == nil then
		return ''
	end
	return tostring(value):match('^%s*(.-)%s*$') or ''
end

local function normalized(value)
	return trim(value):lower()
end

function M.as_ordered_names(settings)
	if type(settings) ~= 'table' or type(settings.weaponskill_no_skillchain_targets) ~= 'table' then
		return {}
	end
	local out = {}
	for i = 1, #settings.weaponskill_no_skillchain_targets do
		local name = trim(settings.weaponskill_no_skillchain_targets[i])
		if name ~= '' then
			out[#out + 1] = name
		end
	end
	return out
end

function M.is_name_blocked(settings, name)
	local key = normalized(name)
	if key == '' then
		return false
	end
	for _, configured in ipairs(M.as_ordered_names(settings)) do
		if normalized(configured) == key then
			return true
		end
	end
	return false
end

function M.is_mob_blocked(settings, mob)
	return type(mob) == 'table' and M.is_name_blocked(settings, mob.name)
end

function M.append_name(settings, name)
	local value = trim(name)
	if type(settings) ~= 'table' or value == '' then
		return false, 'NO_SKILLCHAIN_TARGET_BAD_NAME'
	end
	if M.is_name_blocked(settings, value) then
		return true, 'NO_SKILLCHAIN_TARGET_ALREADY'
	end
	local names = M.as_ordered_names(settings)
	names[#names + 1] = value
	settings.weaponskill_no_skillchain_targets = names
	return true, ''
end

function M.remove_index(settings, index)
	if type(settings) ~= 'table' or type(index) ~= 'number' or index < 1 or index ~= math.floor(index) then
		return false, 'NO_SKILLCHAIN_TARGET_BAD_INDEX'
	end
	local names = M.as_ordered_names(settings)
	if index > #names then
		return false, 'NO_SKILLCHAIN_TARGET_NOT_FOUND'
	end
	table.remove(names, index)
	settings.weaponskill_no_skillchain_targets = names
	return true, ''
end

return M
