local runtime = require('uc_pup_runtime')

local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_pup_pet_combat_adapter deps.%s must be a function'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local burden_state = runtime.new_state()
	local last_player_id = 0
	local last_ctx_now = 0
	local lifecycle_observed = false

	local adapter = {}

	local function publish(snapshot, ctx, extra)
		local status = runtime.status_snapshot(
			burden_state,
			snapshot.config,
			ctx,
			ctx.now
		)
		status.state = tostring(extra and extra.state or (snapshot.correct_pet and 'ready' or 'no_automaton'))
		status.reason = tostring(extra and extra.reason or '')
		status.pattern = snapshot.config.maneuvers.pattern
		status.activate_if_missing = snapshot.config.activate_if_missing
		status.deploy_on_combat_start = snapshot.config.deploy_on_combat_start
		_G.UC_PUP_AUTOMATION_STATUS = status
	end

	local function relax_known_lifecycle_hold(ctx, previous_pet_id, had_lifecycle_observation)
		if had_lifecycle_observation ~= true then
			return
		end
		local current_pet_id = ctx.pet_present == true and (tonumber(ctx.pet_id) or 0) or 0
		local reset_reason = tostring(burden_state.last_reason or '')
		local known_pet_transition = current_pet_id > 0 and current_pet_id ~= (tonumber(previous_pet_id) or 0)
		local known_zone_transition = reset_reason == 'zone_change'
		if not known_pet_transition and not known_zone_transition then
			return
		end
		local now = tonumber(ctx.now) or 0
		if (tonumber(burden_state.quiet_until) or 0) > now then
			-- The reset itself is known, so the conservative burden estimate is enough.
			-- Keep the modeled starting burden from runtime.observe(), but remove the
			-- fixed unknown-history hold and let maneuver_safe() decide when the next
			-- Maneuver is actually safe.
			burden_state.quiet_until = now
			burden_state.last_reason = 'modeled_burden:' .. reset_reason
		end
	end

	function adapter.snapshot(ctx)
		require_table(ctx, 'ctx')
		if ctx.player_present ~= true or tostring(ctx.player.main_job or '') ~= 'PUP' then
			return {
				enabled = false,
				valid = false,
				correct_pet = false,
				job = 'PUP',
			}
		end
		local config = runtime.config_from_settings(ctx.settings)
		last_player_id = tonumber(ctx.player_id) or tonumber(ctx.player.id) or 0
		last_ctx_now = tonumber(ctx.now) or last_ctx_now
		local previous_pet_id = tonumber(burden_state.pet_id) or 0
		local had_lifecycle_observation = lifecycle_observed
		runtime.observe(burden_state, ctx, ctx.now, config)
		relax_known_lifecycle_hold(ctx, previous_pet_id, had_lifecycle_observation)
		lifecycle_observed = true
		local snapshot = {
			enabled = config.enabled == true,
			valid = true,
			correct_pet = ctx.pet_present == true and (tonumber(ctx.pet_id) or 0) > 0,
			config = config,
			job = 'PUP',
			pet_name = tostring(ctx.pet_name or 'Automaton'),
		}
		if snapshot.correct_pet then
			snapshot.pet_id = tonumber(ctx.pet_id)
		end
		publish(snapshot, ctx)
		return snapshot
	end

	function adapter.maintenance(snapshot, ctx)
		require_table(snapshot, 'Puppetmaster snapshot')
		require_table(ctx, 'ctx')
		if snapshot.enabled ~= true then
			return nil
		end
		local player_id = tonumber(ctx.player_id) or tonumber(ctx.player and ctx.player.id) or 0
		local player_name = tostring(ctx.player_name or (ctx.player and ctx.player.name) or '')
		if player_id <= 0 or player_name == '' then
			return nil
		end

		if snapshot.correct_pet ~= true then
			if snapshot.config.activate_if_missing ~= true then
				publish(snapshot, ctx, { state = 'no_automaton', reason = 'activate_disabled' })
				return nil
			end
			local ready, reason = runtime.recast_ready(ctx, runtime.RECAST_ACTIVATE)
			if not ready then
				publish(snapshot, ctx, { state = 'activate_blocked', reason = reason })
				return nil
			end
			if get_ja_resource('Activate') == nil then
				error('Puppetmaster Activate resource is missing')
			end
			local retry_key = 'pup:activate'
			return {
				kind = 'activate',
				family_id = 'maintenance.puppetmaster.activate',
				action_type = 'pet',
				action_name = 'Activate',
				target_kind = 'self',
				target_id = player_id,
				target_name = player_name,
				priority_band = runtime.PRIORITY_ACTIVATE,
				urgency = 0.96,
				range = 0.0,
				retry_key = retry_key,
				expected_ack = 'pet_command',
				expected_effect = 'automaton_present',
				lock_class = 'pet_command',
				reason_code = 'pup_automaton_missing',
				command = {
					kind = 'activate',
					action_name = 'Activate',
					recast_id = runtime.RECAST_ACTIVATE,
					recast_before = tonumber(ctx.ability_recasts[runtime.RECAST_ACTIVATE]) or 0,
					retry_key = retry_key,
				},
				detail = {
					adapter_action_kind = 'activate',
					recast_id = runtime.RECAST_ACTIVATE,
				},
			}
		end

		if snapshot.config.maneuvers.enabled ~= true then
			return nil
		end
		local name = runtime.next_missing_maneuver(snapshot.config, ctx.player)
		if name == nil then
			publish(snapshot, ctx, { state = 'maneuvers_satisfied', reason = '' })
			return nil
		end
		local safe, reason, burden, wait_seconds = runtime.maneuver_safe(
			burden_state,
			snapshot.config,
			ctx,
			name,
			ctx.now
		)
		if not safe then
			publish(snapshot, ctx, {
				state = 'maneuver_guard',
				reason = ('%s:%s:burden=%.1f:wait=%.1f'):format(reason, name, burden, wait_seconds),
			})
			return nil
		end
		local maneuver = runtime.maneuver(name)
		local retry_key = ('pup:maneuver:%s'):format(name)
		return {
			kind = 'maneuver',
			family_id = 'maintenance.puppetmaster.maneuver',
			action_type = 'pet',
			action_name = name,
			target_kind = 'self',
			target_id = player_id,
			target_name = player_name,
			priority_band = runtime.PRIORITY_MANEUVER,
			urgency = 0.74,
			range = 0.0,
			retry_key = retry_key,
			expected_ack = 'pet_command',
			expected_effect = 'maneuver_recast_consumed',
			lock_class = 'pet_command',
			reason_code = 'pup_maneuver_missing',
			command = {
				kind = 'maneuver',
				action_name = name,
				action_id = maneuver.action_id,
				recast_id = runtime.RECAST_MANEUVER,
				recast_before = tonumber(ctx.ability_recasts[runtime.RECAST_MANEUVER]) or 0,
				pet_id = snapshot.pet_id,
				retry_key = retry_key,
			},
			detail = {
				adapter_action_kind = 'maneuver',
				maneuver = name,
				burden_before = burden,
				burden_projected = burden + maneuver.burden,
			},
		}
	end

	function adapter.engagement(snapshot, ctx)
		require_table(snapshot, 'Puppetmaster snapshot')
		require_table(ctx, 'ctx')
		if snapshot.enabled ~= true
			or snapshot.correct_pet ~= true
			or snapshot.config.deploy_on_combat_start ~= true
			or ctx.target_valid ~= true then
			return nil
		end
		local ready = runtime.recast_ready(ctx, runtime.RECAST_DEPLOY)
		if not ready then
			return nil
		end
		local resource = get_ja_resource('Deploy')
		if resource == nil then
			error('Puppetmaster Deploy resource is missing')
		end
		local range = action_effective_range(resource.range)
		local retry_key = ('pup:deploy:%d:%d'):format(ctx.combat_generation, snapshot.pet_id)
		return {
			kind = 'deploy',
			action_name = 'Deploy',
			priority_band = runtime.PRIORITY_DEPLOY,
			urgency = 0.78,
			range = range,
			recast_id = runtime.RECAST_DEPLOY,
			retry_key = retry_key,
			command = {
				kind = 'deploy',
				action_name = 'Deploy',
				pet_id = snapshot.pet_id,
				target_id = ctx.target_id,
				combat_generation = ctx.combat_generation,
				retry_key = retry_key,
			},
		}
	end

	function adapter.offensive_action(_, _)
		return nil
	end

	function adapter.revalidate(snapshot, selected, ctx)
		require_table(snapshot, 'Puppetmaster snapshot')
		require_table(selected, 'selected')
		require_table(ctx, 'ctx')
		if snapshot.enabled ~= true then
			return false, 'puppetmaster_disabled'
		end
		local detail = type(selected.detail) == 'table' and selected.detail or {}
		local action_kind = tostring(detail.adapter_action_kind or '')
		local command = type(detail.pet_command) == 'table' and detail.pet_command or nil
		if action_kind == 'activate' then
			if snapshot.correct_pet == true then
				return false, 'automaton_present'
			end
			local ready = runtime.recast_ready(ctx, runtime.RECAST_ACTIVATE)
			return ready, ready and '' or 'activate_not_ready'
		end
		if command == nil then
			return false, 'missing_pet_command'
		end
		if snapshot.correct_pet ~= true or tonumber(ctx.pet_id) ~= tonumber(command.pet_id) then
			return false, 'stale_pet'
		end
		if command.kind == 'deploy' then
			if ctx.target_valid ~= true
				or tonumber(ctx.target_id) ~= tonumber(command.target_id)
				or tonumber(ctx.combat_generation) ~= tonumber(command.combat_generation) then
				return false, 'stale_target'
			end
			local current = adapter.engagement(snapshot, ctx)
			if current == nil then
				return false, 'deploy_not_executable'
			end
			return true, ''
		elseif command.kind == 'maneuver' then
			local wanted = runtime.next_missing_maneuver(snapshot.config, ctx.player)
			if wanted ~= command.action_name then
				return false, wanted == nil and 'maneuvers_satisfied' or 'maneuver_goal_changed'
			end
			local safe, reason = runtime.maneuver_safe(
				burden_state,
				snapshot.config,
				ctx,
				command.action_name,
				ctx.now
			)
			if not safe then
				return false, reason
			end
			return true, ''
		end
		return false, 'unsupported_puppetmaster_action'
	end

	function adapter.observe_action(act, observed_at)
		if type(act) ~= 'table' or last_player_id <= 0 then
			return false
		end
		if tonumber(act.actor_id) ~= last_player_id then
			return false
		end
		local name = runtime.maneuver_from_action_id(act.param)
		if name == nil then
			return false
		end
		return runtime.record_maneuver(burden_state, name, tonumber(observed_at) or last_ctx_now)
	end

	function adapter.observe_coordinator_event(event)
		if type(event) ~= 'table' then
			return
		end
		if event.kind == 'maneuver' and event.outcome == 'failed' then
			burden_state.last_reason = 'maneuver_failed:' .. tostring(event.reason or '')
		end
	end

	return adapter
end

return M
