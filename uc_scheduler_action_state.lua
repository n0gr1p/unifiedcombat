local M = {}
local ENGAGE_ACTION_TAIL_S = 0.35
local SPELL_SUCCESS_TAIL_S = 0.2

local function timeline_log(event_code, fields, dedupe_key, interval)
	local fn = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(fn) == 'function' then
		pcall(fn, event_code, fields, dedupe_key, interval)
	end
end

local function spell_elapsed_fields(st, now, extra)
	extra = type(extra) == 'table' and extra or {}
	local sent_at = tonumber(st.last_sent_at) or 0
	local packet_start_at = tonumber(st.packet_start_at) or 0
	local cooldown_until = tonumber(st.cooldown_until) or 0
	local tail_until = tonumber(st.post_spell_tail_until) or 0
	local fields = {
		spell = tostring(extra.spell or st.last_action_name or ''),
		provider = tostring(extra.provider or st.last_action_provider or ''),
		target = tostring(extra.target or st.last_target_name or ''),
		target_id = tonumber(extra.target_id) or tonumber(st.last_target_id) or 0,
		message_id = tonumber(extra.message_id) or 0,
		old_kind = tostring(extra.old_kind or st.last_send_kind or ''),
		release_reason = tostring(extra.release_reason or ''),
		since_sent_s = (sent_at > 0) and ('%.2f'):format(math.max(0, now - sent_at)) or '',
		since_packet_start_s = (packet_start_at > 0) and ('%.2f'):format(math.max(0, now - packet_start_at)) or 'na',
		cooldown_s = ('%.2f'):format(math.max(0, cooldown_until - now)),
		tail_s = ('%.2f'):format(math.max(0, tail_until - now)),
		action_token = tostring(tonumber(st.action_token) or 0),
		cast_type = tostring(extra.cast_type or st.last_def_action_type or ''),
	}
	for key, value in pairs(extra) do
		if fields[key] == nil or fields[key] == '' then
			fields[key] = value
		end
	end
	return fields
end

local function note_missing_high_level_spell_sent(st, now, first_event)
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return
	end
	if st.high_level_spell_sent_logged == true or st.spell_sent_log_missing_emitted == true then
		return
	end
	st.spell_sent_log_missing_emitted = true
	timeline_log('SPELL_SENT_LOG_MISSING', spell_elapsed_fields(st, now, {
		release_reason = 'missing_high_level_spell_sent',
		first_lifecycle_event = tostring(first_event or ''),
		estimated_sent_at = (tonumber(st.last_sent_at) or 0) > 0 and ('%.3f'):format(tonumber(st.last_sent_at) or 0) or '',
		source = tostring(st.last_action_source or ''),
		high_level_spell_sent = '0',
	}), ('spell_sent_log_missing:%s:%s'):format(tostring(st.last_action_name or ''), tostring(tonumber(st.action_token) or 0)), 0.25)
end

local function current_token_string(st)
	return tostring(tonumber(st.action_token) or 0)
end

local function mark_terminal_outcome(st, now, outcome, meta)
	meta = type(meta) == 'table' and meta or {}
	local token = current_token_string(st)
	local existing = tostring(st.terminal_outcome or '')
	local existing_token = tostring(st.terminal_action_token or '')
	if existing ~= '' and existing_token == token then
		return false, existing
	end
	st.terminal_outcome = tostring(outcome or '')
	st.terminal_action_token = token
	st.terminal_at = now
	st.terminal_message_id = tonumber(meta.message_id) or 0
	st.terminal_message_param = tonumber(meta.message_param) or 0
	local sent_at = tonumber(st.last_sent_at) or 0
	st.terminal_since_sent_s = (sent_at > 0) and math.max(0, now - sent_at) or 0
	return true, ''
end

local function log_late_completion_ignored(st, now, original_outcome, late_classification, meta)
	meta = type(meta) == 'table' and meta or {}
	timeline_log('SPELL_LATE_COMPLETION_IGNORED', spell_elapsed_fields(st, now, {
		release_reason = 'late_completion_ignored',
		original_outcome = tostring(original_outcome or ''),
		original_terminal_at = (tonumber(st.terminal_at) or 0) > 0 and ('%.3f'):format(tonumber(st.terminal_at) or 0) or '',
		original_since_sent_s = (tonumber(st.terminal_since_sent_s) or 0) > 0 and ('%.2f'):format(tonumber(st.terminal_since_sent_s) or 0) or '0.00',
		late_message_id = tonumber(meta.message_id) or 0,
		late_message_param = tonumber(meta.message_param) or 0,
		late_completion = tostring(late_classification or ''),
	}), ('spell_late_completion_ignored:%s:%s:%s'):format(tostring(st.last_action_name or ''), current_token_string(st), tostring(original_outcome or '')), 0.05)
