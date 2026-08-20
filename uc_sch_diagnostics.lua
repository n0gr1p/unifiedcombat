local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_number(value, name)
	if type(value) ~= 'number' then
		error(name .. ' must be a number')
	end
	return value
end

local function display(value)
	if value == nil then
		return 'unobserved'
	end
	if type(value) == 'boolean' then
		return value and 'true' or 'false'
	end
	if value == '' then
		return 'none'
	end
	return tostring(value)
end

local function display_age(now, observed_at)
	if type(observed_at) ~= 'number' or observed_at <= 0 then
		return 'unknown'
	end
	return ('%.1f'):format(math.max(0, now - observed_at))
end

local function number_list(values)
	if values == nil then
		return 'unobserved'
	end
	require_table(values, 'Scholar diagnostic number list')
	if #values == 0 then
		return 'none'
	end
	local out = {}
	for i = 1, #values do
		if type(values[i]) ~= 'number' then
			error('Scholar diagnostic number list entries must be numeric')
		end
		out[i] = tostring(values[i])
	end
	return table.concat(out, ',')
end

local function owned_summary(owned_buffs)
	if owned_buffs == nil then
		return 'unobserved'
	end
	require_table(owned_buffs, 'Scholar diagnostic owned buffs')
	local recipients = 0
	local effects = 0
	local present = 0
	local absent = 0
	local unknown = 0
	for _, families in pairs(owned_buffs) do
		require_table(families, 'Scholar diagnostic owned buff families')
		recipients = recipients + 1
		for _, owner in pairs(families) do
			require_table(owner, 'Scholar diagnostic owned buff')
			effects = effects + 1
			if owner.presence == 'present' then
				present = present + 1
			elseif owner.presence == 'absent' then
				absent = absent + 1
			elseif owner.presence == 'unknown' then
				unknown = unknown + 1
			else
				error('Scholar diagnostic owned buff presence is invalid')
			end
		end
	end
	return ('recipients:%d effects:%d present:%d absent:%d unknown:%d'):format(
		recipients,
		effects,
		present,
		absent,
		unknown
	)
end

local function owned_detail_lines(owned_buffs)
	if owned_buffs == nil then
		return {}
	end
	require_table(owned_buffs, 'Scholar diagnostic owned buffs')
	local rows = {}
	for target_id, families in pairs(owned_buffs) do
		if type(target_id) ~= 'number' or target_id <= 0 or target_id % 1 ~= 0 then
			error('Scholar diagnostic owned buff target key must be a positive integer')
		end
		require_table(families, 'Scholar diagnostic owned buff families')
		for family, owner in pairs(families) do
			if type(family) ~= 'string' or family == '' then
				error('Scholar diagnostic owned buff family must be a non-empty string')
			end
			require_table(owner, 'Scholar diagnostic owned buff')
			if owner.target_id ~= target_id then
				error('Scholar diagnostic owned buff target id must match its state key')
			end
			rows[#rows + 1] = {
				target_id = target_id,
				family = family,
				owner = owner,
			}
		end
	end
	table.sort(rows, function(left, right)
		if left.target_id ~= right.target_id then
			return left.target_id < right.target_id
		end
		return left.family < right.family
	end)
	local lines = {}
	for i = 1, #rows do
		local row = rows[i]
		local owner = row.owner
		lines[#lines + 1] = ('UC SCH owned target=%s/%s family=%s spell=%s presence=%s duration=%s/%s reason=%s model=%s source=%s last_observed_at=%s'):format(
			display(row.target_id),
			display(owner.target_name),
			display(row.family),
			display(owner.exact_spell),
			display(owner.presence),
			display(owner.duration_confidence),
			display(owner.estimated_expires_at),
			display(owner.duration_reason),
			display(owner.duration_model_key),
			display(owner.duration_source),
			display(owner.last_observed_at)
		)
	end
	return lines
end

local function first_storm_assignment(storms)
	if type(storms) ~= 'table' or type(storms.assignments) ~= 'table' then
		return 'unobserved'
	end
	for i = 1, #storms.assignments do
		local assignment = storms.assignments[i]
		if type(assignment) ~= 'table' then
			error('Scholar diagnostic storm assignment must be a table')
		end
		if assignment.state ~= 'satisfied_owned_present' then
			return ('%s->%s:%s/%s'):format(
				display(assignment.spell),
				display(assignment.target_name),
				display(assignment.state),
				display(assignment.blocker)
			)
		end
	end
	return #storms.assignments == 0 and 'none' or 'all_satisfied'
end

