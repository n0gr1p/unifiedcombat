local capabilities = require('uc_sch_capabilities')

local M = {}

local ARM_TIMEOUT_S = 30
local SETTLE_S = 2
local EVENT_LIMIT = 64

local ability_names = {}
for _, ability in pairs(capabilities.abilities) do
	ability_names[ability.id] = ability.name
end

local spell_names = {
	[capabilities.regen_spells['Regen V'].id] = 'Regen V',
	[capabilities.embrava.id] = 'Embrava',
}
for _, spell in pairs(capabilities.storm_spells) do
	spell_names[spell.id] = spell.name
end

local ability_categories = { [6] = true, [13] = true, [14] = true, [15] = true }
local spell_categories = { [4] = true, [8] = true }

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

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar trace values must not contain cycles')
	end
	visited[value] = true
	local out = {}
	for key, inner in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner, visited)
	end
	visited[value] = nil
	return out
end

local function sorted_number_list(values)
	local out = {}
	for i = 1, #values do
		local value = values[i]
		if type(value) ~= 'number' or value < 0 or value % 1 ~= 0 then
			error('Scholar trace buff ids must be non-negative integers')
		end
		out[#out + 1] = value
	end
	table.sort(out)
	return out
end

local function optional_number(value, name)
	if value ~= nil and type(value) ~= 'number' then
		error(name .. ' must be numeric when present')
	end
	return value
end

local function party_signature(party)
	require_table(party, 'Scholar trace sample party')
	if #party > 6 then
		error('Scholar trace sample party must contain no more than six members')
	end
	local parts = {}
	local seen_ids = {}
	for i = 1, #party do
		local member = require_table(party[i], 'Scholar trace sample party member')
		if type(member.id) ~= 'number' or member.id <= 0 or member.id % 1 ~= 0 then
			error('Scholar trace party member id must be a positive integer')
		end
		if seen_ids[member.id] then
			error('Scholar trace party member ids must be unique')
		end
		seen_ids[member.id] = true
		if type(member.name) ~= 'string' or member.name == '' then
			error('Scholar trace party member name must be a non-empty string')
		end
		if type(member.hpp) ~= 'number' or member.hpp < 0 or member.hpp > 100 then
			error('Scholar trace party member hpp must be a number from 0 through 100')
		end
		optional_number(member.x, 'Scholar trace party member x')
		optional_number(member.y, 'Scholar trace party member y')
		optional_number(member.z, 'Scholar trace party member z')
		optional_number(
			member.coordinate_observed_at,
			'Scholar trace party member coordinate_observed_at'
		)
		if type(member.x) == 'number' and type(member.y) == 'number'
			and type(member.coordinate_observed_at) ~= 'number' then
			error('Scholar trace party member coordinates require coordinate_observed_at')
		end
		if member.source ~= nil and type(member.source) ~= 'string' then
			error('Scholar trace party member source must be a string when present')
		end
		if member.buff_source ~= nil and type(member.buff_source) ~= 'string' then
			error('Scholar trace party member buff_source must be a string when present')
		end
		local buffs = member.buffs == nil and nil or sorted_number_list(
			require_table(member.buffs, 'Scholar trace party member buffs')
		)
		parts[#parts + 1] = table.concat({
			tostring(member.id),
			member.name,
			tostring(member.hpp),
			tostring(member.x),
			tostring(member.y),
			tostring(member.z),
			tostring(member.source),
			tostring(member.buff_source),
			buffs == nil and 'nil' or table.concat(buffs, ','),
		}, ':')
	end
	return table.concat(parts, '|')
end

local function sample_signature(sample)
	local buffs = sorted_number_list(require_table(sample.buffs, 'Scholar trace sample buffs'))
	local party_state_signature = party_signature(sample.party)
	if type(sample.main_job) ~= 'string' or sample.main_job == '' then
		error('Scholar trace main_job must be a non-empty string')
	end
	if type(sample.main_job_level) ~= 'number'
		or sample.main_job_level <= 0
		or sample.main_job_level % 1 ~= 0 then
		error('Scholar trace main_job_level must be a positive integer')
	end
	if type(sample.job_points_present) ~= 'boolean' then
		error('Scholar trace job_points_present must be a boolean')
	end
	if type(sample.job_points_spent) ~= 'number'
		or sample.job_points_spent < 0
		or sample.job_points_spent % 1 ~= 0 then
		error('Scholar trace job_points_spent must be a non-negative integer')
	end
	if type(sample.recast_present) ~= 'boolean' then
		error('Scholar trace recast_present must be a boolean')
	end
	if sample.recast_present then
		if type(sample.recast) ~= 'number' or sample.recast < 0 then
			error('Scholar trace recast must be a non-negative number when present')
		end
	elseif sample.recast ~= nil then
		error('Scholar trace recast must be nil when absent')
	end
	if type(sample.candidate) ~= 'string' or type(sample.blocker) ~= 'string' then
		error('Scholar trace candidate and blocker must be strings')
	end
	if type(sample.party_generation) ~= 'number'
		or sample.party_generation <= 0
		or sample.party_generation % 1 ~= 0 then
		error('Scholar trace party_generation must be a positive integer')
	end
	return table.concat({
		tostring(sample.main_job),
		tostring(sample.main_job_level),
		tostring(sample.job_points_present),
		tostring(sample.job_points_spent),
		tostring(sample.recast_present),
		tostring(sample.recast),
		table.concat(buffs, ','),
		tostring(sample.candidate),
		tostring(sample.blocker),
		tostring(sample.party_generation),
		party_state_signature,
	}, '|'), buffs
