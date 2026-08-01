local M = {}

local function finite_number(value)
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	return number
end

local function distance_2d(a, b)
	local ax = finite_number(a and a.x)
	local ay = finite_number(a and a.y)
	local bx = finite_number(b and b.x)
	local by = finite_number(b and b.y)
	if ax == nil or ay == nil or bx == nil or by == nil then
		return nil
	end
	local dx = ax - bx
	local dy = ay - by
	return math.sqrt(dx * dx + dy * dy)
end

local function target_policy(config)
	local exact = {}
	local substring = {}
	for i = 1, #config.targets do
		local entry = config.targets[i]
		local normalized = tostring(entry.name):lower()
		local policy = {
			name = entry.name,
			priority = tonumber(entry.priority),
		}
		if config.match_mode == 'exact' then
			exact[normalized] = policy
		else
			substring[#substring + 1] = {
				token = normalized,
				policy = policy,
			}
		end
	end
	return exact, substring
end

local function match_target(name, config, exact, substring)
	local normalized = tostring(name or ''):lower()
	if normalized == '' then
		return nil
	end
	if config.match_mode == 'exact' then
		return exact[normalized]
	end
	local matched = nil
	for i = 1, #substring do
		local entry = substring[i]
		if normalized:find(entry.token, 1, true) then
			if matched ~= nil then
				error(('camp pulling target "%s" matches more than one substring policy'):format(name))
			end
			matched = entry.policy
		end
	end
	return matched
end

function M.pull_demand(config, mobs, friendly_claims, pull_registry)
	if type(config) ~= 'table'
		or type(mobs) ~= 'table'
		or type(friendly_claims) ~= 'table'
		or type(pull_registry) ~= 'table'
		or type(pull_registry.quota_eligible) ~= 'function' then
		error('camp pull demand requires config, mobs, friendly_claims, and pull_registry contracts')
	end
	local active_count = 0
	local low_hpp_active = false
	for _, mob in pairs(mobs) do
		local id = tonumber(mob and mob.id) or 0
		local claim_id = tonumber(mob and mob.claim_id) or 0
		local hpp = tonumber(mob and mob.hpp) or 0
		local spawn_type = tonumber(mob and mob.spawn_type) or 0
		local friendly_claimed = claim_id > 0 and friendly_claims[claim_id] == true
		local tracked_active = id > 0 and pull_registry.quota_eligible(mob, friendly_claims)
		if mob.valid_target == true
			and spawn_type == 16
			and hpp > 0
			and (friendly_claimed or tracked_active) then
			active_count = active_count + 1
			if hpp <= config.replenish_below_hpp then
				low_hpp_active = true
			end
		end
	end
	local demanded = active_count < config.max_active_mobs
		or (active_count == config.max_active_mobs and low_hpp_active)
	return demanded, {
		active_count = active_count,
		low_hpp_active = low_hpp_active,
		quota = config.max_active_mobs,
	}
end

function M.select_candidate(config, ctx, anchor, friendly_claims, cooldowns, ignored)
	if type(config) ~= 'table'
		or type(ctx) ~= 'table'
		or type(anchor) ~= 'table'
		or type(friendly_claims) ~= 'table'
		or type(cooldowns) ~= 'table'
		or type(ignored) ~= 'function' then
		error('camp pull candidate selection received an invalid contract')
	end
	local me_z = finite_number(ctx.me and ctx.me.z)
	if me_z == nil then
		return nil, 'PULL_PLAYER_Z_UNAVAILABLE'
	end
	local exact, substring = target_policy(config)
	local candidates = {}
	for _, mob in pairs(ctx.mob_array) do
		local id = tonumber(mob and mob.id) or 0
		local hpp = tonumber(mob and mob.hpp) or 0
		local claim_id = tonumber(mob and mob.claim_id) or 0
		local status = tonumber(mob and mob.status) or 0
		local spawn_type = tonumber(mob and mob.spawn_type) or 0
		local policy = match_target(mob and mob.name, config, exact, substring)
		local camp_distance = distance_2d(mob, anchor)
		local mob_z = finite_number(mob and mob.z)
		local z_delta = mob_z and math.abs(mob_z - me_z) or nil
		local cooldown_until = tonumber(cooldowns[id]) or 0
		if id > 0
			and policy ~= nil
			and mob.valid_target == true
			and spawn_type == 16
			and hpp == 100
			and status == 0
			and claim_id == 0
			and camp_distance ~= nil
			and camp_distance <= config.leash_yalms
			and z_delta ~= nil
			and z_delta <= config.max_z_delta
			and cooldown_until <= ctx.now
			and not ignored(mob) then
			candidates[#candidates + 1] = {
				id = id,
				name = tostring(mob.name),
				priority = policy.priority,
				camp_distance = camp_distance,
				mob = mob,
			}
		end
	end
	table.sort(candidates, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		if a.camp_distance ~= b.camp_distance then
			return a.camp_distance < b.camp_distance
		end
		return a.id < b.id
	end)
	return candidates[1], candidates[1] and 'PULL_CANDIDATE_SELECTED' or 'PULL_NO_CANDIDATE'
end

function M.candidate_eligible(config, ctx, anchor, cooldowns, ignored, mob)
	if type(config) ~= 'table'
		or type(ctx) ~= 'table'
		or type(anchor) ~= 'table'
		or type(cooldowns) ~= 'table'
		or type(ignored) ~= 'function' then
		error('camp pull candidate validation received an invalid contract')
	end
	local id = tonumber(mob and mob.id) or 0
	local me_z = finite_number(ctx.me and ctx.me.z)
	local mob_z = finite_number(mob and mob.z)
	if id <= 0 or me_z == nil or mob_z == nil then
		return false, 'PULL_GEOMETRY_UNAVAILABLE'
	end
	local exact, substring = target_policy(config)
	if match_target(mob.name, config, exact, substring) == nil then
		return false, 'PULL_TARGET_POLICY_MISMATCH'
	end
	if mob.valid_target ~= true
		or tonumber(mob.spawn_type) ~= 16
		or tonumber(mob.hpp) ~= 100
		or tonumber(mob.status) ~= 0
		or (tonumber(mob.claim_id) or 0) ~= 0 then
		return false, 'PULL_TARGET_STATE_INVALID'
	end
	local camp_distance = distance_2d(mob, anchor)
	if camp_distance == nil or camp_distance > config.leash_yalms then
		return false, 'PULL_TARGET_OUT_OF_LEASH'
	end
	if math.abs(mob_z - me_z) > config.max_z_delta then
		return false, 'PULL_TARGET_Z_DELTA'
	end
	if (tonumber(cooldowns[id]) or 0) > ctx.now then
		return false, 'PULL_TARGET_COOLDOWN'
	end
	if ignored(mob) then
		return false, 'PULL_TARGET_IGNORED'
	end
	return true, 'PULL_TARGET_ELIGIBLE'
end

function M.distance_2d(a, b)
	return distance_2d(a, b)
end

return M
