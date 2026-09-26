package.path = './?.lua;' .. package.path

local healing = require('uc_defensive_healing')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s (expected=%s actual=%s)'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then error(message) end
end

local function member(id, name, x, y, hpp, missing, is_self)
	return {
		id = id,
		name = name,
		x = x,
		y = y,
		hpp = hpp,
		missing = missing,
		is_self = is_self == true,
		coordinate_observed_at = 99.8,
	}
end

local function plan(members, injured_ids, minimum_targets, mechanics)
	return healing.plan_aoe({
		now = 100,
		members = members,
		injured_recipient_ids = injured_ids,
		minimum_targets = minimum_targets,
		mechanics = mechanics,
		member_priority = function(row) return row.is_self and 1 or 5 end,
		estimate_missing_hp = function(row) return row.missing end,
	})
end

local members = {
	member(1, 'Self', -12, 0, 100, 0, true),
	member(2, 'Lowest', 0, 0, 20, 1000),
	member(3, 'Third', 15.1, 0, 60, 400),
	member(4, 'Fourth', 15.2, 0, 70, 300),
	member(5, 'Best Anchor', 7.6, 0, 100, 0),
}

local best = plan(members, { 2, 3, 4 }, 3, healing.mechanics.curaga)
assert_equal(best.state, 'ready', 'Curaga geometry should produce a candidate')
assert_equal(best.selected.anchor_id, 5, 'Curaga must choose the best anchor instead of the lowest-HP member')
assert_equal(best.selected.coverage_count, 3, 'Curaga coverage count')
assert_equal(best.selected.aggregate_missing_hp, 1700, 'Curaga aggregate missing HP')
assert_equal(best.selected.lowest_covered_hpp, 20, 'Curaga criticality must use the worst covered recipient')

local anchor_199 = {
	member(1, 'Self', 0, 0, 100, 0, true),
	member(2, 'Anchor', 19.9, 0, 100, 0),
	member(3, 'A', 19.9, 0, 70, 300),
	member(4, 'B', 19.9, 14.9, 60, 400),
}
local boundary = plan(anchor_199, { 3, 4 }, 2, healing.mechanics.curaga)
assert_equal(boundary.state, 'ready', '19.9-yalm Curaga anchor and 14.9-yalm recipient must be eligible')
assert_equal(boundary.selected.anchor_id, 2, '19.9-yalm Curaga anchor should win')

local anchor_2001 = {
	member(1, 'Self', 0, 0, 100, 0, true),
	member(2, 'Anchor', 20.01, 0, 100, 0),
	member(3, 'A', 20.01, 0, 70, 300),
	member(4, 'B', 20.01, 1, 60, 400),
}
local out_of_range = plan(anchor_2001, { 3, 4 }, 2, healing.mechanics.curaga)
assert_equal(out_of_range.state, 'blocked', 'Curaga anchor beyond 20.0 yalms must be rejected')
assert_equal(out_of_range.blocker, 'AOE_COVERAGE_BELOW_MINIMUM', 'in-range anchors without coverage must report minimum failure')

local radius_boundary = {
	member(1, 'Self', 0, 0, 100, 0, true),
	member(2, 'A', 20.0, 0, 70, 300),
	member(3, 'B', 4.99, 0, 60, 400),
}
local radius_result = plan(radius_boundary, { 2, 3 }, 2, healing.mechanics.curaga)
assert_equal(radius_result.state, 'blocked', 'recipient beyond 15.0 yalms must not count toward Curaga minimum')

local min_result = plan(members, { 2, 3, 4 }, 4, healing.mechanics.curaga)
assert_equal(min_result.blocker, 'AOE_COVERAGE_BELOW_MINIMUM', 'Curaga minimum target count must be honored')

local missing_geometry = {
	member(1, 'Self', 0, 0, 100, 0, true),
	member(2, 'A', nil, 0, 70, 300),
	member(3, 'B', 1, 0, 60, 400),
}
local missing_result = plan(missing_geometry, { 2, 3 }, 2, healing.mechanics.curaga)
assert_equal(missing_result.blocker, 'AOE_GEOMETRY_UNKNOWN', 'missing geometry must suppress Curaga')
missing_geometry[2].x = 0.5
missing_geometry[2].coordinate_observed_at = 90
local stale_result = plan(missing_geometry, { 2, 3 }, 2, healing.mechanics.curaga)
assert_equal(stale_result.blocker, 'AOE_GEOMETRY_UNKNOWN', 'stale geometry must suppress Curaga')

