-- Shared targeting helpers for melee/dd2 target scans.

local M = {}

local PARTY_KEYS = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
local PARTY_KEY_SET = {
	['p0'] = true,
	['p1'] = true,
	['p2'] = true,
	['p3'] = true,
	['p4'] = true,
	['p5'] = true,
}

local function alliance_scope_enabled(opts)
	if type(opts) == 'table' and opts.include_alliance ~= nil then
		return opts.include_alliance == true
	end
	return rawget(_G, 'UC_ENABLE_ALLIANCE_TARGET_SCOPE') == true
end

local function get_party_table(opts)
	if type(opts) == 'table' and type(opts.party) == 'table' then
		return opts.party
	end
	return windower.ffxi.get_party()
end

local function append_member_id(ids, set, id)
	local member_id = tonumber(id) or 0
	if member_id <= 0 or set[member_id] == true then
		return
	end
	ids[#ids + 1] = member_id
	set[member_id] = true
end

local function sorted_alliance_keys(party)
	local keys = {}
	for key, _ in pairs(party or {}) do
		if type(key) == 'string' and not PARTY_KEY_SET[key] and key:match('^a%d+$') then
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

function M.get_friendly_combat_member_ids(opts)
	local party = get_party_table(opts)
	local ids = {}
	local set = {}
	if type(party) ~= 'table' then
		return ids, set
	end

	for _, key in ipairs(PARTY_KEYS) do
		local entry = party[key]
		local mob = entry and entry.mob
		append_member_id(ids, set, mob and mob.id)
	end

	if alliance_scope_enabled(opts) then
		for _, key in ipairs(sorted_alliance_keys(party)) do
			local entry = party[key]
			local mob = entry and entry.mob
			append_member_id(ids, set, mob and mob.id)
		end
	end

	return ids, set
end

function M.build_friendly_claims(opts)
	return M.get_friendly_combat_member_ids(opts)
end

function M.is_friendly_party_or_alliance_member_id(id, opts)
	local member_id = tonumber(id) or 0
	if member_id <= 0 then
		return false
	end
	local _, set = M.get_friendly_combat_member_ids(opts)
	return set[member_id] == true
end

function M.mob_targets_friendly_member(mob, friendly_id_set, now)
	if type(mob) ~= 'table' then
		return false, 'missing_mob'
	end
	if type(friendly_id_set) ~= 'table' then
		error('mob_targets_friendly_member requires a friendly id set')
	end
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('mob_targets_friendly_member requires current time')
	end

	local target_index = tonumber(mob.target_index) or 0
	if target_index > 0 then
		local target = windower.ffxi.get_mob_by_index(target_index)
		if target and friendly_id_set[tonumber(target.id) or 0] == true then
			return true, 'target_index'
		end
	end

	local direct_target_id = tonumber(mob.target) or 0
	if direct_target_id > 0 and friendly_id_set[direct_target_id] == true then
		return true, 'target_id'
	end

	local action_targets = rawget(_G, 'UC_MOB_LAST_ACTION_TARGETS')
	local record = type(action_targets) == 'table' and action_targets[tonumber(mob.id) or 0] or nil
	if type(record) == 'table' then
		local age = observed_at - (tonumber(record.at) or 0)
		local action_target_id = tonumber(record.target_id) or 0
		if age >= 0 and age <= 5.0 and friendly_id_set[action_target_id] == true then
			return true, 'recent_action'
		end
	end

	return false, 'no_friendly_target_evidence'
end

function M.build_party_claims()
	return M.build_friendly_claims()
end

--- Select claimed main target plus optional prime fallback.
--- @param marray table
--- @param opts table
--- @return integer id_targ
--- @return integer idalt_targ
function M.pick_primary_and_prime(marray, opts)
	local id_targ = -1
	local dist_targ = -1
	local hpp_targ = -1
	local idalt_targ = -1
	local distalt_targ = -1
	if type(marray) ~= 'table' then
		return id_targ, idalt_targ
	end
	opts = opts or {}
	local claims_set = opts.claims_set or {}
	local manual = opts.manual == true
	local partner = opts.partner == true
	local tank = opts.tank == true
	local hunter_claim = opts.hunter_claim == true
	local prime = opts.prime == true
	local ignore_fn = opts.ignore_fn
	local partner_block_fn = opts.partner_block_fn
	for _, mob in pairs(marray) do
		if type(mob) == 'table' then
			local claim_id = mob.claim_id
			local claim_ok = hunter_claim or claims_set[claim_id] == true
			local blocked = type(ignore_fn) == 'function' and ignore_fn(mob) or false
			if claim_ok and mob.valid_target and not blocked then
				local partner_block = partner and type(partner_block_fn) == 'function' and partner_block_fn(mob.id) or false
				if manual or not partner or not partner_block then
					if (mob.spawn_type == 16 or manual) and (mob.hpp or 0) > 0 then
						if not tank then
							if dist_targ == -1 or mob.distance < dist_targ then
								id_targ = mob.id
								dist_targ = mob.distance
							end
						else
							if hpp_targ == -1 or (mob.hpp or 0) > hpp_targ then
								id_targ = mob.id
								hpp_targ = mob.hpp or 0
							end
						end
					end
				end
			elseif prime and id_targ == -1 then
				if claim_id == 0 and mob.spawn_type == 16 and mob.status == 1 and not blocked then
					local tempd = mob.distance
					if tempd and tempd:sqrt() < 8 and mob.valid_target and (mob.hpp or 0) > 0 then
						if distalt_targ == -1 or mob.distance < distalt_targ then
							idalt_targ = mob.id
							distalt_targ = mob.distance
						end
					end
				end
			end
		end
	end
	return id_targ, idalt_targ
end

return M
