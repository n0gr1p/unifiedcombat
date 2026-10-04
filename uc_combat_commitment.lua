local M = {}

local function call_build_set(fn)
	if type(fn) ~= 'function' then
		return {}
	end
	local _, set = fn()
	if type(set) ~= 'table' then
		return {}
	end
	return set
end

function M.evaluate(ctx, target, deps)
	ctx = type(ctx) == 'table' and ctx or {}
	target = type(target) == 'table' and target or {}
	deps = type(deps) == 'table' and deps or {}

	local target_id = tonumber(target.id) or 0
	local claim_id = tonumber(target.claim_id) or 0
	if target_id <= 0 then
		return {
			committed = false,
			reason = 'invalid_target',
			claim_id = claim_id,
			claim_check = 'invalid_target',
		}
	end

	local claims_set = type(deps.claims_set) == 'table' and deps.claims_set
		or call_build_set(deps.build_friendly_claims)
	local party_ids = type(deps.party_ids) == 'table' and deps.party_ids
		or (type(deps.build_party_id_set) == 'function' and deps.build_party_id_set() or {})
	if type(party_ids) ~= 'table' then
		party_ids = {}
	end

	local player_engaged = deps.allow_player_engaged == true
		and tonumber(ctx.player and ctx.player.status) == 1
		and tonumber(target.status) == 1
	local party_claimed_ok = claims_set[claim_id] == true
	local camp_pull_order = nil
	if type(deps.camp_pull_order) == 'function' then
		camp_pull_order = deps.camp_pull_order(target, claims_set)
	end
	local camp_pull_ok = camp_pull_order ~= nil
	local prime_unclaimed_ok = false
	if type(deps.prime_unclaimed_party_aggressive_ok) == 'function' then
		prime_unclaimed_ok = deps.prime_unclaimed_party_aggressive_ok(ctx.settings, target, party_ids) == true
	end
	local force_target_id = tonumber(deps.force_target_id) or 0
	local force_leader_engage = force_target_id > 0 and force_target_id == target_id
	local committed = player_engaged or party_claimed_ok or camp_pull_ok or prime_unclaimed_ok or force_leader_engage

	local reason = 'selection_only'
	if player_engaged then
		reason = 'player_engaged'
	elseif party_claimed_ok then
		reason = 'party_claimed'
	elseif camp_pull_ok then
		reason = 'camp_pull'
	elseif prime_unclaimed_ok then
		reason = 'prime_aggressive'
	elseif force_leader_engage then
		reason = 'fight_leader'
	end

	return {
		committed = committed,
		reason = reason,
		claim_id = claim_id,
		player_engaged = player_engaged,
		party_claimed = party_claimed_ok,
		camp_pull_order = camp_pull_order,
		prime_unclaimed = prime_unclaimed_ok,
		force_leader = force_leader_engage,
		claim_check = ('party_claimed=%s,camp_pull=%s,prime_unclaimed=%s,force_leader=%s,claim_id=%d'):format(
			party_claimed_ok and '1' or '0',
			camp_pull_ok and tostring(camp_pull_order) or '0',
			prime_unclaimed_ok and '1' or '0',
			force_leader_engage and '1' or '0',
			claim_id
		),
	}
end

function M.evaluate_runtime(ctx, target, opts)
	ctx = type(ctx) == 'table' and ctx or {}
	opts = type(opts) == 'table' and opts or {}
	local targeting_common = require('uc_targeting_common')
	local camp_pull_registry = require('uc_camp_pull_registry')
	local scheduler_config = require('uc_scheduler_config')
	local follow_config = require('uc_follow_config')
	local fight_leader = require('uc_fight_leader')
	local config = type(ctx.config) == 'table' and ctx.config or {}

	local force_target_id = 0
	local fight = follow_config.fight(config)
	if type(fight) == 'table' and fight.leader == true then
		local leader_id = follow_config.fight_leader_id(config)
		if leader_id > 0 then
			force_target_id = tonumber(fight_leader.leader_target_id(leader_id)) or 0
		end
	end

	local function build_party_id_set()
		local _, set = targeting_common.get_friendly_combat_member_ids()
		return set
	end

	local function prime_unclaimed_party_aggressive_ok(_, mob, party_ids)
		if not scheduler_config.combat_prime_from_config(config) then
			return false
		end
		if not mob or (tonumber(mob.claim_id) or 0) ~= 0 then
			return false
		end
		if (tonumber(mob.status) or 0) ~= 1 then
			return false
		end
		return targeting_common.mob_targets_friendly_member(mob, party_ids, tonumber(ctx.now) or 0) == true
	end

	return M.evaluate(ctx, target, {
		build_friendly_claims = targeting_common.build_friendly_claims,
		build_party_id_set = build_party_id_set,
		camp_pull_order = camp_pull_registry.combat_order,
		prime_unclaimed_party_aggressive_ok = prime_unclaimed_party_aggressive_ok,
		force_target_id = force_target_id,
		allow_player_engaged = opts.allow_player_engaged == true,
	})
end

return M
