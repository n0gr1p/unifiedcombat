package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_false(value, message)
	assert_equal(value, false, message)
end

local function assert_contains(source, needle, message)
	if not source:find(needle, 1, true) then
		error(message or ('missing expected text: ' .. tostring(needle)))
	end
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local content = fh:read('*a')
	fh:close()
	return content
end

local scheduler_config = require('uc_scheduler_config')
local camp_puller = require('uc_camp_puller')
local pull_registry = require('uc_camp_pull_registry')

local function pull_config(enabled)
	return {
		enabled = enabled,
		mode = 'camp',
		action = { type = 'spell', name = 'Dia II' },
		targets = { { name = 'Apex Crab', priority = 20 } },
		match_mode = 'exact',
		max_active_mobs = 1,
		replenish_below_hpp = 20,
		leash_yalms = 35.0,
		max_z_delta = 2.0,
		cast_range_ratio = 0.90,
		settle_seconds = 0.40,
		reaction_timeout_seconds = 4.0,
		retry_limit = 2,
		retry_window_seconds = 2.5,
		target_cooldown_seconds = 20.0,
		camp_arrival_yalms = 0.75,
	}
end

local function make_provider(observed)
	return camp_puller.new({
		resolve_camp_anchor = function()
			return { x = 0, y = 0, z = 0 }, 'CAMP_READY'
		end,
		get_friendly_claims = function() return { [100] = true } end,
		ignored = function(config, mob)
			observed.ignore_config = config
			local names = scheduler_config.targeting_ignore_names_from_config(config)
			for _, name in ipairs(names) do
				if tostring(name) == tostring(mob and mob.name or '') then return true end
			end
			return false
		end,
		get_spell_resource = function(name)
			if name == 'Dia II' then return { id = 24, en = 'Dia II', range = 12 } end
			return nil
		end,
		get_ja_resource = function() return nil end,
		action_effective_range = function() return 20.0 end,
		action_ready = function() return true, 'READY', 'spell' end,
		log = function() end,
		action_timeline_log = function() end,
		pull_action_in_flight = function() return false end,
		can_start_journey = function() return true, '' end,
		get_zone_id = function() return 100 end,
		send_ipc_message = function() end,
	})
end

local function make_ctx(canonical_enabled, flat_enabled, ignore_names)
	local mob = {
		id = 300,
		name = 'Apex Crab',
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		status = 0,
		claim_id = 0,
		x = 20,
		y = 0,
		z = 0,
		distance = 400,
	}
	return {
		now = 1.0,
		config = {
			combat = { pulling = pull_config(canonical_enabled) },
			targeting = { target_ignore_names = ignore_names or {} },
		},
		settings = {
			camp_pulling = pull_config(flat_enabled),
			target_ignore_names = { 'Flat Ignore Only' },
		},
		player_present = true,
		player = { id = 10, vitals = { hpp = 100 } },
		me = { id = 10, x = 0, y = 0, z = 0 },
		mob_array = { mob },
		mobs_by_id = { [300] = mob },
		target_id_snapshot = 0,
	}
end

local function test_accessor()
	local cfg = { combat = { pulling = pull_config(true) } }
	assert_true(scheduler_config.combat_pulling_from_config(cfg).enabled,
		'canonical pulling accessor must return config.combat.pulling')
	assert_equal(scheduler_config.combat_pulling_from_config({}), nil,
		'missing canonical pulling subtree must fail closed')
end

local function test_canonical_on_flat_off()
	pull_registry.reset('phase3_pulling_on')
	local observed = {}
	local provider = make_provider(observed)
	local ctx = make_ctx(true, false)
	local acquired = provider.acquire_lane(ctx)
	assert_true(acquired, 'canonical pulling ON + flat OFF must acquire pull lane')
	assert_equal(provider.status_snapshot().state, 'APPROACH',
		'canonical pulling ON must begin a journey')
	assert_true(type(observed.ignore_config) == 'table',
		'candidate ignore callback must receive canonical config')
	assert_true(observed.ignore_config == ctx.config,
		'camp puller must pass ctx.config, not flat settings, into target-ignore evaluation')
end

local function test_canonical_off_flat_on()
	pull_registry.reset('phase3_pulling_off')
	local observed = {}
	local provider = make_provider(observed)
	local ctx = make_ctx(false, true)
	assert_false(provider.acquire_lane(ctx),
		'canonical pulling OFF + flat ON must not acquire pull lane')
	assert_equal(provider.status_snapshot().state, 'IDLE',
		'canonical pulling OFF must remain idle')
	local out = {}
	provider.collect(ctx, out)
	assert_equal(#out, 0, 'canonical pulling OFF + flat ON must not emit pull proposals')
	assert_equal(provider.status_snapshot().reason, 'PULL_DISABLED',
		'canonical pulling disable reason mismatch')
end

local function test_canonical_ignore()
	pull_registry.reset('phase3_pulling_ignore')
	local observed = {}
	local provider = make_provider(observed)
	local ctx = make_ctx(true, false, { 'Apex Crab' })
	assert_false(provider.acquire_lane(ctx),
		'canonical target-ignore must prevent camp-pull candidate acquisition')
	assert_equal(provider.status_snapshot().state, 'IDLE',
		'ignored candidate must leave camp puller idle')
	assert_true(observed.ignore_config == ctx.config,
		'canonical target-ignore evaluation must receive ctx.config')
end

local function test_static_wiring()
	local puller = read_all('uc_camp_puller.lua')
	local scheduler = read_all('unified_scheduler.lua')
	local follow = read_all('uc_party_follow.lua')
	local pathing = read_all('uc_pathing.lua')

	assert_contains(puller, 'scheduler_config.combat_pulling_from_config(ctx.config)',
		'camp-puller provider must source configuration from ctx.config')
	assert_contains(puller, 'ignored(ctx.config, mob)',
		'camp-puller initial candidate ignore evaluation must use canonical config')
	assert_contains(puller, 'ignored(ctx.config, candidate)',
		'camp-puller active candidate revalidation must use canonical config')
	assert_contains(scheduler, "local root = require('uc_scheduler_context_utils').get_config()",
		'scheduler camp-pulling helper must load canonical config')
	assert_contains(scheduler, 'uc_scheduler_config.combat_pulling_from_config(root)',
		'scheduler camp-pulling helper must select canonical combat.pulling')
	assert_contains(scheduler, 'uc_scheduler_config.combat_pulling_from_config(ctx.config)',
		'camp-puller dispatch must re-read canonical pull config')
	assert_contains(follow, "uc_active_config.get_path('config.combat.pulling')",
		'party-follow movement suppression must read canonical pulling config')
	assert_contains(pathing, "uc_active_config.get_path('config.combat.pulling')",
		'pathing movement suppression must read canonical pulling config')
end

local previous_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)
local ok, err = pcall(function()
	test_accessor()
	test_canonical_on_flat_off()
	test_canonical_off_flat_on()
	test_canonical_ignore()
	test_static_wiring()
	io.stdout:write('selftest_phase3_pulling_authority: OK (camp-pulling config + ignore + movement ownership)\n')
end)
rawset(_G, 'Start_Engine', previous_engine)
pull_registry.reset('phase3_pulling_complete')
if not ok then error(err, 0) end