local divine_members = {
	member(1, 'Self', 0, 0, 100, 0, true),
	member(2, 'Anchor', 10.6, 0, 100, 0),
	member(3, 'A', 10.6, 0, 70, 300),
	member(4, 'B', 10.6, 9.9, 60, 400),
}
local divine = plan(divine_members, { 3, 4 }, 2, healing.mechanics.divine_waltz)
assert_equal(divine.state, 'ready', 'Divine Waltz 10.6 target and 9.9 radius boundaries must be eligible')
assert_equal(divine.selected.anchor_id, 2, 'Divine Waltz should choose its deterministic best anchor')
divine_members[2].x = 10.61
divine_members[3].x = 10.61
divine_members[4].x = 10.61
local divine_range = plan(divine_members, { 3, 4 }, 2, healing.mechanics.divine_waltz)
assert_equal(divine_range.state, 'blocked', 'Divine Waltz anchor beyond 10.6 yalms must be rejected')
local divine_minimum = plan({
	member(1, 'Self', 0, 0, 100, 0, true),
	member(2, 'A', 1, 0, 70, 300),
	member(3, 'B', 2, 0, 60, 400),
}, { 2, 3 }, 3, healing.mechanics.divine_waltz)
assert_equal(divine_minimum.blocker, 'AOE_COVERAGE_BELOW_MINIMUM', 'Divine Waltz configured minimum must be honored')

local critical_single = { type = 'cure', target = { hpp = 20 } }
local routine_aoe = { aoe = true, coverage_count = 3, aggregate_missing_hp = 1500, lowest_covered_hpp = 20 }
local aoe_allowed, aoe_reason = healing.should_admit_aoe(critical_single, routine_aoe, 35)
assert_true(not aoe_allowed, 'critical single-target Cure must not be displaced merely by minimum AoE coverage')
assert_equal(aoe_reason, 'CRITICAL_SINGLE_TARGET_PRESERVED', 'critical single-target protection reason')

local critical_multicure = {
	aoe = true,
	coverage_count = 2,
	aggregate_missing_hp = 1800,
	lowest_covered_hpp = 18,
	critical_multicure = true,
	critical_coverage_count = 2,
}
local multicure_allowed, multicure_reason = healing.should_admit_aoe(critical_single, critical_multicure, 35)
assert_true(multicure_allowed, 'Curaga covering two critical recipients must override a critical single-target Cure')
assert_equal(multicure_reason, 'CRITICAL_MULTICURE_OVERRIDE', 'critical multicure override reason')

local insufficient_critical_multicure = {
	aoe = true,
	coverage_count = 2,
	aggregate_missing_hp = 1800,
	lowest_covered_hpp = 18,
	critical_multicure = true,
	critical_coverage_count = 1,
}
local insufficient_allowed, insufficient_reason = healing.should_admit_aoe(critical_single, insufficient_critical_multicure, 35)
assert_true(not insufficient_allowed, 'Curaga covering fewer than two critical recipients must not override a critical single-target Cure')
assert_equal(insufficient_reason, 'CRITICAL_SINGLE_TARGET_PRESERVED', 'single critical recipient must keep single-target protection')

