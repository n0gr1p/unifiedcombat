local M = {}

local DHARTOK_POST_CESSPOOL_TP_KEYS = {
	clobbering_wave = true,
	fetid_eddies = true,
	noyade = true,
	nullifying_rain = true,
}

local function field(line, name)
	return line:match(name .. '=([^ ]*)')
end

function M.parse_line(line)
	if type(line) ~= 'string' then
		error('encounter field audit line must be a string')
	end
	if line:find('| ENCOUNTER_RAW_ABILITY_CANDIDATE |', 1, true) then
		return {
			event = 'ability',
			actor_id = tonumber(field(line, 'actor_id')) or 0,
			actor_name = tostring(field(line, 'actor_name') or ''),
			category = tonumber(field(line, 'category')) or 0,
			phase = tostring(field(line, 'phase') or ''),
			ability_id = tonumber(field(line, 'ability_id')) or 0,
			ability_key = tostring(field(line, 'ability_key') or ''),
			target_count = tonumber(field(line, 'target_count')) or 0,
			targets_summary = tostring(field(line, 'targets_summary') or ''),
			actions_summary = tostring(field(line, 'actions_summary') or ''),
			observed_at = tonumber(field(line, 'observed_at')),
		}
	end
	if line:find('| ENCOUNTER_RAW_ACTION_RESULT_CANDIDATE |', 1, true) then
		return {
			event = 'action_result',
			action_class = tostring(field(line, 'action_class') or ''),
			action_key = tostring(field(line, 'action_key') or ''),
			actor_id = tonumber(field(line, 'actor_id')) or 0,
			target_id = tonumber(field(line, 'target_id')) or 0,
			target_name = tostring(field(line, 'target_name') or ''),
			success = field(line, 'success') == 'true',
			observed_at = tonumber(field(line, 'observed_at')),
		}
	end
	return nil
end

local function target_coordinates_resolved(summary)
	return summary ~= ''
		and summary:find('x=,', 1, true) == nil
		and summary:find('y=,', 1, true) == nil
end

function M.analyze(lines)
	if type(lines) ~= 'table' then
		error('encounter field audit lines must be a table')
	end
	local result = {
		ability_events = {},
		action_results = {},
		ability_counts = {},
		cesspool_sequences = {},
	}
	for i = 1, #lines do
		local event = M.parse_line(lines[i])
		if event ~= nil then
			if event.event == 'ability' then
				result.ability_events[#result.ability_events + 1] = event
				local key = table.concat({
					event.actor_name,
					event.ability_key,
					event.phase,
					tostring(event.category),
				}, ':')
				result.ability_counts[key] = (result.ability_counts[key] or 0) + 1
			else
				result.action_results[#result.action_results + 1] = event
			end
		end
	end
	for i = 1, #result.ability_events do
		local event = result.ability_events[i]
		if event.actor_name == 'Dhartok'
			and event.ability_key == 'cesspool'
			and event.phase == 'completed' then
			local following = {}
			for j = i + 1, #result.ability_events do
				local candidate = result.ability_events[j]
				if candidate.actor_id == event.actor_id
					and candidate.phase == 'completed'
					and candidate.ability_key == 'cesspool' then
					break
				end
				if candidate.observed_at ~= nil
					and event.observed_at ~= nil
					and candidate.observed_at - event.observed_at > 180.0 then
					break
				end
				if candidate.actor_id == event.actor_id
					and candidate.phase == 'completed'
					and DHARTOK_POST_CESSPOOL_TP_KEYS[candidate.ability_key] == true then
					following[#following + 1] = candidate
					if #following == 2 then
						break
					end
				end
			end
			local second = following[2]
			result.cesspool_sequences[#result.cesspool_sequences + 1] = {
				cesspool = event,
				first_tp = following[1],
				second_tp = second,
				second_target_authoritative = second ~= nil
					and second.target_count == 1
					and target_coordinates_resolved(second.targets_summary),
			}
		end
	end
	return result
end

function M.summary_lines(result)
	if type(result) ~= 'table' then
		error('encounter field audit result must be a table')
	end
	local lines = {
		('raw_ability_events=%d raw_action_results=%d cesspool_sequences=%d'):format(
			#(result.ability_events or {}),
			#(result.action_results or {}),
			#(result.cesspool_sequences or {})
		),
	}
	local keys = {}
	for key in pairs(result.ability_counts or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for i = 1, #keys do
		lines[#lines + 1] = ('ability %s count=%d'):format(keys[i], result.ability_counts[keys[i]])
	end
	for i = 1, #(result.cesspool_sequences or {}) do
		local sequence = result.cesspool_sequences[i]
		lines[#lines + 1] = ('cesspool_sequence index=%d first=%s second=%s authoritative_second_target=%s targets=%s'):format(
			i,
			tostring(sequence.first_tp and sequence.first_tp.ability_key or ''),
			tostring(sequence.second_tp and sequence.second_tp.ability_key or ''),
			tostring(sequence.second_target_authoritative == true),
			tostring(sequence.second_tp and sequence.second_tp.targets_summary or '')
		)
	end
	return lines
end

return M
