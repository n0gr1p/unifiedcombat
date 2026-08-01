local M = {}

local function live_monster(mob)
	return type(mob) == 'table'
		and mob.valid_target == true
		and (tonumber(mob.spawn_type) or 0) == 16
		and (tonumber(mob.hpp) or 0) > 0
end

function M.decide(input)
	assert(type(input) == 'table', 'partner arbitration requires input')
	assert(type(input.partners) == 'table', 'partner arbitration requires partner snapshots')
	assert(type(input.mobs) == 'table', 'partner arbitration requires mob snapshots')
	assert(type(input.claims_set) == 'table', 'partner arbitration requires friendly claims')
	assert(type(input.blocked_mob_ids) == 'table', 'partner arbitration requires blocked mob ids')

	if input.partner_enabled ~= true then
		return nil
	end

	local my_id = tonumber(input.my_id) or 0
	local current = input.current_target
	if my_id <= 0 or tonumber(input.player_status) ~= 1 or not live_monster(current) then
		return nil
	end

	local current_id = tonumber(current.id) or 0
	local winner_id = 0
	local occupied_target_ids = {}
	for _, partner in ipairs(input.partners) do
		local partner_id = tonumber(partner and partner.id) or 0
		local target_id = tonumber(partner and partner.target_id) or 0
		if partner_id > 0 and tonumber(partner.status) == 1 and target_id > 0 and partner.target_live == true then
			occupied_target_ids[target_id] = true
			if target_id == current_id and (winner_id == 0 or partner_id < winner_id) then
				winner_id = partner_id
			end
		end
	end

	if winner_id == 0 or my_id <= winner_id then
		return nil
	end

	if input.autotarget_enabled == true then
		local best = nil
		local best_distance = 1e9
		for _, mob in pairs(input.mobs) do
			local mob_id = tonumber(mob and mob.id) or 0
			local claim_id = tonumber(mob and mob.claim_id) or 0
			local distance = tonumber(mob and mob.distance)
			if mob_id > 0 and mob_id ~= current_id and live_monster(mob)
				and input.claims_set[claim_id] == true
				and input.blocked_mob_ids[mob_id] ~= true
				and occupied_target_ids[mob_id] ~= true
				and distance ~= nil and distance < best_distance then
				best = mob
				best_distance = distance
			end
		end
		if best then
			return {
				action = 'switch',
				winner_id = winner_id,
				from_target_id = current_id,
				target_id = tonumber(best.id),
			}
		end
	end

	return {
		action = 'disengage',
		winner_id = winner_id,
		from_target_id = current_id,
	}
end

return M