local function planned_recipient_ids(plan)
	if plan == nil then
		return nil
	end
	require_table(plan, 'Scholar diagnostic plan')
	local recipients = require_table(
		plan.expected_recipients,
		'Scholar diagnostic plan recipients'
	)
	local ids = {}
	for i = 1, #recipients do
		local recipient = require_table(
			recipients[i],
			'Scholar diagnostic Regen plan recipient'
		)
		if type(recipient.id) ~= 'number' then
			error('Scholar diagnostic Regen plan recipient id must be numeric')
		end
		ids[i] = recipient.id
	end
	return ids
end

function M.status_lines(status, at)
	require_table(status, 'Scholar diagnostic status')
	local now = require_number(at, 'Scholar diagnostic status time')
	local runtime = type(status.runtime) == 'table' and status.runtime or {}
	local arts = type(runtime.arts) == 'table' and runtime.arts or {}
	local arts_evaluation = type(status.arts) == 'table' and status.arts or {}
	local charge = type(runtime.stratagem) == 'table' and runtime.stratagem or {}
	local sequence = type(runtime.active_sequence) == 'table' and runtime.active_sequence or nil
	local pending = type(runtime.pending) == 'table' and runtime.pending or nil
	local lane = type(runtime.lane) == 'table' and runtime.lane or {}
	local last = type(runtime.last_sequence) == 'table' and runtime.last_sequence or nil
	local regen = type(status.regen) == 'table' and status.regen or {}
	local storms = type(status.storms) == 'table' and status.storms or {}
	local sublimation = type(status.sublimation) == 'table' and status.sublimation or {}
	local candidate = type(status.candidate) == 'table' and status.candidate or nil
	local last_trace = type(status.last_trace) == 'table' and status.last_trace or nil
	local last_action_result = type(status.last_action_result) == 'table'
		and status.last_action_result or nil
	local lines = {}
	lines[#lines + 1] = ('UC SCH overview mode=%s enabled=%s eligibility=%s profile_generation=%s party_generation=%s candidate=%s blocker=%s proposals=%s'):format(
		display(status.mode),
		display(status.enabled),
		display(status.eligibility or runtime.eligibility),
		display(runtime.profile_generation),
		display(status.party_generation),
		display(candidate and candidate.action_name or 'none'),
		display(status.first_blocker),
		display(status.proposals_emitted)
	)
	lines[#lines + 1] = ('UC SCH context main_job=%s level=%s jp_present=%s jp_spent=%s engine=%s maintenance=%s player_hpp=%s environment_age_s=%s'):format(
		display(runtime.environment and runtime.environment.main_job),
		display(status.main_job_level),
		display(status.job_points_present),
		display(status.job_points_spent),
		display(runtime.environment and runtime.environment.engine_enabled),
		display(runtime.environment and runtime.environment.maintenance_enabled),
		display(runtime.environment and runtime.environment.player_hpp),
		display_age(now, runtime.environment and runtime.environment.observed_at)
	)
	lines[#lines + 1] = ('UC SCH arts observed=%s desired=%s age_s=%s commit_until=%s state=%s blocker=%s plan=%s recast=%s/%s readiness=%s sublimation_observed=%s sublimation_age_s=%s'):format(
		display(arts.observed),
		display(arts.desired),
		display_age(now, arts.observed_at),
		display(arts.commit_until),
		display(arts_evaluation.state),
		display(arts_evaluation.blocker),
		display(arts_evaluation.plan and arts_evaluation.plan.purpose or 'none'),
		display(arts_evaluation.plan and arts_evaluation.plan.recast_id or 'none'),
		display(arts_evaluation.plan and arts_evaluation.plan.observed_recast or 'none'),
		display(arts_evaluation.plan and arts_evaluation.plan.readiness_source or 'none'),
		display(runtime.sublimation and runtime.sublimation.observed),
		display_age(now, runtime.sublimation and runtime.sublimation.observed_at)
	)
	lines[#lines + 1] = ('UC SCH charge available=%s maximum=%s confidence=%s recast_present=%s recast=%s age_s=%s model=%s source=%s reason=%s tabula=%s last_used_at=%s'):format(
		display(charge.estimated_available),
		display(charge.maximum),
		display(charge.confidence),
		display(charge.recast_present),
		display(charge.observed_recast),
		display_age(now, charge.observed_at),
		display(charge.model_key),
		display(charge.decoder_source),
		display(charge.reason),
		display(charge.tabula_rasa_active),
		display(charge.last_used_at)
	)
	lines[#lines + 1] = ('UC SCH sequence id=%s generation=%s purpose=%s phase=%s deadline=%s pending=%s/%s expected_buff=%s lane=%s/%s retry_at=%s'):format(
		display(sequence and sequence.id or 'none'),
		display(sequence and sequence.generation or 'none'),
		display(sequence and sequence.purpose or 'none'),
		display(sequence and sequence.phase or 'none'),
		display(sequence and sequence.deadline or 'none'),
		display(pending and pending.action_type or 'none'),
		display(pending and pending.action_name or 'none'),
		display(pending and pending.expected_buff_id or 'none'),
		display(lane.class),
		display(lane.reason),
		display(runtime.next_retry_at)
	)
	lines[#lines + 1] = ('UC SCH regen state=%s blocker=%s missing=%s unknown=%s unowned=%s geometry=%s model=%s source=%s selected=%s/%s plan=%s/%s expected=%s charge_model=%s'):format(
		display(regen.state),
		display(regen.blocker),
		number_list(regen.missing_recipient_ids),
		number_list(regen.unknown_recipient_ids),
		number_list(regen.unowned_existing_recipient_ids),
		display(regen.geometry and regen.geometry.blocker),
		display(regen.geometry and regen.geometry.mechanics_model_key),
		display(regen.geometry and regen.geometry.mechanics_source),
		display(regen.geometry and regen.geometry.selected and regen.geometry.selected.anchor_id or 'none'),
		display(regen.geometry and regen.geometry.selected and regen.geometry.selected.coverage_count or 'none'),
		display(regen.plan and regen.plan.spell or 'none'),
		display(regen.plan and regen.plan.anchor_id or 'none'),
		number_list(planned_recipient_ids(regen.plan)),
		display(regen.plan and regen.plan.charge_model_key or 'none')
	)
	lines[#lines + 1] = ('UC SCH storms state=%s blocker=%s assignments=%s first_unsatisfied=%s plan=%s/%s expected=%s duration=%s/%s'):format(
		display(storms.state),
		display(storms.blocker),
		display(type(storms.assignments) == 'table' and #storms.assignments or nil),
		first_storm_assignment(storms),
		display(storms.plan and storms.plan.spell or 'none'),
		display(storms.plan and storms.plan.target_id or 'none'),
		number_list(planned_recipient_ids(storms.plan)),
		display(storms.plan and storms.plan.duration_confidence or 'none'),
		display(storms.plan and storms.plan.duration_model_key or 'none')
	)
	lines[#lines + 1] = ('UC SCH sublimation state=%s blocker=%s enabled=%s plan=%s recast=%s/%s readiness=%s safety=%s/%s release_capacity=%s/%s missing_mp=%s owned=%s unexpected=%s'):format(
		display(sublimation.state),
		display(sublimation.blocker),
		display(sublimation.enabled),
		display(sublimation.plan and sublimation.plan.purpose or 'none'),
		display(sublimation.plan and sublimation.plan.recast_id or 'none'),
		display(sublimation.plan and sublimation.plan.observed_recast or 'none'),
		display(sublimation.plan and sublimation.plan.readiness_source or 'none'),
		display(sublimation.plan and sublimation.plan.safety_model_key or 'none'),
		display(sublimation.plan and sublimation.plan.safety_source or 'none'),
		display(sublimation.plan and sublimation.plan.release_capacity_model_key or 'none'),
		display(sublimation.plan and sublimation.plan.minimum_missing_mp or 'none'),
		display(sublimation.plan and sublimation.plan.missing_mp or 'none'),
		owned_summary(runtime.owned_buffs),
		number_list(runtime.unexpected_recipients)
	)
	local owned_lines = owned_detail_lines(runtime.owned_buffs)
	for i = 1, #owned_lines do
		lines[#lines + 1] = owned_lines[i]
	end
	lines[#lines + 1] = ('UC SCH last_sequence id=%s generation=%s result=%s reason=%s finished_at=%s action_result=%s/%s/%s unknown_messages=%s trace=%s/%s/%s'):format(
		display(last and last.id or 'none'),
		display(last and last.generation or 'none'),
		display(last and last.result or 'none'),
		display(last and last.reason or 'none'),
		display(last and last.finished_at or 'none'),
		display(last_action_result and last_action_result.action_name or 'none'),
		display(last_action_result and last_action_result.outcome or 'none'),
		display(last_action_result and last_action_result.blocker or 'none'),
		number_list(last_action_result and last_action_result.unknown_message_ids or {}),
		display(status.trace_armed and status.trace_phase or 'idle'),
		display(last_trace and last_trace.id or 'none'),
		display(last_trace and last_trace.terminal_reason or 'none')
	)
	return lines
end

local function charge_signature(snapshot)
	local charge = snapshot.stratagem
	if type(charge) ~= 'table' then
		return 'unobserved'
	end
	return table.concat({
		display(charge.estimated_available),
		display(charge.maximum),
		display(charge.confidence),
		display(charge.recast_present),
		display(charge.model_key),
		display(charge.decoder_source),
		display(charge.reason),
		display(charge.tabula_rasa_active),
	}, '|')
end

local function owner_signature(snapshot)
	local owned = snapshot.owned_buffs
	if type(owned) ~= 'table' then
		return 'unobserved'
	end
	local parts = {}
	for target_id, families in pairs(owned) do
		for family, owner in pairs(families) do
			parts[#parts + 1] = table.concat({
				tostring(target_id),
				tostring(family),
				display(owner.exact_spell),
				display(owner.status_id),
				display(owner.presence),
			}, ':')
		end
	end
	table.sort(parts)
	return table.concat(parts, '|')
end

local function append(events, code, fields)
	events[#events + 1] = {
		code = code,
		fields = fields,
	}
end

function M.runtime_events(previous, current, at)
	if previous ~= nil then
		require_table(previous, 'Previous Scholar runtime snapshot')
	end
	require_table(current, 'Current Scholar runtime snapshot')
	local now = require_number(at, 'Scholar diagnostic event time')
	local events = {}
	if previous == nil or charge_signature(previous) ~= charge_signature(current) then
		local charge = require_table(current.stratagem, 'Current Scholar charge snapshot')
		append(events, 'SCH_CHARGE_OBSERVATION', {
			available = charge.estimated_available,
			maximum = charge.maximum,
			confidence = charge.confidence,
			recast_present = charge.recast_present,
			recast = charge.observed_recast,
			model = charge.model_key,
			source = charge.decoder_source,
			reason = charge.reason,
			at = now,
		})
	end
	local before_sequence = previous and previous.active_sequence or nil
	local after_sequence = current.active_sequence
	if before_sequence == nil and type(after_sequence) == 'table' then
		append(events, 'SCH_SEQUENCE_START', {
			id = after_sequence.id,
			generation = after_sequence.generation,
			purpose = after_sequence.purpose,
			phase = after_sequence.phase,
			at = now,
		})
	elseif type(before_sequence) == 'table' and type(after_sequence) == 'table'
		and (before_sequence.id ~= after_sequence.id
			or before_sequence.generation ~= after_sequence.generation
			or before_sequence.phase ~= after_sequence.phase) then
		append(events, 'SCH_SEQUENCE_TRANSITION', {
			id = after_sequence.id,
			generation = after_sequence.generation,
			from = before_sequence.phase,
			to = after_sequence.phase,
			at = now,
		})
	end
	local before_last = previous and previous.last_sequence or nil
	local after_last = current.last_sequence
	local last_changed = type(after_last) == 'table' and (
		type(before_last) ~= 'table'
		or before_last.id ~= after_last.id
		or before_last.generation ~= after_last.generation
		or before_last.finished_at ~= after_last.finished_at
	)
	if last_changed then
		local code = after_last.result == 'complete'
			and 'SCH_SEQUENCE_COMPLETE' or 'SCH_SEQUENCE_ABORT'
		append(events, code, {
			id = after_last.id,
			generation = after_last.generation,
			result = after_last.result,
			reason = after_last.reason,
			at = now,
		})
		if after_last.reason == 'action_rejected' then
			append(events, 'SCH_ACTION_REJECT', {
				id = after_last.id,
				generation = after_last.generation,
				at = now,
			})
		elseif after_last.reason == 'confirmation_timeout' then
			append(events, 'SCH_ACTION_TIMEOUT', {
				id = after_last.id,
				generation = after_last.generation,
				at = now,
			})
		end
	end
	if previous ~= nil and owner_signature(previous) ~= owner_signature(current) then
		append(events, 'SCH_RECIPIENT_RECONCILE', {
			owned = owned_summary(current.owned_buffs),
			at = now,
		})
	end
	local before_lane = previous and previous.lane or nil
	local after_lane = current.lane
	if type(after_lane) == 'table' then
		local before_reserved = type(before_lane) == 'table' and before_lane.reserved == true
		local after_reserved = after_lane.reserved == true
		if not before_reserved and after_reserved then
			append(events, 'SCH_LANE_ACQUIRE', {
				class = after_lane.class,
				reason = after_lane.reason,
				at = now,
			})
		elseif before_reserved and not after_reserved then
			append(events, 'SCH_LANE_RELEASE', {
				class = before_lane.class,
				reason = current.last_sequence and current.last_sequence.reason or '',
				at = now,
			})
		end
	end
	return events
end

function M.event_line(event)
	require_table(event, 'Scholar diagnostic event')
	if type(event.code) ~= 'string' or event.code == '' then
		error('Scholar diagnostic event code must be a non-empty string')
	end
	local fields = require_table(event.fields, 'Scholar diagnostic event fields')
	local keys = {}
	for key in pairs(fields) do
		if type(key) ~= 'string' then
			error('Scholar diagnostic event field keys must be strings')
		end
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local parts = { event.code }
	for i = 1, #keys do
		local key = keys[i]
		parts[#parts + 1] = key .. '=' .. display(fields[key])
	end
	return table.concat(parts, ' ')
end

function M.trace_lines(record)
	require_table(record, 'Scholar trace record')
	if type(record.events) ~= 'table' then
		error('Scholar trace record events must be a table')
	end
	local lines = {
		('UC SCH trace id=%s phase=%s action=%s terminal=%s events=%d'):format(
			display(record.id),
			display(record.phase),
			display(record.focus_action_name),
			display(record.terminal_reason),
			#record.events
		),
	}
	for index = 1, #record.events do
		local event = require_table(record.events[index], 'Scholar trace event')
		if type(event.kind) ~= 'string' or event.kind == '' then
			error('Scholar trace event kind must be a non-empty string')
		end
		local prefix = ('  %02d %s %s'):format(index, display(event.at), event.kind)
		if event.kind == 'sample' then
			lines[#lines + 1] = prefix .. (' level=%s jp=%s/%s recast=%s/%s buffs=%s candidate=%s blocker=%s party_generation=%s party=%d'):format(
				display(event.main_job_level),
				display(event.job_points_present),
				display(event.job_points_spent),
				display(event.recast_present),
				display(event.recast),
				number_list(event.buffs),
				display(event.candidate),
				display(event.blocker),
				display(event.party_generation),
				type(event.party) == 'table' and #event.party or 0
			)
			local party = require_table(event.party, 'Scholar trace sample event party')
			for member_index = 1, #party do
				local member = require_table(party[member_index], 'Scholar trace sample event member')
				lines[#lines + 1] = ('    party[%d] id=%s name=%s hpp=%s xyz=%s,%s,%s coordinate_observed_at=%s source=%s buff_source=%s buffs=%s'):format(
					member_index,
					display(member.id),
					display(member.name),
					display(member.hpp),
					display(member.x),
					display(member.y),
					display(member.z),
					display(member.coordinate_observed_at),
					display(member.source),
					display(member.buff_source),
					number_list(member.buffs)
				)
			end
		elseif event.kind == 'action' then
			lines[#lines + 1] = prefix .. (' category=%s id=%s name=%s targets=%d'):format(
				display(event.category),
				display(event.action_id),
				display(event.action_name),
				type(event.targets) == 'table' and #event.targets or 0
			)
			local targets = require_table(event.targets, 'Scholar trace action event targets')
			for target_index = 1, #targets do
				local target = require_table(targets[target_index], 'Scholar trace action event target')
				local actions = require_table(target.actions, 'Scholar trace action event target actions')
				for action_index = 1, #actions do
					local action = require_table(actions[action_index], 'Scholar trace action event result')
					lines[#lines + 1] = ('    target[%d].action[%d] id=%s message=%s param=%s add=%s/%s spike=%s/%s'):format(
						target_index,
						action_index,
						display(target.target_id),
						display(action.message),
						display(action.param),
						display(action.add_effect_message),
						display(action.add_effect_param),
						display(action.spike_effect_message),
						display(action.spike_effect_param)
					)
				end
			end
		elseif event.kind == 'action_message' then
			lines[#lines + 1] = prefix .. (' actor=%s target=%s message=%s params=%s,%s,%s source=%s'):format(
				display(event.actor_id),
				display(event.target_id),
				display(event.message_id),
				display(event.param_1),
				display(event.param_2),
				display(event.param_3),
				display(event.source)
			)
		elseif event.kind == 'terminal' then
			lines[#lines + 1] = prefix .. ' reason=' .. display(event.reason)
		elseif event.kind == 'armed' then
			lines[#lines + 1] = prefix
		else
			error('Unsupported Scholar trace event kind: ' .. event.kind)
		end
	end
	return lines
end

return M
