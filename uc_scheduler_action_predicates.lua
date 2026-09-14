local M = {}

local function action_name(name)
	return tostring(name or ''):lower()
end

function M.ja_targets_enemy(ja)
	local targets = ja and ja.targets
	if type(targets) == 'string' then
		return targets:find('Enemy', 1, true) ~= nil
	end
	if type(targets) == 'number' then
		local n = math.floor(targets)
		return (n % 64) >= 32
	end
	if type(targets) == 'table' then
		return targets.Enemy == true or targets.enemy == true
	end
	return false
end

function M.ja_requires_engaged_front(name, ja)
	if (tonumber(ja and ja.id) or 0) == 46 then -- Shield Bash
		return true
	end
	return action_name(name) == 'shield bash'
end

function M.ja_requires_engaged(name, ja)
	if M.ja_requires_engaged_front(name, ja) then
		return true
	end
	local normalized = action_name(name)
	return normalized == 'gambit' or normalized == 'rayke'
end

return M
