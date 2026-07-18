local res = require('resources')
local brd_song_options = require('uc_brd_song_options')

local M = {}

local SONG_START_TIMEOUT_S = 2.0
local SONG_CAST_TIMEOUT_S = 20.0
local SONG_CONFIRM_TIMEOUT_S = 2.0
local REFRESH_BASE_LEAD_S = 8.0
local REFRESH_PER_SONG_LEAD_S = 4.0
local TIMER_MATCH_TOLERANCE = 60
local SUCCESS_MESSAGES = {
	[205] = true,
	[230] = true,
	[266] = true,
	[280] = true,
}

local JA = {
	nightingale = { name = 'Nightingale', buff_id = 347 },
	troubadour = { name = 'Troubadour', buff_id = 348 },
	marcato = { name = 'Marcato', buff_id = 231 },
	clarion = { name = 'Clarion Call', buff_id = 499 },
}

local function initial_server_time_offset(epoch)
	local now = tonumber(epoch) or os.time()
	local vana_time = now - 1009810800
	return math.floor(now - (vana_time * 60 % 0x100000000) / 60)
end

local state = {
	snapshot = nil,
	snapshot_at = 0,
	snapshot_source = 'none',
	pending = nil,
	owners = {},
	force = nil,
	nitro_armed = false,
	nitro_was_active = false,
	marcato_reservation = '',
	config_signature = '',
	identity = '',
	last_blocker = 'not_evaluated',
	last_transition = '',
	trace_armed = false,
	trace_lines = {},
	manual_capture = nil,
	log_enabled = false,
	log_path = '',
	log_error = '',
	server_time_offset = initial_server_time_offset(os.time()),
	server_time_source = 'epoch_estimate',
	scheduler_failure = nil,
	action_lane_reserved = false,
	action_lane_reason = '',
}

local spell_by_name = nil

local function clone_array(values)
	local out = {}
	if type(values) == 'table' then
		for i = 1, #values do
			out[i] = values[i]
		end
	end
	return out
end

