local res = require('resources')

local M = {}

local function trim(value)
	if type(value) ~= 'string' then
		return ''
	end
	return value:match('^%s*(.-)%s*$') or ''
end

function M.completed(act)
	if type(act) ~= 'table' then
		return nil
	end
	local category = tonumber(act.category) or 0
	local action_id = tonumber(act.param) or 0
	local action_type = nil
	local action_name = ''
	if category == 4 then
		action_type = 'spell'
		local spell = action_id > 0 and res.spells and res.spells[action_id] or nil
		action_name = trim(spell and spell.en)
	elseif category == 6 or category == 13 or category == 14 or category == 15 then
		action_type = 'ja'
		local ability = action_id > 0 and res.job_abilities and res.job_abilities[action_id] or nil
		action_name = trim(ability and ability.en)
	else
		return nil
	end
	local actor_id = tonumber(act.actor_id) or 0
	if actor_id <= 0 or action_id <= 0 or action_name == '' then
		return nil
	end
	local target_ids = {}
	for i = 1, #(act.targets or {}) do
		local target_id = tonumber(act.targets[i] and act.targets[i].id) or 0
		if target_id > 0 then
			target_ids[#target_ids + 1] = target_id
		end
	end
	return {
		actor_id = actor_id,
		category = category,
		action_id = action_id,
		action_type = action_type,
		action_name = action_name,
		target_ids = target_ids,
	}
end

function M.party_member_actor_id(source_name)
	local wanted = trim(source_name):lower()
	if wanted == '' then
		return 0
	end
	local party = windower.ffxi.get_party()
	if type(party) ~= 'table' then
		return 0
	end
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local entry = party[key]
		local mob = entry and entry.mob or nil
		local name = trim((mob and mob.name) or (entry and entry.name))
		local id = tonumber((mob and mob.id) or (entry and entry.mob_id) or (entry and entry.id)) or 0
		if id > 0 and name:lower() == wanted then
			return id
		end
	end
	return 0
end

function M.current_enemy_instance_valid(actor_id)
	local id = tonumber(actor_id) or 0
	if id <= 0 then
		return false
	end
	local mob = windower.ffxi.get_mob_by_id(id)
	if type(mob) ~= 'table' then
		return false
	end
	local hpp = tonumber(mob.hpp)
	if hpp ~= nil and hpp <= 0 then
		return false
	end
	if mob.valid_target == false then
		return false
	end
	return true
end

return M
