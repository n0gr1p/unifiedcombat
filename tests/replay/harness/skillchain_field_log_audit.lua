local M = {}

local function trim(value)
	return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function parse_fields(text)
	local source = tostring(text or '')
	local starts = {}
	local search_at = 1
	while true do
		local field_start, equals_at, key = source:find('([%a_][%w_]*)=', search_at)
		if not field_start then
			break
		end
		if field_start == 1 or source:sub(field_start - 1, field_start - 1) == ' ' then
			starts[#starts + 1] = {
				field_start = field_start,
				value_start = equals_at + 1,
				key = key,
			}
		end
		search_at = equals_at + 1
	end
	local fields = {}
	for i = 1, #starts do
		local item = starts[i]
		local value_end = (starts[i + 1] and starts[i + 1].field_start - 2) or #source
		fields[item.key] = trim(source:sub(item.value_start, value_end))
	end
	return fields
end

local function parse_line(line)
	local elapsed, actor, event_code, tail = tostring(line or ''):match('^([%d%.]+) | ([^|]+) | ([A-Z0-9_]+)%s*|?%s*(.*)$')
	if not elapsed then
		return nil
	end
	return {
		elapsed = tonumber(elapsed) or 0,
		actor = trim(actor),
		event_code = event_code,
		fields = parse_fields(tail),
	}
end

local function plan_key(fields)
	return table.concat({
		tostring(fields.target_id or ''),
		tostring(fields.resonance_generation or ''),
		tostring(fields.ws_id or ''),
	}, ':')
end

function M.audit_lines(lines, options)
	options = options or {}
	local minimum_dispatches = tonumber(options.minimum_dispatches) or 5
	local plans = {}
	local dispatches = {}
	local pending_results = {}
	local failures = {}
	local session_count = 0
	local ultimate_predictions = 0
	local after_preferred_min = nil
	local before_latest_min = nil

	local function reset_session()
		plans = {}
		dispatches = {}
		pending_results = {}
		failures = {}
		ultimate_predictions = 0
		after_preferred_min = nil
		before_latest_min = nil
	end

	for i = 1, #(lines or {}) do
		local event = parse_line(lines[i])
		if event then
			if event.event_code == 'SESSION_START' then
				session_count = session_count + 1
				reset_session()
			elseif session_count > 0 then
				local fields = event.fields
				if event.event_code == 'SC_CONTINUATION_PLANNED' then
					local key = plan_key(fields)
					plans[key] = fields
					if fields.predicted_result == 'Radiance' or fields.predicted_result == 'Umbra' then
						ultimate_predictions = ultimate_predictions + 1
					end
				elseif event.event_code == 'SC_COMMIT_RESULT'
					and fields.commit_stage == 'dispatch_commit'
					and fields.commit_result == 'SC_DISPATCHED' then
					local key = plan_key(fields)
					local plan = plans[key]
					if not plan then
						failures[#failures + 1] = 'dispatch missing matching plan: ' .. key
					else
						local observed_at = tonumber(fields.observed_at)
						local preferred_at = tonumber(plan.preferred_execute_at)
						local latest_safe_at = tonumber(plan.latest_safe_at)
						if not observed_at or not preferred_at or not latest_safe_at then
							failures[#failures + 1] = 'dispatch has incomplete timing: ' .. key
						else
							local after_preferred = observed_at - preferred_at
							local before_latest = latest_safe_at - observed_at
							after_preferred_min = math.min(after_preferred_min or after_preferred, after_preferred)
							before_latest_min = math.min(before_latest_min or before_latest, before_latest)
							if after_preferred < 0 then
								failures[#failures + 1] = 'dispatch before preferred time: ' .. key
							end
							if before_latest < 0 then
								failures[#failures + 1] = 'dispatch after latest-safe time: ' .. key
							end
						end
					end
					dispatches[key] = (dispatches[key] or 0) + 1
					if dispatches[key] > 1 then
						failures[#failures + 1] = 'duplicate dispatch for target/generation/WS: ' .. key
					end
				elseif event.event_code == 'SC_DISPATCH_PENDING_RESULT' then
					pending_results[plan_key(fields)] = true
				end
			end
		end
	end

	if session_count == 0 then
		failures[#failures + 1] = 'no SESSION_START found'
	end
	local dispatch_count = 0
	for key, count in pairs(dispatches) do
		dispatch_count = dispatch_count + count
		if pending_results[key] ~= true then
			failures[#failures + 1] = 'dispatch missing pending-result reservation: ' .. key
		end
	end
	if dispatch_count < minimum_dispatches then
		failures[#failures + 1] = ('expected at least %d dispatches; observed %d'):format(minimum_dispatches, dispatch_count)
	end
	if options.expect_non_aeonic == true and ultimate_predictions > 0 then
		failures[#failures + 1] = ('non-Aeonic session predicted %d Ultimate continuation(s)'):format(ultimate_predictions)
	end

	return {
		ok = #failures == 0,
		failures = failures,
		session_count = session_count,
		dispatch_count = dispatch_count,
		ultimate_predictions = ultimate_predictions,
		after_preferred_min = after_preferred_min,
		before_latest_min = before_latest_min,
	}
end

function M.audit_file(path, options)
	local handle, err = io.open(path, 'r')
	if not handle then
		error('failed to open field log ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local lines = {}
	for line in handle:lines() do
		lines[#lines + 1] = line
	end
	handle:close()
	return M.audit_lines(lines, options)
end

return M
