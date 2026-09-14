local uc_target_ignore = require('uc_target_ignore')

local M = {}

local PARTY_KEYS = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }

local function alliance_scope_enabled()
	return rawget(_G, 'UC_ENABLE_ALLIANCE_TARGET_SCOPE') == true
end

local function sorted_alliance_keys(party)
	local keys = {}
	for key in pairs(type(party) == 'table' and party or {}) do
		if type(key) == 'string' and key:match('^a%d+$') then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		local na = tonumber(a:match('(%d+)')) or 0
		local nb = tonumber(b:match('(%d+)')) or 0
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return keys
end

local function function_or_default(opts, name, default_value)
	local value = type(opts) == 'table' and opts[name] or nil
	if type(value) == 'function' then
		return value
	end
	return default_value
end

local function windower_function(name)
	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	local fn = type(ffxi) == 'table' and ffxi[name] or nil
	if type(fn) ~= 'function' then
		return function() return nil end
	end
	return fn
end

local function pet_index_for_entry(entry, owner, get_mob_by_id)
	local direct = tonumber(type(entry) == 'table' and entry.pet_index) or 0
	if direct > 0 then
		return direct
	end
	local owner_index = tonumber(type(owner) == 'table' and owner.pet_index) or 0
	if owner_index > 0 then
		return owner_index
	end
	local owner_id = tonumber(type(owner) == 'table' and owner.id) or 0
	if owner_id > 0 then
		local live_owner = get_mob_by_id(owner_id)
		local live_index = tonumber(type(live_owner) == 'table' and live_owner.pet_index) or 0
		if live_index > 0 then
			return live_index
		end
	end
	return 0
end

local function append_party_pet(set, entry, tank_id, get_mob_by_index, get_mob_by_id)
	if type(entry) ~= 'table' then
		return
	end
	local owner = type(entry.mob) == 'table' and entry.mob or nil
	local owner_id = tonumber(owner and owner.id) or 0
	if owner_id <= 0 or owner_id == tank_id then
		return
	end
	local pet_index = pet_index_for_entry(entry, owner, get_mob_by_id)
	if pet_index <= 0 then
		return
	end
	local pet = get_mob_by_index(pet_index)
	local pet_id = tonumber(type(pet) == 'table' and pet.id) or 0
	if pet_id <= 0 then
		return
	end
	set[pet_id] = {
		pet_id = pet_id,
		pet_index = pet_index,
		pet_name = tostring(pet.name or ''),
		owner_id = owner_id,
		owner_name = tostring(owner.name or ''),
		pet = pet,
	}
end

function M.friendly_pet_map(tank_id, opts)
	local get_party = function_or_default(opts, 'get_party', windower_function('get_party'))
	local get_mob_by_index = function_or_default(opts, 'get_mob_by_index', windower_function('get_mob_by_index'))
	local get_mob_by_id = function_or_default(opts, 'get_mob_by_id', windower_function('get_mob_by_id'))
	local party = get_party() or {}
	local set = {}
	for _, key in ipairs(PARTY_KEYS) do
		append_party_pet(set, party[key], tank_id, get_mob_by_index, get_mob_by_id)
	end
	if alliance_scope_enabled() or (type(opts) == 'table' and opts.include_alliance == true) then
		for _, key in ipairs(sorted_alliance_keys(party)) do
			append_party_pet(set, party[key], tank_id, get_mob_by_index, get_mob_by_id)
		end
	end
	return set
end

local function actual_mob_target(mob, opts)
	local get_mob_by_index = function_or_default(opts, 'get_mob_by_index', windower_function('get_mob_by_index'))
	local get_mob_by_id = function_or_default(opts, 'get_mob_by_id', windower_function('get_mob_by_id'))
	local target_index = tonumber(type(mob) == 'table' and mob.target_index) or 0
	if target_index > 0 then
		local target = get_mob_by_index(target_index)
		if type(target) == 'table' and (tonumber(target.id) or 0) > 0 then
			return target
		end
	end
	local target_id = tonumber(type(mob) == 'table' and mob.target) or 0
	if target_id > 0 then
		local target = get_mob_by_id(target_id)
		if type(target) == 'table' and (tonumber(target.id) or 0) > 0 then
			return target
		end
	end
	local action_targets = rawget(_G, 'UC_MOB_LAST_ACTION_TARGETS')
	local record = type(action_targets) == 'table' and action_targets[tonumber(mob and mob.id) or 0] or nil
	if type(record) == 'table' then
		local now = type(opts) == 'table' and tonumber(opts.now) or nil
		if now == nil then
			local time = require('uc_time')
			now = time.now()
		end
		local age = now - (tonumber(record.at) or 0)
		local packet_target_id = tonumber(record.target_id) or 0
		if age >= 0 and age <= 5.0 and packet_target_id > 0 then
			local target = get_mob_by_id(packet_target_id)
			if type(target) == 'table' and (tonumber(target.id) or 0) > 0 then
				return target
			end
			return { id = packet_target_id, name = '(pkt)' }
		end
	end
	return nil
end

local function enemy_distance(mob)
	local squared = tonumber(type(mob) == 'table' and mob.distance)
	if squared == nil or squared < 0 then
		return math.huge
	end
	return math.sqrt(squared)
end

local function should_replace(candidate, best)
	if best == nil then
		return true
	end
	if candidate.victim_hpp ~= best.victim_hpp then
		return candidate.victim_hpp < best.victim_hpp
	end
	if candidate.dist ~= best.dist then
		return candidate.dist < best.dist
	end
	if candidate.mob_hpp ~= best.mob_hpp then
		return candidate.mob_hpp > best.mob_hpp
	end
	return candidate.mob_id < best.mob_id
end

function M.find_violation(settings, player, opts)
	local tank_id = tonumber(type(player) == 'table' and player.id) or 0
	if tank_id <= 0 then
		return nil
	end
	local get_mob_array = function_or_default(opts, 'get_mob_array', windower_function('get_mob_array'))
	local pet_map = M.friendly_pet_map(tank_id, opts)
	if next(pet_map) == nil then
		return nil
	end
	local best = nil
	for _, mob in pairs(get_mob_array() or {}) do
		if type(mob) == 'table'
			and (tonumber(mob.id) or 0) > 0
			and mob.valid_target == true
			and tonumber(mob.spawn_type) == 16
			and (tonumber(mob.hpp) or 0) > 0
			and (tonumber(mob.status) or 0) == 1
			and not uc_target_ignore.is_mob_blocked(settings, mob) then
			local victim = actual_mob_target(mob, opts)
			local victim_id = tonumber(type(victim) == 'table' and victim.id) or 0
			local pet_info = pet_map[victim_id]
			if pet_info ~= nil then
				local hpp = tonumber(victim.hpp)
				if hpp == nil and type(pet_info.pet) == 'table' then
					hpp = tonumber(pet_info.pet.hpp)
				end
				local candidate = {
					mob = mob,
					mob_id = tonumber(mob.id) or 0,
					mob_hpp = tonumber(mob.hpp) or 0,
					dist = enemy_distance(mob),
					victim = victim,
					victim_id = victim_id,
					victim_name = tostring(victim.name or pet_info.pet_name or ''),
					victim_hpp = hpp or 100,
					victim_kind = 'pet',
					owner_id = tonumber(pet_info.owner_id) or 0,
					owner_name = tostring(pet_info.owner_name or ''),
				}
				if should_replace(candidate, best) then
					best = candidate
				end
			end
		end
	end
	return best
end

return M
