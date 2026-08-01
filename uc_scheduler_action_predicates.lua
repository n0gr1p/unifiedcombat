local M = {}

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
	return tostring(name or ''):lower() == 'shield bash'
end

return M
