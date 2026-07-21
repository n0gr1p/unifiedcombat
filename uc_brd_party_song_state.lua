local M = {}

local COUNT_CONFIRM_TIMEOUT_S = 2.0
local TIMER_TIE_TOLERANCE = 60

local state = {
	members = {},
	order = {},
	recovery = nil,
	last_blocker = 'not_evaluated',
}

local function name_is_ignored(ignore_names, name)
	local wanted = tostring(name or ''):lower()
	for i = 1, #(ignore_names or {}) do
		if tostring(ignore_names[i]):lower() == wanted then
			return true
		end
	end
	return false
end

local function is_eligible(member, ignore_names)
	return type(member) == 'table'
		and member.is_self ~= true
		and member.is_npc ~= true
		and tonumber(member.spawn_type) ~= 14
		and member.in_song_range == true
		and (tonumber(member.hpp) or 0) > 0
		and not name_is_ignored(ignore_names, member.name)
end

local function is_targetable(member)
	return type(member) == 'table'
		and member.is_npc ~= true
		and tonumber(member.spawn_type) ~= 14
		and member.in_song_range == true
		and (tonumber(member.hpp) or 0) > 0
end

function M.in_recovery_range(member, recovery_range_yalms, get_mob_by_id)
	if type(recovery_range_yalms) ~= 'number' or recovery_range_yalms < 1.0 or recovery_range_yalms > 20.0 then
		return false, nil
	end
	if type(member) ~= 'table' or member.id == nil then
		return false, nil
	end
	if member.is_self then
		return true, 0
	end
	assert(type(get_mob_by_id) == 'function', 'Bard recovery range requires get_mob_by_id')
	local mob = get_mob_by_id(member.id)
	if not mob or mob.distance == nil then
		return false, nil
	end
	local distance = mob.distance:sqrt()
	return distance <= recovery_range_yalms, distance
end

local function observed_song_count(member, song_status_ids)
	if type(member.buffs) ~= 'table' then
		return nil
	end
	local count = 0
	for i = 1, #member.buffs do
		if song_status_ids[tonumber(member.buffs[i]) or 0] == true then
			count = count + 1
		end
	end
	return count
end

local function effect_count(member)
	local count = 0
	for _ in pairs(member.effects or {}) do
		count = count + 1
	end
	return count
end

local function clear_member(member, reason)
	member.effects = {}
	member.unknown_count = 0
	member.pending_count = nil
	member.confidence = 'unknown'
	member.loss_reason = tostring(reason or 'state_invalidated')
end

local function recovery_signature(song_limit, observed_count)
	return tostring(tonumber(song_limit) or 0) .. ':' .. tostring(tonumber(observed_count) or -1)
end

local function reconcile_observed_count(member, count)
	local known = effect_count(member)
	if count < known then
		clear_member(member, 'observed_song_count_loss')
		member.unknown_count = count
		return
	end
	member.unknown_count = count - known
	if member.unknown_count == 0 then
		member.confidence = 'confirmed'
		member.loss_reason = nil
	else
		member.confidence = 'partial'
		member.loss_reason = 'unowned_active_songs'
	end
end

function M.reset()
	state.members = {}
	state.order = {}
	state.recovery = nil
	state.last_blocker = 'reset'
end