local scheduler_file = assert(io.open('./unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(scheduler_source:find('local critical_injured_ids = {}', 1, true) ~= nil, 'scheduler must track critical injured recipients separately')
assert_true(scheduler_source:find('injured_recipient_ids = critical_injured_ids', 1, true) ~= nil, 'scheduler must plan emergency Curaga from critical recipients')
assert_true(scheduler_source:find('minimum_targets = 2', 1, true) ~= nil, 'critical multicure must trigger at two recipients independent of normal Curaga minimum')
assert_true(scheduler_source:find('candidate.critical_multicure = true', 1, true) ~= nil, 'scheduler must mark emergency Curaga candidates for admission override')

assert_equal(healing.mechanics.curing_waltz_ranges['Curing Waltz'], 20.6, 'Curing Waltz I range')
assert_equal(healing.mechanics.curing_waltz_ranges['Curing Waltz II'], 20.6, 'Curing Waltz II range')
assert_equal(healing.mechanics.curing_waltz_ranges['Curing Waltz III'], 20.7, 'Curing Waltz III range')
assert_equal(healing.mechanics.curing_waltz_ranges['Curing Waltz IV'], 20.7, 'Curing Waltz IV range')
assert_equal(healing.mechanics.curing_waltz_ranges['Curing Waltz V'], 20.7, 'Curing Waltz V range')
assert_equal(healing.mechanics.healing_waltz_range, 24.9, 'Healing Waltz range')

assert_true(healing.healing_waltz_supports('curse', 'Cursna'), 'Healing Waltz should support Curse')
assert_true(healing.healing_waltz_supports('paralysis', 'Paralyna'), 'Healing Waltz should support Paralysis')
assert_true(healing.healing_waltz_supports('virus', 'Viruna'), 'Healing Waltz should support Disease/Virus')
assert_true(healing.healing_waltz_supports('attack_down', 'Erase'), 'Healing Waltz should support compatible Erase effects')
assert_true(not healing.healing_waltz_supports('amnesia', 'Erase'), 'Healing Waltz must not support Amnesia')
assert_true(not healing.healing_waltz_supports('doom', 'Cursna'), 'Healing Waltz must not support Doom')
assert_true(not healing.healing_waltz_supports('helix', 'Erase'), 'Healing Waltz must not support Helix effects')
assert_true(not healing.healing_waltz_supports('petrification', 'Stona'), 'Healing Waltz must not support Petrification')
assert_true(not healing.healing_waltz_supports('elegy', 'Erase'), 'Healing Waltz must not support songs')
assert_true(not healing.healing_waltz_supports('stun', 'Erase'), 'Healing Waltz must not support Stun')
assert_true(not healing.healing_waltz_supports('mute', 'Erase'), 'Healing Waltz must not support Mute')
assert_true(not healing.healing_waltz_supports('terror', 'Erase'), 'Healing Waltz must not support Terror')
assert_true(not healing.healing_waltz_supports('kaustra', 'Erase'), 'Healing Waltz must not support Kaustra')

local buffs = { [99] = { en = 'Amnesia' }, [100] = { en = 'Silence' } }
local ja = { tp_cost = 350, recast_id = 7, range = 12 }
local ready = healing.evaluate_waltz_resource_gate({
	action_ready = true, action_kind = 'ja', player_buffs = { 100 }, buff_resources = buffs,
	ja_resource = ja, current_tp = 700, tp_reserve = 300,
})
assert_true(ready.ready, 'Waltz should remain usable while Silenced')
assert_equal(ready.tp_cost, 350, 'Waltz TP cost must come from the JA resource')
local reserve_block = healing.evaluate_waltz_resource_gate({
	action_ready = true, action_kind = 'ja', player_buffs = {}, buff_resources = buffs,
	ja_resource = ja, current_tp = 649, tp_reserve = 300,
})
assert_equal(reserve_block.reason, 'WALTZ_INSUFFICIENT_TP', 'Waltz TP reserve must be honored')
local amnesia_block = healing.evaluate_waltz_resource_gate({
	action_ready = true, action_kind = 'ja', player_buffs = { 99 }, buff_resources = buffs,
	ja_resource = ja, current_tp = 1000, tp_reserve = 0,
})
assert_equal(amnesia_block.reason, 'WALTZ_AMNESIA', 'Waltz must be rejected while Amnesic')
local recast_block = healing.evaluate_waltz_resource_gate({
	action_ready = false, action_reason = 'BLOCK_DEFENSIVE_RECAST', action_kind = 'ja',
	player_buffs = {}, buff_resources = buffs, ja_resource = ja, current_tp = 1000, tp_reserve = 0,
})
assert_equal(recast_block.reason, 'WALTZ_RECAST', 'Waltz recast rejection should be explicit')

io.stdout:write('selftest_defensive_healing: OK\n')
