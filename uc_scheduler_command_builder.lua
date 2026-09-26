local M = {}

function M.build_action_command(deps, action_name, action_kind, target_member)
	local target = target_member or {}
	if action_kind == 'item' then
		return ('input /item "%s" <me>'):format(tostring(action_name))
	end
	local mode = deps.action_target_mode(action_name, action_kind)
	local target_token = '<me>'
	if target.use_entity_id == true then
		local target_id = tonumber(target.id)
		if target_id == nil or target_id <= 0 then
			error('entity-id action target requires a positive target id')
		end
		target_token = tostring(target_id)
	elseif mode ~= 'self_only' then
		if target.is_self == true then
			target_token = '<me>'
		elseif (tonumber(target.id) or 0) > 0 and target.is_self == false then
			-- When the caller has explicitly resolved a non-self entity, preserve
			-- that identity in the Windower command instead of falling back to a
			-- quoted display name. This keeps off-target scheduler actions (for
			-- example SCH Immanence spell steps) GearSwap-visible without requiring
			-- the entity to be the player's current <t>.
			target_token = tostring(tonumber(target.id) or 0)
		elseif (tonumber(target.id) or 0) > 0 and target.is_mob == true then
			target_token = tostring(tonumber(target.id) or 0)
		elseif target.name and tostring(target.name) ~= '' then
			target_token = '"' .. tostring(target.name):gsub('"', '') .. '"'
		end
	end
	if action_kind == 'ja' then
		return ('input /ja "%s" %s'):format(tostring(action_name), target_token)
	end
	return ('input /ma "%s" %s'):format(tostring(action_name), target_token)
end

return M
