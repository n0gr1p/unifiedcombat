local M = {}

function M.build(opts)
	if type(opts) ~= 'table' then
		error('opts must be a table')
	end
	if type(opts.turn) ~= 'function' then
		error('opts.turn must be a function')
	end
	return require('uc_movement_dispatcher').build({
		dispatcher = opts.dispatcher,
		run = opts.run,
		turn = opts.turn,
		source_prefix = 'scheduler_movement_facade',
	})
end

return M
