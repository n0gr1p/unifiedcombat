local M = {}

function M.action_state(scheduler)
	scheduler.action_state = scheduler.action_state or {}
	return scheduler.action_state
end

function M.action_mark_sent(scheduler, kind, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	st.action_start = now
	st.action_end = now - 0.001
	st.last_action = now
	st.action_delay = 0.6
	st.cooldown_until = math.max(tonumber(st.cooldown_until) or 0, now + 0.6)
	st.last_send_kind = tostring(kind or '')
end

function M.action_mark_packet_start(scheduler, now_s)
	local st = M.action_state(scheduler)
	st.action_start = now_s()
end

function M.action_mark_packet_end(scheduler, now_s)
	local st = M.action_state(scheduler)
	st.action_end = now_s()
end

function M.action_is_acting(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	local start_at = tonumber(st.action_start) or 0
	local end_at = tonumber(st.action_end) or 0
	local send_kind = tostring(st.last_send_kind or '')
	local timeout = tonumber(st.lag_timeout) or 8.0
	if send_kind == 'ja' then
		timeout = tonumber(st.ja_lag_timeout) or 1.0
	end
	if start_at > 0 and end_at < start_at and (now - start_at) > timeout then
		st.action_end = now
		end_at = now
	end
	local acting = end_at < start_at
	local last = st.last_acting_state == true
	if last and not acting then
		st.action_delay = 0.5
		st.last_action = now
		st.cooldown_until = math.max(tonumber(st.cooldown_until) or 0, now + 0.5)
	elseif (not last) and acting then
		st.action_delay = 0.6
	end
	st.last_acting_state = acting
	return acting
end

function M.action_dispatch_blocked(scheduler, now_s, globals)
	local st = M.action_state(scheduler)
	local now = now_s()
	local settings = rawget(globals, 'UC_SETTINGS') or {}
	local combat_log_on = (settings.log_combat_sched == true) or (settings.log_combat_sched == 1) or (tostring(settings.log_combat_sched or ''):lower() == 'true')
	local diag = rawget(globals, 'UC_LOG_DIAG')
	local function direct_combat_log(msg)
		if not combat_log_on then
			return
		end
		if type(diag) == 'function' then
			pcall(diag, 'combat_sched', tostring(msg or ''))
		end
	end
	if M.action_is_acting(scheduler, now_s) then
		if combat_log_on then
			local start_at = tonumber(st.action_start) or 0
			local end_at = tonumber(st.action_end) or 0
			local send_kind = tostring(st.last_send_kind or '')
			local timeout = tonumber(st.lag_timeout) or 8.0
			if send_kind == 'ja' then
				timeout = tonumber(st.ja_lag_timeout) or 1.0
			end
			direct_combat_log(('action_block acting=1 kind=%s now=%.3f start=%.3f end=%.3f age=%.3f timeout=%.3f'):format(
				send_kind,
				tonumber(now) or 0,
				tonumber(start_at) or 0,
				tonumber(end_at) or 0,
				(tonumber(now) or 0) - (tonumber(start_at) or 0),
				tonumber(timeout) or 0
			))
		end
		return true, 'BLOCK_ACTION_ACTING'
	end
	if now < (tonumber(st.cooldown_until) or 0) then
		if combat_log_on then
			direct_combat_log(('action_block cooldown=1 now=%.3f until=%.3f remain=%.3f kind=%s'):format(
				tonumber(now) or 0,
				tonumber(st.cooldown_until) or 0,
				(tonumber(st.cooldown_until) or 0) - (tonumber(now) or 0),
				tostring(st.last_send_kind or '')
			))
		end
		return true, 'BLOCK_ACTION_COOLDOWN'
	end
	return false, nil
end

return M
