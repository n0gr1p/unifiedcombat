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

local demanded, demand = policy.pull_demand(config, {}, { [100] = true })
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
}, { [100] = true })
assert_equal(demanded, false, 'full healthy quota must not demand a pull')

demanded = policy.pull_demand(config, {
	{
		id = 1,
		valid_target = true,
		spawn_type = 16,
		hpp = 20,
		claim_id = 100,
	},
}, { [100] = true })
assert_equal(demanded, true, 'low-HPP active mob should permit early replenish')

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

io.stdout:write('selftest_camp_puller_policy: OK\n')
