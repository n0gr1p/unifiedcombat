local targeting_common = require('uc_targeting_common')

local M = {}

local MAX_CAST_RANGE = 21.0
local bound_target_id = 0
local bound_target_name = ''

local function ffxi_api()
	if type(windower) ~= 'table' or type(windower.ffxi) ~= 'table' then
		return nil
	end
	return windower.ffxi
end

local function friendly_claims()
	local _ids, claims = targeting_common.build_friendly_claims()
	return type(claims) == 'table' and claims or {}
end

local function distance_yalms(target)
	local squared = tonumber(target and target.distance)
	if squared == nil or squared < 0 then
		return nil
	end
	return math.sqrt(squared)
end

local function validate_with_claims(target, claims, max_range)
	if type(target) ~= 'table' then
		return false, 'target_missing'
	end
	if (tonumber(target.id) or 0) <= 0 then
		return false, 'target_id_invalid'
	end
	if target.valid_target ~= true then
		return false, 'target_not_valid'
	end
	if (tonumber(target.hpp) or 0) <= 0 then
		return false, 'target_dead'
	end
	if tonumber(target.spawn_type) ~= 16 then
		return false, 'target_not_hostile_mob'
	end
	local claim_id = tonumber(target.claim_id) or 0
	if claim_id <= 0 or claims[claim_id] ~= true then
		return false, 'target_not_party_claimed'
	end
	if max_range ~= nil then
		local range = distance_yalms(target)
		if range == nil then
			return false, 'target_range_unknown'
		end
		if range > max_range then
			return false, 'target_out_of_range'
		end
	end
	return true, ''
end

local function snapshot(target)
	return {
		id = tonumber(target.id) or 0,
		name = tostring(target.name or ''),
		hpp = tonumber(target.hpp) or 0,
		valid_target = target.valid_target == true,
		claim_id = tonumber(target.claim_id) or 0,
		spawn_type = tonumber(target.spawn_type) or 0,
		distance = tonumber(target.distance),
	}
end

function M.validate(target, opts)
	opts = type(opts) == 'table' and opts or {}
	local max_range = opts.max_range
	if max_range == nil and opts.require_cast_range == true then
		max_range = MAX_CAST_RANGE
	end
	return validate_with_claims(target, friendly_claims(), max_range)
end

function M.resolve(target_id, opts)
	local id = tonumber(target_id) or 0
	if id <= 0 then
		return nil, 'target_id_invalid'
	end
	local ffxi = ffxi_api()
	if ffxi == nil or type(ffxi.get_mob_by_id) ~= 'function' then
		return nil, 'target_lookup_unavailable'
	end
	local ok, target = pcall(ffxi.get_mob_by_id, id)
	if not ok or type(target) ~= 'table' or (tonumber(target.id) or 0) ~= id then
		return nil, 'target_not_found'
	end
	local valid, reason = M.validate(target, opts)
	if not valid then
		return nil, reason
	end
	return snapshot(target), ''
end

function M.bind(target)
	if type(target) ~= 'table' or (tonumber(target.id) or 0) <= 0 then
		return false, 'target_id_invalid'
	end
	bound_target_id = tonumber(target.id) or 0
	bound_target_name = tostring(target.name or '')
	return true, ''
end

function M.clear()
	bound_target_id = 0
	bound_target_name = ''
end

function M.bound()
	return {
		id = bound_target_id,
		name = bound_target_name,
	}
end

function M.resolve_bound(opts)
	if bound_target_id <= 0 then
		return nil, 'no_bound_target'
	end
	return M.resolve(bound_target_id, opts)
end

function M.validate_bound(opts)
	local target, reason = M.resolve_bound(opts)
	return target ~= nil, reason, target
end

function M.select()
	-- Once a chain starts, its enemy identity is sticky. If that mob stops being
	-- a valid friendly claim, return nil so the runtime aborts instead of silently
	-- switching the chain to a different enemy.
	if bound_target_id > 0 then
		return M.resolve_bound({ max_range = MAX_CAST_RANGE })
	end

	local ffxi = ffxi_api()
	if ffxi == nil then
		return nil, 'target_lookup_unavailable'
	end
	local claims = friendly_claims()

	-- Prefer the player's selected mob when it is already the correct friendly
	-- claim, but selection is only a preference, never a requirement.
	if type(ffxi.get_mob_by_target) == 'function' then
		local ok, selected = pcall(ffxi.get_mob_by_target, 't')
		if ok and type(selected) == 'table' then
			local valid = validate_with_claims(selected, claims, MAX_CAST_RANGE)
			if valid then
				return snapshot(selected), ''
			end
		end
	end

	if type(ffxi.get_mob_array) ~= 'function' then
		return nil, 'mob_array_unavailable'
	end
	local ok, mobs = pcall(ffxi.get_mob_array)
	if not ok or type(mobs) ~= 'table' then
		return nil, 'mob_array_unavailable'
	end

	local best = nil
	local best_distance = math.huge
	for _, mob in pairs(mobs) do
		if type(mob) == 'table' then
			local valid = validate_with_claims(mob, claims, MAX_CAST_RANGE)
			if valid then
				local squared = tonumber(mob.distance) or math.huge
				if squared < best_distance then
					best = mob
					best_distance = squared
				end
			end
		end
	end
	if best == nil then
		return nil, 'no_valid_party_claimed_target'
	end
	return snapshot(best), ''
end

M.MAX_CAST_RANGE = MAX_CAST_RANGE

return M
