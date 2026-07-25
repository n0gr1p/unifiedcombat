local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected)
			.. ', actual=' .. tostring(actual))
	end
end

local function main()
	local runs = {}
	local targets = {}
	local commands = {}
	local sleeps = {}
	local executor = require('uc_scheduler_pull_executor').build({
		dispatcher = require('uc_scheduler_dispatcher'),
		run = function(value)
			runs[#runs + 1] = value
		end,
		set_target = function(target_id)
			targets[#targets + 1] = target_id
			return true
		end,
		send_command = function(command)
			commands[#commands + 1] = command
		end,
		sleep = function(seconds)
			sleeps[#sleeps + 1] = seconds
		end,
	})

	executor.stop({ reason = 'test_stop' })
	executor.run_heading(1.25, { reason = 'test_move' })
	assert_equal(executor.select_target(101, { reason = 'test_target' }), true, 'target result')
	executor.send_command('input /ma "Flash" 101', { reason = 'test_command' })
	executor.sleep(0.05)

	assert_equal(#runs, 2, 'movement execution count')
	assert_equal(runs[1], false, 'stop call shape')
	assert_equal(runs[2], 1.25, 'heading call shape')
	assert_equal(#targets, 1, 'target execution count')
	assert_equal(targets[1], 101, 'target id')
	assert_equal(#commands, 1, 'command execution count')
	assert_equal(commands[1], 'input /ma "Flash" 101', 'command')
	assert_equal(#sleeps, 1, 'sleep execution count')
	assert_equal(sleeps[1], 0.05, 'sleep duration')

	local command_calls = 0
	local rejected = require('uc_scheduler_pull_executor').build({
		dispatcher = {
			dispatch_intent = function()
				return { ok = false, executed = false, reason = 'commit_rejected' }
			end,
		},
		run = function() end,
		set_target = function() return true end,
		send_command = function()
			command_calls = command_calls + 1
		end,
		sleep = function() end,
	})
	local ok, err = pcall(function()
		rejected.send_command('input /ja "Provoke" 101')
	end)
	assert_equal(ok, false, 'rejected command must fail fast')
	assert_equal(command_calls, 0, 'rejected command must not execute a fallback')
	assert_equal(tostring(err):find('commit_rejected', 1, true) ~= nil, true, 'rejection reason')

	io.stdout:write('selftest_scheduler_pull_executor: OK\n')
end

main()
