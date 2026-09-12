local M = {}
local recovery_hold = require('uc_recovery_hold')

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

local function require_source_prefix(value)
	if type(value) ~= 'string' or value == '' then
		error('opts.source_prefix must be a non-empty string')
	end
	return value
end

local function require_executed(result, operation)
	if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
		local reason = type(result) == 'table' and result.reason or 'missing_dispatch_result'
		error('uc_movement_dispatcher ' .. operation .. ' failed: ' .. tostring(reason))
	end
	return result
end

local function require_meta(meta)
	if meta ~= nil and type(meta) ~= 'table' then
		error('movement intent meta must be a table')
	end
	return meta
end

local function heading_meta(meta, heading)
	require_meta(meta)
	local out = {}
	if meta ~= nil then
		for key, value in pairs(meta) do
			out[key] = value
		end
	end
	out.heading = heading
	return out
end

local function timeline_log(event_code, fields)
	local logger = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(logger) == 'function' then
		pcall(logger, event_code, fields, nil, 0)
	end
end

local function trace_fields(operation, intent, owner_before, result)
	local meta = type(intent.meta) == 'table' and intent.meta or {}
	return {
		operation = tostring(operation or ''),
		kind = tostring(intent.kind or ''),
		source = tostring(intent.source or ''),
		target_id = tonumber(intent.target_id) or tonumber(meta.target_id) or 0,
		run_x = tonumber(intent.run_x),
		run_y = tonumber(intent.run_y),
		heading = tonumber(intent.heading) or tonumber(meta.heading),
		owner_before = tostring(owner_before or ''),
		owner_after = tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or ''),
		lock_until = tonumber(rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')) or 0,
		movement_mode = tostring(rawget(_G, 'UC_MOVEMENT_MODE') or ''),
		preengage = rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true,
		ok = type(result) == 'table' and result.ok == true,
		executed = type(result) == 'table' and result.executed == true,
		result_reason = type(result) == 'table' and tostring(result.reason or '') or '',
		meta_reason = tostring(meta.reason or ''),
	}
end

function M.build(opts)
	opts = require_table(opts, 'opts')
	local dispatcher = require_table(opts.dispatcher, 'opts.dispatcher')
	require_function(dispatcher.dispatch_intent, 'opts.dispatcher.dispatch_intent')
	local run = require_function(opts.run, 'opts.run')
	local turn = opts.turn
	if turn ~= nil then
		turn = require_function(turn, 'opts.turn')
	end
	local source_prefix = require_source_prefix(opts.source_prefix)
	local sources = {
		stop = source_prefix .. ':stop',
		release = source_prefix .. ':release',
		run_vector = source_prefix .. ':run_vector',
		run_heading = source_prefix .. ':run_heading',
		run_forward = source_prefix .. ':run_forward',
		turn = source_prefix .. ':turn',
		move_towards = source_prefix .. ':move_towards',
		move_away_from = source_prefix .. ':move_away_from',
	}
	local run_deps = {
		execute = true,
		run = run,
	}

	local function dispatch(operation, intent, deps, hooks)
		intent.source = sources[operation]
		local owner_before = rawget(_G, 'UC_MOVEMENT_OWNER')
		local result = dispatcher.dispatch_intent(intent, deps, hooks)
		timeline_log('MOVEMENT_DISPATCH', trace_fields(operation, intent, owner_before, result))
		if type(result) == 'table' and result.reason == recovery_hold.BLOCK_REASON then
			return result
		end
		return require_executed(result, operation)
	end

	local executor = {
		release = function(meta)
			return dispatch('release', {
				kind = 'run_stop',
				meta = require_meta(meta),
			}, run_deps, {
				allow_during_recovery_hold = true,
			})
		end,
		stop = function(meta)
			return dispatch('stop', {
				kind = 'run_stop',
				meta = require_meta(meta),
			}, run_deps)
		end,
		run_vector = function(run_x, run_y, meta)
			return dispatch('run_vector', {
				kind = 'run',
				run_x = run_x,
				run_y = run_y,
				meta = require_meta(meta),
			}, run_deps)
		end,
		run_heading = function(heading, meta)
			local numeric_heading = tonumber(heading)
			if numeric_heading == nil then
				error('uc_movement_dispatcher heading must be numeric')
			end
			return dispatch('run_heading', {
				kind = 'run',
				run_x = math.cos(numeric_heading),
				run_y = math.sin(numeric_heading),
				meta = heading_meta(meta, numeric_heading),
			}, {
				execute = true,
				run = function()
					run(numeric_heading)
				end,
			})
		end,
		run_forward = function(meta)
			return dispatch('run_forward', {
				kind = 'run_forward',
				meta = require_meta(meta),
			}, {
				execute = true,
				run_forward = function()
					run()
				end,
			})
		end,
		move_towards = function(mover, target_id, meta)
			require_table(mover, 'mover')
			require_function(mover.move_towards, 'mover.move_towards')
			return dispatch('move_towards', {
				kind = 'move_towards',
				target_id = target_id,
				meta = require_meta(meta),
			}, {
				execute = true,
				move_towards = function(id)
					mover:move_towards(id)
				end,
			})
		end,
		move_away_from = function(mover, target_id, meta)
			require_table(mover, 'mover')
			require_function(mover.move_away_from, 'mover.move_away_from')
			return dispatch('move_away_from', {
				kind = 'move_away_from',
				target_id = target_id,
				meta = require_meta(meta),
			}, {
				execute = true,
				move_away_from = function(id)
					mover:move_away_from(id)
				end,
			})
		end,
	}

	if turn ~= nil then
		executor.turn = function(heading, meta)
			return dispatch('turn', {
				kind = 'turn',
				heading = heading,
				meta = require_meta(meta),
			}, {
				execute = true,
				turn = turn,
			})
		end
	end

	return executor
end

return M
