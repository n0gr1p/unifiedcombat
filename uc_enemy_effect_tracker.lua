local M = {}

local tracked = {}

local death_messages = {
	[20] = true, [97] = true, [113] = true, [406] = true, [605] = true, [646] = true,
}

local remove_messages = {
	[64] = true, [204] = true, [206] = true, [321] = true, [322] = true, [341] = true, [350] = true, [531] = true,
}
local gain_messages = {
	[230] = true, [236] = true, [237] = true, [266] = true, [268] = true, [269] = true, [270] = true, [271] = true,
	[272] = true, [278] = true, [280] = true, [285] = true, [286] = true, [287] = true, [304] = true, [667] = true,
	[668] = true, [669] = true,
}

local function now_s()
	local s = rawget(_G, 'socket')
	if type(s) ~= 'table' or type(s.gettime) ~= 'function' then
		local ok, mod = pcall(require, 'socket')
		if ok then
			s = mod
		end
	end
	if type(s) ~= 'table' or type(s.gettime) ~= 'function' then
		error('uc_enemy_effect_tracker requires LuaSocket socket.gettime')
	end
	return s.gettime()
end

local function is_enemy_npc_by_id(id)
	local n = tonumber(id) or 0
	if n <= 0 then
		return false
	end
	local m = windower.ffxi.get_mob_by_id(n)
	return m and tonumber(m.spawn_type) == 16
end

