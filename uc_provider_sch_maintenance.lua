local sch_config = require('uc_sch_config')
local sch_action_observer = require('uc_sch_action_observer')
local sch_action_results = require('uc_sch_action_results')
local sch_charge_model = require('uc_sch_charge_model')
local sch_diagnostics = require('uc_sch_diagnostics')
local sch_maintenance = require('uc_sch_maintenance')
local sch_party = require('uc_sch_party')
local sch_runtime = require('uc_sch_runtime')
local sch_trace = require('uc_sch_trace')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(value, name)
	if type(value) ~= 'function' then
		error(name .. ' must be a function')
	end
	return value
end

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar provider status must not contain cycles')
	end
	visited[value] = true
	local out = {}
	for key, inner in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner, visited)
	end
	visited[value] = nil
	return out
end

local function sorted_keys(value)
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		local left_type = type(left)
		local right_type = type(right)
		if left_type ~= right_type then
			return left_type < right_type
		end
		return tostring(left) < tostring(right)
	end)
	return keys
end

local function signature(value, seen)
	local value_type = type(value)
	if value_type ~= 'table' then
		return value_type .. ':' .. tostring(value)
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar provider config must not contain cycles')
	end
	visited[value] = true
	local parts = { 'table{' }
	local keys = sorted_keys(value)
	for i = 1, #keys do
		local key = keys[i]
		parts[#parts + 1] = signature(key, visited)
		parts[#parts + 1] = '='
		parts[#parts + 1] = signature(value[key], visited)
		parts[#parts + 1] = ';'
	end
	parts[#parts + 1] = '}'
	visited[value] = nil
	return table.concat(parts)
end

local function player_progress(player)
	local level = player.main_job_level
	if type(level) ~= 'number' or level <= 0 or level % 1 ~= 0 then
		error('Scholar provider main_job_level must be a positive integer')
	end
	local present = false
	local spent = 0
	if player.job_points ~= nil then
		if type(player.job_points) ~= 'table' then
			error('Scholar provider job_points must be a table when present')
		end
		local job_key = tostring(player.main_job):lower()
		local row = player.job_points[job_key]
		if row ~= nil then
			if type(row) ~= 'table' then
				error('Scholar provider main-job job-point row must be a table')
			end
			if type(row.jp_spent) ~= 'number'
				or row.jp_spent < 0
				or row.jp_spent % 1 ~= 0 then
				error('Scholar provider jp_spent must be a non-negative integer')
			end
			present = true
			spent = row.jp_spent
		end
	end
	return level, present, spent
end

function M.new(deps)
	deps = require_table(deps, 'Scholar provider dependencies')
	local get_party_members = require_function(deps.get_party_members, 'deps.get_party_members')
	local resolve_spell_name = require_function(deps.resolve_spell_name, 'deps.resolve_spell_name')
	local resolve_ability_name = require_function(deps.resolve_ability_name, 'deps.resolve_ability_name')
	local get_action_result_catalog = require_function(
		deps.get_action_result_catalog,
		'deps.get_action_result_catalog'
	)
	local get_charge_catalog = require_function(deps.get_charge_catalog, 'deps.get_charge_catalog')
	local get_area_mechanics = require_function(deps.get_area_mechanics, 'deps.get_area_mechanics')
	local log = require_function(deps.log, 'deps.log')
	local runtime = deps.runtime or sch_runtime
	local provider = {
		generation = 0,
		config_signature = '',
		status = {
			mode = 'observe_only',
			first_blocker = 'not_evaluated',
		},
		trace = sch_trace.new(),
		party_tracker = sch_party.new_tracker(),
		last_logged_trace_id = 0,
		last_runtime_snapshot = nil,
		last_observe_signature = '',
		last_action_result = nil,
	}

	function provider.collect(ctx, out)
		require_table(ctx, 'Scholar provider context')
		require_table(out, 'Scholar provider output')
		local settings = require_table(ctx.settings, 'Scholar provider settings')
		local config = settings.sch
		if config == nil then
			config = sch_config.default_config()
		end
		local config_signature = signature(config)
		if provider.config_signature ~= config_signature then
			provider.config_signature = config_signature
			provider.generation = provider.generation + 1
		end
		local player = require_table(ctx.player, 'Scholar provider player')
		local vitals = require_table(player.vitals, 'Scholar provider player vitals')
		local main_job_level, job_points_present, job_points_spent = player_progress(player)
		local party_members = get_party_members(ctx)
		local party_snapshot = sch_party.observe(provider.party_tracker, party_members, ctx.now)
		local observed_party_members = party_snapshot.members
		runtime.configure(config, { main_job = player.main_job }, provider.generation, ctx.now)
		runtime.observe_environment({
			engine_enabled = ctx.engine_enabled,
			maintenance_enabled = ctx.maintenance_enabled,
			main_job = player.main_job,
			player_hpp = vitals.hpp,
			party_generation = party_snapshot.generation,
			party_members = observed_party_members,
		}, ctx.now)
		runtime.observe_player_buffs(require_table(player.buffs, 'Scholar provider player buffs'), ctx.now)
		runtime.observe_party_buffs(observed_party_members, ctx.now)
		if type(ctx.ability_recasts_present) ~= 'boolean' then
			error('Scholar provider ability_recasts_present must be a boolean')
		end
		local observed_recast = nil
		if ctx.ability_recasts_present then
			local recasts = require_table(ctx.ability_recasts, 'Scholar provider ability recasts')
			observed_recast = recasts[231]
			if type(observed_recast) ~= 'number' or observed_recast < 0 then
				error('Scholar provider ability recasts missing shared id 231')
			end
		end
		local tabula_rasa_active = runtime.snapshot().stratagem.tabula_rasa_active
		local charge_observation = sch_charge_model.decode({
			main_job_level = main_job_level,
			job_points_present = job_points_present,
			job_points_spent = job_points_spent,
			recast_present = ctx.ability_recasts_present,
			observed_recast = observed_recast,
			tabula_rasa_active = tabula_rasa_active,
		}, get_charge_catalog(main_job_level, job_points_present, job_points_spent))
		runtime.observe_charge(charge_observation, ctx.now)
		runtime.tick(ctx.now)
		local runtime_snapshot = runtime.snapshot()
		local evaluation = sch_maintenance.evaluate(config, {
			now = ctx.now,
			player = player,
			party_members = observed_party_members,
			area_mechanics = get_area_mechanics(),
		}, runtime_snapshot)
		provider.status = evaluation
		provider.status.runtime = runtime_snapshot
		provider.status.party_generation = party_snapshot.generation
		provider.status.party_roster_signature = party_snapshot.roster_signature
		provider.status.main_job_level = main_job_level
		provider.status.job_points_present = job_points_present
		provider.status.job_points_spent = job_points_spent
		provider.status.proposals_emitted = 0
		provider.status.last_action_result = clone_value(provider.last_action_result)
		local runtime_events = sch_diagnostics.runtime_events(
			provider.last_runtime_snapshot,
			runtime_snapshot,
			ctx.now
		)
		local diagnostics_active = evaluation.enabled == true
			or runtime_snapshot.active_sequence ~= nil
			or (provider.last_runtime_snapshot ~= nil
				and provider.last_runtime_snapshot.active_sequence ~= nil)
		if diagnostics_active then
			for i = 1, #runtime_events do
				log(sch_diagnostics.event_line(runtime_events[i]))
			end
		end
		provider.last_runtime_snapshot = clone_value(runtime_snapshot)
		local trace_completed = provider.trace.observe_sample({
			main_job = player.main_job,
			main_job_level = main_job_level,
			job_points_present = job_points_present,
			job_points_spent = job_points_spent,
			recast_present = ctx.ability_recasts_present == true,
			recast = observed_recast,
			buffs = player.buffs,
			candidate = evaluation.candidate and evaluation.candidate.action_name or '',
			blocker = evaluation.first_blocker or '',
			party = observed_party_members,
			party_generation = party_snapshot.generation,
		}, ctx.now)
		local trace_snapshot = provider.trace.snapshot()
		provider.status.trace_armed = trace_snapshot.armed
		provider.status.trace_phase = trace_snapshot.active and trace_snapshot.active.phase or 'idle'
		provider.status.last_trace = trace_snapshot.last
		local observe_signature = signature({
			enabled = evaluation.enabled,
			candidate = evaluation.candidate and evaluation.candidate.action_name or '',
			blocker = evaluation.first_blocker,
			arts = evaluation.arts and evaluation.arts.state or '',
			regen = evaluation.regen and evaluation.regen.state or '',
			storms = evaluation.storms and evaluation.storms.state or '',
			sublimation = evaluation.sublimation and evaluation.sublimation.state or '',
			lane = runtime_snapshot.lane.class,
			party_generation = party_snapshot.generation,
		})
		if evaluation.enabled and observe_signature ~= provider.last_observe_signature then
			provider.last_observe_signature = observe_signature
			log(('SCH_OBSERVE candidate=%s blocker=%s phase=%s lane=%s party_generation=%d'):format(
				tostring(evaluation.candidate and evaluation.candidate.action_name or ''),
				tostring(evaluation.first_blocker or ''),
				tostring(provider.status.runtime.active_sequence and provider.status.runtime.active_sequence.phase or ''),
				tostring(provider.status.runtime.lane.class),
				party_snapshot.generation
			))
		end
		if trace_completed and trace_snapshot.last ~= nil
			and trace_snapshot.last.id ~= provider.last_logged_trace_id then
			provider.last_logged_trace_id = trace_snapshot.last.id
			log(('SCH_TRACE_COMPLETE id=%d action=%s reason=%s events=%d'):format(
				tonumber(trace_snapshot.last.id) or 0,
				tostring(trace_snapshot.last.focus_action_name or ''),
				tostring(trace_snapshot.last.terminal_reason or ''),
				#(trace_snapshot.last.events or {})
			))
		end
		-- Observe-only mode must never append to scheduler arbitration.
		return false
	end

	function provider.status_snapshot()
		local status = clone_value(provider.status)
		local trace_snapshot = provider.trace.snapshot()
		status.trace_armed = trace_snapshot.armed
		status.trace_phase = trace_snapshot.active and trace_snapshot.active.phase or 'idle'
		status.last_trace = trace_snapshot.last
		return status
	end

	function provider.status_lines(now)
		return sch_diagnostics.status_lines(provider.status_snapshot(), now)
	end

	function provider.arm_trace_once(now)
		return provider.trace.arm(now)
	end

	function provider.observe_action(act, player_id, now)
		local traced = provider.trace.observe_action(act, player_id, now)
		local runtime_snapshot = runtime.snapshot()
		if runtime_snapshot.active_sequence == nil then
			return traced
		end
		local observation = sch_action_observer.classify(
			act,
			player_id,
			resolve_spell_name,
			resolve_ability_name
		)
		if observation == nil then
			return traced
		end
		local pending = runtime_snapshot.pending
		if observation.phase == 'result'
			and type(pending) == 'table'
			and pending.action_type == observation.action_type
			and pending.action_name == observation.action_name then
			local expected_recipients
			if observation.action_type == 'spell' then
				expected_recipients = require_table(
					runtime_snapshot.active_sequence.expected_recipients,
					'Scholar active sequence expected recipients'
				)
			else
				expected_recipients = {
					{ id = pending.target_id, name = '' },
				}
			end
			local classification = sch_action_results.classify({
				action_type = observation.action_type,
				action_name = observation.action_name,
				expected_recipients = expected_recipients,
				raw_targets = require_table(act.targets, 'Scholar action-result packet targets'),
				catalog = get_action_result_catalog(
					observation.action_type,
					observation.action_name
				),
			})
			provider.last_action_result = classification
			provider.status.last_action_result = clone_value(classification)
			if classification.state == 'classified' then
				if classification.outcome == 'success'
					or classification.outcome == 'partial_success' then
					observation.success = true
					observation.successful_recipients = classification.successful_recipients
				else
					observation.success = false
					observation.interrupted = classification.interrupted
				end
			else
				observation.result_unclassified = true
			end
		end
		local observed = runtime.observe_local_action(observation, now)
		return traced or observed
	end

	function provider.observe_action_message(msg, player_id, now)
		return provider.trace.observe_action_message(msg, player_id, now)
	end

	function provider.trace_snapshot()
		return provider.trace.snapshot()
	end

	function provider.trace_active()
		return provider.trace.snapshot().armed
	end

	return provider
end

return M
