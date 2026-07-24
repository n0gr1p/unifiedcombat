local dispatcher = require('uc_scheduler_dispatcher')
local movement_dispatcher = require('uc_movement_dispatcher')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_errors(fn, expected_text)
	local ok, err = pcall(fn)
	if ok then
		error('expected error containing: ' .. expected_text)
	end
	if not tostring(err):find(expected_text, 1, true) then
		error('unexpected error: ' .. tostring(err))
	end
end

local function read(path)
	local file = assert(io.open(path, 'rb'))
	local text = file:read('*a')
	file:close()
	return text
end

local function main()
	local run_calls = {}
	local turn_calls = {}
	local dispatched_intents = {}
	local recording_dispatcher = {
		dispatch_intent = function(intent, deps)
			dispatched_intents[#dispatched_intents + 1] = intent
			return dispatcher.dispatch_intent(intent, deps)
		end,
	}
	local executor = movement_dispatcher.build({
		dispatcher = recording_dispatcher,
		run = function(...)
			run_calls[#run_calls + 1] = { count = select('#', ...), ... }
		end,
		turn = function(heading)
			turn_calls[#turn_calls + 1] = heading
		end,
		source_prefix = 'phase4_test',
	})

	local result = executor.run_vector(0.25, -0.75, { reason = 'vector_test' })
	assert_true(result.ok and result.executed, 'vector dispatch result')
	assert_equal(dispatched_intents[1].source, 'phase4_test:run_vector', 'vector source')
	assert_equal(dispatched_intents[1].meta.reason, 'vector_test', 'vector metadata')
	assert_equal(run_calls[1].count, 2, 'vector run arity')
	assert_equal(run_calls[1][1], 0.25, 'vector x')
	assert_equal(run_calls[1][2], -0.75, 'vector y')

	result = executor.run_heading(1.25, { reason = 'heading_test' })
	assert_equal(dispatched_intents[2].source, 'phase4_test:run_heading', 'heading source')
	assert_equal(dispatched_intents[2].meta.heading, 1.25, 'heading metadata')
	assert_equal(dispatched_intents[2].meta.reason, 'heading_test', 'heading reason metadata')
	assert_equal(run_calls[2].count, 1, 'heading run arity')
	assert_equal(run_calls[2][1], 1.25, 'heading run value')

	result = executor.stop({ reason = 'stop_test' })
	assert_equal(dispatched_intents[3].source, 'phase4_test:stop', 'stop source')
	assert_equal(run_calls[3].count, 1, 'stop run arity')
	assert_equal(run_calls[3][1], false, 'stop run value')

	executor.run_forward()
	assert_equal(run_calls[4].count, 0, 'forward run arity')

	executor.turn(2.5)
	assert_equal(turn_calls[1], 2.5, 'turn value')

	local mover_calls = {}
	local mover = {
		move_towards = function(_, target_id)
			mover_calls[#mover_calls + 1] = 'towards:' .. tostring(target_id)
		end,
		move_away_from = function(_, target_id)
			mover_calls[#mover_calls + 1] = 'away:' .. tostring(target_id)
		end,
	}
	executor.move_towards(mover, 1001)
	executor.move_away_from(mover, 1002)
	assert_equal(mover_calls[1], 'towards:1001', 'move-towards dispatch')
	assert_equal(mover_calls[2], 'away:1002', 'move-away dispatch')

	assert_errors(function()
		movement_dispatcher.build({
			dispatcher = dispatcher,
			run = function()
			end,
			source_prefix = '',
		})
	end, 'opts.source_prefix must be a non-empty string')
	assert_errors(function()
		executor.run_vector(nil, 1)
	end, 'missing_run_x')
	assert_errors(function()
		executor.run_heading('not-a-heading')
	end, 'heading must be numeric')

	local migrated_files = {
		'UnifiedCombat.lua',
		'uc_lilith_easy_formation_runtime.lua',
		'uc_nyzul_runtime.lua',
		'uc_party_follow.lua',
		'uc_pathing.lua',
	}
	for i = 1, #migrated_files do
		local source = read(migrated_files[i])
		assert_true(source:find("require('uc_movement_dispatcher').build({", 1, true) ~= nil,
			migrated_files[i] .. ' must build the shared movement dispatcher')
		assert_true(source:find('windower.ffxi.run(', 1, true) == nil,
			migrated_files[i] .. ' must not directly execute movement')
	end

	local scheduler_facade_source = read('uc_scheduler_movement_facade.lua')
	assert_true(scheduler_facade_source:find("require('uc_movement_dispatcher').build({", 1, true) ~= nil,
		'scheduler movement facade must delegate to the shared movement dispatcher')
	assert_true(read('unified_combat_core.lua'):find('core.legacy_movement_executor', 1, true) ~= nil,
		'legacy core movement must remain explicit for Phase 5 cutover')

	io.stdout:write('selftest_movement_dispatcher_phase4: OK\n')
end

main()