end

local function emit_spell_action_release(st, now, release_reason, dedupe_suffix)
	timeline_log('SPELL_ACTION_STATE_RELEASE', spell_elapsed_fields(st, now, {
		release_reason = tostring(release_reason or ''),
		old_kind = tostring(st.last_send_kind or ''),
	}), ('spell_action_state_release:%s:%s'):format(tostring(st.last_action_name or ''), tostring(dedupe_suffix or release_reason or '')), 0.05)
end

local function emit_spell_token_overwrite_without_terminal(st, now, next_token, meta)
	meta = type(meta) == 'table' and meta or {}
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return
	end
	if (tonumber(st.action_token) or 0) <= 0 then
		return
	end
	if tostring(st.terminal_outcome or '') ~= '' then
		return
	end
	timeline_log('SPELL_ACTION_TOKEN_OVERWRITE_WITHOUT_TERMINAL', spell_elapsed_fields(st, now, {
		release_reason = 'token_overwrite_without_terminal',
		old_kind = tostring(st.last_send_kind or ''),
		last_local_message_id = tonumber(st.last_action_message_id) or 0,
		last_local_message_param = tonumber(st.last_action_message_param) or 0,
		prev_spell = tostring(st.last_action_name or ''),
		prev_provider = tostring(st.last_action_provider or ''),
		prev_target = tostring(st.last_target_name or ''),
		prev_target_id = tonumber(st.last_target_id) or 0,
		prev_action_token = tostring(tonumber(st.action_token) or 0),
		new_spell = tostring(meta.action_name or ''),
		new_provider = tostring(meta.provider or ''),
		new_target = tostring(meta.target_name or ''),
		new_target_id = tonumber(meta.target_id) or 0,
		new_action_token = tostring(tonumber(next_token) or 0),
	}), ('spell_token_overwrite_without_terminal:%s:%s'):format(tostring(st.last_action_name or ''), tostring(tonumber(st.action_token) or 0)), 0.05)
end

local function engage_bypass_kind(st, reason, now)
	local send_kind = tostring(st.last_send_kind or '')
	local timeline_reason = tostring(st.timeline_last_engage_block_reason or '')
	local post_spell_tail_until = tonumber(st.post_spell_tail_until) or 0
	if send_kind == 'ws' then
		return 'weaponskill'
	end
	if send_kind == 'ja' then
		return 'job_ability'
	end
	if send_kind == 'spell' then
		if reason == 'BLOCK_ACTION_ACTING' then
			return 'spell'
		end
		if timeline_reason == 'BLOCK_POST_SPELL_TAIL' or (post_spell_tail_until > 0 and now < post_spell_tail_until) then
			return 'post_spell_tail'
		end
		return 'cooldown'
	end
	return 'cooldown'
end

function M.action_state(scheduler)
	scheduler.action_state = scheduler.action_state or {}
	return scheduler.action_state
end

