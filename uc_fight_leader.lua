---@diagnostic disable: undefined-global
--[[
  When settings.fight_leader and settings.fight_leader_id are set, prefer that party
  member's current target as mid if it is a valid combat mob and passes claim rules.
]]

local M = {}

local uc_target_ignore = require('uc_target_ignore')

local function has_value(tab, val)
	if not tab then
		return false
	end
	for _, v in ipairs(tab) do
		if v == val then
			return true
		end
	end
	return false
end

local function party_member_mob_ids()
	local party = windower.ffxi.get_party()
	if not party then
		return {}
	end
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	local out = {}
	for _, key in ipairs(keys) do
		local e = party[key]
		local ok, mob = pcall(function()
			return e and e.mob
		end)
		if ok and mob and mob.id and mob.id ~= 0 then
			out[#out + 1] = mob.id
		end
	end
	return out
end

function M.leader_target_id(fight_leader_id)
	if not fight_leader_id or fight_leader_id == 0 then
		return 0
	end
	local p = windower.ffxi.get_player()
	if not p then
		return 0
	end
	if p.id == fight_leader_id then
		local ok, t = pcall(function()
			return windower.ffxi.get_mob_by_target('t')
		end)
		if ok and t and t.id and t.id ~= 0 then
			return t.id
		end
		return 0
	end
	local ok, leader_mob = pcall(function()
		return windower.ffxi.get_mob_by_id(fight_leader_id)
	end)
	if not ok or not leader_mob or not leader_mob.target_index then
		return 0
	end
	local ok2, tid = pcall(function()
		return windower.ffxi.get_mob_by_index(leader_mob.target_index).id
	end)
	if ok2 and tid and tid ~= 0 then
		return tid
	end
	return 0
end

--- @param hunter_in_claim boolean  if true, settings.hunter bypasses party-claim check (DD2 behavior)
--- @param partner_skip fun(tid: number): boolean  if true, do not use this mob as override
function M.resolve_mid_override(settings, hunter_in_claim, partner_skip)
	if not settings or not settings.fight_leader or (settings.fight_leader_id or 0) == 0 then
		return 0
	end
	local tid = M.leader_target_id(settings.fight_leader_id)
	if tid <= 0 then
		return 0
	end
	local ok, m = pcall(function()
		return windower.ffxi.get_mob_by_id(tid)
	end)
	if not ok or not m then
		return 0
	end
	if m.hpp == nil or m.hpp <= 0 or m.spawn_type ~= 16 or not m.valid_target then
		return 0
	end
	local claims = party_member_mob_ids()
	local claim_party = has_value(claims, m.claim_id)
	if hunter_in_claim and settings.hunter then
		claim_party = true
	end
	if not claim_party then
		if not (settings.prime and m.claim_id == 0) then
			return 0
		end
	end
	if partner_skip and partner_skip(tid) then
		return 0
	end
	if settings and uc_target_ignore.is_mob_blocked(settings, m) then
		return 0
	end
	return tid
end

return M
