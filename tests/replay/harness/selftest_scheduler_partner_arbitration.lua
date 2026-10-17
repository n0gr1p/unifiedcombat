local arbitration = dofile('uc_scheduler_partner_arbitration.lua')

local function read_file(path)
	local handle = assert(io.open(path, 'rb'))
	local contents = handle:read('*a')
	handle:close()
	return contents
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function base_input()
	return {
		partner_enabled = true,
		autotarget_enabled = true,
		my_id = 200,
		player_status = 1,
		current_target = { id = 900, valid_target = true, spawn_type = 16, hpp = 80 },
		partners = {
			{ id = 100, status = 1, target_id = 900, target_live = true },
		},
		mobs = {},
		claims_set = { [100] = true, [200] = true },
		blocked_mob_ids = {},
	}
end

local input = base_input()
local decision = arbitration.decide(input)
assert_equal(decision.action, 'disengage', 'higher-id loser must disengage when no alternate mob exists')
assert_equal(decision.winner_id, 100, 'lower-id partner must win shared mob')
assert_equal(decision.from_target_id, 900, 'disengage must identify shared mob')

input = base_input()
input.mobs = {
	{ id = 901, claim_id = 200, valid_target = true, spawn_type = 16, hpp = 90, distance = 16 },
	{ id = 902, claim_id = 100, valid_target = true, spawn_type = 16, hpp = 75, distance = 9 },
}
decision = arbitration.decide(input)
assert_equal(decision.action, 'switch', 'higher-id loser should switch when an eligible mob exists')
assert_equal(decision.target_id, 902, 'nearest eligible mob should be selected')

input = base_input()
input.autotarget_enabled = false
input.mobs = {
	{ id = 902, claim_id = 100, valid_target = true, spawn_type = 16, hpp = 75, distance = 9 },
}
decision = arbitration.decide(input)
assert_equal(decision.action, 'disengage', 'autotarget off must still pull loser off shared mob')

input = base_input()
input.my_id = 50
decision = arbitration.decide(input)
assert_equal(decision, nil, 'lower-id player must retain shared mob')

input = base_input()
input.partners[1].status = 0
decision = arbitration.decide(input)
assert_equal(decision, nil, 'idle partner target selection must not trigger arbitration')

