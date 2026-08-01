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

local proposal = nil
local run_calls = {}
local me = { id = 1, name = 'Tester', x = 0, y = 0 }
local original_active_config = package.loaded.uc_active_config
local original_combat_formation = package.loaded.uc_combat_formation
local original_lilith_easy_encounter = package.loaded.uc_lilith_easy_encounter

package.loaded.uc_active_config = {
	get_path = function()
		return nil
	end,
}
package.loaded.uc_combat_formation = {
	evaluate = function(context)
		assert_equal(context.me.id, me.id, 'formation evaluator player')
		return proposal
	end,
}
package.loaded.uc_lilith_easy_encounter = {
	observe = function()
		return false, 'not_used'
	end,
	status = function()
		return {}
	end,
}

windower = {
	ffxi = {
		run = function(...)
			run_calls[#run_calls + 1] = { count = select('#', ...), ... }
		end,
		get_mob_by_target = function(target)
			if target == 'me' then
				return me
			end
			return nil
		end,
		get_party = function()
			return {
				p0 = { mob = me },
			}
		end,
		get_mob_by_id = function()
			return nil
		end,
		get_mob_by_index = function()
			return nil
		end,
	},
}

local runtime = assert(loadfile('uc_lilith_easy_formation_runtime.lua'))()
local observation = {
	config = {
		role = 'tank',
	},
	ready = true,
	center = { x = 0, y = 0 },
	boss = {
		id = 900,
		hpp = 100,
		status = 1,
		x = 0,
		y = 0,
	},
}

_G.UC_FORMATION_STATUS = {}
proposal = {
	action = 'move',
	reason = 'FORMATION_TEST_MOVE',
	goal = { x = 5, y = 0 },
}
local acted, reason, owns = runtime.run_tick(observation)
assert_true(acted, 'formation move must execute')
assert_equal(reason, 'FORMATION_TEST_MOVE', 'formation move reason')
assert_true(owns, 'formation move must own movement')
assert_equal(#run_calls, 1, 'formation move run count')
assert_equal(run_calls[1].count, 1, 'formation heading run arity')
assert_true(type(run_calls[1][1]) == 'number', 'formation heading must be numeric')

proposal = {
	action = 'hold',
	reason = 'FORMATION_TEST_HOLD',
}
acted, reason, owns = runtime.run_tick(observation)
assert_true(acted, 'formation hold after movement must execute stop')
assert_equal(reason, 'FORMATION_TEST_HOLD', 'formation hold reason')
assert_true(owns, 'formation hold must own movement')
assert_equal(#run_calls, 2, 'formation stop run count')
assert_equal(run_calls[2].count, 1, 'formation stop run arity')
assert_equal(run_calls[2][1], false, 'formation stop value')

local stopped, stop_reason = runtime.stop('FORMATION_ALREADY_STOPPED')
assert_equal(stopped, false, 'inactive formation stop result')
assert_equal(stop_reason, 'FORMATION_NOT_MOVING', 'inactive formation stop reason')

package.loaded.uc_active_config = original_active_config
package.loaded.uc_combat_formation = original_combat_formation
package.loaded.uc_lilith_easy_encounter = original_lilith_easy_encounter

io.stdout:write('selftest_formation_movement_dispatcher_phase4: OK\n')
