local M = {}

function M.family_key(member_name, buff_id)
	return tostring(member_name) .. ':' .. tostring(buff_id)
end

function M.attempt_key(kind, member_name, action_name)
	return table.concat({ tostring(kind), tostring(member_name), tostring(action_name) }, '::')
end

return M
