local policy = require('uc_scheduler_na_policy')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_nil(actual, message)
	if actual ~= nil then
		error((message or 'expected nil') .. ': actual=' .. tostring(actual))
	end
end

local buffs = {
	[1] = { en = 'Attack Down' },
	[2] = { en = 'poison' },
	[3] = { en = 'paralysis' },
	[4] = { en = 'Dia' },
}

local debuff_map = {
	['Attack Down'] = 'Erase',
	['poison'] = 'Poisona',
	['paralysis'] = 'Paralyna',
	['Dia'] = 'Erase',
}

local built_in_priority = {
	attack_down = 3,
	poison = 0,
	paralysis = 1,
	dia = 5,
}

local known_status_keys = {
	attack_down = true,
	poison = true,
	paralysis = true,
	dia = true,
}

local function normalize_status(buff_res)
	local key = tostring(buff_res and buff_res.en or ''):lower():gsub('%s+', '_')
	return key
end

local function member_priority(member)
	if member.is_self then
		return 1
	end
	if member.spawn_type == 14 then
		return 6
	end
	return 5
end

local ready = {
	Erase = true,
	Poisona = true,
	Paralyna = true,
}

local alternative_enabled = false
local spell_blocked = false
local alternative_in_range = true

local deps = {
	buffs = buffs,
	debuff_map = debuff_map,
	status_removal_priority = built_in_priority,
	known_status_keys = known_status_keys,
	debuff_spell_for_buff_id = function()
		return nil
	end,
	normalize_status_removal_key = normalize_status,
	action_ready = function(spell)
		return ready[spell] == true
	end,
	attempt_allowed = function()
		return true
	end,
	in_party_cast_range = function(member)
		return member.in_range ~= false
	end,
	spell_status_removal_blocked = function()
		return spell_blocked
	end,
	status_removal_alternative_in_range = function()
		return alternative_enabled and alternative_in_range
	end,
	status_removal_alternative = function()
		if not alternative_enabled or not alternative_in_range then return nil end
		return { action_name = 'Healing Waltz', action_kind = 'ja', target_range = 24.9, tp_cost = 200 }
	end,
	member_priority = member_priority,
	pri_default = function(member_prio, action_prio)
		return member_prio + ((action_prio or 5) / 10)
	end,
}

local function choose(members, enabled, limit_enabled, priority)
	return policy.choose_status_removal(members, {
		enabled = enabled,
		limit_enabled = limit_enabled,
		priority = priority,
		now = 10,
	}, deps)
end

