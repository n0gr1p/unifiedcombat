local M = {}

function M.p1_update_pending_state(scheduler, ctx, p1_pending_is_live_state, p1_number)
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		phase.pending = nil
		return
	end
	local now = ctx.now
	local state_name = tostring(pending.state or '')
	if p1_pending_is_live_state(state_name) and now > p1_number(pending.effect_deadline, 0) then
		pending.state = 'timed_out'
		pending.result = 'effect_timeout'
		local dkey = tostring(pending.duplicate_suppression_key or '')
		if dkey ~= '' then
			phase.recent_duplicate_until[dkey] = now + 0.75
		end
	end
	if (pending.state == 'timed_out' or pending.state == 'failed' or pending.state == 'canceled') and now > p1_number(pending.completion_deadline, now) then
		phase.pending = nil
	end
	if pending.state == 'complete' and now > p1_number(pending.completion_deadline, now) then
		phase.pending = nil
	end
end

function M.p1_set_pending_globals(scheduler, globals)
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		globals.UC_SCHED_P1_PENDING_STATE = ''
		return
	end
	globals.UC_SCHED_P1_PENDING_STATE = tostring(pending.state or '')
end

function M.p1_pending_mark_complete(scheduler, now, result_code)
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	pending.state = 'complete'
	pending.result = tostring(result_code or 'complete')
	pending.effect_at = now
	pending.completion_deadline = now + 0.75
	local dkey = tostring(pending.duplicate_suppression_key or '')
	if dkey ~= '' then
		phase.recent_duplicate_until[dkey] = now + 0.75
	end
end

function M.p1_pending_mark_failed(scheduler, now, result_code, retry_delay)
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	local delay = tonumber(retry_delay) or 0
	pending.state = 'failed'
	pending.result = tostring(result_code or 'failed')
	pending.effect_at = now
	pending.completion_deadline = now + delay
	local dkey = tostring(pending.duplicate_suppression_key or '')
	if dkey ~= '' then
		phase.recent_duplicate_until[dkey] = now + delay
	end
end

return M
