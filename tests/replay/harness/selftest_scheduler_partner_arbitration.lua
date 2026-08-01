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

local scheduler_source = read_file('unified_scheduler.lua')
local arbitration_start = assert(scheduler_source:find('function scheduler.try_partner_tiebreak(settings)', 1, true))
local arbitration_call = assert(scheduler_source:find('scheduler.try_partner_tiebreak(s)', 1, true))
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