local function sorted_copy(values)
	local out = clone_array(values)
	table.sort(out, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return out
end

local function join(values)
	local out = {}
	for i = 1, #(values or {}) do
		out[#out + 1] = tostring(values[i])
	end
	return table.concat(out, ',')
end

local function log_value(value)
	if type(value) == 'table' then
		return '[' .. join(value) .. ']'
	end
	return tostring(value == nil and '' or value):gsub('[\r\n\t]', ' ')
end

local function diagnostic_log(event, fields)
	if state.log_enabled ~= true then
		return false
	end
	local keys = {}
	for key in pairs(type(fields) == 'table' and fields or {}) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	local parts = { os.date('%Y-%m-%d %H:%M:%S'), tostring(event or '') }
	for i = 1, #keys do
		local key = keys[i]
		parts[#parts + 1] = key .. '=' .. log_value(fields[key])
	end
	local fh, err = io.open(state.log_path, 'a')
	if not fh then
		state.log_error = tostring(err or 'open_failed')
		return false
	end
	fh:write(table.concat(parts, '\t') .. '\n')
	fh:close()
	return true
end

local function reserve_action_lane(reason)
	state.action_lane_reserved = true
	state.action_lane_reason = tostring(reason or 'brd_sequence')
end

local function release_action_lane(reason)
	state.action_lane_reserved = false
	state.action_lane_reason = tostring(reason or '')
end

local function owner_summary()
	local names = {}
	for name in pairs(state.owners) do
		names[#names + 1] = name
	end
	table.sort(names)
	local out = {}
	for i = 1, #names do
		local owner = state.owners[names[i]]
		out[#out + 1] = ('%s:%d:%s:%s'):format(
			names[i],
			tonumber(owner.status_id) or 0,
			tostring(owner.endtime or 0),
			join(owner.recipients or {})
		)
	end
	return table.concat(out, '|')
end

local function trace(line)
	if state.trace_armed ~= true then
		return
	end
	state.trace_lines[#state.trace_lines + 1] = tostring(line or '')
end

local function finish_trace(line)
	trace(line)
	state.trace_armed = false
end

local function ensure_spell_index()
	if spell_by_name ~= nil then
		return spell_by_name
	end
	spell_by_name = {}
	for id, spell in pairs(res.spells or {}) do
		if type(spell) == 'table' and type(spell.en) == 'string' and spell.en ~= '' then
			spell_by_name[spell.en] = {
				id = tonumber(spell.id) or tonumber(id) or 0,
				name = spell.en,
				status_id = tonumber(spell.status) or 0,
				type = tostring(spell.type or ''),
				targets = spell.targets,
			}
		end
	end
	return spell_by_name
end

local function get_song(name)
	return ensure_spell_index()[tostring(name or '')]
end

local function get_song_by_id(spell_id)
	for _, spell in pairs(ensure_spell_index()) do
		if tonumber(spell.id) == tonumber(spell_id) then
			return spell
		end
	end
	return nil
end

local function is_general_song(spell)
	return type(spell) == 'table'
		and spell.id > 0
		and spell.status_id > 0
		and spell.type == 'BardSong'
		and brd_song_options.is_self_target(spell.targets)
end

local function has_buff(player, buff_id)
	for _, id in ipairs(type(player) == 'table' and player.buffs or {}) do
		if tonumber(id) == tonumber(buff_id) then
			return true
		end
	end
	return false
end

local function family_endtimes(snapshot, status_id)
	local family = type(snapshot) == 'table' and snapshot[tonumber(status_id)] or nil
	if type(family) ~= 'table' then
		return {}
	end
	return sorted_copy(family.endtimes)
end

local function snapshot_song_count(snapshot)
	local song_statuses = {}
	for _, spell in pairs(ensure_spell_index()) do
		if is_general_song(spell) then
			song_statuses[spell.status_id] = true
		end
	end
	local count = 0
	for status_id, family in pairs(type(snapshot) == 'table' and snapshot or {}) do
		if song_statuses[tonumber(status_id)] and type(family) == 'table' then
			count = count + (tonumber(family.count) or #(family.endtimes or {}))
		end
	end
	return count
end

local function multiset_delta(before, after)
	local unmatched_before = sorted_copy(before)
	local added = {}
	for i = 1, #after do
		local value = tonumber(after[i]) or 0
		local best_index = nil
		local best_distance = nil
		for j = 1, #unmatched_before do
			local distance = math.abs(value - (tonumber(unmatched_before[j]) or 0))
			if distance <= TIMER_MATCH_TOLERANCE and (best_distance == nil or distance < best_distance) then
				best_index = j
				best_distance = distance
			end
		end
		if best_index ~= nil then
			table.remove(unmatched_before, best_index)
		else
			added[#added + 1] = value
		end
	end
	return added, unmatched_before
end

local function remove_owner_by_endtime(status_id, endtime)
	for name, owner in pairs(state.owners) do
		if tonumber(owner.status_id) == tonumber(status_id)
			and math.abs((tonumber(owner.endtime) or 0) - (tonumber(endtime) or 0)) <= TIMER_MATCH_TOLERANCE then
			state.owners[name] = nil
			return name
		end
	end
	return ''
end

local function prune_owners()
	local names_by_status = {}
	for name, owner in pairs(state.owners) do
		local status_id = tonumber(owner.status_id) or 0
		names_by_status[status_id] = names_by_status[status_id] or {}
		names_by_status[status_id][#names_by_status[status_id] + 1] = name
	end
	for status_id, names in pairs(names_by_status) do
		table.sort(names)
		local unmatched = family_endtimes(state.snapshot, status_id)
		for i = 1, #names do
			local name = names[i]
			local owner = state.owners[name]
			local best_index = nil
			local best_distance = nil
			for j = 1, #unmatched do
				local distance = math.abs((tonumber(owner.endtime) or 0) - (tonumber(unmatched[j]) or 0))
				if distance <= TIMER_MATCH_TOLERANCE and (best_distance == nil or distance < best_distance) then
					best_index = j
					best_distance = distance
				end
			end
			if best_index ~= nil then
				owner.endtime = tonumber(unmatched[best_index]) or 0
				table.remove(unmatched, best_index)
			else
			diagnostic_log('OWNER_PRUNE', {
				name = name,
				status_id = status_id,
				owner_endtime = owner.endtime,
				active_endtimes = family_endtimes(state.snapshot, status_id),
			})
			state.owners[name] = nil
			end
		end
	end
end

local function server_now_raw(epoch)
	local now = tonumber(epoch) or os.time()
	return (now - state.server_time_offset) * 60
end

local function remaining_seconds(endtime, epoch)
	return ((tonumber(endtime) or 0) - server_now_raw(epoch)) / 60
end

local function config_signature(config, player)
	return table.concat({
		tostring(config.enabled),
		join(config.songs),
		join(config.dummy_songs),
		tostring(config.use_nitro),
		tostring(config.use_clarion_call),
		tostring(config.use_marcato),
		tostring(config.marcato_song),
		tostring(player and player.main_job or ''),
		tostring(player and player.sub_job or ''),
	}, '|')
end

local function effective_config(config, player)
	local limit = #config.songs
	if tostring(player and player.main_job or '') == 'BRD' and config.use_clarion_call ~= true then
		limit = math.min(limit, 4)
	end
	if limit == #config.songs then
		return config
	end
	local songs = {}
	for i = 1, limit do
		songs[i] = config.songs[i]
	end
	return {
		enabled = config.enabled,
		songs = songs,
		dummy_songs = config.dummy_songs,
		use_nitro = config.use_nitro,
		use_clarion_call = config.use_clarion_call,
		use_marcato = config.use_marcato,
		marcato_song = config.marcato_song,
	}
end

local function validate_config(config, player)
	if type(config) ~= 'table' then
		return false, 'missing_config'
	end
	if type(config.enabled) ~= 'boolean' or type(config.songs) ~= 'table' or type(config.dummy_songs) ~= 'table' then
		return false, 'invalid_config_shape'
	end
	if type(config.use_nitro) ~= 'boolean' or type(config.use_clarion_call) ~= 'boolean'
		or type(config.use_marcato) ~= 'boolean' or type(config.marcato_song) ~= 'string' then
		return false, 'invalid_config_shape'
	end
	local main_job = tostring(player and player.main_job or '')
	local sub_job = tostring(player and player.sub_job or '')
	if main_job ~= 'BRD' and sub_job ~= 'BRD' then
		return false, 'job_not_brd'
	end
	if #config.songs == 0 then
		return false, 'no_songs_configured'
	end
	if main_job ~= 'BRD' and #config.songs > 1 then
		return false, 'subjob_song_limit'
	end
	if main_job == 'BRD' and #config.songs > 5 then
		return false, 'main_job_song_limit'
	end
	local seen = {}
	for i = 1, #config.songs do
		local name = config.songs[i]
		if type(name) ~= 'string' or name == '' or not is_general_song(get_song(name)) then
			return false, 'invalid_song:' .. tostring(name)
		end
		if seen[name] then
			return false, 'duplicate_song:' .. name
		end
		seen[name] = true
	end
	local dummy_seen = {}
	for i = 1, #config.dummy_songs do
		local name = config.dummy_songs[i]
		if type(name) ~= 'string' or name == '' or not is_general_song(get_song(name)) then
			return false, 'invalid_dummy_song:' .. tostring(name)
		end
		if seen[name] or dummy_seen[name] then
			return false, 'duplicate_dummy_song:' .. name
		end
		dummy_seen[name] = true
	end
	if main_job == 'BRD' then
		local effective_song_count = config.use_clarion_call and #config.songs or math.min(#config.songs, 4)
		local additional = math.max(0, effective_song_count - 2)
		if #config.dummy_songs < additional then
			return false, 'insufficient_dummy_songs'
		end
	else
		if config.use_nitro or config.use_clarion_call or config.use_marcato then
			return false, 'main_job_abilities_unavailable'
		end
	end
	if config.use_marcato then
		if config.marcato_song == '' or seen[config.marcato_song] ~= true then
			return false, 'invalid_marcato_song'
		end
	elseif config.marcato_song ~= '' then
		return false, 'marcato_song_without_option'
	end
	return true, ''
end

local function reset_runtime(reason, preserve_trace)
	diagnostic_log('RESET', {
		reason = reason,
		pending = type(state.pending) == 'table' and state.pending.name or '',
		owners = owner_summary(),
	})
	state.snapshot = nil
	state.snapshot_at = 0
	state.snapshot_source = 'none'
	state.pending = nil
	state.scheduler_failure = nil
	release_action_lane(reason)
	state.owners = {}
	state.force = nil
	state.nitro_armed = false
	state.nitro_was_active = false
	state.marcato_reservation = ''
	state.last_blocker = tostring(reason or 'reset')
	state.last_transition = ''
	state.manual_capture = nil
	if preserve_trace ~= true then
		state.trace_armed = false
		state.trace_lines = {}
	end
end

function M.reset(reason)
	reset_runtime(reason, false)
	state.config_signature = ''
	state.identity = ''
end

local function proposal(action_type, action_name, reason_code, urgency, detail)
	reserve_action_lane(reason_code)
	state.last_blocker = ''
	diagnostic_log('PROPOSAL', {
		action_type = action_type,
		action_name = action_name,
		reason = reason_code,
		urgency = urgency,
		snapshot_count = snapshot_song_count(state.snapshot),
		owners = owner_summary(),
	})
	return {
		action_type = action_type,
		action_name = action_name,
		reason_code = reason_code,
		urgency = urgency,
		detail = detail or {},
	}
end

local function ready(ctx, name, expected_kind)
	if type(ctx.action_ready) ~= 'function' then
		return false, 'missing_action_ready'
	end
	local ok, reason, kind = ctx.action_ready(name, tonumber(ctx.player and ctx.player.id) or 0)
	if kind ~= expected_kind then
		return false, 'wrong_action_kind'
	end
	return ok == true, tostring(reason or '')
end

local function start_force_generation(config)
	local complete = {}
	state.force = { complete = complete, started_at = os.time() }
	reserve_action_lane('brd_nitro_force')
	state.last_transition = 'nitro_force_started'
	trace('force:start songs=' .. join(config.songs))
end

local function next_force_song(config)
	if type(state.force) ~= 'table' then
		return ''
	end
	for i = 1, #config.songs do
		local name = config.songs[i]
		if state.force.complete[name] ~= true then
			return name
		end
	end
	state.force = nil
	state.last_transition = 'nitro_force_complete'
	return ''
end

local function mark_song_confirmed(name, required_complete)
	if type(state.force) == 'table' and required_complete then
		state.force.complete[name] = true
	end
	if state.marcato_reservation == name and required_complete then
		state.marcato_reservation = ''
	end
end

local function recipients_cover(required, actual)
	local have = {}
	for i = 1, #(actual or {}) do
		have[tonumber(actual[i]) or 0] = true
	end
	for i = 1, #(required or {}) do
		if have[tonumber(required[i]) or 0] ~= true then
			return false
		end
	end
	return true
end

local function resolve_pending_from_snapshot()
	local pending = state.pending
	if type(pending) ~= 'table' or pending.success ~= true or type(state.snapshot) ~= 'table' then
		return false
	end
	local after = family_endtimes(state.snapshot, pending.status_id)
	local added, removed = multiset_delta(pending.before_endtimes, after)
	diagnostic_log('TIMER_DELTA', {
		song = pending.name,
		status_id = pending.status_id,
		before = pending.before_endtimes,
		after = after,
		added = added,
		removed = removed,
		recipients = pending.recipients,
		required_recipients = pending.required_recipients,
	})
	trace(('063: status=%d before=[%s] after=[%s] added=[%s] removed=[%s]'):format(
		pending.status_id,
		join(pending.before_endtimes),
		join(after),
		join(added),
		join(removed)
	))
	if #added == 0 then
		diagnostic_log('CONFIRM_WAIT_NO_DELTA', { song = pending.name, status_id = pending.status_id })
		return false
	end
	if #added ~= 1 or #removed > 1 then
		state.last_blocker = 'ambiguous_timer_delta'
		finish_trace('resolve:ambiguous_timer_delta')
		state.pending = nil
		diagnostic_log('CONFIRM_REJECT_AMBIGUOUS', {
			song = pending.name,
			added = added,
			removed = removed,
		})
		return false
	end
	local replaced = ''
	if #removed == 1 then
		replaced = remove_owner_by_endtime(pending.status_id, removed[1])
	end
	state.owners[pending.name] = {
		status_id = pending.status_id,
		endtime = added[1],
		recipients = pending.recipients,
		confirmed_at = os.time(),
		is_dummy = pending.is_dummy,
	}
	local required_complete = recipients_cover(pending.required_recipients, pending.recipients)
	diagnostic_log('OWNER_CONFIRM', {
		song = pending.name,
		status_id = pending.status_id,
		endtime = added[1],
		replaced = replaced,
		recipients = pending.recipients,
		required_recipients = pending.required_recipients,
		required_complete = required_complete,
		owners = owner_summary(),
	})
	mark_song_confirmed(pending.name, required_complete)
	state.last_transition = ('confirmed:%s replaced:%s'):format(pending.name, replaced)
	finish_trace(('resolve:confirmed song=%s endtime=%d replaced=%s recipients=%s'):format(
		pending.name,
		added[1],
		replaced,
		join(pending.recipients)
	))
	state.pending = nil
	return true
end

function M.on_status_snapshot(snapshot, now)
	if type(snapshot) ~= 'table' then
		return false
	end
	local capture = state.manual_capture
	if type(capture) == 'table' and capture.phase == 'await_063' then
		local family = type(snapshot[capture.status_id]) == 'table' and snapshot[capture.status_id] or {}
		state.trace_lines[#state.trace_lines + 1] = ('capture 063 song=%s status=%d count=%d endtimes=[%s]'):format(
			capture.song,
			capture.status_id,
			tonumber(family.count) or 0,
			join(family.endtimes or {})
		)
		state.last_transition = 'manual_capture_complete:' .. capture.song
		state.manual_capture = nil
	end
	state.snapshot = snapshot
	state.snapshot_at = tonumber(now) or os.time()
	state.snapshot_source = 'packet_063'
	local pending_status = type(state.pending) == 'table' and state.pending.status_id or 0
	diagnostic_log('SNAPSHOT_063', {
		now = now,
		song_count = snapshot_song_count(snapshot),
		pending = type(state.pending) == 'table' and state.pending.name or '',
		pending_status = pending_status,
		pending_endtimes = pending_status > 0 and family_endtimes(snapshot, pending_status) or {},
		owners_before_prune = owner_summary(),
	})
	local resolved = resolve_pending_from_snapshot()
	prune_owners()
	return resolved
end

function M.on_server_clock(timestamp, time_offset, now)
	local packet_timestamp = tonumber(timestamp)
	local packet_time_offset = tonumber(time_offset)
	local epoch = tonumber(now) or os.time()
	if packet_timestamp == nil or packet_time_offset == nil then
		return false
	end
	local vana_time = packet_timestamp * 60 - math.floor(packet_time_offset)
	state.server_time_offset = math.floor(epoch - (vana_time % 0x100000000) / 60)
	state.server_time_source = 'packet_037'
	diagnostic_log('SERVER_CLOCK', {
		timestamp = packet_timestamp,
		time_offset = packet_time_offset,
		server_time_offset = state.server_time_offset,
	})
	return true
end

function M.note_dispatch(action, action_token, now)
	if type(action) ~= 'table' or tostring(action.action_type or '') ~= 'spell' then
		return true
	end
	local spell = get_song(action.action_name)
	if not is_general_song(spell) or type(state.snapshot) ~= 'table' then
		state.last_blocker = type(state.snapshot) == 'table' and 'dispatched_invalid_song' or 'no_status_snapshot'
		return false
	end
	state.pending = {
		name = spell.name,
		spell_id = spell.id,
		status_id = spell.status_id,
		token = tostring(action_token or ''),
		dispatched_at = tonumber(now) or os.time(),
		phase = 'awaiting_start',
		before_endtimes = family_endtimes(state.snapshot, spell.status_id),
		before_count = snapshot_song_count(state.snapshot),
		recipients = {},
		success = false,
		is_dummy = type(action.detail) == 'table' and action.detail.is_dummy == true,
		required_recipients = type(action.detail) == 'table' and clone_array(action.detail.required_recipient_ids) or {},
	}
	diagnostic_log('DISPATCH', {
		now = now,
		token = state.pending.token,
		song = state.pending.name,
		spell_id = state.pending.spell_id,
		status_id = state.pending.status_id,
		before_endtimes = state.pending.before_endtimes,
		before_count = state.pending.before_count,
		required_recipients = state.pending.required_recipients,
		owners = owner_summary(),
	})
	trace(('dispatch: token=%s song=%s spell_id=%d status=%d before=[%s]'):format(
		state.pending.token,
		spell.name,
		spell.id,
		spell.status_id,
		join(state.pending.before_endtimes)
	))
	return true
end

function M.on_action(act, player_id, now)
	local capture = state.manual_capture
	if type(capture) == 'table' and capture.phase == 'await_028'
		and type(act) == 'table' and tonumber(act.actor_id) == tonumber(player_id)
		and tonumber(act.category) == 4 then
		local captured_spell = get_song_by_id(act.param)
		if is_general_song(captured_spell) then
			local results = {}
			for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
				for _, result in ipairs(type(target.actions) == 'table' and target.actions or {}) do
					results[#results + 1] = ('%s:%d:%d'):format(
						tostring(target.id or 0),
						tonumber(result.message) or 0,
						tonumber(result.param) or 0
					)
				end
			end
			capture.phase = 'await_063'
			capture.song = captured_spell.name
			capture.spell_id = captured_spell.id
			capture.status_id = captured_spell.status_id
			capture.action_at = tonumber(now) or os.time()
			state.trace_lines[#state.trace_lines + 1] = ('capture 028 song=%s spell_id=%d status=%d results=[%s]'):format(
				capture.song,
				capture.spell_id,
				capture.status_id,
				table.concat(results, ',')
			)
			state.last_transition = 'manual_capture_awaiting_063:' .. capture.song
		end
	end
	local pending = state.pending
	if type(pending) ~= 'table' or type(act) ~= 'table' then
		return false
	end
	local raw_results = {}
	for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
		for _, result in ipairs(type(target.actions) == 'table' and target.actions or {}) do
			raw_results[#raw_results + 1] = ('%s:%d:%d'):format(
				tostring(target.id or 0),
				tonumber(result.message) or 0,
				tonumber(result.param) or 0
			)
		end
	end
	diagnostic_log('ACTION_028', {
		now = now,
		actor_id = act.actor_id,
		player_id = player_id,
		category = act.category,
		action_param = act.param,
		pending_song = pending.name,
		pending_spell_id = pending.spell_id,
		results = raw_results,
	})
	if tonumber(act.actor_id) == tonumber(player_id) and tonumber(act.category) == 8 then
		for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
			for _, result in ipairs(type(target.actions) == 'table' and target.actions or {}) do
				if tonumber(result.message) == 327 and tonumber(result.param) == pending.spell_id then
					pending.started_at = tonumber(now) or os.time()
					pending.phase = 'casting'
					diagnostic_log('ACTION_START', {
						song = pending.name,
						spell_id = pending.spell_id,
						started_at = pending.started_at,
					})
					return true
				end
			end
		end
	end
	if tonumber(act.actor_id) ~= tonumber(player_id) or tonumber(act.category) ~= 4 or tonumber(act.param) ~= pending.spell_id then
		diagnostic_log('ACTION_IGNORE_PENDING_MISMATCH', { pending_song = pending.name })
		return false
	end
	local recipients = {}
	local message_trace = {}
	for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
		local target_ok = false
		for _, result in ipairs(type(target.actions) == 'table' and target.actions or {}) do
			local message_id = tonumber(result.message) or 0
			local param = tonumber(result.param) or 0
			message_trace[#message_trace + 1] = ('%s:%d:%d'):format(tostring(target.id or 0), message_id, param)
			if SUCCESS_MESSAGES[message_id] and param == pending.status_id then
				target_ok = true
			end
		end
		if target_ok then
			recipients[#recipients + 1] = tonumber(target.id) or 0
		end
	end
	trace(('028: song=%s targets=[%s] results=[%s]'):format(pending.name, join(recipients), join(message_trace)))
	if #recipients == 0 then
		state.last_blocker = 'no_successful_recipients'
		finish_trace('resolve:no_successful_recipients')
		state.pending = nil
		diagnostic_log('ACTION_REJECT_NO_RECIPIENTS', { song = pending.name, results = message_trace })
		return false
	end
	local local_success = false
	for i = 1, #recipients do
		if tonumber(recipients[i]) == tonumber(player_id) then
			local_success = true
			break
		end
	end
	if not local_success then
		state.last_blocker = 'no_local_timer_recipient'
		finish_trace('resolve:no_local_timer_recipient')
		state.pending = nil
		diagnostic_log('ACTION_REJECT_NO_LOCAL', { song = pending.name, recipients = recipients })
		return false
	end
	pending.success = true
	pending.success_at = tonumber(now) or os.time()
	pending.phase = 'awaiting_snapshot'
	pending.recipients = recipients
	diagnostic_log('ACTION_SUCCESS', {
		song = pending.name,
		recipients = recipients,
		required_recipients = pending.required_recipients,
		results = message_trace,
	})
	return resolve_pending_from_snapshot()
end

local function owner_covers(name, required_recipients)
	local owner = state.owners[name]
	return type(owner) == 'table' and recipients_cover(required_recipients, owner.recipients)
end

local function next_missing_base_song(config, base_count, required_recipients)
	local limit = math.min(base_count, #config.songs)
	for i = 1, limit do
		if not owner_covers(config.songs[i], required_recipients) then
			return config.songs[i]
		end
	end
	return ''
end

local function next_missing_dummy(config, required)
	for i = 1, required do
		if state.owners[config.dummy_songs[i]] == nil then
			return config.dummy_songs[i]
		end
	end
	return ''
end

local function next_missing_final(config, required_recipients)
	for i = 1, #config.songs do
		if not owner_covers(config.songs[i], required_recipients) then
			return config.songs[i]
		end
	end
	return ''
end

local function urgent_song(config, now_epoch)
	local best_name = ''
	local best_remaining = nil
	local refresh_lead = REFRESH_BASE_LEAD_S + (#config.songs * REFRESH_PER_SONG_LEAD_S)
	for i = 1, #config.songs do
		local name = config.songs[i]
		local owner = state.owners[name]
		if type(owner) == 'table' then
			local remaining = remaining_seconds(owner.endtime, now_epoch)
			if remaining <= refresh_lead and (best_remaining == nil or remaining < best_remaining) then
				best_name = name
				best_remaining = remaining
			end
		end
	end
	return best_name, best_remaining
end

local function song_proposal(ctx, name, reason, urgency, is_dummy, required_recipients)
	local ok, why = ready(ctx, name, 'spell')
	if not ok then
		state.last_blocker = 'not_ready:' .. name .. ':' .. why
		return nil
	end
	reserve_action_lane(reason)
	return proposal('spell', name, reason, urgency, {
		is_dummy = is_dummy == true,
		required_recipient_ids = clone_array(required_recipients),
	})
end

local function required_recipient_ids(ctx)
	local player_id = tonumber(ctx.player and ctx.player.id) or 0
	if player_id <= 0 then
		return {}
	end
	-- General-song ownership is authoritative on the Bard's local timer. Party
	-- recipients are evidence only; roster members may be dead, remote, or out of range.
	return { player_id }
end

local function maybe_marcato(config, ctx, song_name, nitro_active)
	if config.use_marcato ~= true or song_name ~= config.marcato_song then
		return nil
	end
	if has_buff(ctx.player, JA.marcato.buff_id) then
		state.marcato_reservation = song_name
		return nil
	end
	if config.use_nitro and not nitro_active then
		return nil
	end
	local song_ok = ready(ctx, song_name, 'spell')
	local marcato_ok = ready(ctx, JA.marcato.name, 'ja')
	if song_ok and marcato_ok then
		state.marcato_reservation = song_name
		return proposal('ja', JA.marcato.name, 'brd_marcato_for_song', 0.82, { reserved_song = song_name })
	end
	return nil
end

function M.propose(config, ctx)
	ctx = type(ctx) == 'table' and ctx or {}
	local player = ctx.player
	if type(player) == 'table' and type(player.vitals) == 'table' and tonumber(player.vitals.hpp) == 0 then
		reset_runtime('player_ko', true)
		return nil
	end
	local ok, reason = validate_config(config, player)
	if not ok then
		state.last_blocker = reason
		release_action_lane(reason)
		diagnostic_log('CONFIG_REJECT', { reason = reason })
		return nil
	end
	if config.enabled ~= true then
		state.last_blocker = 'disabled'
		release_action_lane('disabled')
		return nil
	end
	local signature = config_signature(config, player)
	if state.config_signature ~= '' and state.config_signature ~= signature then
		reset_runtime('config_changed', true)
	end
	state.config_signature = signature
	config = effective_config(config, player)
	state.identity = tostring(player.name or '') .. ':' .. tostring(player.main_job or '') .. ':' .. tostring(player.sub_job or '')
	if type(state.snapshot) ~= 'table' then
		state.snapshot = {}
		state.snapshot_at = tonumber(ctx.now) or os.time()
		state.snapshot_source = 'startup_rebuild'
		state.last_transition = 'snapshot_bootstrap_rebuild'
		diagnostic_log('SNAPSHOT_BOOTSTRAP', { songs = config.songs, dummy_songs = config.dummy_songs })
	end
	local now = tonumber(ctx.now) or os.time()
	if type(state.pending) == 'table' then
		local timeout_phase = 'start'
		local timeout_started_at = state.pending.dispatched_at
		local timeout_seconds = SONG_START_TIMEOUT_S
		if state.pending.success == true then
			timeout_phase = 'snapshot'
			timeout_started_at = state.pending.success_at
			timeout_seconds = SONG_CONFIRM_TIMEOUT_S
		elseif state.pending.started_at ~= nil then
			timeout_phase = 'cast'
			timeout_started_at = state.pending.started_at
			timeout_seconds = SONG_CAST_TIMEOUT_S
		end
		if now - timeout_started_at > timeout_seconds then
			local timed_out_song = state.pending.name
			diagnostic_log('CONFIRM_TIMEOUT', {
				song = timed_out_song,
				age = now - timeout_started_at,
				phase = timeout_phase,
				success = state.pending.success,
			})
			state.last_blocker = 'song_confirmation_timeout:' .. timed_out_song
			finish_trace('resolve:timeout song=' .. timed_out_song)
			if timeout_phase == 'start' or timeout_phase == 'cast' then
				state.scheduler_failure = {
					reason = timeout_phase == 'start' and 'start_timeout' or 'cast_terminal_timeout',
					song = timed_out_song,
					retry_delay = 0.75,
				}
			end
			state.pending = nil
		else
			state.last_blocker = 'song_confirmation_pending:' .. state.pending.name
			return nil
		end
	end
	prune_owners()
	local required_recipients = required_recipient_ids(ctx)
	local nitro_active = has_buff(player, JA.nightingale.buff_id) and has_buff(player, JA.troubadour.buff_id)
	if state.nitro_armed and nitro_active and not state.nitro_was_active then
		start_force_generation(config)
		state.nitro_armed = false
	end
	state.nitro_was_active = nitro_active
	if state.marcato_reservation ~= '' and not has_buff(player, JA.marcato.buff_id) then
		state.marcato_reservation = ''
	end
	if state.marcato_reservation ~= '' then
		return song_proposal(ctx, state.marcato_reservation, 'brd_marcato_reserved_song', 0.98, false, required_recipients)
	end
	local urgent, remaining = urgent_song(config, os.time())
	if urgent ~= '' then
		local marcato = maybe_marcato(config, ctx, urgent, nitro_active)
		if marcato then
			return marcato
		end
		return song_proposal(ctx, urgent, 'brd_song_expiring', 0.98, false, required_recipients)
	end
	local forced = next_force_song(config)
	if forced ~= '' then
		local marcato = maybe_marcato(config, ctx, forced, nitro_active)
		if marcato then
			return marcato
		end
		return song_proposal(ctx, forced, 'brd_nitro_forced_refresh', 0.88, false, required_recipients)
	end
	local main_brd = tostring(player.main_job or '') == 'BRD'
	local base_count = main_brd and 2 or 1
	local base_song = next_missing_base_song(config, base_count, required_recipients)
	if base_song ~= '' then
		local marcato = maybe_marcato(config, ctx, base_song, nitro_active)
		if marcato then return marcato end
		return song_proposal(ctx, base_song, 'brd_build_base_song', 0.76, false, required_recipients)
	end
	local required_dummy = main_brd and math.max(0, #config.songs - base_count) or 0
	local count = snapshot_song_count(state.snapshot)
	if required_dummy > 0 and count < #config.songs then
		if #config.songs > 4 and count >= 4 and not has_buff(player, JA.clarion.buff_id) then
			local clarion_ready = ready(ctx, JA.clarion.name, 'ja')
			if config.use_clarion_call and clarion_ready then
				return proposal('ja', JA.clarion.name, 'brd_capacity_clarion', 0.77)
			end
			state.last_blocker = 'clarion_unavailable_for_fifth_song'
			release_action_lane('clarion_unavailable_for_fifth_song')
			return nil
		end
		local dummy = next_missing_dummy(config, required_dummy)
		if dummy ~= '' then
			return song_proposal(ctx, dummy, 'brd_build_capacity_dummy', 0.75, true, required_recipients)
		end
		state.last_blocker = 'capacity_build_no_timer_transition'
		release_action_lane('capacity_build_no_timer_transition')
		return nil
	end
	local missing = next_missing_final(config, required_recipients)
	if missing ~= '' then
		local marcato = maybe_marcato(config, ctx, missing, nitro_active)
		if marcato then
			return marcato
		end
		return song_proposal(ctx, missing, 'brd_replace_dummy_with_final', 0.74, false, required_recipients)
	end
	if config.use_nitro and tostring(player.main_job or '') == 'BRD' and not nitro_active then
		local night_active = has_buff(player, JA.nightingale.buff_id)
		local troub_active = has_buff(player, JA.troubadour.buff_id)
		local night_ready = ready(ctx, JA.nightingale.name, 'ja')
		local troub_ready = ready(ctx, JA.troubadour.name, 'ja')
		if night_active and not troub_active and state.nitro_armed and troub_ready then
			return proposal('ja', JA.troubadour.name, 'brd_nitro_troubadour', 0.79)
		end
		if not night_active and not troub_active and night_ready and troub_ready then
			state.nitro_armed = true
			return proposal('ja', JA.nightingale.name, 'brd_nitro_nightingale', 0.78)
		end
	end
	state.last_blocker = remaining and ('waiting_deadline:' .. tostring(math.floor(remaining))) or 'songs_satisfied'
	if not state.nitro_armed then
		release_action_lane(state.last_blocker)
	end
	return nil
end

function M.action_lane_status()
	return state.action_lane_reserved == true, state.action_lane_reason
end

function M.arm_trace_once()
	state.trace_armed = true
	state.trace_lines = {}
	return true
end

function M.arm_manual_capture_once()
	state.manual_capture = { phase = 'await_028' }
	state.trace_lines = {}
	state.last_transition = 'manual_capture_armed'
	return true
end

function M.start_diagnostic_log()
	local player = windower.ffxi.get_player()
	if type(player) ~= 'table' or type(player.name) ~= 'string' or player.name == '' then
		return false, 'missing_player'
	end
	local safe_name = player.name:lower():gsub('[^a-z0-9_-]', '_')
	local path = windower.addon_path .. 'data/logs/' .. safe_name .. '_brd_maintenance.log'
	local fh, err = io.open(path, 'w')
	if not fh then
		return false, tostring(err or 'open_failed')
	end
	fh:write(('BRD_DIAGNOSTIC_V1\tstarted=%s\tcharacter=%s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), player.name))
	fh:close()
	state.log_path = path
	state.log_error = ''
	state.log_enabled = true
	diagnostic_log('LOG_START', {
		identity = state.identity,
		snapshot_source = state.snapshot_source,
		snapshot_count = snapshot_song_count(state.snapshot),
		owners = owner_summary(),
	})
	return true, path
end

function M.stop_diagnostic_log()
	if state.log_enabled == true then
		diagnostic_log('LOG_STOP', {
			blocker = state.last_blocker,
			transition = state.last_transition,
			owners = owner_summary(),
		})
	end
	state.log_enabled = false
	return state.log_path
end

function M.diagnostic_log_status()
	return state.log_enabled, state.log_path, state.log_error
end

function M.note_scheduler_rejection(reason, action_name)
	state.last_blocker = 'scheduler:' .. tostring(reason or 'rejected') .. ':' .. tostring(action_name or '')
	diagnostic_log('SCHEDULER_REJECT', { reason = reason, action_name = action_name })
	trace(state.last_blocker)
end

function M.cancel_pending(reason)
	if type(state.pending) ~= 'table' then
		return false
	end
	state.last_blocker = tostring(reason or 'pending_cancelled') .. ':' .. state.pending.name
	diagnostic_log('PENDING_CANCEL', { reason = reason, song = state.pending.name })
	finish_trace('resolve:' .. state.last_blocker)
	state.pending = nil
	state.marcato_reservation = ''
	return true
end

function M.reject_pending_before_start(message_id, now)
	if type(state.pending) ~= 'table' or state.pending.phase ~= 'awaiting_start' then
		return false
	end
	local song = state.pending.name
	state.last_blocker = 'server_reject_unable_cast:' .. song
	diagnostic_log('SERVER_REJECT', {
		song = song,
		message_id = message_id,
		phase = state.pending.phase,
		age = (tonumber(now) or os.time()) - state.pending.dispatched_at,
	})
	finish_trace(('resolve:server_reject_unable_cast message=%d song=%s'):format(tonumber(message_id) or 0, song))
	state.pending = nil
	state.marcato_reservation = ''
	return true
end

function M.take_scheduler_failure()
	local failure = state.scheduler_failure
	state.scheduler_failure = nil
	return failure
end

function M.status_lines()
	local lines = {
		('BRD identity=%s blocker=%s transition=%s'):format(state.identity, state.last_blocker, state.last_transition),
		('BRD snapshot=%s source=%s count=%d pending=%s'):format(
			type(state.snapshot) == 'table' and 'yes' or 'no',
			state.snapshot_source,
			snapshot_song_count(state.snapshot),
			type(state.pending) == 'table' and state.pending.name or 'none'
		),
		('BRD server_clock=%s offset=%d'):format(
			tostring(state.server_time_source),
			tonumber(state.server_time_offset) or 0
		),
		('BRD nitro_force=%s marcato_reservation=%s owners=%d'):format(
			type(state.force) == 'table' and 'active' or 'none',
			state.marcato_reservation ~= '' and state.marcato_reservation or 'none',
			(function()
				local count = 0
				for _ in pairs(state.owners) do count = count + 1 end
				return count
			end)()
		),
		('BRD action_lane=%s reason=%s'):format(
			state.action_lane_reserved and 'reserved' or 'open',
			state.action_lane_reason ~= '' and state.action_lane_reason or 'none'
		),
		('BRD log=%s path=%s error=%s'):format(
			state.log_enabled and 'on' or 'off',
			state.log_path ~= '' and state.log_path or 'none',
			state.log_error ~= '' and state.log_error or 'none'
		),
	}
	for name, owner in pairs(state.owners) do
		lines[#lines + 1] = ('BRD owner=%s status=%d remaining=%.1fs recipients=%s'):format(
			name,
			tonumber(owner.status_id) or 0,
			remaining_seconds(owner.endtime, os.time()),
			join(owner.recipients)
		)
	end
	if #state.trace_lines > 0 then
		for i = 1, #state.trace_lines do
			lines[#lines + 1] = 'BRD trace ' .. state.trace_lines[i]
		end
	end
	return lines
end

M._test = {
	state = state,
	validate_config = validate_config,
	effective_config = effective_config,
	multiset_delta = multiset_delta,
	remaining_seconds = remaining_seconds,
	server_now_raw = server_now_raw,
	reset = M.reset,
}

return M
