local M = {}

local JOB_ABILITY_CATEGORIES = {
	[6] = true,
	[13] = true,
	[14] = true,
	[15] = true,
}

local SPELL_CATEGORIES = {
	[4] = true,
	[8] = true,
}

local function resolved_name(resolver, action_id, kind)
	local name = resolver(action_id)
	if name == nil then
		return '', false
	end
	if type(name) ~= 'string' or name == '' then
		error('Scholar ' .. kind .. ' resolver must return a non-empty string or nil')
	end
	return name, true
end

function M.classify(act, player_id, resolve_spell_name, resolve_ability_name)
	if type(act) ~= 'table' then
		error('Scholar action observer requires an action table')
	end
	if type(player_id) ~= 'number' or player_id <= 0 or player_id % 1 ~= 0 then
		error('Scholar action observer requires a positive integer player id')
	end
	if type(resolve_spell_name) ~= 'function' then
		error('Scholar action observer requires a spell-name resolver')
	end
	if type(resolve_ability_name) ~= 'function' then
		error('Scholar action observer requires an ability-name resolver')
	end
	if type(act.actor_id) ~= 'number' then
		error('Scholar action observer actor_id must be numeric')
	end
	if act.actor_id ~= player_id then
		return nil
	end
	if type(act.category) ~= 'number' then
		error('Scholar action observer category must be numeric')
	end
	if not SPELL_CATEGORIES[act.category] and not JOB_ABILITY_CATEGORIES[act.category] then
		return nil
	end
	if type(act.param) ~= 'number' or act.param < 0 or act.param % 1 ~= 0 then
		error('Scholar action observer param must be a non-negative integer')
	end
	if SPELL_CATEGORIES[act.category] then
		local name, recognized = resolved_name(resolve_spell_name, act.param, 'spell')
		return {
			action_type = 'spell',
			action_name = name,
			action_id = act.param,
			recognized = recognized,
			phase = act.category == 8 and 'cast_start' or 'result',
		}
	end
	if JOB_ABILITY_CATEGORIES[act.category] then
		local name, recognized = resolved_name(resolve_ability_name, act.param, 'job ability')
		return {
			action_type = 'job_ability',
			action_name = name,
			action_id = act.param,
			recognized = recognized,
			phase = 'result',
		}
	end
	error('Scholar action observer category classification is inconsistent')
end

return M
