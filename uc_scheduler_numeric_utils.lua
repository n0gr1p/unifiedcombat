local M = {}

function M.bool_setting(v, default_value)
	if v == nil then
		return default_value == true
	end
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

function M.p1_number(v, default_value)
	local n = tonumber(v)
	if n == nil then
		return default_value
	end
	return n
end

function M.p1_clamp_urgency(v)
	local n = M.p1_number(v, 0)
	if n < 0 then
		return 0
	end
	if n > 1 then
		return 1
	end
	return n
end

return M