end

local function raw_targets(targets)
	require_table(targets, 'Scholar trace action targets')
	local out = {}
	for target_index = 1, #targets do
		local target = targets[target_index]
		require_table(target, 'Scholar trace action target')
		if type(target.id) ~= 'number' or target.id <= 0 or target.id % 1 ~= 0 then
			error('Scholar trace action target id must be a positive integer')
		end
		local actions = require_table(target.actions, 'Scholar trace target actions')
		local copied = {
			target_id = target.id,
			actions = {},
		}
		for action_index = 1, #actions do
			local action = require_table(actions[action_index], 'Scholar trace target action')
			if type(action.message) ~= 'number' or action.message < 0 or action.message % 1 ~= 0 then
				error('Scholar trace target action message must be a non-negative integer')
			end
			if type(action.param) ~= 'number' or action.param < 0 or action.param % 1 ~= 0 then
				error('Scholar trace target action param must be a non-negative integer')
			end
			local optional_fields = {
				'add_effect_message',
				'add_effect_param',
				'spike_effect_message',
				'spike_effect_param',
			}
			for i = 1, #optional_fields do
				local value = action[optional_fields[i]]
				if value ~= nil and type(value) ~= 'number' then
					error('Scholar trace optional action fields must be numeric when present')
				end
			end
			copied.actions[#copied.actions + 1] = {
				message = action.message,
				param = action.param,
				add_effect_message = action.add_effect_message,
				add_effect_param = action.add_effect_param,
				spike_effect_message = action.spike_effect_message,
				spike_effect_param = action.spike_effect_param,
			}
		end
		out[#out + 1] = copied
	end
	return out
end

function M.new()
	local recorder = {
		next_id = 0,
		active = nil,
		last = nil,
	}

	local function append(event)
		local trace = recorder.active
		if trace == nil then
			return false
		end
		if #trace.events >= EVENT_LIMIT then
			trace.phase = 'complete'
			trace.terminal_reason = 'event_limit'
			trace.completed_at = event.at
			recorder.last = trace
			recorder.active = nil
			return false
		end
		trace.events[#trace.events + 1] = event
		return true
	end

	local function finish(reason, now)
		local trace = recorder.active
		if trace == nil then
			return false
		end
		trace.phase = 'complete'
		trace.terminal_reason = tostring(reason)
		trace.completed_at = require_number(now, 'Scholar trace completion time')
		append({ kind = 'terminal', at = now, reason = reason })
		recorder.last = trace
		recorder.active = nil
		return true
	end

	function recorder.arm(now)
		now = require_number(now, 'Scholar trace arm time')
		if recorder.active ~= nil then
			return false, 'Scholar one-shot trace is already armed.'
		end
		recorder.next_id = recorder.next_id + 1
		recorder.active = {
			id = recorder.next_id,
			phase = 'awaiting_relevant_action',
			armed_at = now,
			expires_at = now + ARM_TIMEOUT_S,
			settle_until = 0,
			terminal_reason = '',
			events = {
				{ kind = 'armed', at = now },
			},
			last_sample_signature = '',
		}
		return true, 'Scholar one-shot transaction trace armed for 30 seconds.'
	end

	function recorder.observe_sample(sample, now)
		if recorder.active == nil then
			return false
		end
		now = require_number(now, 'Scholar trace sample time')
		require_table(sample, 'Scholar trace sample')
		local trace = recorder.active
		local signature, buffs = sample_signature(sample)
		if signature ~= trace.last_sample_signature then
			trace.last_sample_signature = signature
			append({
				kind = 'sample',
				at = now,
				main_job = tostring(sample.main_job),
				main_job_level = sample.main_job_level,
				job_points_present = sample.job_points_present,
				job_points_spent = sample.job_points_spent,
				recast_present = sample.recast_present,
				recast = sample.recast,
				buffs = buffs,
				candidate = tostring(sample.candidate or ''),
				blocker = tostring(sample.blocker or ''),
				party_generation = require_number(
					sample.party_generation,
					'Scholar trace sample party generation'
				),
				party = clone_value(require_table(sample.party, 'Scholar trace sample party')),
			})
		end
		return recorder.tick(now)
	end

	function recorder.observe_action(act, player_id, now)
		if recorder.active == nil then
			return false
		end
		now = require_number(now, 'Scholar trace action time')
		require_table(act, 'Scholar trace action')
		if type(player_id) ~= 'number' or player_id <= 0 or player_id % 1 ~= 0 then
			error('Scholar trace player id must be a positive integer')
		end
		if type(act.actor_id) ~= 'number' then
			error('Scholar trace action actor id must be numeric')
		end
		if act.actor_id ~= player_id then
			return false
		end
		if type(act.category) ~= 'number' or act.category < 0 or act.category % 1 ~= 0 then
			error('Scholar trace action category must be a non-negative integer')
		end
		if type(act.param) ~= 'number' or act.param < 0 or act.param % 1 ~= 0 then
			error('Scholar trace action id must be a non-negative integer')
		end
		local category = act.category
		local action_id = act.param
		local action_name = ability_categories[category] and ability_names[action_id]
			or (spell_categories[category] and spell_names[action_id] or nil)
		local trace = recorder.active
		if trace.phase == 'awaiting_relevant_action' and action_name == nil then
			return false
		end
		if not ability_categories[category] and not spell_categories[category] then
			return false
		end
		if trace.phase == 'awaiting_relevant_action' then
			trace.phase = 'capturing'
			trace.focus_action_id = action_id
			trace.focus_action_name = action_name
		elseif trace.focus_action_name == 'action_message' and action_name ~= nil then
			trace.focus_action_id = action_id
			trace.focus_action_name = action_name
		end
		append({
			kind = 'action',
			at = now,
			category = category,
			action_id = action_id,
			action_name = action_name or '',
			targets = raw_targets(require_table(act.targets, 'Scholar trace action targets')),
		})
		if category == 8 then
			trace.phase = 'capturing'
			trace.settle_until = 0
		elseif category == 4 or ability_categories[category] then
			trace.phase = 'settling'
			trace.settle_until = now + SETTLE_S
		end
		return true
	end

	function recorder.observe_action_message(msg, player_id, now)
		if recorder.active == nil then
			return false
		end
		now = require_number(now, 'Scholar trace action-message time')
		require_table(msg, 'Scholar trace action message')
		if type(player_id) ~= 'number' or player_id <= 0 or player_id % 1 ~= 0 then
			error('Scholar trace action-message player id must be a positive integer')
		end
		if type(msg.actor_id) ~= 'number' then
			error('Scholar trace action-message actor id must be numeric')
		end
		if msg.actor_id ~= player_id then
			return false
		end
		local required_fields = { 'target_id', 'message_id', 'param_1' }
		for i = 1, #required_fields do
			local value = msg[required_fields[i]]
			if type(value) ~= 'number' or value < 0 or value % 1 ~= 0 then
				error('Scholar trace action-message required fields must be non-negative integers')
			end
		end
		local optional_fields = { 'param_2', 'param_3' }
		for i = 1, #optional_fields do
			local value = msg[optional_fields[i]]
			if value ~= nil and (type(value) ~= 'number' or value < 0 or value % 1 ~= 0) then
				error('Scholar trace optional action-message fields must be non-negative integers when present')
			end
		end
		local trace = recorder.active
		if trace.phase == 'awaiting_relevant_action' then
			trace.phase = 'settling'
			trace.focus_action_id = 0
			trace.focus_action_name = 'action_message'
			trace.settle_until = now + SETTLE_S
		end
		append({
			kind = 'action_message',
			at = now,
			actor_id = msg.actor_id,
			target_id = msg.target_id,
			message_id = msg.message_id,
			param_1 = msg.param_1,
			param_2 = msg.param_2,
			param_3 = msg.param_3,
			source = tostring(msg._uc_source or ''),
		})
		return true
	end

	function recorder.tick(now)
		if recorder.active == nil then
			return false
		end
		now = require_number(now, 'Scholar trace tick time')
		local trace = recorder.active
		if trace.phase == 'settling' and now >= trace.settle_until then
			return finish('settled', now)
		end
		if now >= trace.expires_at then
			return finish('timeout_' .. trace.phase, now)
		end
		return false
	end

	function recorder.snapshot()
		return {
			armed = recorder.active ~= nil,
			active = clone_value(recorder.active),
			last = clone_value(recorder.last),
		}
	end

	return recorder
end

return M