local function main()
	local parsed = policy.parse_priority_list(' Poison | PARALYZE | poison | Dia | NotAStatus ', known_status_keys)
	assert_equal(#parsed.order, 3, 'priority parser must trim, dedupe, and discard unknown entries')
	assert_equal(parsed.order[1], 'poison', 'Poison priority mismatch')
	assert_equal(parsed.order[2], 'paralysis', 'Paralyze alias/case priority mismatch')
	assert_equal(parsed.order[3], 'dia', 'Dia priority mismatch')

	local self = { name = 'WhiteMage', id = 1, is_self = true, hpp = 100, buffs = { 1 } }
	local ally = { name = 'Ally', id = 2, hpp = 100, buffs = { 2 } }
	local trust = { name = 'Trust', id = 3, spawn_type = 14, hpp = 100, buffs = { 2 } }

	assert_nil(choose({ self, ally }, false, false, ''), 'NA disabled must produce no work')
	local unrestricted = choose({ self, ally }, true, false, '')
	assert_equal(unrestricted.spell, 'Erase', 'unrestricted behavior must preserve member-first winner')
	assert_equal(unrestricted.target.name, 'WhiteMage', 'unrestricted self priority must remain unchanged')
	assert_equal(unrestricted.na_limited, false, 'unrestricted candidate marker mismatch')
	assert_nil(choose({ self, ally }, true, true, ''), 'enabled empty limit must fail closed')

	local dhartok = choose({ self, ally }, true, true, 'Poison')
	assert_equal(dhartok.spell, 'Poisona', 'Dhartok regression must select Poisona')
	assert_equal(dhartok.target.name, 'Ally', 'Dhartok regression target mismatch')
	assert_equal(dhartok.na_limited, true, 'limited candidate marker mismatch')
	for _ = 1, 3 do
		local repeated = choose({ self, ally }, true, true, 'Poison')
		assert_equal(repeated.spell, 'Poisona', 'persistent Attack Down must never create an Erase loop')
	end

	self.buffs = { 3 }
	local cross_party = choose({ self, ally }, true, true, 'Poison|Paralyze')
	assert_equal(cross_party.spell, 'Poisona', 'ally Poison must outrank self Paralyna')
	local cross_trust = choose({ self, trust }, true, true, 'Poison|Paralyze')
	assert_equal(cross_trust.spell, 'Poisona', 'eligible trust Poison must outrank self Paralyna')

	self.buffs = { 2 }
	local same_status = choose({ ally, self, trust }, true, true, 'Poison')
	assert_equal(same_status.target.name, 'WhiteMage', 'same-status targeting must preserve existing member priority')

	self.buffs = {}
	ally.buffs = { 2 }
	local first = choose({ self, ally }, true, true, 'Poison|Paralyze')
	assert_equal(first.spell, 'Poisona', 'first evaluation must select Poison')
	ally.buffs = { 3 }
	local second = choose({ self, ally }, true, true, 'Poison|Paralyze')
	assert_equal(second.spell, 'Paralyna', 'Paralyze must become eligible after Poison clears')
	self.buffs = { 2 }
	local third = choose({ self, ally }, true, true, 'Poison|Paralyze')
	assert_equal(third.spell, 'Poisona', 'reapplied Poison must immediately preempt Paralyze')

	self.buffs = { 1 }
	ally.buffs = {}
	assert_nil(choose({ self, ally }, true, true, 'Poison'), 'unlisted status must never create a candidate')
	self.buffs = { 3 }
	assert_nil(choose({ self }, true, true, 'Poison'), 'limited list must be able to exclude self Paralyna')

	self.buffs = { 3 }
	ally.buffs = { 2 }
	local configured = choose({ self, ally }, true, true, 'Poison|Paralyze')
	local ordinary_cure = { type = 'cure', spell = 'Cure IV', prio = 1, target = { name = 'Other', hpp = 60 } }
	local critical_cure = { type = 'cure', spell = 'Cure IV', prio = 1, target = { name = 'Other', hpp = 20 } }
	local chosen, reason = policy.choose_defensive_action({ cure = ordinary_cure, debuff = configured }, 35)
	assert_equal(chosen, configured, 'configured limited removal must outrank ordinary Cure')
	assert_equal(reason, 'BLOCK_DEFENSIVE_NA', 'limited removal reason mismatch')
	chosen, reason = policy.choose_defensive_action({ cure = critical_cure, debuff = configured }, 35)
	assert_equal(chosen, critical_cure, 'existing critical Cure classification must outrank limited removal')
	assert_equal(reason, 'BLOCK_DEFENSIVE_CURE', 'critical Cure reason mismatch')
	local critical_aoe = { type = 'cure', action_name = 'Curaga III', action_kind = 'spell', lowest_covered_hpp = 20, target = { name = 'Healthy Anchor', hpp = 100 } }
	chosen = policy.choose_defensive_action({ cure = critical_aoe, debuff = configured }, 35)
	assert_equal(chosen, critical_aoe, 'AoE criticality must use the worst covered recipient rather than anchor HPP')

	local self_paralyna = choose({ self }, true, false, '')
	chosen = policy.choose_defensive_action({ cure = ordinary_cure, debuff = self_paralyna }, 35)
	assert_equal(chosen, self_paralyna, 'unrestricted self-Paralyna behavior must remain unchanged')

	ready.Poisona = false
	local actionable = choose({ self, ally }, true, true, 'Poison|Paralyze')
	assert_equal(actionable.spell, 'Paralyna', 'unready higher-priority status must not block actionable lower status')
	ready.Poisona = true

	alternative_enabled = true
	self.buffs = {}
	ally.buffs = { 2 }
	local spell_preferred = choose({ ally }, true, false, '')
	assert_equal(spell_preferred.action_name, 'Poisona', 'ready spell removal must retain deterministic preference over Healing Waltz')
	assert_equal(spell_preferred.action_kind, 'spell', 'ready spell removal kind')
	ready.Poisona = false
	local waltz_fallback = choose({ ally }, true, false, '')
	assert_equal(waltz_fallback.action_name, 'Healing Waltz', 'Healing Waltz must become available when the spell is not ready')
	assert_equal(waltz_fallback.action_kind, 'ja', 'Healing Waltz candidate kind')
	assert_nil(waltz_fallback.spell, 'Healing Waltz must not pretend to be a spell')
	ready.Poisona = true
	spell_blocked = true
	local silenced_waltz = choose({ ally }, true, false, '')
	assert_equal(silenced_waltz.action_name, 'Healing Waltz', 'Healing Waltz must replace spell removal when spell casting is blocked')
	local limited_waltz = choose({ ally }, true, true, 'Poison')
	assert_equal(limited_waltz.action_name, 'Healing Waltz', 'Healing Waltz must honor the limited NA priority list')
	spell_blocked = false
	ally.in_range = false
	local extended_range_waltz = choose({ ally }, true, false, '')
	assert_equal(extended_range_waltz.action_name, 'Healing Waltz', 'Healing Waltz alternative range must remain independent of spell range')
	alternative_in_range = false
	assert_nil(choose({ ally }, true, false, ''), 'Healing Waltz outside 24.9-yalm range must be rejected')

	io.stdout:write('selftest_na_status_removal_priority: OK\n')
end

main()
