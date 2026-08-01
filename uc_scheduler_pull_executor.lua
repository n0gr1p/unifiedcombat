local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(value, name)
	if type(value) ~= 'function' then
		error(name .. ' must be a function')
	end
	return value
end

function M.build(opts)
	opts = require_table(opts, 'opts')
	local dispatcher = require_table(opts.dispatcher, 'opts.dispatcher')
	require_function(dispatcher.dispatch_intent, 'opts.dispatcher.dispatch_intent')
	local run = require_function(opts.run, 'opts.run')
	local set_target = require_function(opts.set_target, 'opts.set_target')
	local send_command = require_function(opts.send_command, 'opts.send_command')
	local sleep = require_function(opts.sleep, 'opts.sleep')
	local movement = require('uc_movement_dispatcher').build({
		dispatcher = dispatcher,
		run = run,
		source_prefix = 'scheduler_pull',
	})

	return {
		stop = movement.stop,
		run_heading = movement.run_heading,
		select_target = function(target_id, meta)
			local result = dispatcher.dispatch_intent({
				kind = 'select_target',
				source = 'scheduler_pull:target',
				target_id = target_id,
				meta = meta,
			}, {
				execute = true,
				set_target = set_target,
			})
			return type(result) == 'table'
				and result.ok == true
				and result.executed == true
				and result.dep_result == true
		end,
		sleep = sleep,
		send_command = function(command, meta)
			local result = dispatcher.dispatch_intent({
				kind = 'send_command',
				source = 'scheduler_pull:action',
				command = command,
				meta = meta,
			}, {
				execute = true,
				send_command = send_command,
			})
			if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
				error('uc_scheduler_pull_executor command dispatch failed: '
					.. tostring(type(result) == 'table' and result.reason or 'missing_dispatch_result'))
			end
		end,
	}
end

return M
