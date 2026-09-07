local fh = assert(io.open('unified_scheduler.lua', 'r'))
local source = fh:read('*a')
fh:close()

local function extract(first, next_marker)
	local start_at = assert(source:find(first, 1, true), first)
	local end_at = assert(source:find(next_marker, start_at + #first, true), next_marker)
	return source:sub(start_at, end_at - 1)
end

local function new_case()
	local env = setmetatable({}, { __index = _G })
	env._G = env
	local state = { now = 100, status = 0, moving = true, stops = 0, sends = 0, events = {} }
	local selected = {
		provider = 'defensive_internal', action_type = 'spell', action_name = 'Refresh',
		target_name = 'Niightsiide', target_id = 560699, legacy_command = '/ma "Refresh" <me>',
	}
	env.scheduler = {
		phase1 = { last_selected = selected, last_plan = {} },
		action_timeline_log = function(event, fields)
			table.insert(state.events, { event = event, fields = fields })
		end,
		validate_cure_target = function() return true end,
	}
	env.now_s = function() return state.now end
	env.windower = { ffxi = {
		get_player = function() return { status = state.status } end,
		run = function() state.stops = state.stops + 1 end,
	} }
	env.domain_ownership = { is_enabled = function(domain) return domain == 'defensive' end }
	env.action_dispatch_blocked = function() return false end
	env.action_ready = function() return true, nil, selected.action_type end
	env.action_state = function() return { last_action_name = 'Barsilencera' } end
	env.require = function(name)
		if name == 'lor/lor_actor' then
			return { Actor = { new = function()
				return { is_moving = function() return state.moving end }
			end } }
		elseif name == 'uc_scheduler_dispatcher' then
			return {}
		elseif name == 'uc_scheduler_run_stop_ownership' then
			return { apply_run_stop_ownership = function(opts)
				assert(opts.intent.kind == 'run_stop')
				opts.run(false)
			end }
		end
		error('unexpected dependency: ' .. name)
	end
	local function load_chunk(code)
		local chunk = assert(loadstring(code))
		setfenv(chunk, env)
		return chunk()
	end
	load_chunk('local CAST_MOVEMENT_SETTLE_SECONDS = 0.1\n' .. extract(
		'function scheduler.apply_cast_movement_hold(reason, at)', 'local function current_zone_id()'))
	load_chunk(extract('function scheduler.defensive_spell_movement_blocked(', 'local function p1_dispatch_defensive_internal('))
	local defensive_sender = load_chunk(extract(
		'local function p1_dispatch_defensive_internal(', 'local function p1_dispatch_defensive_healbot(')
		.. '\nreturn p1_dispatch_defensive_internal')
	env.p1_dispatch_defensive_internal = function()
		state.sends = state.sends + 1
		return true, 'TEST_SENT'
	end
	load_chunk(extract('function scheduler.dispatch_selected_plan(settings)', 'local function try_charm_sleeper_emergency('))
	return env, state, selected, defensive_sender
end

local function assert_no_movement_change(env, state)
	assert(state.stops == 0, 'deferred spell must not stop movement')
	assert(state.sends == 0, 'deferred spell must not dispatch')
	assert(env.UC_MOVEMENT_OWNER == 'follow', 'must preserve follow ownership')
	assert(env.UC_MOVEMENT_MODE == 'FOLLOW', 'must preserve movement mode')
	assert(env.UC_MOVEMENT_LOCK_UNTIL == 99, 'must not extend movement lock')
	assert(env.UC_CAST_MOVEMENT_SETTLE_UNTIL == nil, 'must not start cast settling')
end

-- Both persistent flags and brief timestamp holds must defer before the first stop.
local follow_cases = {
	{ UC_PARTY_FOLLOW_RUN_ACTIVE = true },
	{ UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL = 200 },
	{ UC_PARTY_FOLLOW_NEEDS_CATCHUP = true },
	{ UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = 200 },
}
for _, flags in ipairs(follow_cases) do
	local env, state = new_case()
	env.UC_MOVEMENT_OWNER = 'follow'
	env.UC_MOVEMENT_MODE = 'FOLLOW'
	env.UC_MOVEMENT_LOCK_UNTIL = 99
	for key, value in pairs(flags) do env[key] = value end
	for tick = 1, 20 do
		local blocked, reason = env.scheduler.dispatch_selected_plan({})
		assert(blocked and reason == 'BLOCK_DEFENSIVE_FOLLOW_MOVE_ACTIVE')
		assert_no_movement_change(env, state)
		assert(state.events[#state.events].event == 'DEFENSIVE_FOLLOW_MOVE_BLOCKED')
		assert(state.events[#state.events].fields.action == 'Refresh')
		state.now = state.now + 0.63
	end
end

do
	local env, state = new_case()
	env.UC_PREENGAGE_APPROACH_ACTIVE = true
	local blocked, reason = env.scheduler.dispatch_selected_plan({})
	assert(blocked and reason == 'BLOCK_DEFENSIVE_PREENGAGE_MOVE_ACTIVE')
	assert(state.stops == 0 and state.sends == 0)
end

-- Once caught up, a moving caster still stops and settles before dispatch.
do
	local env, state = new_case()
	env.UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL = 99
	env.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = 99
	local blocked, reason = env.scheduler.dispatch_selected_plan({})
	assert(blocked and reason == 'BLOCK_SCHED_CAST_MOVEMENT_SETTLE')
	assert(state.stops == 1 and state.sends == 0)
	state.moving = false
	state.now = 100.05
	assert(select(2, env.scheduler.dispatch_selected_plan({})) == 'BLOCK_SCHED_CAST_MOVEMENT_SETTLE')
	assert(state.sends == 0)
	state.now = 100.11
	assert(select(2, env.scheduler.dispatch_selected_plan({})) == 'TEST_SENT')
	assert(state.sends == 1 and env.UC_CAST_MOVEMENT_SETTLE_UNTIL == nil)
end

-- Preserve the existing engaged-player exception and non-spell behavior.
do
	local env, state = new_case()
	state.status = 1
	env.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
	assert(select(2, env.scheduler.dispatch_selected_plan({})) == 'BLOCK_SCHED_CAST_MOVEMENT_SETTLE')
	assert(state.stops == 1)
end
do
	local env, state, selected = new_case()
	selected.action_type = 'ja'
	env.UC_PARTY_FOLLOW_RUN_ACTIVE = true
	assert(select(2, env.scheduler.dispatch_selected_plan({})) == 'TEST_SENT')
	assert(state.stops == 0 and state.sends == 1)
end

-- If follow starts after the early check, the real defensive sender rechecks it.
do
	local env, state, selected, defensive_sender = new_case()
	state.moving = false
	env.p1_dispatch_defensive_internal = function(action, settings)
		env.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
		return defensive_sender(action, settings)
	end
	assert(select(2, env.scheduler.dispatch_selected_plan({})) == 'BLOCK_DEFENSIVE_FOLLOW_MOVE_ACTIVE')
	assert(state.stops == 0 and state.sends == 0)
end

-- Other spell providers retain their existing cast-settle behavior.
do
	local env, state, selected = new_case()
	selected.provider = 'maintenance_geo'
	env.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
	assert(select(2, env.scheduler.dispatch_selected_plan({})) == 'BLOCK_SCHED_CAST_MOVEMENT_SETTLE')
	assert(state.stops == 1 and state.sends == 0)
end

io.stdout:write('selftest_defensive_follow_cast_settle: OK\n')
