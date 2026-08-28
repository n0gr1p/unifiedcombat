package.path = package.path .. ';./?.lua'

local policy = require('uc_camp_puller_policy')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(
			message or 'values differ',
			tostring(expected),
			tostring(actual)
		))
	end
end

local config = {
	targets = {
		{ name = 'Apex Crab', priority = 20 },
		{ name = 'Apex Pugil', priority = 10 },
	},
	match_mode = 'exact',
	max_active_mobs = 1,
	replenish_below_hpp = 20,
	leash_yalms = 35.0,
	max_z_delta = 2.0,
}

local tracked_active_ids = {}
local pull_registry = {
	quota_eligible = function(mob)
		return tracked_active_ids[tonumber(mob and mob.id) or 0] == true
	end,
}

local demanded, demand = policy.pull_demand(config, {}, { [100] = true }, pull_registry)
assert_equal(demanded, true, 'empty quota should demand a pull')
assert_equal(demand.active_count, 0, 'empty quota active count mismatch')

demanded, demand = policy.pull_demand(config, {
	{
		id = 1,
		valid_target = true,
		spawn_type = 16,
		hpp = 80,
		claim_id = 100,
	},
}, { [100] = true }, pull_registry)
assert_equal(demanded, false, 'full healthy quota must not demand a pull')

demanded = policy.pull_demand(config, {
	{
		id = 1,
		valid_target = true,
		spawn_type = 16,
		hpp = 20,
		claim_id = 100,
	},
}, { [100] = true }, pull_registry)
assert_equal(demanded, true, 'low-HPP active mob should permit early replenish')

tracked_active_ids[2] = true
demanded, demand = policy.pull_demand(config, {
	{
		id = 2,
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		status = 1,
		claim_id = 0,
	},
}, { [100] = true }, pull_registry)
assert_equal(demanded, false, 'tracked unclaimed hostile mob must occupy a quota slot')
assert_equal(demand.active_count, 1, 'tracked unclaimed hostile active count mismatch')

local ctx = {
	now = 10,
	me = {
		z = 0,
	},
	mob_array = {
		{
			id = 300,
			name = 'Apex Pugil',
			valid_target = true,
			spawn_type = 16,
			hpp = 100,
			status = 0,
			claim_id = 0,
			x = 3,
			y = 4,
			z = 0,
		},
		{
			id = 302,
			name = 'Apex Crab',
			valid_target = true,
			spawn_type = 16,
			hpp = 100,
			status = 0,
			claim_id = 0,
			x = 10,
			y = 0,
			z = 0,
		},
		{
			id = 301,
			name = 'Apex Crab',
			valid_target = true,
			spawn_type = 16,
			hpp = 100,
			status = 0,
			claim_id = 0,
			x = 10,
			y = 0,
			z = 0,
		},
	},
}

local candidate = policy.select_candidate(
	config,
	ctx,
	{ x = 0, y = 0 },
	{},
	{},
	function()
		return false
	end
)
assert_equal(candidate.id, 301, 'priority then distance then id ordering mismatch')

local cooldown_candidate = policy.select_candidate(
	config,
	ctx,
	{ x = 0, y = 0 },
	{},
	{ [301] = 20 },
	function()
		return false
	end
)
assert_equal(cooldown_candidate.id, 302, 'target cooldown filtering mismatch')

local sleeping_threat = {
	id = 303,
	name = 'Apex Pugil',
	valid_target = true,
	spawn_type = 16,
	hpp = 100,
	status = 1,
	claim_id = 0,
	target_index = 0,
	target = 0,
	x = 12,
	y = 0,
	z = 0,
}
_G.UC_MOB_LAST_ACTION_TARGETS = {
	[303] = {
		target_id = 100,
		at = 1,
		category = 'mob_tp_finish',
	},
}
local threat_ctx = {
	now = 10,
	me = { z = 0 },
	mob_array = {
		ctx.mob_array[2],
		sleeping_threat,
	},
}
local threat_candidate, threat_reason = policy.select_candidate(
	config,
	threat_ctx,
	{ x = 0, y = 0 },
	{ [100] = true },
	{},
	function()
		return false
	end
)
assert_equal(threat_candidate.id, 303, 'remembered party threat must outrank an ordinary idle pull candidate')
assert_equal(threat_candidate.threat_recovery, true, 'remembered party threat must be marked as threat recovery')
assert_equal(threat_reason, 'PULL_THREAT_RECOVERY_SELECTED', 'remembered party threat selection reason mismatch')

_G.UC_MOB_LAST_ACTION_TARGETS[303].target_id = 999
threat_candidate = policy.select_candidate(
	config,
	threat_ctx,
	{ x = 0, y = 0 },
	{ [100] = true },
	{},
	function()
		return false
	end
)
assert_equal(threat_candidate.id, 302, 'new non-friendly action evidence must invalidate remembered party threat recovery')

config.match_mode = 'substring'
config.targets = {
	{ name = 'Crab', priority = 1 },
}
candidate = policy.select_candidate(
	config,
	ctx,
	{ x = 0, y = 0 },
	{},
	{},
	function()
		return false
	end
)
assert_equal(candidate.id, 301, 'substring target matching mismatch')

_G.UC_MOB_LAST_ACTION_TARGETS = nil
io.stdout:write('selftest_camp_puller_policy: OK\n')
