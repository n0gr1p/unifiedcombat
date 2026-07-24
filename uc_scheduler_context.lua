local M = {}

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_scheduler_context requires function dependency: ' .. tostring(name))
	end
	return fn
end

function M.build(settings, phase1, deps)
	if type(phase1) ~= 'table' then
		error('uc_scheduler_context requires phase1 state')
	end
	local get_player = require_function(deps, 'get_player')
	local get_mob_by_target = require_function(deps, 'get_mob_by_target')
	local get_party = require_function(deps, 'get_party')
	local get_mob_array = require_function(deps, 'get_mob_array')
	local now = require_function(deps, 'now')

	local raw_player = get_player()
	local raw_me = get_mob_by_target('me')
	local raw_target = get_mob_by_target('t')
	local raw_party = get_party()
	local raw_mob_array = get_mob_array()
	local player = raw_player or {}
	local me = raw_me or {}
	local target = raw_target or {}
	local party = raw_party or {}
	local mob_array = raw_mob_array or {}
	local mobs_by_id = {}
	for _, mob in pairs(mob_array) do
		local mob_id = tonumber(mob and mob.id) or 0
		if mob_id > 0 then
			mobs_by_id[mob_id] = mob
		end
	end
	if tonumber(target.id) and tonumber(target.id) > 0 then
		mobs_by_id[tonumber(target.id)] = target
	end
	if tonumber(me.id) and tonumber(me.id) > 0 then
		mobs_by_id[tonumber(me.id)] = me
	end

	phase1.tick = (tonumber(phase1.tick) or 0) + 1
	return {
		now = now(),
		tick = phase1.tick,
		settings = settings or {},
		player = player,
		player_present = raw_player ~= nil,
		me = me,
		me_present = raw_me ~= nil,
		target = target,
		target_present = raw_target ~= nil,
		party = party,
		mob_array = mob_array,
		mobs_by_id = mobs_by_id,
		player_status = tonumber(player.status) or -1,
		player_id = tonumber(player.id) or 0,
		player_name = tostring(player.name or ''),
		me_id = tonumber(me.id) or 0,
		me_name = tostring(me.name or ''),
	}
end

return M
