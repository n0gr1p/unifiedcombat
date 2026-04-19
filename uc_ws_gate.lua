local M = {}

function M.busy_for_gate(opts)
	local is_casting = opts and opts.is_casting == true
	local hard_busy = opts and opts.hard_busy == true
	return (is_casting or hard_busy) and 1 or 0
end

function M.evaluate(opts)
	local ws_enabled = opts and opts.ws_enabled == true
	local tp = tonumber(opts and opts.tp) or 0
	local dist = tonumber(opts and opts.dist) or 0
	local hpp = tonumber(opts and opts.hpp) or 0
	local busy = tonumber(opts and opts.busy) or 0
	local max_dist = tonumber(opts and opts.max_dist) or 6
	local ws_name = tostring(opts and opts.ws_name or '')

	if not ws_enabled then
		return false, 'WS_OFF'
	end
	if tp <= 999 then
		return false, 'TP_LT_1000'
	end
	if dist >= max_dist then
		return false, 'OUT_OF_RANGE'
	end
	if hpp <= 0 then
		return false, 'TARGET_DEAD'
	end
	if busy ~= 0 then
		return false, 'BUSY'
	end
	if ws_name == '' then
		return false, 'NO_VALID_WS'
	end
	return true, 'READY'
end

return M
