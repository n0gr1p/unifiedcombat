local M = {}

function M.p1_pending_is_live_state(state_name)
	return state_name == 'selected' or state_name == 'dispatching' or state_name == 'sent' or state_name == 'acknowledged'
end

function M.p1_duplicate_suppressed(scheduler, ctx, proposal, p1_number)
	local dkey = tostring(proposal and proposal.duplicate_suppression_key or '')
	if dkey == '' then
		return false
	end
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) == 'table' then
		local pkey = tostring(pending.duplicate_suppression_key or '')
		local state_name = tostring(pending.state or '')
		if pkey == dkey and M.p1_pending_is_live_state(state_name) then
			return true
		end
	end
	local until_ts = p1_number(phase.recent_duplicate_until[dkey], 0)
	if until_ts > ctx.now then
		return true
	end
	return false
end

function M.p1_get_locks(scheduler, ctx, p1_number, globals)
	local phase = scheduler.phase1
	local pending = phase.pending
	local pending_live = type(pending) == 'table' and M.p1_pending_is_live_state(tostring(pending.state or ''))
	local pet_pending_live = pending_live and tostring(pending.action_type or '') == 'pet'
	local zone_suspend_until = rawget(globals, 'UC_ZONE_SUSPEND_UNTIL')
	local zone_guard_active = type(zone_suspend_until) == 'number' and ctx.now < zone_suspend_until
	local now = ctx.now
	local duplicate_lock_until = 0
	for _, until_ts in pairs(phase.recent_duplicate_until) do
		local u = p1_number(until_ts, 0)
		if u > duplicate_lock_until then
			duplicate_lock_until = u
		end
	end
	return {
		zone_guard_lock = { hard = zone_guard_active },
		cast_lock = { hard = pending_live },
		movement_lock = { hard = pending_live and not pet_pending_live },
		target_lock = { hard = false },
		duplicate_lock = { hard = duplicate_lock_until > now, until_ts = duplicate_lock_until },
	}
end

function M.p1_hard_lock_reject(locks, proposal)
	local action_type = tostring(proposal and proposal.action_type or '')
	if locks.zone_guard_lock and locks.zone_guard_lock.hard and action_type ~= 'move' then
		return 'zone_guard'
	end
	if (action_type == 'spell' or action_type == 'ja' or action_type == 'ws'
		or action_type == 'item' or action_type == 'pet')
		and locks.cast_lock and locks.cast_lock.hard then
		return 'hard_locked'
	end
	if action_type == 'move' and locks.movement_lock and locks.movement_lock.hard then
		return 'hard_locked'
	end
	return ''
end

function M.p1_build_lock_summary(ctx, locks, p1_get_locks)
	local parts = {}
	local lock_state = locks or p1_get_locks(ctx)
	if lock_state.zone_guard_lock and lock_state.zone_guard_lock.hard then
		parts[#parts + 1] = 'zone_guard_lock'
	end
	if lock_state.cast_lock and lock_state.cast_lock.hard then
		parts[#parts + 1] = 'cast_lock'
	end
	if lock_state.movement_lock and lock_state.movement_lock.hard then
		parts[#parts + 1] = 'movement_lock'
	end
	if lock_state.duplicate_lock and lock_state.duplicate_lock.hard then
		parts[#parts + 1] = 'duplicate_lock'
	end
	return table.concat(parts, '|')
end

function M.reset_runtime_locks(globals, action_state)
	globals.UC_MOVE_FREEZE_PREP_KEY = ''
	globals.UC_MOVE_FREEZE_PREP_UNTIL = 0
	local st = action_state()
	st.action_start = 0
	st.action_end = 0
	st.last_send_kind = ''
	st.cooldown_until = 0
	st.action_delay = 0
	st.last_action = 0
	st.last_acting_state = false
end

return M