input = base_input()
input.mobs = {
	{ id = 902, claim_id = 100, valid_target = true, spawn_type = 16, hpp = 75, distance = 9 },
	{ id = 903, claim_id = 100, valid_target = true, spawn_type = 16, hpp = 75, distance = 12 },
}
input.partners[#input.partners + 1] = { id = 300, status = 1, target_id = 902, target_live = true }
decision = arbitration.decide(input)
assert_equal(decision.action, 'switch', 'occupied alternate must not prevent switching to a free mob')
assert_equal(decision.target_id, 903, 'partner-occupied alternate mob must be excluded')

-- The scheduler executes this same gate for both partner-target set building
-- and revalidation/arbitration. Opposed legacy flats cannot resurrect either.
local context_utils = require('uc_scheduler_context_utils')
local canonical = { follow = { partner = { enabled = false } } }
assert_equal(context_utils.partner_enabled({ partner = true }, canonical), false,
    'canonical partner OFF must defeat stale flat ON')
canonical.follow.partner.enabled = true
assert_equal(context_utils.partner_enabled({ partner = false }, canonical), true,
    'canonical partner ON must defeat stale flat OFF')
canonical.follow.partner = nil
assert_equal(context_utils.partner_enabled({ partner = true }, canonical), false,
    'missing canonical partner leaf must not resurrect stale flat ON')
canonical.follow = nil
assert_equal(context_utils.partner_enabled({ partner = true }, canonical), false,
    'missing canonical follow domain must not resurrect stale flat ON')
assert_equal(context_utils.partner_enabled({ partner = 'on' }, nil), true,
    'genuine no-profile partner settings retain legacy toggle support')
assert_equal(context_utils.partner_enabled({ partner = false }, nil), false,
    'no-profile explicit disabled partner remains disabled')

-- Autotarget is a separate arbitration decision: canonical OFF allows the
-- safety disengage but never resurrects a stale flat target switch.
local flat_autotarget_on = { autotarget = true }
local flat_autotarget_off = { autotarget = false }
local canonical_target_off = { combat = { autotarget = false } }
local canonical_target_on = { combat = { autotarget = true } }
local autotarget_policy = context_utils.partner_autotarget_enabled
assert_equal(autotarget_policy(flat_autotarget_on, canonical_target_off), false,
    'canonical autotarget OFF must defeat stale flat ON')
assert_equal(autotarget_policy(flat_autotarget_off, canonical_target_on), true,
    'canonical autotarget ON must defeat stale flat OFF')
assert_equal(autotarget_policy(flat_autotarget_on, { combat = {} }), false,
    'missing canonical autotarget must not revive flat ON')
assert_equal(autotarget_policy(flat_autotarget_on, {}), false,
    'missing canonical combat domain must not revive flat ON')
assert_equal(autotarget_policy(flat_autotarget_on, nil), true,
    'genuine no-config autotarget ON remains compatible')
assert_equal(autotarget_policy(flat_autotarget_off, nil), false,
    'genuine no-config autotarget OFF remains disabled')
input = base_input()
input.mobs = {
    { id = 902, claim_id = 100, valid_target = true, spawn_type = 16, hpp = 75, distance = 9 },
}
input.autotarget_enabled = autotarget_policy(flat_autotarget_on, canonical_target_off)
decision = arbitration.decide(input)
assert_equal(decision.action, 'disengage',
    'canonical autotarget OFF must retain safe disengage instead of switching')
input.autotarget_enabled = autotarget_policy(flat_autotarget_off, canonical_target_on)
decision = arbitration.decide(input)
assert_equal(decision.action, 'switch', 'canonical autotarget ON permits normal reassignment')
assert_equal(decision.target_id, 902, 'canonical autotarget ON picks the alternate target')

local scheduler_source = read_file('unified_scheduler.lua')
assert_equal(scheduler_source:find(
    "autotarget_enabled = require('uc_scheduler_context_utils').partner_autotarget_enabled(settings, config)",
    1, true) ~= nil, true,
    'partner arbitration must consume canonical autotarget without and/or false fallthrough')
assert_equal(scheduler_source:find(
    "and uc_scheduler_config.combat_autotarget_from_config(config) or uc_scheduler_config.combat_autotarget(settings)",
    1, true), nil,
    'stale flat autotarget must never override canonical false at arbitration')
local policy_reader = "require('uc_scheduler_context_utils').partner_enabled(settings, config)"
local _, reader_calls = scheduler_source:gsub(policy_reader:gsub('([^%w])', '%%%1'), '')
assert_equal(reader_calls, 2, 'both partner target set and arbitration must share canonical authority')
assert_equal(scheduler_source:find('or bool_setting(settings and settings.partner, false)', 1, true), nil,
    'canonical partner=false must not fall through to flat partner=true')
local arbitration_start = assert(scheduler_source:find('function scheduler.try_partner_tiebreak(settings, config)', 1, true))
local arbitration_call = assert(scheduler_source:find('scheduler.try_partner_tiebreak(s, get_tick_ctx().config)', 1, true))
local reaction_lock_call = assert(scheduler_source:find('scheduler.refresh_reaction_lock()', arbitration_call, true))
assert_equal(arbitration_call < reaction_lock_call, true, 'partner arbitration must run before normal scheduler locks')
assert_equal(scheduler_source:find("kind = 'switch_target'", arbitration_start, true) ~= nil, true,
	'scheduler arbitration must dispatch target switch intent')
assert_equal(scheduler_source:find('switch_target = uc_attack.switch_target', arbitration_start, true) ~= nil, true,
	'scheduler arbitration must inject target switch executor')
assert_equal(scheduler_source:find("kind = 'disengage'", arbitration_start, true) ~= nil, true,
	'scheduler arbitration must dispatch disengage intent')
assert_equal(scheduler_source:find('disengage = uc_attack.disengage', arbitration_start, true) ~= nil, true,
	'scheduler arbitration must inject disengage executor')

print('selftest_scheduler_partner_arbitration: OK')