local function ensure_target(target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return nil
	end
	local t = tracked[tid]
	if type(t) ~= 'table' then
		t = {
			effects = {},
			updated_at = 0,
		}
		tracked[tid] = t
	end
	return t
end

local function set_effect(target_id, effect_id, source)
	local tid = tonumber(target_id) or 0
	local eid = tonumber(effect_id) or 0
	if tid <= 0 or eid <= 0 then
		return false, nil
	end
	local t = ensure_target(tid)
	if not t then
		return false, nil
	end
	local was_new = t.effects[eid] == nil
	t.effects[eid] = {
		seen_at = now_s(),
		source = tostring(source or ''),
	}
	t.updated_at = now_s()
	return true, was_new and 'add' or 'refresh'
end

local function clear_effect(target_id, effect_id)
	local tid = tonumber(target_id) or 0
	local eid = tonumber(effect_id) or 0
	local t = tracked[tid]
	if tid <= 0 or eid <= 0 or type(t) ~= 'table' then
		return false, nil
	end
	if t.effects[eid] ~= nil then
		t.effects[eid] = nil
		t.updated_at = now_s()
		return true, 'remove'
	end
	return false, nil
end

local function clear_target(target_id)
	local tid = tonumber(target_id) or 0
	if tid > 0 and tracked[tid] ~= nil then
		tracked[tid] = nil
		return true, 'clear_target'
	end
	return false, nil
end

function M.clear_all()
	tracked = {}
end

function M.clear_effect(target_id, effect_id)
	local ok, ev = clear_effect(target_id, effect_id)
	if ok then
		return { target_id = tonumber(target_id) or 0, effect_id = tonumber(effect_id) or 0, event = ev, source = 'direct_clear' }
	end
	return nil
end

function M.sweep_invalid(max_age_s)
	local age = tonumber(max_age_s) or 90
	local cutoff = now_s() - age
	for tid, t in pairs(tracked) do
		local remove_target = false
		if type(t) ~= 'table' then
			remove_target = true
		else
			local mob = windower.ffxi.get_mob_by_id(tonumber(tid) or 0)
			if not mob or tonumber(mob.spawn_type) ~= 16 or (tonumber(mob.hpp) or 0) <= 0 then
				remove_target = true
			else
				for eid, row in pairs(t.effects or {}) do
					local at = tonumber(row and row.seen_at) or 0
					if at > 0 and at < cutoff then
						t.effects[eid] = nil
					end
				end
				local has_any = false
				for _, _ in pairs(t.effects or {}) do
					has_any = true
					break
				end
				if not has_any then
					remove_target = true
				end
			end
		end
		if remove_target then
			tracked[tid] = nil
		end
	end
end

function M.on_action(act, dispellable_set)
	if type(act) ~= 'table' or type(dispellable_set) ~= 'table' then
		return
	end
	local actor_id = tonumber(act.actor_id) or 0
	if actor_id <= 0 then
		return
	end
	if type(act.targets) ~= 'table' then
		return
	end
	local events = {}
	for _, target in ipairs(act.targets) do
		local tid = tonumber(target and target.id) or 0
		if type(target.actions) == 'table' then
			for _, a in ipairs(target.actions) do
				local message_id = tonumber(a and a.message) or 0
				-- Removal actions can be emitted by player-cast effects (Dispel/Finale) and
				-- will not be visible via enemy actor-based gain tracking.
				if tid > 0 and is_enemy_npc_by_id(tid) and remove_messages[message_id] == true then
					local remove_eid = tonumber(a and a.param) or 0
					if remove_eid > 0 then
						local ok, ev = clear_effect(tid, remove_eid)
						if ok and ev then
							events[#events + 1] = {
								target_id = tid,
								effect_id = remove_eid,
								event = ev,
								source = 'action_remove',
							}
						end
					end
				end
				if is_enemy_npc_by_id(actor_id) then
					local target_is_enemy = tid > 0 and is_enemy_npc_by_id(tid)
					-- Only treat action params as enemy-buff gain signals when the packet
					-- target is an enemy NPC. This prevents hostile actions aimed at party
					-- members (or other non-enemy targets) from being misclassified as
					-- removable enemy self-buffs.
					if target_is_enemy then
						local eid = tonumber(a and a.param) or 0
						if eid > 0 and dispellable_set[eid] == true then
							local owner = tid
							local ok, ev = set_effect(owner, eid, 'action')
							if ok and ev then
								events[#events + 1] = { target_id = owner, effect_id = eid, event = ev, source = 'action' }
							end
						end
						local aeid = tonumber(a and a.add_effect_param) or 0
						if aeid > 0 and dispellable_set[aeid] == true then
							local owner = tid
							local ok, ev = set_effect(owner, aeid, 'add_effect')
							if ok and ev then
								events[#events + 1] = { target_id = owner, effect_id = aeid, event = ev, source = 'add_effect' }
							end
						end
						local seid = tonumber(a and a.spike_effect_param) or 0
						if seid > 0 and dispellable_set[seid] == true then
							local owner = tid
							local ok, ev = set_effect(owner, seid, 'spike_effect')
							if ok and ev then
								events[#events + 1] = { target_id = owner, effect_id = seid, event = ev, source = 'spike_effect' }
							end
						end
					end
				end
			end
		end
	end
	return events
end

function M.on_action_message(msg, dispellable_set)
	if type(msg) ~= 'table' then
		return
	end
	local actor_id = tonumber(msg.actor_id) or 0
	local target_id = tonumber(msg.target_id) or 0
	local effect_id = tonumber(msg.effect_id) or tonumber(msg.param_1) or 0
	local message_id = tonumber(msg.message_id) or 0

	if death_messages[message_id] == true then
		local ok, ev = clear_target(target_id)
		if ok then
			return { { target_id = target_id, effect_id = 0, event = ev, source = ('msg_%d'):format(message_id) } }
		end
		return {}
	end
	if remove_messages[message_id] == true and effect_id > 0 then
		local ok, ev = clear_effect(target_id, effect_id)
		if ok then
			return { { target_id = target_id, effect_id = effect_id, event = ev, source = ('msg_%d'):format(message_id) } }
		end
		return { { target_id = target_id, effect_id = effect_id, event = 'remove_miss', source = ('msg_%d'):format(message_id) } }
	end
	if type(dispellable_set) ~= 'table' then
		return
	end
	if effect_id > 0 and dispellable_set[effect_id] == true then
		local actor_is_enemy = actor_id > 0 and is_enemy_npc_by_id(actor_id)
		local target_is_enemy = target_id > 0 and is_enemy_npc_by_id(target_id)
		if gain_messages[message_id] == true or target_id == actor_id then
			local owner = target_is_enemy and target_id or actor_id
			if not (owner > 0 and is_enemy_npc_by_id(owner)) and actor_is_enemy then
				owner = actor_id
			end
			local ok, ev = set_effect(owner, effect_id, ('msg_%d'):format(message_id))
			if ok and ev then
				return { { target_id = owner, effect_id = effect_id, event = ev, source = ('msg_%d'):format(message_id) } }
			end
		end
	end
	return {}
end

function M.get_effects(target_id)
	local tid = tonumber(target_id) or 0
	local t = tracked[tid]
	local out = {}
	if type(t) ~= 'table' then
		return out
	end
	for eid, row in pairs(t.effects or {}) do
		out[#out + 1] = {
			effect_id = tonumber(eid) or 0,
			seen_at = tonumber(row and row.seen_at) or 0,
			source = tostring(row and row.source or ''),
		}
	end
	table.sort(out, function(a, b)
		if (a.seen_at or 0) ~= (b.seen_at or 0) then
			return (a.seen_at or 0) > (b.seen_at or 0)
		end
		return (a.effect_id or 0) < (b.effect_id or 0)
	end)
	return out
end

function M.list_targets()
	local out = {}
	for tid, t in pairs(tracked) do
		local count = 0
		for _, _ in pairs((type(t) == 'table' and t.effects) or {}) do
			count = count + 1
		end
		if count > 0 then
			out[#out + 1] = { target_id = tonumber(tid) or 0, count = count, updated_at = tonumber(t.updated_at) or 0 }
		end
	end
	table.sort(out, function(a, b)
		if (a.count or 0) ~= (b.count or 0) then
			return (a.count or 0) > (b.count or 0)
		end
		return (a.target_id or 0) < (b.target_id or 0)
	end)
	return out
end

return M
