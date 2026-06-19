local M = {}
local ENGAGE_ACTION_TAIL_S = 0.35
local SPELL_SUCCESS_TAIL_S = 0.2

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
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
end

function M.action_mark_engage_sent(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	st.action_start = now
	st.action_end = now
	st.last_action = now
	st.action_delay = ENGAGE_ACTION_TAIL_S
	st.cooldown_until = math.max(tonumber(st.cooldown_until) or 0, now + ENGAGE_ACTION_TAIL_S)
	st.last_send_kind = 'engage'
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
end

function M.action_mark_sent_with_meta(scheduler, kind, now_s, meta)
	M.action_mark_sent(scheduler, kind, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	st.last_action_name = tostring(meta.action_name or '')
	st.last_action_provider = tostring(meta.provider or '')
	st.last_def_action_type = tostring(meta.def_action_type or '')
	st.last_target_id = tonumber(meta.target_id) or 0
	st.last_target_kind = tostring(meta.target_kind or '')
	if (st.last_action_provider == 'defensive_internal' or st.last_action_provider == 'defensive_healbot')
		and st.last_def_action_type == 'cure' then
		st.defensive_cure_weave_until = now + 5.0
	end
end

function M.defensive_cure_weave_ready(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	local last_provider = tostring(st.last_action_provider or '')
	local last_send_kind = tostring(st.last_send_kind or '')
	local last_def_type = tostring(st.last_def_action_type or '')
	local weave_until = tonumber(st.defensive_cure_weave_until) or 0
	if weave_until <= 0 or now > weave_until then
		return false
	end
	if last_def_type ~= 'cure' then
		return false
	end
	if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then
		return false
	end
	if last_send_kind ~= 'spell' and last_send_kind ~= 'defensive_healbot' then
		return false
	end
	return true
end

function M.action_mark_packet_start(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	st.action_start = now
	local timeline_log = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(timeline_log) == 'function' then
		pcall(timeline_log, 'SPELL_PACKET_START', {
			spell = tostring(st.last_action_name or ''),
			provider = tostring(st.last_action_provider or ''),
			kind = tostring(st.last_send_kind or ''),
		}, ('spell_packet_start:%s'):format(tostring(st.last_action_name or '')), 0.05)
	end
end

function M.action_mark_packet_end(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	st.action_end = now
	local timeline_log = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(timeline_log) == 'function' then
		pcall(timeline_log, 'SPELL_PACKET_END', {
			spell = tostring(st.last_action_name or ''),
			provider = tostring(st.last_action_provider or ''),
			kind = tostring(st.last_send_kind or ''),
		}, ('spell_packet_end:%s'):format(tostring(st.last_action_name or '')), 0.05)
	end
end

function M.clear_local_defensive_spell_interruption(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	local last_send_kind = tostring(st.last_send_kind or '')
	local last_provider = tostring(st.last_action_provider or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then
		return false
	end
	st.action_end = now
	st.cooldown_until = now
	st.action_delay = 0
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	return true
end

function M.clear_local_spell_interruption(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	local last_send_kind = tostring(st.last_send_kind or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	st.action_end = now
	st.cooldown_until = now
	st.action_delay = 0
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	local timeline_log = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(timeline_log) == 'function' then
		pcall(timeline_log, 'SPELL_FAILURE', {
			spell = tostring(st.last_action_name or ''),
			provider = tostring(st.last_action_provider or ''),
			kind = last_send_kind,
		}, ('spell_failure:%s'):format(tostring(st.last_action_name or '')), 0.05)
		pcall(timeline_log, 'SPELL_INTERRUPTED', {
			spell = tostring(st.last_action_name or ''),
			provider = tostring(st.last_action_provider or ''),
			kind = last_send_kind,
		}, ('spell_interrupted:%s'):format(tostring(st.last_action_name or '')), 0.05)
	end
	return true
end

function M.clear_local_defensive_spell_success(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	local last_send_kind = tostring(st.last_send_kind or '')
	local last_provider = tostring(st.last_action_provider or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then
		return false
	end
	st.action_end = now
	st.cooldown_until = now + SPELL_SUCCESS_TAIL_S
	st.action_delay = SPELL_SUCCESS_TAIL_S
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = now
	st.post_spell_tail_until = now + SPELL_SUCCESS_TAIL_S
	return true
end

function M.clear_local_spell_success(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	local last_send_kind = tostring(st.last_send_kind or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	st.action_end = now
	st.cooldown_until = now + SPELL_SUCCESS_TAIL_S
	st.action_delay = SPELL_SUCCESS_TAIL_S
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = now
	st.post_spell_tail_until = now + SPELL_SUCCESS_TAIL_S
	local timeline_log = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(timeline_log) == 'function' then
		pcall(timeline_log, 'SPELL_SUCCESS', {
			spell = tostring(st.last_action_name or ''),
			provider = tostring(st.last_action_provider or ''),
			kind = last_send_kind,
		}, ('spell_success:%s'):format(tostring(st.last_action_name or '')), 0.05)
		pcall(timeline_log, 'POST_SPELL_TAIL_START', {
			spell = tostring(st.last_action_name or ''),
			provider = tostring(st.last_action_provider or ''),
			tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
		}, ('post_spell_tail_start:%s'):format(tostring(st.last_action_name or '')), 0.05)
	end
	return true
end

function M.clear_stale_combat_spell_lock(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	meta = type(meta) == 'table' and meta or {}
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return false
	end
	if tostring(st.last_action_provider or '') ~= 'combat' then
		return false
	end
	if tostring(st.last_target_kind or '') ~= 'mob' then
		return false
	end
	local old_target_id = tonumber(st.last_target_id) or 0
	local new_target_id = tonumber(meta.new_target_id) or 0
	local old_target_invalid = meta.old_target_invalid == true
	local player_status_zero = meta.player_status_zero == true
	local target_transition = old_target_id > 0 and new_target_id > 0 and old_target_id ~= new_target_id
	if not old_target_invalid then
		return false
	end
	if not target_transition and not player_status_zero then
		return false
	end
	local acting = M.action_is_acting(scheduler, now_s)
	if acting and not target_transition then
		return false
	end
	local now = now_s()
	st.action_end = now
	st.cooldown_until = now
	st.action_delay = 0
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	return true
end

function M.engage_attack_on_action_state_gate(scheduler, now_s, globals, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	globals = type(globals) == 'table' and globals or {}
	meta = type(meta) == 'table' and meta or {}
	local blocked, reason = M.action_dispatch_blocked(scheduler, now_s, globals)
	if not blocked then
		return false, nil
	end
	if meta.explicit_attack_on ~= true then
		return true, reason
	end
	if tonumber(meta.player_status) == 1 then
		return true, reason
	end
	if meta.target_selected ~= true or meta.target_valid ~= true then
		return true, reason
	end
	local send_kind = tostring(st.last_send_kind or '')
	local status_value = tonumber(meta.player_status) or 0
	local timeline_log = rawget(globals, 'UC_ACTION_TIMELINE_LOG')
	if send_kind == 'spell' and M.action_is_acting(scheduler, now_s) then
		if type(timeline_log) == 'function' then
			pcall(timeline_log, 'ENGAGE_ACTION_STATE_HELD_ACTIVE_CAST', {
				tid = tonumber(meta.target_id) or 0,
				name = tostring(meta.target_name or ''),
				status = status_value,
				kind = send_kind,
				reason = tostring(reason or 'BLOCK_ACTION_ACTING'),
			}, ('engage_action_state_held:%d'):format(tonumber(meta.target_id) or 0), 0.25)
		end
		return true, reason
	end
	if send_kind == 'engage' then
		return true, reason
	end
	if type(timeline_log) == 'function' then
		pcall(timeline_log, 'ENGAGE_ACTION_STATE_BYPASS', {
			tid = tonumber(meta.target_id) or 0,
			name = tostring(meta.target_name or ''),
			status = status_value,
			kind = send_kind,
			reason = tostring(reason or 'BLOCK_ACTION_STATE'),
		}, ('engage_action_state_bypass:%s:%d'):format(send_kind, tonumber(meta.target_id) or 0), 0.25)
	end
	return false, nil
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
	local function timeline_log(event_code, fields, dedupe_key, interval)
		local fn = rawget(globals, 'UC_ACTION_TIMELINE_LOG')
		if type(fn) == 'function' then
			pcall(fn, event_code, fields, dedupe_key, interval)
		end
	end
	local function timeline_reason(kind)
		local send_kind = tostring(st.last_send_kind or '')
		if kind == 'acting' then
			if send_kind == 'spell' then
				return 'BLOCK_SPELL_CASTING'
			end
			return 'BLOCK_ACTION_STATE'
		end
		if kind == 'cooldown' then
			if send_kind == 'spell' then
				return 'BLOCK_POST_SPELL_TAIL'
			end
			if send_kind == 'engage' then
				return 'BLOCK_DEBOUNCE'
			end
			return 'BLOCK_ACTION_STATE'
		end
		return 'BLOCK_UNKNOWN'
	end
	local current_action_kind = tostring(rawget(globals, 'UC_ACTION_TIMELINE_CURRENT_ACTION') or '')
	local allow_defensive_ja_to_cure_followup = false
	local current_action = rawget(globals, 'UC_DEFENSIVE_CHAIN_ACTION')
	if type(current_action) == 'table' then
		local current_provider = tostring(current_action.provider or '')
		local current_kind = tostring(current_action.action_kind or '')
		local current_def_type = tostring(current_action.def_action_type or '')
		local last_send_kind = tostring(st.last_send_kind or '')
		local last_action_name = tostring(st.last_action_name or ''):lower()
		local last_provider = tostring(st.last_action_provider or '')
		local last_def_type = tostring(st.last_def_action_type or '')
		local since_last_action = now - (tonumber(st.last_action) or 0)
		if current_provider == 'defensive_internal'
			and current_kind == 'spell'
			and current_def_type == 'cure'
			and last_send_kind == 'ja'
			and last_action_name == 'majesty'
			and last_provider == 'defensive_internal'
			and last_def_type == 'buff'
			and since_last_action >= 0
			and since_last_action <= 0.75 then
			allow_defensive_ja_to_cure_followup = true
		end
	end
	if M.action_is_acting(scheduler, now_s) then
		if allow_defensive_ja_to_cure_followup then
			return false, nil
		end
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
		if current_action_kind == 'engage' then
			local reason = timeline_reason('acting')
			st.timeline_last_engage_block_reason = reason
			timeline_log('ACTION_STATE_BLOCK_ENGAGE', {
				reason = reason,
				kind = tostring(st.last_send_kind or ''),
			}, ('engage_action_block:%s'):format(reason), 0.50)
		end
		return true, 'BLOCK_ACTION_ACTING'
	end
	if now < (tonumber(st.cooldown_until) or 0) then
		if allow_defensive_ja_to_cure_followup then
			return false, nil
		end
		if combat_log_on then
			direct_combat_log(('action_block cooldown=1 now=%.3f until=%.3f remain=%.3f kind=%s'):format(
				tonumber(now) or 0,
				tonumber(st.cooldown_until) or 0,
				(tonumber(st.cooldown_until) or 0) - (tonumber(now) or 0),
				tostring(st.last_send_kind or '')
			))
		end
		if current_action_kind == 'engage' then
			local reason = timeline_reason('cooldown')
			st.timeline_last_engage_block_reason = reason
			if reason == 'BLOCK_DEBOUNCE' then
				timeline_log('ENGAGE_DEBOUNCED', {
					reason = reason,
				}, 'engage_debounced', 0.50)
			else
				timeline_log('ACTION_STATE_BLOCK_ENGAGE', {
					reason = reason,
					kind = tostring(st.last_send_kind or ''),
				}, ('engage_action_block:%s'):format(reason), 0.50)
			end
		end
		return true, 'BLOCK_ACTION_COOLDOWN'
	end
	if current_action_kind == 'engage' then
		local last_reason = tostring(st.timeline_last_engage_block_reason or '')
		if last_reason ~= '' then
			timeline_log('ACTION_STATE_RELEASE', {
				reason = last_reason,
			}, ('engage_action_release:%s'):format(last_reason), 0.05)
			if last_reason == 'BLOCK_POST_SPELL_TAIL' then
				local tail_start = tonumber(st.post_spell_tail_started_at) or 0
				local tail_until = tonumber(st.post_spell_tail_until) or 0
				local tail_s = ''
				if tail_start > 0 and tail_until > tail_start then
					tail_s = ('%.2f'):format(tail_until - tail_start)
				end
				timeline_log('POST_SPELL_TAIL_END', {
					reason = last_reason,
					tail_s = tail_s,
				}, 'post_spell_tail_end', 0.05)
				st.post_spell_tail_started_at = 0
				st.post_spell_tail_until = 0
			end
			st.timeline_last_engage_block_reason = ''
		end
	end
	return false, nil
end

return M