function M.action_mark_sent(scheduler, kind, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	st.action_token = (tonumber(st.action_token) or 0) + 1
	st.action_start = now
	st.action_end = now - 0.001
	st.last_action = now
	st.last_sent_at = now
	st.packet_start_at = 0
	st.action_delay = 0.6
	st.cooldown_until = math.max(tonumber(st.cooldown_until) or 0, now + 0.6)
	st.last_send_kind = tostring(kind or '')
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	st.high_level_spell_sent_logged = false
	st.high_level_spell_sent_at = 0
	st.spell_sent_log_missing_emitted = false
	st.timeout_release_at = 0
	st.accepted_completion_after_timeout = false
	st.terminal_outcome = ''
	st.terminal_action_token = ''
	st.terminal_at = 0
	st.terminal_message_id = 0
	st.terminal_message_param = 0
	st.terminal_since_sent_s = 0
	st.last_completion_ignore_reason = ''
end

function M.action_mark_engage_sent(scheduler, now_s)
	local st = M.action_state(scheduler)
	local now = now_s()
	st.action_token = (tonumber(st.action_token) or 0) + 1
	st.action_start = now
	st.action_end = now
	st.last_action = now
	st.last_sent_at = now
	st.packet_start_at = 0
	st.action_delay = ENGAGE_ACTION_TAIL_S
	st.cooldown_until = math.max(tonumber(st.cooldown_until) or 0, now + ENGAGE_ACTION_TAIL_S)
	st.last_send_kind = 'engage'
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
end

function M.action_mark_sent_with_meta(scheduler, kind, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	if tostring(kind or '') == 'spell' then
		emit_spell_token_overwrite_without_terminal(st, now, (tonumber(st.action_token) or 0) + 1, meta)
	end
	M.action_mark_sent(scheduler, kind, now_s)
	st = M.action_state(scheduler)
	now = now_s()
	st.last_action_name = tostring(meta.action_name or '')
	st.last_action_provider = tostring(meta.provider or '')
	st.last_def_action_type = tostring(meta.def_action_type or '')
	st.last_target_id = tonumber(meta.target_id) or 0
	st.last_target_name = tostring(meta.target_name or '')
	st.last_target_kind = tostring(meta.target_kind or '')
	st.last_action_source = tostring(meta.source or meta.caller or '')
	if (st.last_action_provider == 'defensive_internal' or st.last_action_provider == 'defensive_healbot')
		and st.last_def_action_type == 'cure' then
		st.defensive_cure_weave_until = now + 5.0
	end
	if tostring(kind or '') == 'spell' then
		timeline_log('SPELL_ACTION_MARK_SENT', spell_elapsed_fields(st, now, {
			source = tostring(meta.source or meta.caller or ''),
			high_level_spell_sent = '0',
		}), ('spell_action_mark_sent:%s:%s'):format(tostring(st.last_action_name or ''), tostring(tonumber(st.action_token) or 0)), 0.05)
	end
end

function M.note_high_level_spell_sent(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return false
	end
	st.high_level_spell_sent_logged = true
	st.high_level_spell_sent_at = now
	return true
end

function M.last_completion_ignore_reason(scheduler)
	local st = M.action_state(scheduler)
	return tostring(st.last_completion_ignore_reason or '')
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

function M.action_mark_packet_start(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	st.action_start = now
	st.packet_start_at = now
	note_missing_high_level_spell_sent(st, now, 'SPELL_PACKET_START_DETECTED')
	timeline_log('SPELL_PACKET_START', {
		spell = tostring(st.last_action_name or ''),
		provider = tostring(st.last_action_provider or ''),
		kind = tostring(st.last_send_kind or ''),
	}, ('spell_packet_start:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_PACKET_START_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		old_kind = tostring(st.last_send_kind or ''),
	}), ('spell_packet_start_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_CAST_START_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		old_kind = tostring(st.last_send_kind or ''),
		release_reason = 'cast_start',
	}), ('spell_cast_start_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
end

function M.note_local_spell_packet_start(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return false
	end
	if tonumber(st.packet_start_at) and tonumber(st.packet_start_at) > 0 then
		return false
	end
	st.packet_start_at = now
	note_missing_high_level_spell_sent(st, now, 'SPELL_PACKET_START_DETECTED')
	timeline_log('SPELL_PACKET_START_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or tonumber(st.last_action_message_id) or 0,
		old_kind = tostring(st.last_send_kind or ''),
	}), ('spell_packet_start_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_CAST_START_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or tonumber(st.last_action_message_id) or 0,
		old_kind = tostring(st.last_send_kind or ''),
		release_reason = 'cast_start',
	}), ('spell_cast_start_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	return true
end

function M.action_mark_packet_end(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	st.action_end = now
	timeline_log('SPELL_PACKET_END', {
		spell = tostring(st.last_action_name or ''),
		provider = tostring(st.last_action_provider or ''),
		kind = tostring(st.last_send_kind or ''),
	}, ('spell_packet_end:%s'):format(tostring(st.last_action_name or '')), 0.05)
end

function M.clear_local_defensive_spell_interruption(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	local last_send_kind = tostring(st.last_send_kind or '')
	local last_provider = tostring(st.last_action_provider or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then
		return false
	end
	local applied, prior = mark_terminal_outcome(st, now, 'cast_interrupted', meta)
	if not applied then
		st.last_completion_ignore_reason = 'already_terminal_' .. tostring(prior or '')
		log_late_completion_ignored(st, now, prior, 'cast_interrupted', meta)
		return false
	end
	st.action_end = now
	st.cooldown_until = now
	st.action_delay = 0
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	if (tonumber(st.timeout_release_at) or 0) > 0 then
		st.accepted_completion_after_timeout = true
	end
	note_missing_high_level_spell_sent(st, now, 'SPELL_CAST_INTERRUPTED_DETECTED')
	timeline_log('SPELL_CAST_INTERRUPTED_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		release_reason = 'cast_interrupted',
		old_kind = last_send_kind,
	}), ('spell_cast_interrupted_detected:def:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_INTERRUPTION_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		release_reason = 'cast_interrupted',
		old_kind = last_send_kind,
	}), ('spell_interrupt_detected:def:%s'):format(tostring(st.last_action_name or '')), 0.05)
	emit_spell_action_release(st, now, 'cast_interrupted', 'cast_interrupted')
	return true
end

function M.clear_local_spell_interruption(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	local last_send_kind = tostring(st.last_send_kind or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	local applied, prior = mark_terminal_outcome(st, now, 'cast_interrupted', meta)
	if not applied then
		st.last_completion_ignore_reason = 'already_terminal_' .. tostring(prior or '')
		log_late_completion_ignored(st, now, prior, 'cast_interrupted', meta)
		return false
	end
	st.action_end = now
	st.cooldown_until = now
	st.action_delay = 0
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	if (tonumber(st.timeout_release_at) or 0) > 0 then
		st.accepted_completion_after_timeout = true
	end
	note_missing_high_level_spell_sent(st, now, 'SPELL_CAST_INTERRUPTED_DETECTED')
	timeline_log('SPELL_FAILURE', {
		spell = tostring(st.last_action_name or ''),
		provider = tostring(st.last_action_provider or ''),
		kind = last_send_kind,
	}, ('spell_failure:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_INTERRUPTED', {
		spell = tostring(st.last_action_name or ''),
		provider = tostring(st.last_action_provider or ''),
		kind = last_send_kind,
	}, ('spell_interrupted:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_CAST_INTERRUPTED_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		release_reason = 'cast_interrupted',
		old_kind = last_send_kind,
	}), ('spell_cast_interrupted_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_INTERRUPTION_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		release_reason = 'cast_interrupted',
		old_kind = last_send_kind,
	}), ('spell_interrupt_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	emit_spell_action_release(st, now, 'cast_interrupted', 'cast_interrupted')
	return true
end

function M.clear_local_brd_spell_failure(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	if tostring(st.last_send_kind or '') ~= 'spell' or tostring(st.last_action_provider or '') ~= 'maintenance_brd' then
		return false
	end
	if meta.require_prestart == true and (tonumber(st.packet_start_at) or 0) > 0 then
		return false
	end
	local outcome = tostring(meta.terminal_outcome or 'server_reject_unable_cast')
	local applied, prior = mark_terminal_outcome(st, now, outcome, meta)
	if not applied then
		st.last_completion_ignore_reason = 'already_terminal_' .. tostring(prior or '')
		return false
	end
	st.action_end = now
	st.cooldown_until = now
	st.action_delay = 0
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = 0
	st.post_spell_tail_until = 0
	timeline_log('SPELL_PROVIDER_FAILURE', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		release_reason = outcome,
		old_kind = 'spell',
	}), ('spell_server_rejected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	emit_spell_action_release(st, now, outcome, outcome)
	return true
end

function M.clear_local_defensive_spell_success(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	local last_send_kind = tostring(st.last_send_kind or '')
	local last_provider = tostring(st.last_action_provider or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then
		return false
	end
	local applied, prior = mark_terminal_outcome(st, now, 'cast_complete', meta)
	if not applied then
		st.last_completion_ignore_reason = 'already_terminal_' .. tostring(prior or '')
		log_late_completion_ignored(st, now, prior, 'cast_complete', meta)
		return false
	end
	st.action_end = now
	st.cooldown_until = now + SPELL_SUCCESS_TAIL_S
	st.action_delay = SPELL_SUCCESS_TAIL_S
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = now
	st.post_spell_tail_until = now + SPELL_SUCCESS_TAIL_S
	if (tonumber(st.timeout_release_at) or 0) > 0 then
		st.accepted_completion_after_timeout = true
	end
	local release_reason = tostring(meta.release_reason or meta.completion_reason or 'cast_complete')
	note_missing_high_level_spell_sent(st, now, 'SPELL_CAST_COMPLETE_DETECTED')
	timeline_log('SPELL_CAST_COMPLETE_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		param = tonumber(meta.message_param) or 0,
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		completion_reason = tostring(meta.completion_reason or release_reason),
		release_reason = release_reason,
		old_kind = last_send_kind,
		tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
	}), ('spell_cast_complete_detected:def:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_SUCCESS_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		param = tonumber(meta.message_param) or 0,
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		completion_reason = tostring(meta.completion_reason or release_reason),
		release_reason = release_reason,
		old_kind = last_send_kind,
		tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
	}), ('spell_success_detected:def:%s'):format(tostring(st.last_action_name or '')), 0.05)
	emit_spell_action_release(st, now, release_reason, release_reason)
	timeline_log('POST_SPELL_TAIL_START', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		param = tonumber(meta.message_param) or 0,
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		completion_reason = tostring(meta.completion_reason or release_reason),
		release_reason = release_reason,
		old_kind = last_send_kind,
		tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
	}), ('post_spell_tail_start:def:%s'):format(tostring(st.last_action_name or '')), 0.05)
	return true
end

function M.clear_local_spell_success(scheduler, now_s, meta)
	local st = M.action_state(scheduler)
	local now = now_s()
	meta = type(meta) == 'table' and meta or {}
	local last_send_kind = tostring(st.last_send_kind or '')
	if last_send_kind ~= 'spell' then
		return false
	end
	local applied, prior = mark_terminal_outcome(st, now, 'cast_complete', meta)
	if not applied then
		st.last_completion_ignore_reason = 'already_terminal_' .. tostring(prior or '')
		log_late_completion_ignored(st, now, prior, 'cast_complete', meta)
		return false
	end
	st.action_end = now
	st.cooldown_until = now + SPELL_SUCCESS_TAIL_S
	st.action_delay = SPELL_SUCCESS_TAIL_S
	st.last_action = now
	st.last_acting_state = false
	st.post_spell_tail_started_at = now
	st.post_spell_tail_until = now + SPELL_SUCCESS_TAIL_S
	if (tonumber(st.timeout_release_at) or 0) > 0 then
		st.accepted_completion_after_timeout = true
	end
	local release_reason = tostring(meta.release_reason or meta.completion_reason or 'cast_complete')
	note_missing_high_level_spell_sent(st, now, 'SPELL_CAST_COMPLETE_DETECTED')
	timeline_log('SPELL_SUCCESS', {
		spell = tostring(st.last_action_name or ''),
		provider = tostring(st.last_action_provider or ''),
		kind = last_send_kind,
	}, ('spell_success:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_CAST_COMPLETE_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		param = tonumber(meta.message_param) or 0,
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		completion_reason = tostring(meta.completion_reason or release_reason),
		release_reason = release_reason,
		old_kind = last_send_kind,
		tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
	}), ('spell_cast_complete_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	timeline_log('SPELL_SUCCESS_DETECTED', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		param = tonumber(meta.message_param) or 0,
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		completion_reason = tostring(meta.completion_reason or release_reason),
		release_reason = release_reason,
		old_kind = last_send_kind,
		tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
	}), ('spell_success_detected:%s'):format(tostring(st.last_action_name or '')), 0.05)
	emit_spell_action_release(st, now, release_reason, release_reason)
	timeline_log('POST_SPELL_TAIL_START', spell_elapsed_fields(st, now, {
		message_id = tonumber(meta.message_id) or 0,
		param = tonumber(meta.message_param) or 0,
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		completion_reason = tostring(meta.completion_reason or release_reason),
		release_reason = release_reason,
		old_kind = last_send_kind,
		tail_s = ('%.2f'):format(SPELL_SUCCESS_TAIL_S),
	}), ('post_spell_tail_start:%s'):format(tostring(st.last_action_name or '')), 0.05)
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
	if meta.player_dead == true then
		return true, 'BLOCK_PLAYER_DEAD'
	end
	if tonumber(meta.player_status) == 1 then
		return true, 'BLOCK_ALREADY_ENGAGED'
	end
	if meta.target_selected ~= true or meta.target_valid ~= true then
		return true, 'BLOCK_INVALID_TARGET'
	end
	local send_kind = tostring(st.last_send_kind or '')
	local status_value = tonumber(meta.player_status) or 0
	local timeline_log = rawget(globals, 'UC_ACTION_TIMELINE_LOG')
	if send_kind == 'engage' then
		return true, reason
	end
	local bypass_kind = engage_bypass_kind(st, tostring(reason or ''), now)
	if type(timeline_log) == 'function' then
		pcall(timeline_log, 'ENGAGE_ACTION_STATE_BYPASS', {
			tid = tonumber(meta.target_id) or 0,
			name = tostring(meta.target_name or ''),
			status = status_value,
			kind = bypass_kind,
			reason = tostring(reason or 'BLOCK_ACTION_STATE'),
			retry_in_s = tostring(meta.retry_in_s or ''),
			retry_count = tostring(meta.retry_count or ''),
			dispatch_method = tostring(meta.dispatch_method or ''),
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
	local sent_at = tonumber(st.last_sent_at) or 0
	local packet_start_at = tonumber(st.packet_start_at) or 0
	local timeout = tonumber(st.lag_timeout) or 8.0
	if send_kind == 'ja' then
		timeout = tonumber(st.ja_lag_timeout) or 1.0
	end
	if start_at > 0 and end_at < start_at and (now - start_at) > timeout then
		if send_kind == 'spell' then
			local applied, prior = mark_terminal_outcome(st, now, 'timeout', {
				message_id = tonumber(st.last_action_message_id) or 0,
				message_param = tonumber(st.last_action_message_param) or 0,
			})
			if applied then
				note_missing_high_level_spell_sent(st, now, 'SPELL_TIMEOUT_RELEASE')
				st.timeout_release_at = now
				timeline_log('SPELL_TIMEOUT_RELEASE', spell_elapsed_fields(st, now, {
					release_reason = 'timeout',
					old_kind = send_kind,
					message_id = tonumber(st.last_action_message_id) or 0,
					packet_start_detected = (packet_start_at > 0) and '1' or '0',
				last_local_message_id = tonumber(st.last_action_message_id) or 0,
				last_local_message_param = tonumber(st.last_action_message_param) or 0,
				last_ignored_message_id = tonumber(st.last_ignored_action_message_id) or 0,
				last_ignored_message_param = tonumber(st.last_ignored_action_message_param) or 0,
				accepted_completion_after_timeout = st.accepted_completion_after_timeout and '1' or '0',
			}), ('spell_timeout_release:%s'):format(tostring(st.last_action_name or '')), 0.25)
				if type(scheduler.emit_spell_lifecycle_timeout_candidate_summary) == 'function' then
					scheduler.emit_spell_lifecycle_timeout_candidate_summary(scheduler, now_s, st)
				end
				emit_spell_action_release(st, now, 'timeout', 'timeout')
			else
				st.last_completion_ignore_reason = 'already_terminal_' .. tostring(prior or '')
			end
		end
		st.action_end = now
		end_at = now
	end
	local acting = end_at < start_at
	if send_kind == 'spell' and sent_at > 0 and acting and (now - sent_at) >= 5.0 then
		note_missing_high_level_spell_sent(st, now, 'SPELL_ACTION_STATE_LONG_HOLD')
		timeline_log('SPELL_ACTION_STATE_LONG_HOLD', spell_elapsed_fields(st, now, {
			release_reason = 'long_hold',
			packet_start_detected = (packet_start_at > 0) and '1' or '0',
			message_id = tonumber(st.last_action_message_id) or 0,
		}), ('spell_long_hold:%s:%s'):format(tostring(st.last_action_name or ''), tostring(tonumber(st.action_token) or 0)), 2.0)
	end
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
		if send_kind == 'spell' then
			st.timeline_last_block_reason = 'BLOCK_SPELL_CASTING'
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
		if tostring(st.last_send_kind or '') == 'spell' then
			st.timeline_last_block_reason = timeline_reason('cooldown')
		end
		return true, 'BLOCK_ACTION_COOLDOWN'
	end
	do
		local last_reason = tostring(st.timeline_last_block_reason or '')
		if last_reason ~= '' and tostring(st.last_send_kind or '') == 'spell' then
			if last_reason == 'BLOCK_POST_SPELL_TAIL' and (tonumber(st.post_spell_tail_started_at) or 0) > 0 then
				timeline_log('POST_SPELL_TAIL_END', spell_elapsed_fields(st, now, {
					release_reason = last_reason,
					old_kind = tostring(st.last_send_kind or ''),
				}), ('post_spell_tail_end:%s'):format(tostring(st.last_action_name or '')), 0.05)
				st.post_spell_tail_started_at = 0
				st.post_spell_tail_until = 0
			end
			emit_spell_action_release(st, now, last_reason, last_reason)
			st.timeline_last_block_reason = ''
		end
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
