-- Shared targeting helpers for melee/dd2 target scans.

local M = {}

local PARTY_KEYS = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }

function M.build_party_claims()
	local party = windower.ffxi.get_party()
	local ids = {}
	local set = {}
	if type(party) ~= 'table' then
		return ids, set
	end
	for _, key in ipairs(PARTY_KEYS) do
		local entry = party[key]
		local mob = entry and entry.mob
		local id = mob and mob.id or 0
		if id ~= 0 then
			ids[#ids + 1] = id
			set[id] = true
		end
	end
	return ids, set
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
