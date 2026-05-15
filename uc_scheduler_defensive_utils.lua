local M = {}

local debuff_spell_mapping = {
	['paralysis'] = 'Paralyna',
	['silence'] = 'Silena',
	['blindness'] = 'Blindna',
	['poison'] = 'Poisona',
	['petrification'] = 'Stona',
	['curse'] = 'Cursna',
	['disease'] = 'Viruna',
	['plague'] = 'Viruna',
}

function M.debuff_spell_for_buff_id(res_table, buff_id)
	local buffs = res_table and res_table.buffs
	local b = buffs and buffs[buff_id] or nil
	local en = b and b.en and b.en:lower() or ''
	if en == '' then
		return nil
	end
	return debuff_spell_mapping[en]
end

function M.has_buff(buff_list, buff_id)
	if type(buff_list) ~= 'table' then
		return false
	end
	for _, b in ipairs(buff_list) do
		if b == buff_id then
			return true
		end
	end
	return false
end

function M.estimate_missing_hp(member)
	local hp = tonumber(member and member.hp) or 0
	local hpp = tonumber(member and member.hpp) or 100
	local max_hp = tonumber(member and member.max_hp) or 0
	if hpp <= 0 then
		return 0
	end
	if max_hp > 0 and hp >= 0 and hp <= max_hp then
		return math.max(0, math.ceil(max_hp - hp))
	end
	if hp > 0 then
		local max_hp = hp / (hpp / 100.0)
		return math.max(0, math.ceil(max_hp - hp))
	end
	-- HealBot-style fallback guess when exact hp is unavailable.
	local fallback_max = 1500
	local estimated_hp = math.ceil((hpp / 100.0) * fallback_max)
	return math.max(0, fallback_max - estimated_hp)
end

function M.resolve_doom_buff_id(res_table, doom_buff_id)
	if type(doom_buff_id) == 'number' then
		return doom_buff_id
	end
	doom_buff_id = 15
	for id, b in pairs((res_table and res_table.buffs) or {}) do
		local en = tostring((b and b.en) or ''):lower()
		if en == 'doom' then
			doom_buff_id = tonumber(id) or 15
			break
		end
	end
	return doom_buff_id
end

function M.player_has_doom(resolve_doom_buff_id_fn, player)
	if not player or type(player.buffs) ~= 'table' then
		return false
	end
	local bid = resolve_doom_buff_id_fn()
	for _, id in ipairs(player.buffs) do
		if tonumber(id) == bid then
			return true
		end
	end
	return false
end

function M.member_priority(member)
	-- Lower number means higher priority.
	if member.is_self then
		return 1
	end
	if member.spawn_type == 14 then
		return 6
	end
	return 5
end

function M.pri_default(player_prio, action_prio)
	return player_prio + ((action_prio or 5) / 10)
end

function M.danger_level(hpp)
	if hpp <= 20 then
		return 3
	elseif hpp <= 40 then
		return 2
	elseif hpp <= 60 then
		return 1
	end
	return 0
end

function M.cure_better(c1, c2)
	if not c1 then
		return false
	end
	if not c2 then
		return true
	end
	local p1, p2 = c1.member_prio, c2.member_prio
	local d1, d2 = c1.danger, c2.danger
	if p1 < p2 then
		return not (d2 > d1)
	elseif p1 > p2 then
		return d1 > d2
	end
	if d1 ~= d2 then
		return d1 > d2
	end
	return c1.target.hpp < c2.target.hpp
end

function M.cure_tier_for_missing_hp(hp_missing, max_tier, cure_by_tier)
	local tier = math.max(1, math.min(tonumber(max_tier) or 1, 6))
	while tier > 1 do
		local cur = cure_by_tier[tier] and cure_by_tier[tier].potency or 0
		local prev = cure_by_tier[tier - 1] and cure_by_tier[tier - 1].potency or 0
		local delta = cur - prev
		local threshold = cur - (delta * 0.5)
		if hp_missing >= threshold then
			break
		end
		tier = tier - 1
	end
	return tier
end

function M.is_bard_song(spell_name, get_spell_resource_fn)
	local sp = get_spell_resource_fn(spell_name)
	if not sp then
		return false
	end
	if tostring(sp.type or '') == 'BardSong' then
		return true
	end
	local skill = tostring(sp.skill or ''):lower()
	return skill == 'singing'
end

return M