function M.observe(members, ignore_names, song_status_ids, now)
	local seen = {}
	state.order = {}
	now = tonumber(now) or os.time()
	for i = 1, #(members or {}) do
		local member = members[i]
		local id = tonumber(member and member.id) or 0
		if id > 0 then
			seen[id] = true
			local record = state.members[id] or {
				effects = {},
				unknown_count = 0,
				confidence = 'unknown',
			}
			local was_eligible = record.eligible == true
			local prior_count = record.observed_song_count
			record.id = id
			record.name = tostring(member.name or '')
			record.source = tostring(member.source or 'unknown')
			record.buff_source = tostring(member.buff_source or 'missing')
			record.in_song_range = member.in_song_range == true
			record.song_distance = tonumber(member.song_distance)
			record.eligible = is_eligible(member, ignore_names)
			record.targetable = is_targetable(member)
			record.observed_song_count = observed_song_count(member, song_status_ids or {})

			if (tonumber(member.hpp) or 0) <= 0 then
				clear_member(record, 'recipient_ko')
				record.blocked_signature = nil
			elseif was_eligible and record.eligible ~= true then
				record.confidence = 'unknown'
				record.loss_reason = 'recipient_unavailable'
				record.pending_count = nil
				record.blocked_signature = nil
			elseif record.eligible and prior_count ~= record.observed_song_count then
				record.blocked_signature = nil
			end

			local pending = record.pending_count
			if record.targetable and record.observed_song_count ~= nil and type(pending) == 'table' then
				if record.observed_song_count >= pending.expected_count then
					record.pending_count = nil
					if type(state.recovery) == 'table' and state.recovery.member_id == id then
						state.recovery.awaiting_count = false
						state.last_blocker = 'capacity_transition_confirmed'
					end
				elseif now - (tonumber(pending.started_at) or now) > COUNT_CONFIRM_TIMEOUT_S then
					clear_member(record, 'capacity_transition_not_observed')
					record.unknown_count = record.observed_song_count
					record.blocked_signature = recovery_signature(pending.song_limit, record.observed_song_count)
					if type(state.recovery) == 'table' and state.recovery.member_id == id then
						state.recovery = nil
						state.last_blocker = 'capacity_transition_failed:' .. record.name
					end
				end
			end

			if record.targetable and record.observed_song_count ~= nil and record.pending_count == nil then
				reconcile_observed_count(record, record.observed_song_count)
			end
			state.members[id] = record
			state.order[#state.order + 1] = id
		end
	end

	for id in pairs(state.members) do
		if seen[id] ~= true then
			state.members[id] = nil
		end
	end
	if type(state.recovery) == 'table' then
		local member = state.members[state.recovery.member_id]
		if type(member) ~= 'table' or member.eligible ~= true then
			state.recovery = nil
			state.last_blocker = 'recovery_recipient_unavailable'
		end
	end
end

local function unique_shortest_effect(member)
	if (tonumber(member.unknown_count) or 0) > 0 then
		return nil, 'unknown_overwrite_victim'
	end
	local shortest_name = nil
	local shortest_endtime = nil
	local tied = false
	for name, effect in pairs(member.effects or {}) do
		local endtime = tonumber(effect.endtime)
		if endtime == nil or endtime <= 0 then
			return nil, 'unknown_effect_endtime'
		end
		if shortest_endtime == nil or endtime < shortest_endtime - TIMER_TIE_TOLERANCE then
			shortest_name = name
			shortest_endtime = endtime
			tied = false
		elseif math.abs(endtime - shortest_endtime) <= TIMER_TIE_TOLERANCE then
			tied = true
		end
	end
	if shortest_name == nil then
		return nil, 'missing_overwrite_victim'
	end
	if tied then
		return nil, 'ambiguous_overwrite_victim'
	end
	return shortest_name, ''
end

local function targeted_overwrite_candidates(member)
	if (tonumber(member.unknown_count) or 0) > 0 then
		return nil, 'unknown_overwrite_victim'
	end
	local shortest_endtime = nil
	for _, effect in pairs(member.effects or {}) do
		local endtime = tonumber(effect.endtime)
		if endtime == nil or endtime <= 0 then
			return nil, 'unknown_effect_endtime'
		end
		if shortest_endtime == nil or endtime < shortest_endtime then
			shortest_endtime = endtime
		end
	end
	if shortest_endtime == nil then
		return nil, 'missing_overwrite_victim'
	end
	local names = {}
	for name, effect in pairs(member.effects or {}) do
		if math.abs((tonumber(effect.endtime) or 0) - shortest_endtime) <= TIMER_TIE_TOLERANCE then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names, ''
end

function M.plan_targeted_song(member_id, song_name, cast_capacity, protected_songs, allow_unknown_overwrite)
	local member = state.members[tonumber(member_id) or 0]
	if type(member) ~= 'table' or member.targetable ~= true then
		return nil, 'targeted_recipient_unavailable'
	end
	if type(member.pending_count) == 'table' then
		return nil, 'targeted_recipient_count_pending'
	end
	local name = tostring(song_name or '')
	local existing = member.effects[name]
	if type(existing) == 'table' then
		return {
			operation = 'exact_refresh',
			candidate_names = { name },
			requires_troubadour = existing.troubadour_active == true,
		}, ''
	end
	local count = tonumber(member.observed_song_count)
	if count == nil then
		return nil, 'missing_recipient_song_count:' .. member.name
	end
	if count < (tonumber(cast_capacity) or 0) then
		return {
			operation = 'add',
			candidate_names = {},
			requires_troubadour = false,
		}, ''
	end
	local candidates, reason = targeted_overwrite_candidates(member)
	if candidates == nil then
		if reason == 'unknown_overwrite_victim' and allow_unknown_overwrite == true then
			return {
				operation = 'replace',
				candidate_names = {},
				requires_troubadour = true,
				unknown_overwrite = true,
			}, ''
		end
		return nil, reason
	end
	local protected = type(protected_songs) == 'table' and protected_songs or {}
	local requires_troubadour = false
	for i = 1, #candidates do
		local candidate = candidates[i]
		if protected[candidate] == true then
			return nil, 'targeted_candidate_protected:' .. candidate
		end
		if member.effects[candidate].troubadour_active == true then
			requires_troubadour = true
		end
	end
	return {
		operation = 'replace',
		candidate_names = candidates,
		requires_troubadour = requires_troubadour,
	}, ''
end

function M.member_by_name(name)
	local wanted = tostring(name or ''):lower()
	local matched = nil
	for i = 1, #state.order do
		local member = state.members[state.order[i]]
		if type(member) == 'table' and tostring(member.name or ''):lower() == wanted then
			if matched ~= nil then
				return nil, 'ambiguous_targeted_recipient:' .. tostring(name or '')
			end
			matched = member
		end
	end
	if matched == nil then
		return nil, 'targeted_recipient_not_in_party:' .. tostring(name or '')
	end
	return matched, ''
end

function M.mark_member_unknown(member_id, reason)
	local member = state.members[tonumber(member_id) or 0]
	if type(member) ~= 'table' then
		return false
	end
	clear_member(member, reason or 'targeted_state_unknown')
	member.observed_song_count = nil
	return true
end

local function exact_refresh_is_safe_for_all(song_name)
	for i = 1, #state.order do
		local member = state.members[state.order[i]]
		if type(member) == 'table' and member.eligible == true
			and type(member.effects[song_name]) ~= 'table' then
			return false, 'normalization_not_exact_refresh:' .. member.name
		end
	end
	return true, ''
end

function M.exact_refresh_is_safe_for_all(song_name)
	return exact_refresh_is_safe_for_all(song_name)
end

function M.earliest_effect_endtime(song_name)
	local name = tostring(song_name or '')
	local earliest = nil
	local recipient_name = ''
	for i = 1, #state.order do
		local member = state.members[state.order[i]]
		local effect = type(member) == 'table' and member.eligible == true
			and member.effects[name] or nil
		if type(effect) == 'table' then
			local endtime = tonumber(effect.endtime)
			if effect.endtime_confidence ~= 'confirmed' or endtime == nil or endtime <= 0 then
				return nil, '', 'unknown_recipient_song_endtime:' .. member.name .. ':' .. name
			end
			if earliest == nil or endtime < earliest then
				earliest = endtime
				recipient_name = member.name
			end
		end
	end
	return earliest, recipient_name, ''
end

local function enhanced_dummy_to_normalize(member)
	local selected_name = nil
	local selected_endtime = nil
	for name, effect in pairs(member.effects or {}) do
		local endtime = tonumber(effect.endtime)
		if effect.is_dummy == true and effect.troubadour_active == true
			and effect.normalization_attempted ~= true and endtime ~= nil
			and (selected_endtime == nil or endtime < selected_endtime
				or (endtime == selected_endtime and name < selected_name)) then
			selected_name = name
			selected_endtime = endtime
		end
	end
	return selected_name
end

local function normalized_dummy_name(member)
	for name, effect in pairs(member.effects or {}) do
		if effect.is_dummy == true and effect.normalization_attempted == true then
			return name
		end
	end
	return nil
end

local function apply_delivery(member, delivery)
	local name = tostring(delivery.song_name or '')
	local existing = member.effects[name]
	if type(existing) == 'table' then
		if delivery.pianissimo_applied == true and delivery.endtime == nil then
			existing.endtime = 0
			existing.endtime_confidence = 'unknown'
		else
			existing.endtime = tonumber(delivery.endtime) or existing.endtime
			existing.endtime_confidence = delivery.endtime ~= nil and 'confirmed'
				or tostring(existing.endtime_confidence or 'unknown')
		end
		existing.status_id = tonumber(delivery.status_id) or existing.status_id
		existing.confirmed_at = tonumber(delivery.confirmed_at) or os.time()
		existing.is_dummy = delivery.is_dummy == true
		existing.troubadour_active = delivery.troubadour_active == true
		existing.soul_voice_applied = delivery.soul_voice_applied == true
		existing.pianissimo_applied = delivery.pianissimo_applied == true
		existing.normalization_attempted = delivery.normalizes_dummy == true
		existing.alignment_attempted = delivery.aligns_final == true
		return 'exact_refresh'
	end

	local count = tonumber(member.observed_song_count)
	local capacity = tonumber(delivery.cast_capacity) or 0
	if count ~= nil and capacity > count then
		member.effects[name] = {
			endtime = tonumber(delivery.endtime) or 0,
			status_id = tonumber(delivery.status_id) or 0,
			confirmed_at = tonumber(delivery.confirmed_at) or os.time(),
			is_dummy = delivery.is_dummy == true,
			troubadour_active = delivery.troubadour_active == true,
			soul_voice_applied = delivery.soul_voice_applied == true,
			pianissimo_applied = delivery.pianissimo_applied == true,
			endtime_confidence = delivery.endtime ~= nil and 'confirmed' or 'unknown',
			normalization_attempted = delivery.normalizes_dummy == true,
			alignment_attempted = delivery.aligns_final == true,
		}
		member.pending_count = {
			before_count = count,
			expected_count = count + 1,
			started_at = tonumber(delivery.confirmed_at) or os.time(),
			song_limit = tonumber(delivery.song_limit) or capacity,
		}
		return 'awaiting_add_confirmation'
	end

	local victim, reason = unique_shortest_effect(member)
	if victim ~= nil then
		member.effects[victim] = nil
	elseif (tonumber(member.unknown_count) or 0) > 0 then
		member.unknown_count = member.unknown_count - 1
		member.confidence = 'partial'
		member.loss_reason = reason
	else
		member.confidence = 'unknown'
		member.loss_reason = reason
	end
	member.effects[name] = {
		endtime = tonumber(delivery.endtime) or 0,
		status_id = tonumber(delivery.status_id) or 0,
		confirmed_at = tonumber(delivery.confirmed_at) or os.time(),
		is_dummy = delivery.is_dummy == true,
		troubadour_active = delivery.troubadour_active == true,
		soul_voice_applied = delivery.soul_voice_applied == true,
		pianissimo_applied = delivery.pianissimo_applied == true,
		endtime_confidence = delivery.endtime ~= nil and 'confirmed' or 'unknown',
		normalization_attempted = delivery.normalizes_dummy == true,
		alignment_attempted = delivery.aligns_final == true,
	}
	return victim ~= nil and ('replaced:' .. victim) or reason
end

function M.record_delivery(delivery)
	if type(delivery) ~= 'table' or tostring(delivery.song_name or '') == '' then
		return false
	end
	local recovery_member_id = tonumber(delivery.recovery_member_id) or 0
	for i = 1, #(delivery.recipients or {}) do
		local id = tonumber(delivery.recipients[i]) or 0
		local member = state.members[id]
		if type(member) == 'table' then
			local outcome = apply_delivery(member, delivery)
			if id == recovery_member_id and delivery.is_dummy == true and delivery.normalizes_dummy ~= true
				and type(state.recovery) == 'table' then
				if outcome == 'awaiting_add_confirmation' then
					state.recovery.awaiting_count = true
					state.last_blocker = 'capacity_transition_pending:' .. member.name
				else
					member.blocked_signature = recovery_signature(delivery.song_limit, member.observed_song_count)
					state.recovery = nil
					state.last_blocker = 'capacity_dummy_did_not_add:' .. member.name
				end
			end
		end
	end
	return true
end

local function start_recovery(config, song_limit)
	for i = 1, #state.order do
		local member = state.members[state.order[i]]
		local count = tonumber(member and member.observed_song_count)
		if type(member) == 'table' and member.eligible == true and count ~= nil and count < song_limit
			and member.blocked_signature ~= recovery_signature(song_limit, count) then
			state.recovery = {
				member_id = member.id,
				member_name = member.name,
				song_limit = song_limit,
				phase = 'capacity',
				awaiting_count = false,
			}
			state.last_blocker = 'recovery_started:' .. member.name
			return state.recovery
		end
	end
	return nil
end

local function first_capacity_dummy(member, config)
	for i = 1, #config.dummy_songs do
		if member.effects[config.dummy_songs[i]] == nil then
			return config.dummy_songs[i]
		end
	end
	return ''
end

local function desired_song_within_limit(config, name, song_limit)
	for i = 1, song_limit do
		if config.songs[i] == name then
			return true
		end
	end
	return false
end

local function area_song_is_safe(song_name, cast_capacity)
	for i = 1, #state.order do
		local member = state.members[state.order[i]]
		if type(member) == 'table' and member.eligible == true then
			local count = tonumber(member.observed_song_count)
			if count == nil then
				return false, 'missing_recipient_song_count:' .. member.name
			end
			if member.effects[song_name] == nil and count >= cast_capacity then
				local victim, reason = unique_shortest_effect(member)
				if victim == nil or member.effects[victim].is_dummy ~= true then
					return false, 'unsafe_alignment_recipient:' .. member.name .. ':' .. tostring(reason)
				end
			end
		end
	end
	return true, ''
end

local function missing_final_action(config, song_limit, troubadour_active)
	for song_index = 1, song_limit do
		local song_name = config.songs[song_index]
		local needed = false
		for i = 1, #state.order do
			local member = state.members[state.order[i]]
			if type(member) == 'table' and member.eligible == true
				and tonumber(member.observed_song_count) == song_limit
				and member.effects[song_name] == nil then
				local victim, reason = unique_shortest_effect(member)
				if victim == nil then
					return nil, 'ambiguous_final_recovery:' .. member.name .. ':' .. tostring(reason)
				end
				if member.effects[victim].is_dummy ~= true then
					if desired_song_within_limit(config, victim, song_limit) then
						local enhanced_dummy = troubadour_active ~= true and enhanced_dummy_to_normalize(member) or nil
						if enhanced_dummy ~= nil then
							local normalization_safe, normalization_reason = exact_refresh_is_safe_for_all(enhanced_dummy)
							if normalization_safe then
								return enhanced_dummy, '', 'brd_recovery_normalize_dummy', 'normalize_dummy'
							end
							return nil, normalization_reason
						end
						if member.effects[victim].alignment_attempted == true then
							local normalized_dummy = normalized_dummy_name(member)
							if normalized_dummy ~= nil then
								return nil, 'dummy_duration_normalization_failed:' .. member.name .. ':' .. normalized_dummy
							end
							return nil, 'recovery_alignment_failed:' .. member.name .. ':' .. victim
						end
						local safe, safe_reason = area_song_is_safe(victim, 2)
						if safe then
							return victim, '', 'brd_recovery_align_shortest', 'align_final'
						end
						return nil, safe_reason
					end
					return nil, 'ambiguous_final_recovery:' .. member.name .. ':shortest_not_alignable:' .. victim
				end
				needed = true
			end
		end
		if needed then
			return song_name, '', nil
		end
	end
	return '', '', nil
end

local function capacity_final_action(config, song_limit, recovery_member)
	local recovery_count = tonumber(recovery_member.observed_song_count)
	local cast_capacity = song_limit == 5 and recovery_count < 4 and 4 or song_limit
	for song_index = 1, cast_capacity do
		local song_name = config.songs[song_index]
		if recovery_member.effects[song_name] == nil then
			for i = 1, #state.order do
				local member = state.members[state.order[i]]
				if type(member) == 'table' and member.eligible == true then
					local count = tonumber(member.observed_song_count)
					if count == nil then
						return nil, 'missing_recipient_song_count:' .. member.name
					end
					if count >= cast_capacity and member.effects[song_name] == nil then
						local victim, reason = unique_shortest_effect(member)
						if victim == nil or member.effects[victim].is_dummy ~= true then
							return nil, 'ambiguous_capacity_final:' .. member.name .. ':' .. tostring(reason)
						end
					end
				end
			end
			return song_name, '', cast_capacity
		end
	end
	return '', 'no_missing_capacity_final', cast_capacity
end

function M.next_action(config, song_limit, clarion_active, clarion_ready, troubadour_active)
	local recovery = state.recovery or start_recovery(config, song_limit)
	if type(recovery) ~= 'table' then
		if state.last_blocker == 'not_evaluated' then
			state.last_blocker = 'party_songs_satisfied'
		end
		return nil
	end
	local member = state.members[recovery.member_id]
	if type(member) ~= 'table' or member.eligible ~= true then
		state.recovery = nil
		state.last_blocker = 'recovery_recipient_unavailable'
		return nil
	end
	if recovery.awaiting_count == true or type(member.pending_count) == 'table' then
		return nil
	end

	local count = tonumber(member.observed_song_count)
	if count == nil then
		state.last_blocker = 'missing_recipient_song_count:' .. member.name
		return nil
	end
	if count < recovery.song_limit then
		if recovery.song_limit == 5 and count >= 4 and clarion_active ~= true then
			if clarion_ready == true then
				return {
					action_type = 'ja',
					action_name = 'Clarion Call',
					reason_code = 'brd_recovery_clarion',
					member_id = member.id,
				}
			end
			local degraded_final, degraded_blocker, degraded_reason, degraded_transition = missing_final_action(config, 4, troubadour_active)
			if degraded_final == nil then
				state.recovery = nil
				state.last_blocker = degraded_blocker
				return nil
			end
			if degraded_final ~= '' then
				local reason_code = 'brd_recovery_degraded_final'
				if degraded_reason ~= nil then
					reason_code = degraded_reason
				end
				return {
					action_type = 'spell',
					action_name = degraded_final,
					reason_code = reason_code,
					member_id = member.id,
					is_dummy = degraded_transition == 'normalize_dummy',
					cast_capacity = 2,
					normalizes_dummy = degraded_transition == 'normalize_dummy',
					aligns_final = degraded_transition == 'align_final',
				}
			end
			state.last_blocker = 'degraded_fifth_waiting_for_clarion:' .. member.name
			return nil
		end
		local dummy = first_capacity_dummy(member, config)
		if dummy == '' then
			local capacity_final, capacity_blocker, cast_capacity = capacity_final_action(config, recovery.song_limit, member)
			if capacity_final == nil or capacity_final == '' then
				member.blocked_signature = recovery_signature(recovery.song_limit, count)
				state.recovery = nil
				if capacity_final == nil then
					state.last_blocker = capacity_blocker
				else
					state.last_blocker = 'no_distinct_capacity_dummy:' .. member.name
				end
				return nil
			end
			return {
				action_type = 'spell',
				action_name = capacity_final,
				reason_code = 'brd_recovery_capacity_final',
				member_id = member.id,
				is_dummy = false,
				cast_capacity = cast_capacity,
			}
		end
		return {
			action_type = 'spell',
			action_name = dummy,
			reason_code = 'brd_recovery_dummy',
			member_id = member.id,
			is_dummy = true,
			cast_capacity = recovery.song_limit == 5 and count < 4 and 4 or recovery.song_limit,
		}
	end

	-- Another eligible player may still have a slot deficit after the selected
	-- recipient was repaired. Build every count before replacing placeholders.
	for i = 1, #state.order do
		local other = state.members[state.order[i]]
		local other_count = tonumber(other and other.observed_song_count)
		if type(other) == 'table' and other.eligible == true and other_count ~= nil and other_count < song_limit then
			state.recovery = nil
			return M.next_action(config, song_limit, clarion_active, clarion_ready)
		end
	end

	local final, blocker, final_reason, final_transition = missing_final_action(config, song_limit, troubadour_active)
	if final == nil then
		state.recovery = nil
		state.last_blocker = blocker
		return nil
	end
	if final ~= '' then
		local reason_code = 'brd_recovery_final'
		if final_reason ~= nil then
			reason_code = final_reason
		end
		return {
			action_type = 'spell',
			action_name = final,
			reason_code = reason_code,
			member_id = member.id,
			is_dummy = final_transition == 'normalize_dummy',
			cast_capacity = 2,
			normalizes_dummy = final_transition == 'normalize_dummy',
			aligns_final = final_transition == 'align_final',
		}
	end
	state.recovery = nil
	state.last_blocker = 'party_recovery_complete'
	return nil
end

function M.last_blocker()
	return state.last_blocker
end

function M.is_recovery_active()
	return type(state.recovery) == 'table'
end

function M.status_lines()
	local lines = {
		('BRD party recovery=%s blocker=%s'):format(
			type(state.recovery) == 'table' and state.recovery.member_name or 'none',
			state.last_blocker
		),
	}
	for i = 1, #state.order do
		local member = state.members[state.order[i]]
		lines[#lines + 1] = ('BRD recipient=%s eligible=%s targetable=%s count=%s known=%d unknown=%d confidence=%s source=%s buffs=%s range=%s distance=%s loss=%s'):format(
			member.name,
			member.eligible and 'yes' or 'no',
			member.targetable and 'yes' or 'no',
			member.observed_song_count == nil and 'unknown' or tostring(member.observed_song_count),
			effect_count(member),
			tonumber(member.unknown_count) or 0,
			tostring(member.confidence or 'unknown'),
			tostring(member.source or 'unknown'),
			tostring(member.buff_source or 'missing'),
			member.in_song_range and 'yes' or 'no',
			member.song_distance == nil and 'unknown' or ('%.1f'):format(member.song_distance),
			tostring(member.loss_reason or 'none')
		)
		local effect_names = {}
		for effect_name in pairs(member.effects) do
			effect_names[#effect_names + 1] = effect_name
		end
		table.sort(effect_names)
		for effect_index = 1, #effect_names do
			local effect_name = effect_names[effect_index]
			local effect = member.effects[effect_name]
			lines[#lines + 1] = ('BRD recipient_effect=%s song=%s endtime=%s endtime_confidence=%s troubadour=%s soul_voice=%s pianissimo=%s'):format(
				member.name,
				effect_name,
				tostring(effect.endtime),
				tostring(effect.endtime_confidence),
				effect.troubadour_active and 'yes' or 'no',
				effect.soul_voice_applied and 'yes' or 'no',
				effect.pianissimo_applied and 'yes' or 'no'
			)
		end
	end
	return lines
end

M._test = {
	state = state,
	unique_shortest_effect = unique_shortest_effect,
	targeted_overwrite_candidates = targeted_overwrite_candidates,
	exact_refresh_is_safe_for_all = exact_refresh_is_safe_for_all,
}

return M
