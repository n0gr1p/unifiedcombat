local runtime_factory = require('uc_generic_formation_runtime')

local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_false(condition, message)
	if condition ~= false then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local proposal = nil
local intents = {}
local runs = {}
local dispatcher = {
	dispatch_intent = function(intent, deps)
		intents[#intents + 1] = intent
		if intent.kind == 'run' then
			deps.run(intent.run_x, intent.run_y)
		elseif intent.kind == 'run_stop' then
			deps.run(false)
		else
			error('unexpected movement intent: ' .. tostring(intent.kind))
		end
		return { ok = true, executed = true, reason = 'executed' }
	end,
}
local runtime = runtime_factory.build({
	solver = {
		evaluate = function()
			return proposal
		end,
	},
	dispatcher = dispatcher,
	run = function(...)
		runs[#runs + 1] = { count = select('#', ...), ... }
	end,
	source_prefix = 'generic_formation_test',
})

local ctx = {
	config = { enabled = true },
	me = { x = 0, y = 0 },
}

proposal = {
	action = 'move',
	reason = 'FORMATION_REPOSITION',
	goal = { x = 5, y = 0 },
}
local acted, reason, owns = runtime.run_tick(ctx)
assert_true(acted, 'generic formation move must act')
assert_equal(reason, 'FORMATION_REPOSITION', 'generic formation move reason mismatch')
assert_true(owns, 'enabled generic formation must own movement')
assert_equal(#intents, 1, 'generic formation move intent count mismatch')
assert_equal(intents[1].kind, 'run', 'generic formation move intent kind mismatch')
assert_equal(intents[1].source, 'generic_formation_test:run_heading', 'generic formation dispatcher source mismatch')
assert_equal(runs[1].count, 1, 'generic formation heading run arity mismatch')

proposal = {
	action = 'hold',
	reason = 'FORMATION_POSITION_VALID',
}
acted, reason, owns = runtime.run_tick(ctx)
assert_true(acted, 'hold after movement must stop active run')
assert_equal(reason, 'FORMATION_POSITION_VALID', 'generic formation hold reason mismatch')
assert_true(owns, 'enabled hold must retain formation ownership')
assert_equal(intents[2].kind, 'run_stop', 'generic formation stop intent kind mismatch')
assert_equal(runs[2][1], false, 'generic formation stop must call run(false)')

proposal = {
	action = 'error',
	reason = 'FORMATION_UNSATISFIED',
}
acted, reason, owns = runtime.run_tick(ctx)
assert_false(acted, 'inactive unsatisfied formation must not dispatch')
assert_equal(reason, 'FORMATION_UNSATISFIED', 'generic formation error reason mismatch')
assert_true(owns, 'enabled unsatisfied formation must own movement')
assert_equal(#intents, 2, 'unsatisfied formation must not guess movement')

ctx.config.enabled = false
acted, reason, owns = runtime.run_tick(ctx)
assert_false(acted, 'disabled inactive formation must not dispatch')
assert_equal(reason, 'FORMATION_DISABLED', 'disabled formation reason mismatch')
assert_false(owns, 'disabled inactive formation must not own movement')

local status = runtime.status()
assert_false(status.enabled, 'runtime status enabled mismatch')
assert_false(status.moving, 'runtime status moving mismatch')
assert_equal(status.reason, 'FORMATION_DISABLED', 'runtime status reason mismatch')

runtime.reset('test_complete')
assert_equal(runtime.status().reason, 'test_complete', 'runtime reset reason mismatch')

io.stdout:write('selftest_generic_formation_runtime: OK\n')
