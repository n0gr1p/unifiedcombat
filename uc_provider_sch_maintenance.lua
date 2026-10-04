local sch_config = require('uc_sch_config')
local sch_action_observer = require('uc_sch_action_observer')
local sch_action_results = require('uc_sch_action_results')
local sch_charge_model = require('uc_sch_charge_model')
local sch_diagnostics = require('uc_sch_diagnostics')
local sch_maintenance = require('uc_sch_maintenance')
local sch_party = require('uc_sch_party')
local sch_runtime = require('uc_sch_runtime')
local sch_skillchain_runtime = require('uc_sch_skillchain_runtime')
local sch_skillchain_target = require('uc_sch_skillchain_target')
local sch_trace = require('uc_sch_trace')

local M = {}

sch_skillchain_runtime.install_charge_bridge(sch_runtime)

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

local function default_current_target()
	local target = sch_skillchain_target.select()
	return target
end

local function default_skillchain_snapshot(target_id)
	local ok, core = pcall(require, 'unified_combat_core')
	if not ok or type(core) ~= 'table' or type(core.get_skillchain_snapshot) ~= 'function' then
		return nil
	end
	return core.get_skillchain_snapshot(target_id)
end

function M.config_from_context(ctx)
	require_table(ctx, 'Scholar provider context')
	local root_config = require_table(ctx.config, 'Scholar provider canonical config')
	local config, validation = sch_config.copy_validated(root_config.sch, root_config.profile)
	return config, validation
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
	local action_ready = require_function(deps.action_ready, 'deps.action_ready')
	local sch_spell_ready = require_function(deps.sch_spell_ready, 'deps.sch_spell_ready')
	local select_cure_spell = require_function(deps.select_cure_spell, 'deps.select_cure_spell')
	local status_removal_for_buff = require_function(
		deps.status_removal_for_buff,
		'deps.status_removal_for_buff'
	)
	local is_critical_defensive = require_function(
		deps.is_critical_defensive,
		'deps.is_critical_defensive'
	)
	local get_sublimation_safety = require_function(
		deps.get_sublimation_safety,
		'deps.get_sublimation_safety'
	)
	local get_sublimation_release_mechanics = require_function(
		deps.get_sublimation_release_mechanics,
		'deps.get_sublimation_release_mechanics'
	)
	local ignore_trusts = require_function(deps.ignore_trusts, 'deps.ignore_trusts')
	local log = require_function(deps.log, 'deps.log')
	local routine_priority = tonumber(deps.routine_priority)
	local prepared_priority = tonumber(deps.prepared_priority)
	local defensive_priority = tonumber(deps.defensive_priority)
	if routine_priority == nil or prepared_priority == nil or defensive_priority == nil then
		error('Scholar provider priorities must be numeric')
	end
	local runtime = deps.runtime or sch_runtime
	local skillchain_runtime = deps.skillchain_runtime or sch_skillchain_runtime.new()
	local get_current_target = deps.get_current_target or default_current_target
	local get_skillchain_snapshot = deps.get_skillchain_snapshot or default_skillchain_snapshot
	if type(get_current_target) ~= 'function' or type(get_skillchain_snapshot) ~= 'function' then
		error('Scholar provider skillchain dependencies are invalid')
	end
	local capture = require_table(deps.capture, 'deps.capture')
	if type(capture) ~= 'table'
		or type(capture.start) ~= 'function'
		or type(capture.mark) ~= 'function'
		or type(capture.record_trace) ~= 'function'
		or type(capture.record_sample) ~= 'function'
		or type(capture.stop) ~= 'function'
		or type(capture.status) ~= 'function' then
		error('Scholar provider capture dependency is invalid')
	end
	local provider = {
		generation = 0,
		config_signature = '',
		status = {
			mode = 'live',
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
		local root_config = require_table(ctx.config, 'Scholar provider canonical config')
		local config = M.config_from_context(ctx)
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
		local ignore_trusts_enabled = ignore_trusts(root_config)
		if type(ignore_trusts_enabled) ~= 'boolean' then
			error('Scholar provider ignore_trusts must return a boolean')
		end
		local managed_party_members = {}
		for member_index = 1, #observed_party_members do
			local member = observed_party_members[member_index]
			if not ignore_trusts_enabled or member.is_npc ~= true then
				managed_party_members[#managed_party_members + 1] = member
			end
		end
		runtime.configure(config, { main_job = player.main_job }, provider.generation, ctx.now)
		runtime.observe_environment({
			engine_enabled = ctx.engine_enabled,
			maintenance_enabled = ctx.maintenance_enabled,
			defensive_enabled = ctx.defensive_enabled,
			main_job = player.main_job,
			player_hpp = vitals.hpp,
			party_generation = party_snapshot.generation,
			party_members = managed_party_members,
		}, ctx.now)
		runtime.observe_player_buffs(require_table(player.buffs, 'Scholar provider player buffs'), ctx.now)
		runtime.observe_party_buffs(managed_party_members, ctx.now)
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
		local critical_cure_present = false
		for proposal_index = 1, #out do
			if is_critical_defensive(out[proposal_index], root_config) then
				critical_cure_present = true
				break
			end
		end
		local evaluation = sch_maintenance.evaluate(config, {
			now = ctx.now,
			player = player,
			party_members = managed_party_members,
			area_mechanics = get_area_mechanics(),
			action_ready = action_ready,
			action_readiness_source = 'unified_scheduler:action_ready',
			ability_recasts_present = ctx.ability_recasts_present,
			ability_recasts = ctx.ability_recasts,
			sublimation_safety = get_sublimation_safety(ctx, out),
			sublimation_release_mechanics = get_sublimation_release_mechanics(),
			defensive_enabled = ctx.defensive_enabled,
			critical_cure_present = critical_cure_present,
			critical_hpp = tonumber(
				type(root_config.defensive) == 'table'
				and type(root_config.defensive.thresholds) == 'table'
				and root_config.defensive.thresholds.critical_hpp
			) or 35,
			party_generation = party_snapshot.generation,
			status_removal_for_buff = status_removal_for_buff,
			spell_ready = sch_spell_ready,
			select_cure_spell = select_cure_spell,
		}, runtime_snapshot)
		local skillchain_before = skillchain_runtime:snapshot()
		if runtime_snapshot.active_sequence == nil and skillchain_before.active == nil
			and evaluation.candidate ~= nil then
			local plan = clone_value(require_table(
				evaluation.candidate.plan,
				'Scholar candidate execution plan'
			))
			plan.id = table.concat({
				'sch',
				tostring(provider.generation),
				tostring(plan.purpose),
				tostring(math.floor(ctx.now * 1000)),
			}, ':')
			local sequence_window = plan.purpose == 'party_accession_maintenance' and 20
				or (plan.purpose == 'targeted_storm' and 12
				or (plan.domain == 'defensive' and 12 or 6))
			plan.deadline = ctx.now + sequence_window
			local started, start_reason = runtime.start_sequence(plan, ctx.now)
			if not started then
				evaluation.first_blocker = start_reason
			end
		end
		runtime_snapshot = runtime.snapshot()
		local current_target = get_current_target()
		local core_skillchain_snapshot = nil
		if type(current_target) == 'table' and (tonumber(current_target.id) or 0) > 0 then
			core_skillchain_snapshot = get_skillchain_snapshot(current_target.id)
		end
		skillchain_runtime:update({
			now = ctx.now,
			config = config,
			engine_enabled = ctx.engine_enabled,
			maintenance_enabled = ctx.maintenance_enabled,
			critical_cure_present = critical_cure_present,
			standard_sequence_active = runtime_snapshot.active_sequence ~= nil,
			target = current_target,
			player_buffs = player.buffs,
			skillchain_snapshot = core_skillchain_snapshot,
			charge_snapshot = runtime_snapshot.stratagem,
		})
		local skillchain_runtime_snapshot = skillchain_runtime:snapshot()
		local step, step_reason = runtime.next_step(ctx.now)
		if step == nil and runtime_snapshot.active_sequence == nil then
			local skillchain_step, skillchain_reason = skillchain_runtime:next_step(ctx.now)
			if skillchain_step ~= nil then
				step = skillchain_step
				step_reason = ''
			elseif skillchain_runtime_snapshot.active ~= nil then
				step_reason = skillchain_reason
			end
		end
		runtime_snapshot = runtime.snapshot()
		local emitted = false
		if step ~= nil then
			local skillchain_step = step.sch_skillchain == true
			local active_sequence
			local sequence_domain
			local provider_id
			if skillchain_step then
				active_sequence = { domain = 'maintenance', purpose = 'immanence_skillchain' }
				sequence_domain = 'maintenance'
				provider_id = 'maintenance_sch'
			else
				active_sequence = require_table(
					runtime_snapshot.active_sequence,
					'Scholar active sequence'
				)
				sequence_domain = tostring(active_sequence.domain or '')
				provider_id = sequence_domain == 'defensive'
					and 'defensive_sch' or 'maintenance_sch'
			end
			local proposal_action_type = step.action_type == 'job_ability'
				and 'ja' or step.action_type
			if proposal_action_type ~= 'ja' and proposal_action_type ~= 'spell' then
				error('Scholar runtime emitted an unsupported scheduler action type')
			end
			local proposal_target_id = tonumber(step.target_id) or 0
			local proposal_target_name = tostring(step.target_name or '')
			local target_kind = tostring(step.target_kind or 'ally')
			if proposal_action_type == 'ja' or proposal_target_id == player.id then
				target_kind = 'self'
				proposal_target_id = player.id
				proposal_target_name = player.name
			end
			local prepared = step.sch_skillchain == true
				or runtime_snapshot.lane.class == 'prepared_support'
			out[#out + 1] = {
				proposal_id = ('sch.%d.%s.%d'):format(
					tonumber(step.sequence_generation) or 0,
					tostring(step.phase or ''),
					math.floor(ctx.now * 1000)
				),
				family_id = sequence_domain .. '.sch.' .. tostring(active_sequence.purpose),
				provider = provider_id,
				action_type = proposal_action_type,
				action_name = step.action_name,
				target_kind = target_kind,
				target_id = proposal_target_id,
				target_name = proposal_target_name,
				priority_band = sequence_domain == 'defensive'
					and (prepared and prepared_priority or defensive_priority)
					or (prepared and prepared_priority or routine_priority),
				urgency = prepared and 0.95 or 0.70,
				starvation_eligible = true,
				created_at = ctx.now,
				expires_at = ctx.now + 0.40,
				commit_deadline = ctx.now + 0.25,
				movement_policy = proposal_action_type == 'spell' and 'must_stop' or 'none',
				range_policy = { min = 0.0, max = target_kind == 'enemy' and 21.0 or 12.0, los_required = false },
				recast_key = 'sch:' .. tostring(step.action_name),
				duplicate_suppression_key = step.duplicate_suppression_key,
				lock_class = 'support_action',
				expected_ack = proposal_action_type == 'spell' and 'spell_start' or 'action_start',
				expected_effect = proposal_action_type == 'spell' and 'buff_gain' or 'ability_result',
				sticky = true,
				can_preempt_movement = true,
				can_preempt_same_band = false,
				reason_code = step.reason_code,
				detail = {
					sch_step = clone_value(step),
					purpose = active_sequence.purpose,
					domain = sequence_domain,
					prepared = prepared,
				},
			}
			emitted = true
		elseif (runtime_snapshot.active_sequence ~= nil or skillchain_runtime_snapshot.active ~= nil)
			and step_reason ~= 'sequence_action_pending'
			and step_reason ~= 'sequence_waiting_for_evidence'
			and step_reason ~= 'skillchain_action_pending'
			and step_reason ~= 'skillchain_waiting_for_evidence' then
			evaluation.first_blocker = step_reason
		end
		provider.status = evaluation
		provider.status.runtime = runtime_snapshot
		provider.status.skillchain_runtime = skillchain_runtime_snapshot
		provider.status.party_generation = party_snapshot.generation
		provider.status.party_roster_signature = party_snapshot.roster_signature
		provider.status.main_job_level = main_job_level
		provider.status.job_points_present = job_points_present
		provider.status.job_points_spent = job_points_spent
		provider.status.proposals_emitted = emitted and 1 or 0
		provider.status.last_action_result = clone_value(provider.last_action_result)
		local runtime_events = sch_diagnostics.runtime_events(
			provider.last_runtime_snapshot,
			runtime_snapshot,
			ctx.now
		)
		local diagnostics_active = evaluation.enabled == true
			or runtime_snapshot.active_sequence ~= nil
			or skillchain_runtime_snapshot.active ~= nil
			or (provider.last_runtime_snapshot ~= nil
				and provider.last_runtime_snapshot.active_sequence ~= nil)
		if diagnostics_active then
			for i = 1, #runtime_events do
				log(sch_diagnostics.event_line(runtime_events[i]))
			end
		end
		provider.last_runtime_snapshot = clone_value(runtime_snapshot)
		local trace_sample = {
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
		}
		if capture.status().active == true then
			capture.record_sample(trace_sample, ctx.now)
		end
		local trace_completed = provider.trace.observe_sample(trace_sample, ctx.now)
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
			skillchain_phase = skillchain_runtime_snapshot.active and skillchain_runtime_snapshot.active.phase or '',
			party_generation = party_snapshot.generation,
		})
		if evaluation.enabled and observe_signature ~= provider.last_observe_signature then
			provider.last_observe_signature = observe_signature
			log(('SCH_OBSERVE candidate=%s blocker=%s phase=%s lane=%s party_generation=%d'):format(
				tostring(evaluation.candidate and evaluation.candidate.action_name or ''),
				tostring(evaluation.first_blocker or ''),
				tostring(provider.status.runtime.active_sequence and provider.status.runtime.active_sequence.phase
					or (provider.status.skillchain_runtime.active and provider.status.skillchain_runtime.active.phase) or ''),
				tostring(provider.status.runtime.lane.class),
				party_snapshot.generation
			))
		end
		if trace_completed and trace_snapshot.last ~= nil
			and trace_snapshot.last.id ~= provider.last_logged_trace_id then
			provider.last_logged_trace_id = trace_snapshot.last.id
			if capture.status().active == true then
				local persisted, persist_message = capture.record_trace(trace_snapshot.last, ctx.now)
				if not persisted then
					error('Scholar trace persistence failed: ' .. tostring(persist_message))
				end
			end
			log(('SCH_TRACE_COMPLETE id=%d action=%s reason=%s events=%d'):format(
				tonumber(trace_snapshot.last.id) or 0,
				tostring(trace_snapshot.last.focus_action_name or ''),
				tostring(trace_snapshot.last.terminal_reason or ''),
				#(trace_snapshot.last.events or {})
			))
		end
		return emitted
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
					{ id = player_id, name = '' },
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

	function provider.note_dispatched(step, now)
		if type(step) == 'table' and step.sch_skillchain == true then
			return skillchain_runtime:note_dispatched(step, now)
		end
		return runtime.note_dispatched(step, now)
	end

	function provider.start_capture(meta, now)
		return capture.start(meta, now)
	end

	function provider.mark_capture(label, now)
		return capture.mark(label, now)
	end

	function provider.stop_capture(reason, now)
		return capture.stop(reason, now)
	end

	function provider.capture_status()
		return capture.status()
	end

	return provider
end

return M