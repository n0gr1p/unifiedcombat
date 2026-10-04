local capabilities = require('uc_smn_capabilities')
local runtime = require('uc_smn_runtime')

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
		error(('uc_smn_maintenance deps.%s must be a function'):format(name))
	end
	return value
end

local function proposal(ctx, spec)
	local player = ctx.player
	local target_id = tonumber(spec.target_id)
	if target_id == nil or target_id <= 0 then
		error('Summoner maintenance proposal requires a positive target id')
	end
	local target_name = tostring(spec.target_name or '')
	if target_name == '' then
		error('Summoner maintenance proposal requires a target name')
	end
	return {
		proposal_id = ('smn.maintenance.%s.%d'):format(spec.key, math.floor(ctx.now * 1000)),
		family_id = 'maintenance.summoner.' .. spec.key,
		provider = 'maintenance_summoner',
		action_type = spec.action_type,
		action_name = spec.action_name,
		target_kind = spec.target_kind,
		target_id = target_id,
		target_name = target_name,
		priority_band = spec.priority_band,
		urgency = spec.urgency,
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.40,
		commit_deadline = ctx.now + 0.25,
		movement_policy = spec.action_type == 'spell' and 'must_stop' or 'none',
		range_policy = { min = 0.0, max = 20.0, los_required = false },
		recast_key = 'smn:' .. spec.key,
		duplicate_suppression_key = ('smn:%s:%d'):format(spec.key, target_id),
		lock_class = spec.action_type == 'pet' and 'pet_command' or 'support_action',
		expected_ack = spec.expected_ack,
		expected_effect = spec.expected_effect,
		sticky = true,
		can_preempt_movement = spec.action_type ~= 'pet',
		can_preempt_same_band = false,
		reason_code = spec.reason_code,
		detail = spec.detail,
		legacy_command = '',
	}
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local action_ready = require_function(deps, 'action_ready')
	local coordinator_can_attempt = require_function(deps, 'coordinator_can_attempt')
	local player_is_moving = require_function(deps, 'player_is_moving')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local log = require_function(deps, 'log')

	local provider = {
		status = {
			state = 'disabled',
			reason = '',
		},
	}

	local function set_status(state, reason)
		provider.status.state = state
		provider.status.reason = reason or ''
		_G.UC_SMN_MAINTENANCE_STATUS = {
			state = provider.status.state,
			reason = provider.status.reason,
			desired_avatar = tostring(provider.status.desired_avatar or ''),
			current_pet = tostring(provider.status.current_pet or ''),
			favor = tostring(provider.status.favor or ''),
			ward = tostring(provider.status.ward or ''),
		}
	end

	local function ward_satisfied(player, ward)
		local effect_ids = require_table(ward.effect_ids, 'Summoner Ward effect_ids')
		if #effect_ids == 0 then
			error('Summoner Ward maintenance requires at least one effect id: ' .. tostring(ward.name))
		end
		for i = 1, #effect_ids do
			if not runtime.has_buff(player, effect_ids[i]) then
				return false
			end
		end
		return true
	end

	local function ward_readiness(config, validation, ctx)
		if config.maintenance.ward.enabled ~= true then
			return nil, 'disabled', nil
		end
		if validation.ward_valid ~= true then
			return nil, 'invalid', nil
		end
		local wards = validation.wards or {}
		for i = 1, #wards do
			local ward = wards[i]
			if not ward_satisfied(ctx.player, ward) then
				local ready, recast_reason = runtime.recast_ready(ctx, runtime.RECAST_WARD)
				if not ready then
					return nil, recast_reason, nil
				end
				local retry_key = ('smn:ward:%s'):format(ward.name)
				local allowed, retry_reason = coordinator_can_attempt(retry_key, ctx.now)
				if not allowed then
					return nil, retry_reason, nil
				end
				local resource = get_ja_resource(ward.name)
				if resource == nil then
					error('Summoner Ward resource missing: ' .. ward.name)
				end
				local mp_cost = tonumber(resource.mp_cost)
				if mp_cost == nil then
					error('Summoner Ward MP cost must be numeric')
				end
				if runtime.player_mp(ctx.player) < mp_cost then
					return nil, 'insufficient_mp', nil
				end
				return ward, 'eligible', resource
			end
		end
		return nil, 'satisfied', nil
	end

	local function desired_avatar(config, validation, ctx)
		local primary = capabilities.avatar(config.avatar)
		if primary == nil then
			error('validated Summoner primary avatar is missing from capabilities')
		end
		local due_ward, ward_state, ward_resource = ward_readiness(config, validation, ctx)
		if due_ward == nil then
			return primary, nil, ward_state, ward_resource
		end
		local ward_avatar = capabilities.avatar(due_ward.avatar)
		if ward_avatar == nil then
			error('validated Summoner Ward avatar is missing from capabilities: ' .. tostring(due_ward.avatar))
		end
		return ward_avatar, due_ward, ward_state, ward_resource
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if rawget(_G, 'Start_Engine') ~= true then
			set_status('engine_off', '')
			return
		end
		if ctx.player_present ~= true then
			set_status('no_player', '')
			return
		end
		if tostring(ctx.player.main_job or '') ~= 'SMN' then
			set_status('not_summoner', '')
			return
		end

		local config, validation = runtime.config_from_config(ctx.config)
		if config.enabled ~= true then
			set_status('disabled', '')
			return
		end
		if validation.valid ~= true or validation.avatar_valid ~= true then
			set_status('invalid_avatar', validation.errors[1] and validation.errors[1].message or '')
			log(('SMN_MAINT_SKIP state=invalid_avatar reason=%s'):format(provider.status.reason))
			return
		end
		local primary_avatar = capabilities.avatar(config.avatar)
		local conduit_active = runtime.has_buff(ctx.player, runtime.BUFF_ASTRAL_CONDUIT)
		if conduit_active
			and ctx.pet_present == true
			and ctx.pet_name == primary_avatar.name then
			provider.status.desired_avatar = primary_avatar.name
			provider.status.current_pet = ctx.pet_name
			provider.status.favor = config.maintenance.avatar_favor
				and (runtime.has_buff(ctx.player, runtime.BUFF_FAVOR) and 'satisfied' or 'suppressed_conduit')
				or 'disabled'
			provider.status.ward = config.maintenance.ward.enabled and 'suppressed_conduit' or 'disabled'
			set_status('conduit_hold', primary_avatar.name)
			return
		end
		local avatar, due_ward, ward_state, ward_resource = desired_avatar(config, validation, ctx)
		provider.status.desired_avatar = avatar.name
		provider.status.current_pet = ''
		if ctx.pet_present == true then
			provider.status.current_pet = ctx.pet_name
		end
		provider.status.favor = 'disabled'
		if config.maintenance.avatar_favor and avatar.name == primary_avatar.name then
			provider.status.favor = 'missing'
		end
		provider.status.ward = ward_state
		local player_id = tonumber(ctx.player_id) or 0
		local player_name = tostring(ctx.player_name or '')
		if player_id <= 0 or player_name == '' then
			error('Summoner maintenance requires player identity')
		end

		if ctx.pet_present ~= true then
			set_status('summon_required', avatar.name)
			if player_is_moving() then
				set_status('summon_blocked', 'player_moving')
				return
			end
			local ready, reason, action_kind = action_ready(avatar.summon_spell, player_id)
			if ready and action_kind == 'spell' then
				out[#out + 1] = proposal(ctx, {
					key = 'summon',
					action_type = 'spell',
					action_name = avatar.summon_spell,
					target_kind = 'self',
					target_id = player_id,
					target_name = player_name,
					priority_band = 120,
					urgency = 1.0,
					expected_ack = 'spell_start',
					expected_effect = 'desired_avatar_present',
					reason_code = 'smn_desired_avatar_missing',
					detail = {
						smn_kind = 'summon',
						desired_avatar = avatar.name,
						summon_spell_id = avatar.summon_spell_id,
					},
				})
			else
				set_status('summon_blocked', tostring(reason or action_kind))
			end
			return
		end

		if ctx.pet_name ~= avatar.name then
			set_status('release_required', ctx.pet_name)
			local retry_key = ('smn:release:%d'):format(ctx.pet_id)
			local allowed, reason = coordinator_can_attempt(retry_key, ctx.now)
			local release_ready, release_reason = runtime.recast_ready(ctx, runtime.RECAST_RELEASE)
			if allowed and release_ready then
				out[#out + 1] = proposal(ctx, {
					key = 'release',
					action_type = 'pet',
					action_name = 'Release',
					target_kind = 'self',
					target_id = player_id,
					target_name = player_name,
					priority_band = runtime.PRIORITY_RELEASE,
					urgency = 1.0,
					expected_ack = 'pet_command',
					expected_effect = 'pet_disappeared',
					reason_code = 'smn_wrong_avatar_release',
					detail = {
						smn_kind = 'release',
						desired_avatar = avatar.name,
						pet_command = {
							kind = 'release',
							action_name = 'Release',
							pet_id = ctx.pet_id,
							retry_key = retry_key,
						},
					},
				})
			elseif not allowed then
				set_status('release_backoff', reason)
			else
				set_status('release_blocked', release_reason)
			end
			return
		end

		set_status('avatar_converged', avatar.name)
		if config.maintenance.avatar_favor and avatar.name == primary_avatar.name then
			provider.status.favor = 'eligible'
			if runtime.has_buff(ctx.player, runtime.BUFF_FAVOR) then
				provider.status.favor = 'satisfied'
			end
		end
		if config.maintenance.avatar_favor
			and avatar.name == primary_avatar.name
			and not runtime.has_buff(ctx.player, runtime.BUFF_FAVOR) then
			local ready, reason, action_kind = action_ready('Avatar\'s Favor', player_id)
			if ready and action_kind == 'ja' then
				out[#out + 1] = proposal(ctx, {
					key = 'favor',
					action_type = 'ja',
					action_name = 'Avatar\'s Favor',
					target_kind = 'self',
					target_id = player_id,
					target_name = player_name,
					priority_band = runtime.PRIORITY_FAVOR,
					urgency = 0.80,
					expected_ack = 'action_start',
					expected_effect = 'favor_buff',
					reason_code = 'smn_avatar_favor_missing',
					detail = {
						smn_kind = 'favor',
						desired_avatar = avatar.name,
						expected_effect_id = runtime.BUFF_FAVOR,
						ready_reason = reason,
					},
				})
			end
		end

		if due_ward ~= nil and ctx.pet_name == due_ward.avatar then
			local retry_key = ('smn:ward:%s'):format(due_ward.name)
			provider.status.ward = 'eligible'
			set_status('avatar_converged', avatar.name)
			out[#out + 1] = proposal(ctx, {
				key = 'ward',
				action_type = 'pet',
				action_name = due_ward.name,
				target_kind = 'self',
				target_id = player_id,
				target_name = player_name,
				priority_band = runtime.PRIORITY_WARD,
				urgency = 0.72,
				expected_ack = 'pet_action_start',
				expected_effect = 'ward_effect',
				reason_code = 'smn_ward_effect_missing',
				detail = {
					smn_kind = 'ward',
					desired_avatar = avatar.name,
					mp_cost = tonumber(ward_resource.mp_cost),
					pet_command = {
						kind = 'ward',
						action_name = due_ward.name,
						action_id = due_ward.id,
						recast_id = runtime.RECAST_WARD,
						recast_before = ctx.ability_recasts[runtime.RECAST_WARD],
						expected_effect_ids = due_ward.effect_ids,
						pet_id = ctx.pet_id,
						retry_key = retry_key,
					},
				},
			})
		end
	end

	function provider.revalidate(selected, ctx)
		require_table(selected, 'selected')
		require_table(ctx, 'ctx')
		local detail = require_table(selected.detail, 'selected.detail')
		local config, validation = runtime.config_from_config(ctx.config)
		if config.enabled ~= true or validation.avatar_valid ~= true then
			return false, 'summoner_config_invalid'
		end
		if tostring(ctx.player.main_job or '') ~= 'SMN' then
			return false, 'not_summoner'
		end
		local kind = tostring(detail.smn_kind or '')
		local current_desired, due_ward = desired_avatar(config, validation, ctx)
		if kind == 'summon' then
			if ctx.pet_present == true then
				return false, 'pet_present'
			end
			if player_is_moving() then
				return false, 'player_moving'
			end
			return tostring(selected.action_name or '') == current_desired.summon_spell, 'stale_summon'
		end
		if kind == 'release' then
			local command = require_table(detail.pet_command, 'selected.detail.pet_command')
			local release_ready = runtime.recast_ready(ctx, runtime.RECAST_RELEASE)
			return release_ready
				and ctx.pet_present == true
				and ctx.pet_id == command.pet_id
				and ctx.pet_name ~= current_desired.name,
				'stale_release'
		end
		if ctx.pet_present ~= true or ctx.pet_name ~= current_desired.name then
			return false, 'avatar_mismatch'
		end
		if kind == 'favor' then
			return current_desired.name == validation.avatar.name
				and not runtime.has_buff(ctx.player, runtime.BUFF_FAVOR),
				'favor_satisfied'
		end
		if kind == 'ward' then
			if validation.ward_valid ~= true or due_ward == nil then
				return false, 'ward_invalid'
			end
			local ward_ready = runtime.recast_ready(ctx, runtime.RECAST_WARD)
			if not ward_ready then
				return false, 'ward_recast_unavailable'
			end
			if tostring(selected.action_name or '') ~= due_ward.name then
				return false, 'ward_configuration_changed'
			end
			return not ward_satisfied(ctx.player, due_ward), 'ward_satisfied'
		end
		return false, 'unknown_summoner_maintenance_kind'
	end

	return provider
end

return M
