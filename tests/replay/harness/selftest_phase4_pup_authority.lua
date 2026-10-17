package.path = './?.lua;' .. package.path

local runtime = require('uc_pup_runtime')
local adapter_module = require('uc_pup_pet_combat_adapter')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
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
		error(message or ('missing text: ' .. needle))
	end
end

local function assert_not_contains(source, needle, message)
	if source:find(needle, 1, true) then
		error(message or ('unexpected text: ' .. needle))
	end
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local source = fh:read('*a')
	fh:close()
	return source
end

local function pup_config(opts)
	opts = opts or {}
	local enabled = opts.enabled
	if enabled == nil then enabled = true end
	local activate = opts.activate
	if activate == nil then activate = true end
	local deploy = opts.deploy
	if deploy == nil then deploy = true end
	local maneuvers_enabled = opts.maneuvers_enabled
	if maneuvers_enabled == nil then maneuvers_enabled = true end
	return {
		enabled = enabled,
		activate_if_missing = activate,
		deploy_on_combat_start = deploy,
		maneuvers = {
			enabled = maneuvers_enabled,
			pattern = opts.pattern or { 'Fire Maneuver', 'Fire Maneuver', 'Light Maneuver' },
			post_activate_quiet_seconds = opts.quiet or 120,
			safe_burden_ceiling = opts.ceiling or 30,
		},
	}
end

local function base_ctx(canonical, compatibility, pet_present)
	return {
		now = 10,
		config = {
			profile = { main_job = 'PUP' },
			puppetmaster = canonical,
		},
		settings = {
			profile = { main_job = 'PUP' },
			puppetmaster = compatibility,
		},
		player_present = true,
		player_id = 100,
		player_name = 'Tester',
		player = {
			id = 100,
			name = 'Tester',
			main_job = 'PUP',
			buffs = {},
		},
		pet_present = pet_present == true,
		pet_id = pet_present == true and 200 or 0,
		pet_name = pet_present == true and 'Automaton' or '',
		pet_status = 0,
		pet_inferred_target_id = 0,
		ability_recasts_present = true,
		ability_recasts = {
			[runtime.RECAST_ACTIVATE] = 0,
			[runtime.RECAST_DEPLOY] = 0,
			[runtime.RECAST_MANEUVER] = 0,
		},
		target_valid = true,
		target_id = 300,
		target_hpp = 100,
		combat_generation = 4,
	}
end

local function make_adapter()
	return adapter_module.new({
		get_ja_resource = function(name)
			if name == 'Activate' then return { range = 0 } end
			if name == 'Deploy' then return { range = 12 } end
			return nil
		end,
		action_effective_range = function(raw)
			return tonumber(raw) or 0
		end,
	})
end

local function test_enablement_authority()
	local adapter = make_adapter()
	local canonical = pup_config({ enabled = false })
	local compatibility = pup_config({ enabled = true })
	local ctx = base_ctx(canonical, compatibility, false)
	local snapshot = adapter.snapshot(ctx)
	assert_false(snapshot.enabled, 'canonical PUP disabled must beat compatibility enabled state')
	assert_equal(adapter.maintenance(snapshot, ctx), nil, 'disabled canonical PUP must not maintain')

	adapter = make_adapter()
	canonical = pup_config({ enabled = true })
	compatibility = pup_config({ enabled = false })
	ctx = base_ctx(canonical, compatibility, false)
	snapshot = adapter.snapshot(ctx)
	assert_true(snapshot.enabled, 'canonical PUP enabled must beat compatibility disabled state')
end

local function test_activate_authority()
	local adapter = make_adapter()
	local canonical = pup_config({ activate = false })
	local compatibility = pup_config({ activate = true })
	local ctx = base_ctx(canonical, compatibility, false)
	local snapshot = adapter.snapshot(ctx)
	assert_equal(adapter.maintenance(snapshot, ctx), nil, 'canonical Activate OFF must beat compatibility ON')

	adapter = make_adapter()
	canonical = pup_config({ activate = true })
	compatibility = pup_config({ activate = false })
	ctx = base_ctx(canonical, compatibility, false)
	snapshot = adapter.snapshot(ctx)
	local action = adapter.maintenance(snapshot, ctx)
	assert_true(type(action) == 'table', 'canonical Activate ON must beat compatibility OFF')
	assert_equal(action.action_name, 'Activate', 'canonical Activate action')
