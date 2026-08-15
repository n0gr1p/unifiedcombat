local movement_dispatcher = require('uc_movement_dispatcher')

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

local function require_reason(reason, name)
	if type(reason) ~= 'string' or reason == '' then
		error(name .. ' must be a non-empty string')
	end
	return reason
end

local function copy_table(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copy_table(item)
	end
	return out
end

local function formation_heading(me, goal)
	local me_x = tonumber(me and me.x)
	local me_y = tonumber(me and me.y)
	local goal_x = tonumber(goal and goal.x)
	local goal_y = tonumber(goal and goal.y)
	if me_x == nil or me_y == nil or goal_x == nil or goal_y == nil then
		error('generic formation movement requires numeric player and goal coordinates')
	end
	local dx = goal_x - me_x
	local dy = goal_y - me_y
	if ((dx * dx) + (dy * dy)) < 0.000001 then
		return nil
	end
	return math.atan2(dx, dy) - 1.5708
end

function M.build(opts)
	opts = require_table(opts, 'uc_generic_formation_runtime opts')
	local solver = require_table(opts.solver, 'opts.solver')
	require_function(solver.evaluate, 'opts.solver.evaluate')
	local source_prefix = require_reason(opts.source_prefix, 'opts.source_prefix')
	local movement = movement_dispatcher.build({
		dispatcher = require_table(opts.dispatcher, 'opts.dispatcher'),
		run = require_function(opts.run, 'opts.run'),
		source_prefix = source_prefix,
	})
	local moving = false
	local status = {
		enabled = false,
		moving = false,
		reason = 'FORMATION_RUNTIME_INITIAL',
		proposal = nil,
	}
	local runtime = {}

	local function publish(enabled, reason, proposal)
		status = {
			enabled = enabled == true,
			moving = moving,
			reason = tostring(reason),
			proposal = copy_table(proposal),
		}
	end

	local function stop_active(reason)
		if moving ~= true then
			return false
		end
		movement.stop({ reason = reason })
		moving = false
		return true
	end

	function runtime.run_tick(ctx)
		ctx = require_table(ctx, 'generic formation runtime ctx')
		local config = require_table(ctx.config, 'generic formation runtime ctx.config')
		if type(config.enabled) ~= 'boolean' then
			error('generic formation runtime config.enabled must be boolean')
		end
		if config.enabled ~= true then
			local stopped = stop_active('FORMATION_DISABLED')
			publish(false, 'FORMATION_DISABLED', nil)
			return stopped, 'FORMATION_DISABLED', stopped
		end
		local proposal = solver.evaluate(ctx)
		if type(proposal) ~= 'table' then
			error('generic formation solver must return a proposal table')
		end
		local action = tostring(proposal.action or '')
		local reason = require_reason(proposal.reason, 'generic formation proposal.reason')
		if action == 'error' then
			local stopped = stop_active('FORMATION_ERROR')
			publish(true, reason, proposal)
			return stopped, reason, true
		end
		if action == 'hold' then
			local stopped = stop_active(reason)
			publish(true, reason, proposal)
			return stopped, reason, true
		end
		if action ~= 'move' or type(proposal.goal) ~= 'table' then
			error('generic formation solver returned an invalid proposal')
		end
		local heading = formation_heading(ctx.me, proposal.goal)
		if heading == nil then
			error('generic formation solver returned a zero-vector move')
		end
		movement.run_heading(heading, {
			reason = reason,
			heading = heading,
			goal_x = proposal.goal.x,
			goal_y = proposal.goal.y,
		})
		moving = true
		publish(true, reason, proposal)
		return true, reason, true
	end

	function runtime.stop(reason)
		reason = require_reason(reason, 'generic formation runtime stop reason')
		if stop_active(reason) ~= true then
			return false, 'FORMATION_NOT_MOVING'
		end
		publish(status.enabled, reason, status.proposal)
		return true, reason
	end

	function runtime.reset(reason)
		reason = require_reason(reason, 'generic formation runtime reset reason')
		stop_active(reason)
		publish(false, reason, nil)
	end

	function runtime.status()
		return copy_table(status)
	end

	return runtime
end

local default_runtime = nil

local function get_default_runtime()
	if default_runtime == nil then
		if type(rawget(_G, 'windower')) ~= 'table'
			or type(windower.ffxi) ~= 'table'
			or type(windower.ffxi.run) ~= 'function' then
			error('default generic formation runtime requires windower.ffxi.run')
		end
		default_runtime = M.build({
			solver = require('uc_generic_formation'),
			dispatcher = require('uc_scheduler_dispatcher'),
			run = windower.ffxi.run,
			source_prefix = 'generic_formation',
		})
	end
	return default_runtime
end

function M.run_tick(ctx)
	return get_default_runtime().run_tick(ctx)
end

function M.stop(reason)
	return get_default_runtime().stop(reason)
end

function M.reset(reason)
	return get_default_runtime().reset(reason)
end

function M.status()
	return get_default_runtime().status()
end

return M