end

local function test_deploy_authority()
	local adapter = make_adapter()
	local canonical = pup_config({ deploy = false, maneuvers_enabled = false })
	local compatibility = pup_config({ deploy = true, maneuvers_enabled = true })
	local ctx = base_ctx(canonical, compatibility, true)
	local snapshot = adapter.snapshot(ctx)
	assert_equal(adapter.engagement(snapshot, ctx), nil, 'canonical Deploy OFF must beat compatibility ON')

	adapter = make_adapter()
	canonical = pup_config({ deploy = true, maneuvers_enabled = false })
	compatibility = pup_config({ deploy = false, maneuvers_enabled = true })
	ctx = base_ctx(canonical, compatibility, true)
	snapshot = adapter.snapshot(ctx)
	local action = adapter.engagement(snapshot, ctx)
	assert_true(type(action) == 'table', 'canonical Deploy ON must beat compatibility OFF')
	assert_equal(action.action_name, 'Deploy', 'canonical Deploy action')
end

local function test_maneuver_policy_authority()
	local adapter = make_adapter()
	local canonical = pup_config({
		maneuvers_enabled = false,
		pattern = { 'Light Maneuver' },
		quiet = 7,
		ceiling = 31,
	})
	local compatibility = pup_config({
		maneuvers_enabled = true,
		pattern = { 'Fire Maneuver' },
		quiet = 120,
		ceiling = 0,
	})
	local ctx = base_ctx(canonical, compatibility, true)
	local snapshot = adapter.snapshot(ctx)
	assert_false(snapshot.config.maneuvers.enabled, 'canonical Maneuver enablement must beat compatibility state')
	assert_equal(snapshot.config.maneuvers.pattern[1], 'Light Maneuver', 'canonical Maneuver pattern must beat compatibility pattern')
	assert_equal(snapshot.config.maneuvers.post_activate_quiet_seconds, 7, 'canonical recovery quiet time')
	assert_equal(snapshot.config.maneuvers.safe_burden_ceiling, 31, 'canonical burden ceiling')
	assert_equal(_G.UC_PUP_AUTOMATION_STATUS.next_maneuver, 'Light Maneuver', 'status must reflect canonical Maneuver pattern')
	assert_equal(_G.UC_PUP_AUTOMATION_STATUS.safe_burden_ceiling, 31, 'status must reflect canonical burden ceiling')
	assert_equal(_G.UC_PUP_AUTOMATION_STATUS.quiet_remaining, 7, 'initial observed-pet hold must use canonical quiet time')
	assert_equal(adapter.maintenance(snapshot, ctx), nil, 'canonical Maneuver OFF must suppress maintenance despite compatibility ON')
end

local function test_runtime_observation_uses_canonical_fallback()
	local state = runtime.new_state()
	local canonical = pup_config({ quiet = 9, ceiling = 29 })
	local compatibility = pup_config({ quiet = 120, ceiling = 0 })
	local ctx = base_ctx(canonical, compatibility, true)
	runtime.observe(state, ctx, ctx.now)
	assert_equal(state.quiet_until - ctx.now, 9, 'runtime.observe fallback must use canonical PUP config')
end

local function test_static_boundary()
	local runtime_source = read_all('uc_pup_runtime.lua')
	local adapter_source = read_all('uc_pup_pet_combat_adapter.lua')

	assert_not_contains(runtime_source, 'ctx.settings', 'PUP runtime must not consume compatibility scheduler settings')
	assert_not_contains(adapter_source, 'ctx.settings', 'PUP pet adapter must not consume compatibility scheduler settings')
	assert_contains(runtime_source, 'function M.config_from_config(config)', 'PUP runtime canonical config reader')
	assert_contains(runtime_source, 'M.config_from_config(ctx.config)', 'PUP runtime observation fallback must use canonical config')
	assert_contains(adapter_source, 'runtime.config_from_config(ctx.config)', 'PUP pet adapter must use canonical config')
	assert_contains(runtime_source, 'Compatibility parser for legacy/direct callers and migration tests only.',
		'PUP compatibility parser must be explicitly bounded')
end

test_enablement_authority()
test_activate_authority()
test_deploy_authority()
test_maneuver_policy_authority()
test_runtime_observation_uses_canonical_fallback()
test_static_boundary()

print('selftest_phase4_pup_authority: OK (automation + pet combat)')
