local M = {}

local INDI_COLURE_BUFF_ID = 612
local ENTRUST_BUFF_ID = 584
local BLAZE_OF_GLORY_BUFF_ID = 569
local EFFECT_OBSERVATION_TIMEOUT = 8.0
local SLOW_MAINTENANCE_INTERVAL = 1.0
local SPELL_RANGE_EPSILON = 0.25
local ENTRUST_SPELL_MAX_RANGE_YALMS = 20.9
local ENEMY_LUOPAN_EFFECT_RADIUS_YALMS = 6.5
local JOB_ABILITY_ACTION_CATEGORIES = {
	[6] = true,
	[13] = true,
	[14] = true,
	[15] = true,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_geo_maintenance deps.%s must be a function'):format(name))
	end
	return value
end

local function require_number(deps, name)
	local value = tonumber(deps[name])
	if value == nil then
		error(('uc_geo_maintenance deps.%s must be numeric'):format(name))
	end
	return value
end

local function finite_number(value)
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	return number
end

function M.config_from_context(ctx)
	ctx = require_table(ctx, 'ctx')
	local root = require_table(ctx.config, 'ctx.config')
	local maintenance = require_table(root.maintenance, 'ctx.config.maintenance')
	local config = maintenance.geo
	if type(config) ~= 'table' then
		error('canonical maintenance.geo configuration is required')
	end
	return config
end

local function luopan_present(ctx)
	if type(ctx) ~= 'table' or ctx.pet_present ~= true then
		return false
	end
	local pet = type(ctx.pet) == 'table' and ctx.pet or nil
	local hpp = finite_number(pet and pet.hpp)
	-- Windower can briefly retain the pet entity after a Luopan dies. Treat a
	-- known 0-HP pet as absent while preserving fail-closed behavior when HPP
	-- is unavailable.
	return hpp == nil or hpp > 0
end

local function has_buff(player, buff_id)
	local buffs = type(player) == 'table' and player.buffs or nil
	if type(buffs) ~= 'table' then
		return false
	end
	for i = 1, #buffs do
		if tonumber(buffs[i]) == buff_id then
			return true
		end
	end
	return false
end

local function distance_between(a, b)
	local ax = finite_number(a and a.x)
	local ay = finite_number(a and a.y)
	local bx = finite_number(b and b.x)
	local by = finite_number(b and b.y)
	if ax == nil or ay == nil or bx == nil or by == nil then
		return nil
	end
	local dx = ax - bx
	local dy = ay - by
	return math.sqrt(dx * dx + dy * dy)
end

local function mob_distance(mob)
	local squared = finite_number(mob and mob.distance)
	if squared == nil or squared < 0 then
		return nil
	end
	return math.sqrt(squared)
end

local function proposal(ctx, spec)
	local target_id = tonumber(spec.target_id)
	if target_id == nil or target_id <= 0 then
		error('GEO maintenance proposal requires a positive target id')
	end
	local target_name = tostring(spec.target_name or '')
	if target_name == '' then
		error('GEO maintenance proposal requires a target name')
	end
	local max_range = finite_number(spec.max_range)
	if max_range == nil or max_range <= 0 then
		error('GEO maintenance proposal requires a positive action range')
	end
	local action_type = tostring(spec.action_type or 'spell')
	if action_type ~= 'spell' and action_type ~= 'ja' then
		error('GEO maintenance proposal action_type must be spell or ja')
	end
	local priority_band = finite_number(spec.priority_band)
	if priority_band == nil then
		error('GEO maintenance proposal requires a finite priority band')
	end
	return {
		proposal_id = ('geo.maintenance.%s.%d'):format(spec.kind, math.floor(ctx.now * 1000)),
		family_id = 'maintenance.geo.' .. spec.kind,
		provider = 'maintenance_geo',
		action_type = action_type,
		action_name = spec.action_name,
		target_kind = spec.target_kind,
		target_id = target_id,
		target_name = target_name,
		priority_band = priority_band,
		urgency = spec.urgency,
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.40,
		commit_deadline = ctx.now + 0.25,
		movement_policy = action_type == 'spell' and 'must_stop' or 'none',
		range_policy = {
			min = 0.0,
			max = max_range,
			los_required = false,
		},
		recast_key = 'geo:' .. spec.kind,
		duplicate_suppression_key = ('geo:%s:%d'):format(spec.kind, target_id),
		lock_class = 'support_action',
		expected_ack = action_type == 'spell' and 'spell_start' or 'action_start',
		expected_effect = tostring(spec.expected_effect or ''),
		sticky = true,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = spec.reason_code,
		detail = {
			geo_kind = spec.kind,
			target_kind = spec.target_kind,
			target_id = target_id,
			target_name = target_name,
			max_range = max_range,
			sequence_kind = tostring(spec.sequence_kind or ''),
			sequence_step = tostring(spec.sequence_step or ''),
			blaze_enhanced = spec.blaze_enhanced == true,
			config_contract_signature = spec.config_contract_signature,
		},
		legacy_command = '',
	}
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local action_ready = require_function(deps, 'action_ready')
	local get_spell_resource = require_function(deps, 'get_spell_resource')
	local get_ja_resource = require_function(deps, 'get_ja_resource')
	local get_party_members = require_function(deps, 'get_party_members')
	local get_friendly_claims = require_function(deps, 'get_friendly_claims')
	local resolve_camp_anchor = require_function(deps, 'resolve_camp_anchor')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local target_is_actionable = require_function(deps, 'target_is_actionable')
	local target_is_ignored = require_function(deps, 'target_is_ignored')
	local player_is_moving = require_function(deps, 'player_is_moving')
	local pull_active = require_function(deps, 'pull_active')
	local log = require_function(deps, 'log')
	local action_timeline_log = require_function(deps, 'action_timeline_log')
	local geo_maintenance_priority = require_number(deps, 'geo_maintenance_priority')
	local geo_creation_priority = require_number(deps, 'geo_creation_priority')

	local provider = {
		status = {
			state = 'disabled',
			reason = '',
		},
		state = {
			owned_geo_spell = nil,
			owned_geo_blaze_enhanced = false,
			owned_indi_spell = nil,
			owned_entrust_spell = nil,
			owned_entrust_target_id = 0,
			enemy_target_id = 0,
			ecliptic_luopan_id = 0,
			pending = nil,
			sequence = nil,
			next_retry_at = 0,
			failed_geo_target_id = 0,
			failed_geo_target_until = 0,
			bolster_armed = false,
			diag_last_luopan_signature = '',
			next_slow_maintenance_at = 0,
			config_contract_signature = '',
			config_contracts = nil,
			config_validation_reason = nil,
		},

	}

	local function canonical_reason(state, detail)
		if detail == 'enemy_outside_camp_radius' then
			return 'GEO_ENEMY_OUTSIDE_CAMP_RADIUS'
		elseif state == 'invalid_config' then
			return 'GEO_CONFIG_INVALID'
		elseif state == 'not_geomancer' or state == 'no_player' then
			return 'GEO_JOB_INELIGIBLE'
		elseif state == 'geo_blocked' then
			return 'GEO_TARGET_UNAVAILABLE'
		elseif state == 'entrust_blocked' then
			return 'ENTRUST_TARGET_UNAVAILABLE'
		elseif state == 'unknown_existing' then
			if tostring(detail):find('luopan', 1, true) then
				return 'GEO_EXISTING_IDENTITY_UNKNOWN'
			end
			return 'INDI_EXISTING_IDENTITY_UNKNOWN'
		elseif state == 'awaiting_effect' then
			if tostring(detail):find('geo', 1, true) then
				return 'GEO_SEQUENCE_WAIT_LUOPAN'
			end
			return 'GEO_SEQUENCE_WAIT_BUFF'
		elseif state == 'sequence_failed' or state == 'cast_failed' then
			return 'GEO_SEQUENCE_REJECTED'
		elseif state == 'sequence_held' or state == 'sequence_blocked' or state == 'backoff' then
			return 'GEO_SEQUENCE_WAIT_ACTION'
		elseif state:match('_proposed$') then
			return 'GEO_PROPOSAL_READY'
		elseif state == 'converged' then
			return 'GEO_SATISFIED'
		elseif state == 'blocked' and detail == 'outside_camp_tolerance' then
			return 'GEO_AWAY_FROM_CAMP'
		elseif state == 'blocked' and tostring(detail):find('camp', 1, true) then
			return 'GEO_CAMP_UNSET'
		end
		return tostring(detail or '')
	end

	local function publish_status(state, detail)
		provider.status.state = state
		provider.status.reason = canonical_reason(state, detail)
		provider.status.detail = detail or ''
		_G.UC_GEO_MAINTENANCE_STATUS = {
			state = provider.status.state,
			reason = provider.status.reason,
			detail = provider.status.detail,
			owned_geo_spell = tostring(provider.state.owned_geo_spell or ''),
			owned_geo_blaze_enhanced = provider.state.owned_geo_blaze_enhanced == true,
			owned_indi_spell = tostring(provider.state.owned_indi_spell or ''),
			enemy_target_id = tonumber(provider.state.enemy_target_id) or 0,
			pending_kind = tostring(provider.state.pending and provider.state.pending.kind or ''),
			pending_spell = tostring(provider.state.pending and provider.state.pending.spell or ''),
			sequence_kind = tostring(provider.state.sequence and provider.state.sequence.kind or ''),
			sequence_step = tostring(provider.state.sequence and provider.state.sequence.step or ''),
			atomic = provider.state.sequence and provider.state.sequence.atomic == true or false,
			awaiting_enemy_target = provider.state.sequence
				and provider.state.sequence.awaiting_enemy_target == true or false,
			bolster_armed = provider.state.bolster_armed == true,
		}
	end

	local function geo_diag_fields(ctx, config, geo_present)
		local pending = type(provider.state.pending) == 'table' and provider.state.pending or nil
		local sequence = type(provider.state.sequence) == 'table' and provider.state.sequence or nil
		local pet = type(ctx.pet) == 'table' and ctx.pet or nil
		local pet_hpp = finite_number(pet and pet.hpp)
		local pending_age = ''
		if pending ~= nil and finite_number(pending.sent_at) ~= nil then
			pending_age = ('%.2f'):format(math.max(0, ctx.now - tonumber(pending.sent_at)))
		end
		return {
			at = ('%.3f'):format(tonumber(ctx.now) or 0),
			pet_present = tostring(ctx.pet_present == true),
			pet_id = tonumber(ctx.pet_id) or 0,
			pet_index = tonumber(ctx.pet_index) or 0,
			pet_name = tostring(ctx.pet_name or (pet and pet.name) or ''),
			pet_status = tonumber(ctx.pet_status) or tonumber(pet and pet.status) or -1,
			pet_hpp = pet_hpp == nil and 'nil' or tostring(pet_hpp),
			luopan_present = tostring(geo_present == true),
			owned_geo_spell = tostring(provider.state.owned_geo_spell or ''),
			configured_geo_spell = tostring(config.geo_spell or ''),
			geo_satisfied = tostring(geo_present == true
				and provider.state.owned_geo_spell == config.geo_spell),
			sequence_kind = tostring(sequence and sequence.kind or ''),
			sequence_step = tostring(sequence and sequence.step or ''),
			sequence_atomic = tostring(sequence and sequence.atomic == true or false),
			pending_kind = tostring(pending and pending.kind or ''),
			pending_spell = tostring(pending and pending.spell or ''),
			pending_age_s = pending_age,
			retry_remaining_s = ('%.2f'):format(math.max(
				0,
				(tonumber(provider.state.next_retry_at) or 0) - (tonumber(ctx.now) or 0)
			)),
		}
	end

	local function copy_fields(fields)
		local copy = {}
		for key, value in pairs(fields or {}) do
			copy[key] = value
		end
		return copy
	end

	local function trace_luopan_state(ctx, config, geo_present)
		local fields = geo_diag_fields(ctx, config, geo_present)
		_G.UC_GEO_DIAGNOSTIC_STATUS = copy_fields(fields)
		local signature = table.concat({
			fields.pet_present,
			tostring(fields.pet_id),
			tostring(fields.pet_index),
			fields.pet_hpp,
			fields.luopan_present,
			fields.owned_geo_spell,
			fields.configured_geo_spell,
			fields.sequence_kind,
			fields.sequence_step,
			fields.pending_kind,
		}, '|')
		if signature ~= provider.state.diag_last_luopan_signature then
			provider.state.diag_last_luopan_signature = signature
			action_timeline_log('GEO_LUOPAN_STATE', fields, 'geo_luopan_state:' .. signature, 0)
		end
	end

	local function trace_geo_create_decision(ctx, config, geo_present, outcome, reason, extra)
		if geo_present == true then
			return
		end
		local fields = geo_diag_fields(ctx, config, geo_present)
		fields.outcome = tostring(outcome or '')
		fields.reason = tostring(reason or '')
		if type(extra) == 'table' then
			for key, value in pairs(extra) do
				fields[key] = value
			end
		end
		_G.UC_GEO_DIAGNOSTIC_STATUS = copy_fields(fields)
		local key = table.concat({
			'geo_create_decision',
			fields.outcome,
			fields.reason,
			fields.sequence_kind,
			fields.sequence_step,
			fields.pending_kind,
		}, ':')
		action_timeline_log('GEO_CREATE_DECISION', fields, key, 5.0)
	end

	local function reset_identity()
		provider.state.owned_geo_spell = nil
		provider.state.owned_geo_blaze_enhanced = false
		provider.state.owned_indi_spell = nil
		provider.state.owned_entrust_spell = nil
		provider.state.owned_entrust_target_id = 0
		provider.state.enemy_target_id = 0
		provider.state.ecliptic_luopan_id = 0
		provider.state.pending = nil
		provider.state.sequence = nil
		provider.state.next_retry_at = 0
		provider.state.failed_geo_target_id = 0
		provider.state.failed_geo_target_until = 0
		provider.state.next_slow_maintenance_at = 0
	end

	local function config_contract_signature(config)
		local target = type(config.geo_target) == 'table' and config.geo_target or {}
		local luopan = type(config.luopan) == 'table' and config.luopan or {}
		local entrust = type(config.entrust) == 'table' and config.entrust or {}
		return table.concat({
			tostring(config.enabled == true),
			tostring(config.geo_spell or ''),
			tostring(target.kind or ''),
			tostring(target.name or ''),
			tostring(config.indi_spell or ''),
			tostring(config.ordering or ''),
			tostring(config.require_camp == true),
			tostring(config.camp_tolerance_yalms or ''),
			tostring(config.enemy_geo_requires_camp_radius == true),
			tostring(config.unknown_existing_policy or ''),
			tostring(luopan.placement or ''),
			tostring(luopan.use_blaze_of_glory == true),
			tostring(luopan.use_ecliptic_attrition == true),
			tostring(luopan.use_life_cycle == true),
			tostring(luopan.life_cycle_hpp or ''),
			tostring(luopan.replace_out_of_position == true),
			tostring(luopan.max_camp_distance_yalms or ''),
			tostring(entrust.enabled == true),
			tostring(entrust.spell or ''),
			tostring(entrust.target_name or ''),
		}, '|')
	end

	local function spell_contract(spell_name, prefix, target_kind)
		if type(spell_name) ~= 'string' or not spell_name:match('^' .. prefix .. '%-') then
			return nil, 'invalid_' .. prefix:lower() .. '_spell_name'
		end
		local resource = get_spell_resource(spell_name)
		if type(resource) ~= 'table' or tonumber(resource.id) == nil then
			return nil, 'spell_resource_missing:' .. spell_name
		end
		if tostring(resource.en or '') ~= spell_name then
			return nil, 'spell_resource_name_mismatch:' .. spell_name
		end
		local supported = false
		if type(resource.targets) == 'number' then
			local mask = resource.targets
			if target_kind == 'current_enemy' then
				supported = math.floor(mask / 32) % 2 == 1
			elseif target_kind == 'self' then
				supported = mask % 2 == 1
			elseif target_kind == 'party_member' then
				supported = math.floor(mask / 2) % 2 == 1
					or math.floor(mask / 4) % 2 == 1
			end
		elseif type(resource.targets) == 'table' then
			if target_kind == 'current_enemy' then
				supported = resource.targets.Enemy == true
			elseif target_kind == 'self' then
				supported = resource.targets.Self == true
			elseif target_kind == 'party_member' then
				supported = resource.targets.Party == true or resource.targets.Player == true
			end
		else
			return nil, 'spell_targets_missing:' .. spell_name
		end
		if not supported then
			return nil, 'spell_target_incompatible:' .. spell_name
		end
		local max_range = action_effective_range(resource.range)
		if finite_number(max_range) == nil or max_range < 0 then
			return nil, 'spell_range_invalid:' .. spell_name
		end
		if max_range == 0 and target_kind == 'self' then
			max_range = 0.1
		elseif max_range == 0 then
			return nil, 'spell_range_invalid:' .. spell_name
		end
		return {
			resource = resource,
			max_range = max_range,
		}
	end

	local function ja_contract(action_name)
		local resource = get_ja_resource(action_name)
		if type(resource) ~= 'table' or tonumber(resource.id) == nil then
			return nil, 'ability_resource_missing:' .. action_name
		end
		if tostring(resource.en or '') ~= action_name then
			return nil, 'ability_resource_name_mismatch:' .. action_name
		end
		return resource, nil
	end

	local function validate_config(config)
		if config.enabled ~= true then
			return nil, 'disabled'
		end
		if tostring(config.unknown_existing_policy or '') ~= 'wait_for_clear' then
			return nil, 'unsupported_unknown_existing_policy'
		end
		local target = require_table(config.geo_target, 'maintenance.geo.geo_target')
		local luopan = require_table(config.luopan, 'maintenance.geo.luopan')
		if luopan.placement ~= 'target' and luopan.placement ~= 'camp' then
			return nil, 'unsupported_luopan_placement'
		end
		local geo, geo_reason = spell_contract(config.geo_spell, 'Geo', target.kind)
		if geo == nil then
			return nil, geo_reason
		end
		local indi, indi_reason = spell_contract(config.indi_spell, 'Indi', 'self')
		if indi == nil then
			return nil, indi_reason
		end
		local entrust_spell = nil
		if config.entrust.enabled == true then
			entrust_spell, indi_reason = spell_contract(config.entrust.spell, 'Indi', 'self')
			if entrust_spell == nil then
				return nil, indi_reason
			end
			local _, entrust_reason = ja_contract('Entrust')
			if entrust_reason ~= nil then
				return nil, entrust_reason
			end
			entrust_spell.max_range = ENTRUST_SPELL_MAX_RANGE_YALMS
		end
		local required_abilities = {}
		if config.luopan.use_blaze_of_glory == true then
			required_abilities[#required_abilities + 1] = 'Blaze of Glory'
		end
		if config.luopan.use_ecliptic_attrition == true then
			required_abilities[#required_abilities + 1] = 'Ecliptic Attrition'
		end
		if config.luopan.use_life_cycle == true then
			required_abilities[#required_abilities + 1] = 'Life Cycle'
		end
		if config.luopan.use_blaze_of_glory == true
			or (config.luopan.placement == 'camp'
				and config.luopan.replace_out_of_position == true)
			or target.kind == 'current_enemy' then
			required_abilities[#required_abilities + 1] = 'Full Circle'
		end
		for i = 1, #required_abilities do
			local _, ability_reason = ja_contract(required_abilities[i])
			if ability_reason ~= nil then
				return nil, ability_reason
			end
		end
		return {
			geo = geo,
			indi = indi,
			entrust = entrust_spell,
		}, nil
	end

	local function validate_config_cached(config)
		local signature = config_contract_signature(config)
		if signature ~= provider.state.config_contract_signature then
			-- Retire copied sequence intent, never already-sent pending evidence.
			if provider.state.config_contract_signature ~= '' then
				provider.state.sequence = nil
			end
			provider.state.config_contract_signature = signature
			provider.state.config_contracts, provider.state.config_validation_reason =
				validate_config(config)
			provider.state.next_slow_maintenance_at = 0
		end
		return provider.state.config_contracts, provider.state.config_validation_reason
	end

	local function resolve_party_target(ctx, configured_name)
		local wanted = tostring(configured_name or ''):lower()
		local members = get_party_members(ctx)
		for i = 1, #members do
			local member = members[i]
			if tostring(member.name or ''):lower() == wanted then
				return member
			end
		end
		return nil
	end

	local function tracked_enemy_is_valid(ctx, mob, friendly_claims)
		if not target_is_actionable(mob, ctx.now, true) then
			return false
		end
		if target_is_ignored(ctx.config, mob) then
			return false
		end
		local claim_id = tonumber(mob.claim_id) or 0
		if friendly_claims[claim_id] == true then
			return true
		end
		return false
	end

	local function choose_enemy_target(ctx, preferred_id)
		local friendly_claims = require_table(get_friendly_claims(ctx), 'friendly combat claim set')
		local failed_target_id = finite_number(provider.state.failed_geo_target_id)
		local failed_target_until = finite_number(provider.state.failed_geo_target_until)
		if failed_target_id == nil or failed_target_until == nil then
			error('failed GEO target quarantine state must remain finite')
		end
		if ctx.now >= failed_target_until then
			failed_target_id = 0
			provider.state.failed_geo_target_id = 0
			provider.state.failed_geo_target_until = 0
		end
		local function target_is_available(mob)
			return tonumber(mob and mob.id) ~= failed_target_id
				and tracked_enemy_is_valid(ctx, mob, friendly_claims)
		end

		local preferred = ctx.mobs_by_id[tonumber(preferred_id) or 0]
		if preferred ~= nil and target_is_available(preferred) then
			return preferred, 'sequence_target'
		end

		local selected = nil
		for _, mob in pairs(ctx.mob_array) do
			local claim_id = tonumber(mob and mob.claim_id) or 0
			if friendly_claims[claim_id] == true
				and target_is_available(mob) then
				local mob_hpp = tonumber(mob.hpp) or 0
				local selected_hpp = tonumber(selected and selected.hpp) or math.huge
				local mob_distance = tonumber(mob.distance) or math.huge
				local selected_distance = tonumber(selected and selected.distance) or math.huge
				local mob_id = tonumber(mob.id) or 0
				local selected_id = tonumber(selected and selected.id) or math.huge
				if selected == nil
					or mob_hpp < selected_hpp
					or (mob_hpp == selected_hpp and mob_distance < selected_distance)
					or (mob_hpp == selected_hpp and mob_distance == selected_distance and mob_id < selected_id) then
					selected = mob
				end
			end
		end
		if selected ~= nil then
			return selected, 'friendly_claim'
		end
		return nil
	end

	local function note_enemy_target(target, source, sequence)
		local prior_id = tonumber(provider.state.enemy_target_id) or 0
		local target_id = tonumber(target and target.id) or 0
		provider.state.enemy_target_id = target_id
		if type(sequence) == 'table' then
			sequence.target_id = target_id
		end
		if prior_id == target_id then
			return
		end
		action_timeline_log('GEO_ENEMY_TARGET_CHANGED', {
			from_target_id = prior_id,
			target_id = target_id,
			target = tostring(target and target.name or ''),
			source = tostring(source or 'unavailable'),
			sequence_step = tostring(sequence and sequence.step or ''),
			atomic = sequence and sequence.atomic == true or false,
		}, ('geo_enemy_target:%d:%d'):format(prior_id, target_id), 0.05)
	end

	local function set_sequence_enemy_wait(sequence, waiting, reason)
		local required = waiting == true
		if sequence.awaiting_enemy_target == required then
			return
		end
		sequence.awaiting_enemy_target = required
		action_timeline_log(required and 'GEO_ATOMIC_ENEMY_WAIT' or 'GEO_ATOMIC_ENEMY_READY', {
			target_id = tonumber(sequence.target_id) or 0,
			reason = tostring(reason or ''),
			sequence_step = tostring(sequence.step or ''),
			atomic = sequence.atomic == true,
		}, ('geo_atomic_enemy_wait:%s:%d'):format(
			tostring(required),
			tonumber(sequence.target_id) or 0
		), 0.05)
	end

	local function resolve_geo_target(ctx, config, sequence)
		local kind = tostring(config.geo_target.kind or '')
		if kind == 'self' then
			return {
				id = ctx.player_id,
				name = ctx.player_name,
				is_self = true,
			}, 'self', nil
		end
		if kind == 'party_member' then
			local member = resolve_party_target(ctx, config.geo_target.name)
			if member == nil then
				return nil, nil, 'configured_party_member_unavailable'
			end
			return member, 'party', nil
		end
		if kind == 'current_enemy' then
			local preferred_id = type(sequence) == 'table' and sequence.target_id or 0
			local target, source = choose_enemy_target(ctx, preferred_id)
			if target == nil then
				note_enemy_target(nil, 'unavailable', sequence)
				return nil, nil, 'current_enemy_unavailable'
			end
			note_enemy_target(target, source, sequence)
			return {
				id = provider.state.enemy_target_id,
				name = tostring(target.name or ''),
				is_mob = true,
				mob = target,
			}, 'mob', nil
		end
		return nil, nil, 'unsupported_geo_target_kind'
	end

	local function target_in_range(ctx, target, max_range)
		if target.is_self == true then
			return true, nil
		end
		local mob = target.mob
		if mob == nil and type(ctx.mobs_by_id) == 'table' then
			mob = ctx.mobs_by_id[tonumber(target.id)]
		end
		local distance = mob_distance(mob)
		if distance == nil then
			return false, 'target_geometry_unavailable'
		end
		if distance > max_range + SPELL_RANGE_EPSILON then
			return false, 'target_out_of_range'
		end
		return true, nil
	end

	local function camp_ready(ctx, config)
		if config.require_camp ~= true then
			return true, nil
		end
		local anchor, reason = resolve_camp_anchor()
		if type(anchor) ~= 'table' then
			return false, tostring(reason or 'camp_unavailable')
		end
		local distance = distance_between(ctx.me, anchor)
		if distance == nil then
			return false, 'camp_geometry_unavailable'
		end
		if distance > tonumber(config.camp_tolerance_yalms) then
			return false, 'outside_camp_tolerance'
		end
		return true, nil
	end

	local function enemy_geo_camp_ready(ctx, config, target)
		if config.enemy_geo_requires_camp_radius ~= true
			or tostring(config.geo_target.kind or '') ~= 'current_enemy' then
			return true, nil, nil
		end
		if type(target) ~= 'table' or target.is_mob ~= true or type(target.mob) ~= 'table' then
			error('camp-restricted enemy Geo requires a resolved mob target')
		end
		local anchor, reason = resolve_camp_anchor()
		if type(anchor) ~= 'table' then
			return false, tostring(reason or 'camp_unavailable'), nil
		end
		local distance = distance_between(target.mob, anchor)
		if distance == nil then
			return false, 'enemy_camp_geometry_unavailable', nil
		end
		if distance > tonumber(config.luopan.max_camp_distance_yalms) then
			return false, 'enemy_outside_camp_radius', distance
		end
		return true, nil, distance
	end

	local function observe_identity(ctx)
		local geo_present = luopan_present(ctx)
		local indi_present = has_buff(ctx.player, INDI_COLURE_BUFF_ID)
		local identity_changed = false
		local pending = provider.state.pending
		if type(pending) == 'table' then
			local effect = tostring(pending.effect or pending.kind or '')
			local observed = (effect == 'geo' and geo_present)
				or (effect == 'indi' and indi_present)
			if observed then
				identity_changed = true
				if effect == 'geo' then
					provider.state.owned_geo_spell = pending.spell
					provider.state.owned_geo_blaze_enhanced = pending.blaze_enhanced == true
				elseif effect == 'indi' then
					provider.state.owned_indi_spell = pending.spell
				end
				provider.state.pending = nil
			elseif ctx.now - pending.sent_at > EFFECT_OBSERVATION_TIMEOUT then
				identity_changed = true
				log(('GEO_MAINT_PENDING_TIMEOUT kind=%s spell="%s"'):format(
					tostring(pending.kind),
					tostring(pending.spell)
				))
				provider.state.pending = nil
			end
		end
		if not geo_present then
			if provider.state.owned_geo_spell ~= nil
				or provider.state.owned_geo_blaze_enhanced == true then
				identity_changed = true
			end
			provider.state.owned_geo_spell = nil
			provider.state.owned_geo_blaze_enhanced = false
			if provider.state.pending and provider.state.pending.kind == 'geo' then
				-- Keep the pending cast token until observation timeout.
			end
		end
		if not indi_present then
			if provider.state.owned_indi_spell ~= nil then
				identity_changed = true
			end
			provider.state.owned_indi_spell = nil
		end
		return geo_present, indi_present, identity_changed
	end

	local function emit_spell(ctx, out, kind, spell_name, target, target_kind, max_range, urgency, sequence)
		local in_range, range_reason = target_in_range(ctx, target, max_range)
		if not in_range then
			publish_status(kind .. '_blocked', range_reason)
			return false
		end
		local ready, ready_reason, action_kind = action_ready(spell_name, tonumber(target.id))
		if not ready or action_kind ~= 'spell' then
			publish_status(kind .. '_blocked', tostring(ready_reason or action_kind))
			return false
		end
		local priority_band = geo_maintenance_priority
		if kind == 'geo' then
			priority_band = geo_creation_priority
		end
		out[#out + 1] = proposal(ctx, {
			kind = kind,
			action_name = spell_name,
			target_kind = target_kind,
			target_id = target.id,
			target_name = target.name,
			max_range = max_range,
			urgency = urgency,
			priority_band = priority_band,
			reason_code = 'geo_' .. kind .. '_missing',
			expected_effect = kind == 'geo' and 'luopan_present' or 'indi_colure_present',
			sequence_kind = sequence and sequence.kind or '',
			sequence_step = sequence and sequence.step or '',
			blaze_enhanced = sequence and sequence.blaze_enhanced == true,
			config_contract_signature = provider.state.config_contract_signature,
		})
		publish_status(kind .. '_proposed', spell_name)
		return true
	end

	local function emit_ja(ctx, out, action_name, effect, urgency, sequence)
		local ready, ready_reason, action_kind = action_ready(action_name, ctx.player_id)
		if not ready or action_kind ~= 'ja' then
			publish_status('ja_blocked', tostring(ready_reason or action_kind))
			return false
		end
		local priority_band = geo_maintenance_priority
		if type(sequence) == 'table'
			and sequence.kind == 'geo_create'
			and (sequence.step == 'full_circle' or sequence.step == 'blaze') then
			priority_band = geo_creation_priority
		end
		out[#out + 1] = proposal(ctx, {
			kind = effect,
			action_type = 'ja',
			action_name = action_name,
			target_kind = 'self',
			target_id = ctx.player_id,
			target_name = ctx.player_name,
			max_range = 0.1,
			urgency = urgency,
			priority_band = priority_band,
			reason_code = 'geo_' .. effect,
			expected_effect = effect,
			sequence_kind = sequence and sequence.kind or '',
			sequence_step = sequence and sequence.step or '',
			config_contract_signature = provider.state.config_contract_signature,
		})
		publish_status('ja_proposed', action_name)
		return true
	end

	local function member_has_buff(member, buff_id)
		return has_buff({ buffs = member and member.buffs }, buff_id)
	end

	local function luopan_misplaced(ctx, config)
		if config.luopan.placement ~= 'camp'
			or config.luopan.replace_out_of_position ~= true
			or not luopan_present(ctx) then
			return false, nil
		end
		local anchor, reason = resolve_camp_anchor()
		if type(anchor) ~= 'table' then
			return false, tostring(reason or 'camp_unavailable')
		end
		local distance = distance_between(ctx.pet, anchor)
		if distance == nil then
			return false, 'luopan_geometry_unavailable'
		end
		return distance > tonumber(config.luopan.max_camp_distance_yalms), nil
	end

	local function luopan_outside_enemy_radius(ctx, config, target)
		-- Camp placement converges against the camp anchor in luopan_misplaced;
		-- the legal spell target is not the Luopan's placement anchor in that mode.
		if config.luopan.placement == 'camp'
			or tostring(config.geo_target.kind or '') ~= 'current_enemy'
			or not luopan_present(ctx)
			or target == nil then
			return false, nil, nil
		end
		if target.is_mob ~= true or type(target.mob) ~= 'table' then
			error('enemy-targeted GEO placement requires a resolved mob target')
		end
		local distance = distance_between(ctx.pet, target.mob)
		if distance == nil then
			return false, 'luopan_target_geometry_unavailable', nil
		end
		return distance > ENEMY_LUOPAN_EFFECT_RADIUS_YALMS, nil, distance
	end

	local function blaze_upgrade_ready(ctx, config)
		if config.luopan.use_blaze_of_glory ~= true then
			return false, false
		end
		if has_buff(ctx.player, BLAZE_OF_GLORY_BUFF_ID) then
			return true, true
		end
		local ready, _, action_kind = action_ready('Blaze of Glory', ctx.player_id)
		if action_kind ~= 'ja' then
			error('Blaze of Glory readiness must identify a job ability')
		end
		return ready == true, false
	end

	local function begin_geo_creation(config, needs_full_circle, target_id, blaze_enhanced, blaze_consumed)
		if blaze_consumed == true and blaze_enhanced ~= true then
			error('consumed Blaze sequence must be marked enhanced')
		end
		local step = 'geo_spell'
		if needs_full_circle then
			step = 'full_circle'
		elseif blaze_enhanced == true and blaze_consumed ~= true then
			step = 'blaze'
		end
		provider.state.sequence = {
			kind = 'geo_create',
			step = step,
			atomic = blaze_consumed == true,
			replacement = needs_full_circle == true,
			blaze_enhanced = blaze_enhanced == true,
			target_id = tonumber(target_id) or 0,
			target_kind = tostring(config.geo_target.kind or ''),
			awaiting_enemy_target = false,
		}
		return provider.state.sequence
	end

	local function observe_sequence(ctx, config)
		local sequence = provider.state.sequence
		if type(sequence) ~= 'table' then
			return
		end
		if sequence.kind == 'geo_create' then
			if sequence.step == 'full_circle' and not luopan_present(ctx) then
				provider.state.pending = nil
				if sequence.blaze_enhanced == true and not has_buff(ctx.player, BLAZE_OF_GLORY_BUFF_ID) then
					sequence.step = 'blaze'
				else
					sequence.step = 'geo_spell'
				end
			elseif sequence.step == 'blaze' and has_buff(ctx.player, BLAZE_OF_GLORY_BUFF_ID) then
				provider.state.pending = nil
				sequence.step = 'geo_spell'
				sequence.atomic = true
				sequence.awaiting_enemy_target = false
			elseif sequence.step == 'geo_spell'
				and luopan_present(ctx)
				and provider.state.owned_geo_spell == config.geo_spell
				and provider.state.owned_geo_blaze_enhanced == (sequence.blaze_enhanced == true) then
				provider.state.pending = nil
				if config.luopan.use_ecliptic_attrition == true then
					local ready, ready_reason, action_kind =
						action_ready('Ecliptic Attrition', ctx.player_id)
					if ready == true and action_kind == 'ja' then
						sequence.step = 'ecliptic'
						sequence.atomic = false
					else
						provider.state.sequence = nil
						publish_status('ja_blocked', tostring(ready_reason or action_kind))
					end
				else
					provider.state.sequence = nil
				end
			end
			return
		end
		if sequence.kind == 'entrust' then
			local member = resolve_party_target(ctx, config.entrust.target_name)
			if member == nil then
				provider.state.pending = nil
				provider.state.sequence = nil
				provider.state.next_retry_at = ctx.now + 2.0
				publish_status('sequence_failed', 'entrust_target_unavailable')
				return
			end
			if sequence.step == 'entrust_ja' and has_buff(ctx.player, ENTRUST_BUFF_ID) then
				provider.state.pending = nil
				sequence.step = 'entrust_spell'
				sequence.atomic = true
			elseif sequence.step == 'entrust_spell'
				and member_has_buff(member, INDI_COLURE_BUFF_ID) then
				provider.state.pending = nil
				provider.state.owned_entrust_spell = config.entrust.spell
				provider.state.owned_entrust_target_id = tonumber(member.id) or 0
				provider.state.sequence = nil
			end
		end
	end

	local function collect_sequence(ctx, out, config, contracts)
		local sequence = provider.state.sequence
		if type(sequence) ~= 'table' then
			return false
		end
		if provider.state.pending ~= nil then
			publish_status('awaiting_effect', sequence.step)
			return true
		end
		if sequence.kind == 'geo_create' then
			if sequence.step == 'full_circle' then
				if not luopan_present(ctx) then
					error('GEO Full Circle sequence retained after luopan absence')
				end
				if not emit_ja(ctx, out, 'Full Circle', 'pet_absent', 0.95, sequence) then
					provider.state.sequence = nil
				end
				return true
			end
			if sequence.step == 'blaze' then
				local target, _, reason = resolve_geo_target(ctx, config, sequence)
				if target == nil then
					publish_status('sequence_blocked', reason)
					return true
				end
				local target_at_camp, target_camp_reason = enemy_geo_camp_ready(ctx, config, target)
				if not target_at_camp then
					set_sequence_enemy_wait(sequence, true, target_camp_reason)
					publish_status('sequence_blocked', target_camp_reason)
					return true
				end
				set_sequence_enemy_wait(sequence, false, 'enemy_inside_camp_radius')
				if not emit_ja(ctx, out, 'Blaze of Glory', 'blaze_buff', 0.95, sequence) then
					sequence.step = 'geo_spell'
					sequence.atomic = false
					sequence.blaze_enhanced = false
					return collect_sequence(ctx, out, config, contracts)
				end
				return true
			end
			if sequence.step == 'geo_spell' then
				local target, target_kind, reason = resolve_geo_target(ctx, config, sequence)
				if target == nil then
					set_sequence_enemy_wait(sequence, true, reason)
					publish_status('sequence_blocked', reason)
					return true
				end
				local target_at_camp, target_camp_reason = enemy_geo_camp_ready(ctx, config, target)
				if not target_at_camp then
					set_sequence_enemy_wait(sequence, true, target_camp_reason)
					publish_status('sequence_blocked', target_camp_reason)
					return true
				end
				set_sequence_enemy_wait(sequence, false, 'enemy_inside_camp_radius')
				emit_spell(
					ctx,
					out,
					'geo',
					config.geo_spell,
					target,
					target_kind,
					contracts.geo.max_range,
					1.0,
					sequence
				)
				return true
			end
			if sequence.step == 'ecliptic' then
				if not luopan_present(ctx) then
					provider.state.sequence = nil
					publish_status('sequence_failed', 'luopan_missing_before_ecliptic')
					return true
				end
				sequence.luopan_id = tonumber(ctx.pet_id) or 0
				if not emit_ja(ctx, out, 'Ecliptic Attrition', 'ecliptic_complete', 0.90, sequence) then
					provider.state.sequence = nil
				end
				return true
			end
			error('unsupported GEO creation sequence step: ' .. tostring(sequence.step))
		end
		if sequence.kind == 'entrust' then
			local member = resolve_party_target(ctx, config.entrust.target_name)
			if member == nil then
				provider.state.sequence = nil
				provider.state.next_retry_at = ctx.now + 2.0
				publish_status('sequence_failed', 'entrust_target_unavailable')
				return true
			end
			if sequence.step == 'entrust_ja' then
				if not emit_ja(ctx, out, 'Entrust', 'entrust_buff', 0.90, sequence) then
					provider.state.sequence = nil
				end
				return true
			end
			if sequence.step == 'entrust_spell' then
				if not has_buff(ctx.player, ENTRUST_BUFF_ID) then
					provider.state.sequence = nil
					provider.state.next_retry_at = ctx.now + 2.0
					publish_status('sequence_failed', 'entrust_buff_missing_before_spell')
					return true
				end
				local in_range, range_reason = target_in_range(ctx, member, contracts.entrust.max_range)
				if not in_range then
					provider.state.sequence = nil
					provider.state.next_retry_at = ctx.now + 2.0
					publish_status('sequence_failed', range_reason)
					return true
				end
				if not emit_spell(
					ctx,
					out,
					'entrust',
					config.entrust.spell,
					member,
					'party',
					contracts.entrust.max_range,
					1.0,
					sequence
				) then
					provider.state.sequence = nil
				end
				return true
			end
			error('unsupported Entrust sequence step: ' .. tostring(sequence.step))
		end
		error('unsupported GEO sequence kind: ' .. tostring(sequence.kind))
	end

	local function sequence_restores_missing_luopan(sequence, ctx)
		return not luopan_present(ctx)
			and type(sequence) == 'table'
			and sequence.kind == 'geo_create'
			and (sequence.step == 'full_circle'
				or sequence.step == 'blaze'
				or sequence.step == 'geo_spell')
	end

	local function creation_target_ready(ctx, config, contracts, sequence)
		local target, _, target_reason = resolve_geo_target(ctx, config, sequence)
		if target == nil then
			return false, target_reason
		end
		local target_at_camp, target_camp_reason = enemy_geo_camp_ready(ctx, config, target)
		if not target_at_camp then
			return false, target_camp_reason
		end
		local in_range, range_reason = target_in_range(ctx, target, contracts.geo.max_range)
		if not in_range then
			return false, range_reason
		end
		return true, nil, target
	end

	local function sequence_serves_missing_core_geo(sequence, geo_satisfied)
		return type(sequence) == 'table'
			and sequence.kind == 'geo_create'
			and geo_satisfied ~= true
			and (sequence.step == 'full_circle'
				or sequence.step == 'blaze'
				or sequence.step == 'geo_spell')
	end

	local function preempt_optional_sequence_for_core(ctx, geo_satisfied, indi_satisfied)
		local sequence = provider.state.sequence
		if type(sequence) ~= 'table'
			or provider.state.pending ~= nil
			or (geo_satisfied == true and indi_satisfied == true)
			or sequence_serves_missing_core_geo(sequence, geo_satisfied) then
			return false
		end
		action_timeline_log('GEO_OPTIONAL_SEQUENCE_PREEMPTED', {
			sequence_kind = tostring(sequence.kind or ''),
			sequence_step = tostring(sequence.step or ''),
			geo_satisfied = tostring(geo_satisfied == true),
			indi_satisfied = tostring(indi_satisfied == true),
			reason = 'core_field_missing',
		}, ('geo_optional_preempt:%s:%s'):format(
			tostring(sequence.kind or ''),
			tostring(sequence.step or '')
		), 0.25)
		provider.state.sequence = nil
		publish_status('sequence_preempted', 'core_field_missing')
		return true
	end

	function provider.creation_preempts_pull(ctx)
		require_table(ctx, 'ctx')
		local config = M.config_from_context(ctx)
		if rawget(_G, 'Start_Engine') ~= true
			or config.enabled ~= true
			or ctx.player_present ~= true
			or tostring(ctx.player.main_job or '') ~= 'GEO'
			or luopan_present(ctx) then
			return false
		end
		if type(ctx.player.vitals) == 'table' and tonumber(ctx.player.vitals.hpp) == 0 then
			return false
		end
		local contracts = validate_config_cached(config)
		if contracts == nil then
			return false
		end
		local at_camp = camp_ready(ctx, config)
		if not at_camp then
			return false
		end
		local pending = provider.state.pending
		if type(pending) == 'table'
			and (pending.kind == 'geo' or pending.kind == 'blaze_buff') then
			return true
		end
		if ctx.now < provider.state.next_retry_at then
			return false
		end
		local sequence = provider.state.sequence
		local creation_sequence = sequence_restores_missing_luopan(sequence, ctx)
			and sequence or nil
		local target_ready, _, target =
			creation_target_ready(ctx, config, contracts, creation_sequence)
		if not target_ready then
			return false
		end
		if type(creation_sequence) == 'table' and creation_sequence.step == 'blaze' then
			local ready, _, action_kind = action_ready('Blaze of Glory', ctx.player_id)
			return ready == true and action_kind == 'ja'
		end
		local blaze_ready, blaze_consumed = blaze_upgrade_ready(ctx, config)
		if blaze_ready and not blaze_consumed then
			return true
		end
		local ready, _, action_kind = action_ready(config.geo_spell, tonumber(target.id))
		return ready == true and action_kind == 'spell'
	end

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		local config = M.config_from_context(ctx)
		if rawget(_G, 'Start_Engine') ~= true then
			reset_identity()
			publish_status('engine_off', '')
			return
		end
		if config.enabled ~= true then
			reset_identity()
			publish_status('disabled', '')
			return
		end
		if ctx.player_present ~= true then
			reset_identity()
			publish_status('no_player', '')
			return
		end
		if type(ctx.player.vitals) == 'table' and tonumber(ctx.player.vitals.hpp) == 0 then
			reset_identity()
			publish_status('no_player', 'player_dead')
			return
		end
		if tostring(ctx.player.main_job or '') ~= 'GEO' then
			reset_identity()
			publish_status('not_geomancer', '')
			return
		end
		local contracts, validation_reason = validate_config_cached(config)
		if contracts == nil then
			publish_status('invalid_config', validation_reason)
			log('GEO_MAINT_SKIP state=invalid_config reason=' .. tostring(validation_reason))
			return
		end
		local geo_present, indi_present, identity_changed = observe_identity(ctx)
		observe_sequence(ctx, config)
		trace_luopan_state(ctx, config, geo_present)
		local sequence = provider.state.sequence
		local geo_satisfied = geo_present and provider.state.owned_geo_spell == config.geo_spell
		local indi_satisfied = indi_present and provider.state.owned_indi_spell == config.indi_spell
		if preempt_optional_sequence_for_core(ctx, geo_satisfied, indi_satisfied) then
			sequence = nil
		end
		local pet_hpp = finite_number(ctx.pet and ctx.pet.hpp)
		local life_cycle_due = config.luopan.use_life_cycle == true
			and geo_present
			and pet_hpp ~= nil
			and pet_hpp < tonumber(config.luopan.life_cycle_hpp)
		local ecliptic_due = config.luopan.use_ecliptic_attrition == true
			and geo_present
			and provider.state.ecliptic_luopan_id ~= tonumber(ctx.pet_id)
		local blaze_upgrade_pending = config.luopan.use_blaze_of_glory == true
			and geo_present
			and provider.state.owned_geo_blaze_enhanced ~= true
		local entrust_due = false
		if config.entrust.enabled == true then
			local entrusted_member = resolve_party_target(ctx, config.entrust.target_name)
			local entrusted_member_id = tonumber(entrusted_member and entrusted_member.id) or 0
			entrust_due = entrusted_member == nil
				or type(entrusted_member.buffs) ~= 'table'
				or provider.state.owned_entrust_spell ~= config.entrust.spell
				or provider.state.owned_entrust_target_id ~= entrusted_member_id
				or not member_has_buff(entrusted_member, INDI_COLURE_BUFF_ID)
		end
		local fast_work = type(sequence) == 'table'
			or provider.state.pending ~= nil
			or not geo_satisfied
			or not indi_satisfied
			or provider.state.bolster_armed == true
			or life_cycle_due
			or ecliptic_due
			or blaze_upgrade_pending
			or entrust_due
		local slow_due = ctx.now >= (tonumber(provider.state.next_slow_maintenance_at) or 0)
		if not fast_work and not slow_due then
			if identity_changed then
				publish_status('converged', '')
			end
			return
		end
		if slow_due then
			provider.state.next_slow_maintenance_at = ctx.now + SLOW_MAINTENANCE_INTERVAL
		end
		local at_camp, camp_reason = camp_ready(ctx, config)
		if type(sequence) == 'table'
			and sequence.kind == 'geo_create'
			and sequence.step == 'geo_spell'
			and sequence.atomic == true
			and sequence.target_kind == 'current_enemy' then
			local target = resolve_geo_target(ctx, config, sequence)
			if target == nil then
				set_sequence_enemy_wait(sequence, true, 'current_enemy_unavailable')
			elseif not at_camp then
				set_sequence_enemy_wait(sequence, true, camp_reason)
			else
				local target_at_camp, target_camp_reason = enemy_geo_camp_ready(ctx, config, target)
				set_sequence_enemy_wait(
					sequence,
					not target_at_camp,
					target_at_camp and 'enemy_inside_camp_radius' or target_camp_reason
				)
			end
		end
		-- Movement is resolved by scheduler dispatch. GEO proposals are marked
		-- must_stop/can_preempt_movement, so suppressing proposal collection
		-- while following can starve luopan recovery indefinitely.
		if not at_camp then
			publish_status('blocked', camp_reason)
			trace_geo_create_decision(ctx, config, geo_present, 'blocked', camp_reason, {
				stage = 'camp_ready',
			})
			return
		end

		sequence = provider.state.sequence
		if type(sequence) == 'table' then
			if sequence.atomic ~= true
				and pull_active()
				and not sequence_restores_missing_luopan(sequence, ctx) then
				publish_status('sequence_held', 'pull_active')
				trace_geo_create_decision(ctx, config, geo_present, 'blocked', 'sequence_held:pull_active', {
					stage = 'active_sequence',
				})
				return
			end
			local proposal_count = #out
			collect_sequence(ctx, out, config, contracts)
			if not geo_present then
				trace_geo_create_decision(
					ctx,
					config,
					geo_present,
					#out > proposal_count and 'proposed' or 'blocked',
					#out > proposal_count
						and tostring(out[#out] and out[#out].action_name or provider.status.detail)
						or (tostring(provider.status.state) .. ':' .. tostring(provider.status.detail)),
					{ stage = 'active_sequence' }
				)
			end
			return
		end
		if provider.state.pending ~= nil then
			publish_status('awaiting_effect', provider.state.pending.kind)
			trace_geo_create_decision(ctx, config, geo_present, 'blocked', 'awaiting_effect:' .. tostring(provider.state.pending.kind), {
				stage = 'provider_pending',
			})
			return
		end
		if geo_present and provider.state.owned_geo_spell == nil then
			publish_status('unknown_existing', 'luopan_wait_for_clear')
			return
		end
		if indi_present and provider.state.owned_indi_spell == nil then
			publish_status('unknown_existing', 'indi_wait_for_clear')
			trace_geo_create_decision(ctx, config, geo_present, 'blocked', 'indi_wait_for_clear', {
				stage = 'unknown_existing',
			})
			return
		end
		local pull_in_progress = pull_active()
		if ctx.now < provider.state.next_retry_at then
			publish_status('backoff', 'sequence_retry')
			trace_geo_create_decision(ctx, config, geo_present, 'blocked', 'sequence_retry', {
				stage = 'retry_backoff',
			})
			return
		end

		local geo_target = nil
		local geo_target_kind = nil
		local geo_target_reason = nil
		local geo_target_resolved = false
		local function ensure_geo_target()
			if not geo_target_resolved then
				geo_target, geo_target_kind, geo_target_reason = resolve_geo_target(ctx, config, nil)
				geo_target_resolved = true
			end
			return geo_target
		end
		local function geo_target_is_ready()
			ensure_geo_target()
			if geo_target == nil then
				publish_status('geo_blocked', geo_target_reason)
				trace_geo_create_decision(ctx, config, geo_present, 'blocked', geo_target_reason, {
					stage = 'geo_target',
				})
				return false
			end
			local target_at_camp, target_camp_reason, target_camp_distance =
				enemy_geo_camp_ready(ctx, config, geo_target)
			if not target_at_camp then
				publish_status('geo_blocked', target_camp_reason)
				trace_geo_create_decision(ctx, config, geo_present, 'blocked', target_camp_reason, {
					stage = 'geo_target_camp',
					target_id = tonumber(geo_target.id) or 0,
					target = tostring(geo_target.name or ''),
					target_camp_distance = target_camp_distance and ('%.2f'):format(target_camp_distance) or '',
				})
				return false
			end
			return true
		end
		local function begin_replacement()
			if not geo_target_is_ready() then
				return false
			end
			local full_circle_ready, full_circle_reason, full_circle_kind =
				action_ready('Full Circle', ctx.player_id)
			if full_circle_ready ~= true or full_circle_kind ~= 'ja' then
				publish_status('ja_blocked', tostring(full_circle_reason or full_circle_kind))
				return false
			end
			local proposal_count = #out
			local enhance, consumed = blaze_upgrade_ready(ctx, config)
			begin_geo_creation(config, true, geo_target.id, enhance, consumed)
			collect_sequence(ctx, out, config, contracts)
			if not geo_present then
				trace_geo_create_decision(
					ctx,
					config,
					geo_present,
					#out > proposal_count and 'proposed' or 'blocked',
					#out > proposal_count
						and tostring(out[#out] and out[#out].action_name or provider.status.detail)
						or (tostring(provider.status.state) .. ':' .. tostring(provider.status.detail)),
					{ stage = 'replacement_sequence' }
				)
			end
			return #out > proposal_count
		end
		if geo_present and not geo_satisfied then
			if not begin_replacement() and not indi_satisfied then
				emit_indi()
			end
			return
		end
		if slow_due then
			local misplaced, placement_reason = luopan_misplaced(ctx, config)
			if placement_reason ~= nil then
				publish_status('blocked', placement_reason)
				return
			end
			if misplaced and begin_replacement() then
				return
			end
		end
		if slow_due and geo_satisfied then
			ensure_geo_target()
			local outside_radius, radius_reason, radius_distance =
				luopan_outside_enemy_radius(ctx, config, geo_target)
			if radius_reason ~= nil then
				publish_status('blocked', radius_reason)
				return
			end
			if outside_radius then
				if not geo_target_is_ready() then
					return
				end
				action_timeline_log('GEO_LUOPAN_REPOSITION_REQUIRED', {
					luopan_id = tonumber(ctx.pet_id) or 0,
					target_id = tonumber(geo_target.id) or 0,
					target = tostring(geo_target.name or ''),
					distance = ('%.2f'):format(radius_distance),
					radius = ('%.2f'):format(ENEMY_LUOPAN_EFFECT_RADIUS_YALMS),
				}, ('geo_luopan_reposition:%d:%d'):format(
					tonumber(ctx.pet_id) or 0,
					tonumber(geo_target.id) or 0
				), 0.50)
				if begin_replacement() then
					return
				end
			end
		end

		local function emit_geo()
			if not geo_target_is_ready() then
				return
			end
			local proposal_count = #out
			local enhance, consumed = blaze_upgrade_ready(ctx, config)
			if enhance then
				begin_geo_creation(config, false, geo_target.id, true, consumed)
				collect_sequence(ctx, out, config, contracts)
			else
				emit_spell(
					ctx,
					out,
					'geo',
					config.geo_spell,
					geo_target,
					geo_target_kind,
					contracts.geo.max_range,
					indi_satisfied and 0.70 or 0.85
				)
			end
			trace_geo_create_decision(
				ctx,
				config,
				geo_present,
				#out > proposal_count and 'proposed' or 'blocked',
				#out > proposal_count
					and tostring(out[#out] and out[#out].action_name or provider.status.detail)
					or (tostring(provider.status.state) .. ':' .. tostring(provider.status.detail)),
				{
					stage = enhance and 'geo_create_sequence' or 'direct_geo',
					target_id = tonumber(geo_target.id) or 0,
					target = tostring(geo_target.name or ''),
				}
			)
		end
		local function emit_indi()
			emit_spell(
				ctx,
				out,
				'indi',
				config.indi_spell,
				{
					id = ctx.player_id,
					name = ctx.player_name,
					is_self = true,
				},
				'self',
				contracts.indi.max_range,
				geo_satisfied and 0.70 or 0.80
			)
		end

		if pull_in_progress and geo_present then
			if not indi_satisfied then
				emit_indi()
			else
				publish_status('blocked', 'pull_active')
			end
			return
		end

		if config.ordering == 'indi_first' then
			if not indi_satisfied and not (pull_in_progress and not geo_present) then
				local proposal_count = #out
				emit_indi()
				trace_geo_create_decision(
					ctx,
					config,
					geo_present,
					'blocked',
					#out > proposal_count
						and 'ordering_indi_first:indi_proposed'
						or ('ordering_indi_first:' .. tostring(provider.status.state) .. ':' .. tostring(provider.status.detail)),
					{ stage = 'ordering' }
				)
				return
			elseif not geo_satisfied then
				emit_geo()
				return
			end
		elseif not geo_satisfied then
			emit_geo()
			return
		elseif not indi_satisfied then
			emit_indi()
			return
		end

		local optional_due = false
		local blaze_ready, blaze_consumed = blaze_upgrade_ready(ctx, config)
		if geo_present
			and provider.state.owned_geo_blaze_enhanced ~= true
			and blaze_ready then
			optional_due = true
			if begin_replacement() then
				return
			end
		end

		if provider.state.bolster_armed == true then
			optional_due = true
			if emit_ja(ctx, out, 'Bolster', 'bolster_complete', 0.95, nil) then
				return
			end
		end

		if config.luopan.use_life_cycle == true
			and luopan_present(ctx)
			and finite_number(ctx.pet.hpp) ~= nil
			and tonumber(ctx.pet.hpp) < tonumber(config.luopan.life_cycle_hpp) then
			optional_due = true
			if emit_ja(ctx, out, 'Life Cycle', 'life_cycle_complete', 0.90, nil) then
				return
			end
		end

		if config.luopan.use_ecliptic_attrition == true
			and luopan_present(ctx)
			and provider.state.ecliptic_luopan_id ~= tonumber(ctx.pet_id) then
			optional_due = true
			local ready, ready_reason, action_kind =
				action_ready('Ecliptic Attrition', ctx.player_id)
			if ready == true and action_kind == 'ja' then
				provider.state.sequence = {
					kind = 'geo_create',
					step = 'ecliptic',
					atomic = false,
				}
				collect_sequence(ctx, out, config, contracts)
				if #out > 0 then
					return
				end
			else
				publish_status('ja_blocked', tostring(ready_reason or action_kind))
			end
		end

		if config.entrust.enabled == true and entrust_due then
			optional_due = true
			local member = resolve_party_target(ctx, config.entrust.target_name)
			if member == nil then
				publish_status('entrust_blocked', 'configured_party_member_unavailable')
			elseif type(member.buffs) ~= 'table' then
				publish_status('entrust_blocked', 'target_buff_state_unavailable')
			else
				local member_id = tonumber(member.id) or 0
				if member_has_buff(member, INDI_COLURE_BUFF_ID) then
					publish_status('unknown_existing', 'entrust_target_indi_wait_for_clear')
				elseif has_buff(ctx.player, ENTRUST_BUFF_ID) then
					provider.state.sequence = {
						kind = 'entrust',
						step = 'entrust_spell',
						atomic = true,
						target_id = member_id,
					}
					collect_sequence(ctx, out, config, contracts)
					if #out > 0 then
						return
					end
				else
					local ready, ready_reason, action_kind =
						action_ready('Entrust', ctx.player_id)
					if ready == true and action_kind == 'ja' then
						provider.state.owned_entrust_spell = nil
						provider.state.owned_entrust_target_id = 0
						provider.state.sequence = {
							kind = 'entrust',
							step = 'entrust_ja',
							atomic = false,
							target_id = member_id,
						}
						collect_sequence(ctx, out, config, contracts)
						if #out > 0 then
							return
						end
					else
						publish_status('ja_blocked', tostring(ready_reason or action_kind))
					end
				end
			end
		end

		if not optional_due then
			publish_status('converged', '')
		end
	end

	function provider.revalidate(selected, ctx)
		require_table(selected, 'selected')
		require_table(ctx, 'ctx')
		local config = M.config_from_context(ctx)
		local contracts, validation_reason = validate_config_cached(config)
		if contracts == nil then
			return false, validation_reason
		end
		if tostring(ctx.player.main_job or '') ~= 'GEO' then
			return false, 'not_geomancer'
		end
		if player_is_moving() then
			return false, 'player_moving'
		end
		local at_camp, camp_reason = camp_ready(ctx, config)
		if not at_camp then
			return false, camp_reason
		end
		local detail = require_table(selected.detail, 'selected.detail')
		local kind = tostring(detail.geo_kind or '')
		if tostring(detail.config_contract_signature or '') ~= provider.state.config_contract_signature then
			return false, 'geo_configuration_changed'
		end
		local sequence = provider.state.sequence
		if pull_active()
			and not (type(sequence) == 'table' and sequence.atomic == true)
			and not sequence_restores_missing_luopan(sequence, ctx)
			and not (kind == 'geo' and not luopan_present(ctx)) then
			return false, 'pull_active'
		end
		if tostring(selected.action_type or '') == 'ja' then
			local action_name = tostring(selected.action_name or '')
			if action_name == 'Full Circle' then
				return type(sequence) == 'table'
					and sequence.kind == 'geo_create'
					and sequence.step == 'full_circle'
					and luopan_present(ctx),
					'stale_full_circle'
			elseif action_name == 'Blaze of Glory' then
				return type(sequence) == 'table'
					and sequence.kind == 'geo_create'
					and sequence.step == 'blaze'
					and not has_buff(ctx.player, BLAZE_OF_GLORY_BUFF_ID),
					'stale_blaze'
			elseif action_name == 'Ecliptic Attrition' then
				return type(sequence) == 'table'
					and sequence.kind == 'geo_create'
					and sequence.step == 'ecliptic'
					and luopan_present(ctx),
					'stale_ecliptic'
			elseif action_name == 'Entrust' then
				return type(sequence) == 'table'
					and sequence.kind == 'entrust'
					and sequence.step == 'entrust_ja'
					and not has_buff(ctx.player, ENTRUST_BUFF_ID),
					'stale_entrust'
			elseif action_name == 'Life Cycle' then
				return config.luopan.use_life_cycle == true
					and luopan_present(ctx)
					and finite_number(ctx.pet.hpp) ~= nil
					and tonumber(ctx.pet.hpp) < tonumber(config.luopan.life_cycle_hpp),
					'stale_life_cycle'
			elseif action_name == 'Bolster' then
				return provider.state.bolster_armed == true, 'bolster_not_armed'
			end
			return false, 'unknown_geo_ability'
		end
		if kind == 'geo' then
			if tostring(selected.action_name or '') ~= config.geo_spell then
				return false, 'geo_configuration_changed'
			end
			if luopan_present(ctx) then
				return false, 'luopan_present'
			end
			local target, target_kind, reason = resolve_geo_target(ctx, config, sequence)
			if target == nil then
				return false, reason
			end
			if tostring(target_kind) ~= tostring(selected.target_kind)
				or tonumber(target.id) ~= tonumber(selected.target_id) then
				return false, 'geo_target_changed'
			end
			local target_at_camp, target_camp_reason = enemy_geo_camp_ready(ctx, config, target)
			if not target_at_camp then
				return false, target_camp_reason
			end
			local in_range, range_reason = target_in_range(ctx, target, contracts.geo.max_range)
			return in_range, range_reason or 'stale_geo'
		end
		if kind == 'indi' then
			if tostring(selected.action_name or '') ~= config.indi_spell then
				return false, 'indi_configuration_changed'
			end
			if has_buff(ctx.player, INDI_COLURE_BUFF_ID)
				and provider.state.owned_indi_spell == config.indi_spell then
				return false, 'indi_satisfied'
			end
			return tonumber(selected.target_id) == tonumber(ctx.player_id), 'indi_target_changed'
		end
		if kind == 'entrust' then
			if type(sequence) ~= 'table'
				or sequence.kind ~= 'entrust'
				or sequence.step ~= 'entrust_spell'
				or sequence.atomic ~= true then
				return false, 'stale_entrust_sequence'
			end
			if not has_buff(ctx.player, ENTRUST_BUFF_ID) then
				return false, 'entrust_buff_missing'
			end
			if tostring(selected.action_name or '') ~= config.entrust.spell then
				return false, 'entrust_configuration_changed'
			end
			local member = resolve_party_target(ctx, config.entrust.target_name)
			if member == nil or tonumber(member.id) ~= tonumber(selected.target_id) then
				return false, 'entrust_target_changed'
			end
			local in_range, range_reason = target_in_range(ctx, member, contracts.entrust.max_range)
			return in_range, range_reason or 'stale_entrust_spell'
		end
		return false, 'unknown_geo_maintenance_kind'
	end

	function provider.note_dispatch(selected, at)
		require_table(selected, 'selected')
		local detail = require_table(selected.detail, 'selected.detail')
		local kind = tostring(detail.geo_kind or '')
		local action_type = tostring(selected.action_type or '')
		if action_type ~= 'spell' and action_type ~= 'ja' then
			error('GEO maintenance dispatch action type must be spell or ja')
		end
		if kind == '' then
			error('GEO maintenance dispatch kind must not be empty')
		end
		local sent_at = finite_number(at)
		if sent_at == nil then
			error('GEO maintenance dispatch time must be finite')
		end
		provider.state.pending = {
			kind = kind,
			effect = kind,
			spell = tostring(selected.action_name or ''),
			action_type = action_type,
			target_id = tonumber(selected.target_id),
			sent_at = sent_at,
			blaze_enhanced = detail.blaze_enhanced == true,
		}
		if tostring(selected.action_name or '') == 'Bolster' then
			provider.state.bolster_armed = false
		end
		publish_status('dispatched', kind)
	end

	function provider.note_action_complete(action_name)
		local pending = provider.state.pending
		if type(pending) ~= 'table'
			or pending.action_type ~= 'ja'
			or tostring(action_name or '') ~= pending.spell then
			return false
		end
		if pending.spell == 'Ecliptic Attrition' then
			local sequence = provider.state.sequence
			if type(sequence) == 'table'
				and sequence.kind == 'geo_create'
				and sequence.step == 'ecliptic' then
				provider.state.ecliptic_luopan_id = tonumber(sequence.luopan_id) or 0
				provider.state.sequence = nil
			end
		end
		provider.state.pending = nil
		publish_status('action_complete', pending.spell)
		return true
	end

	function provider.note_ja_action(act, player_id)
		require_table(act, 'act')
		local pending = provider.state.pending
		if type(pending) ~= 'table' or pending.action_type ~= 'ja' then
			return false, 'geo_ja_not_pending'
		end
		local expected_actor_id = tonumber(player_id)
		if expected_actor_id == nil or expected_actor_id <= 0 then
			error('GEO job ability completion requires a positive player id')
		end
		if tonumber(act.actor_id) ~= expected_actor_id then
			return false, 'geo_ja_actor_mismatch'
		end
		local category = tonumber(act.category)
		if category == nil or JOB_ABILITY_ACTION_CATEGORIES[category] ~= true then
			return false, 'geo_ja_category_mismatch'
		end
		local ability = get_ja_resource(pending.spell)
		local expected_action_id = tonumber(ability and ability.id)
		if expected_action_id == nil or expected_action_id <= 0 then
			error('pending GEO job ability resource requires a positive action id')
		end
		if tonumber(act.param) ~= expected_action_id then
			return false, 'geo_ja_action_mismatch'
		end
		local action_name = tostring(pending.spell or '')
		if not provider.note_action_complete(action_name) then
			error('matched GEO job ability packet did not complete its pending action')
		end
		return true, 'geo_ja_action_identity'
	end

	function provider.note_failure(action_name, at)
		local pending = provider.state.pending
		if type(pending) == 'table' and tostring(action_name or '') == pending.spell then
			local failed_at = finite_number(at)
			if failed_at == nil then
				error('GEO maintenance failure time must be finite')
			end
			if pending.kind == 'geo' then
				local failed_target_id = finite_number(pending.target_id)
				if failed_target_id == nil or failed_target_id <= 0 then
					error('failed Geo spell must retain a positive target id')
				end
				provider.state.failed_geo_target_id = failed_target_id
				provider.state.failed_geo_target_until = failed_at + 2.0
				provider.state.enemy_target_id = 0
				action_timeline_log('GEO_ENEMY_TARGET_INVALIDATED', {
					target_id = provider.state.failed_geo_target_id,
					retry_at = ('%.3f'):format(provider.state.failed_geo_target_until),
				}, ('geo_enemy_target_invalidated:%d'):format(
					provider.state.failed_geo_target_id
				), 0.05)
			end
			provider.state.pending = nil
			if type(provider.state.sequence) == 'table' then
				provider.state.sequence = nil
				provider.state.next_retry_at = failed_at + 2.0
			end
			publish_status('cast_failed', pending.kind)
			return true
		end
		return false
	end

	function provider.lane_reserved()
		return type(provider.state.sequence) == 'table'
			and provider.state.sequence.atomic == true
	end

	function provider.pull_for_enemy_allowed()
		local sequence = provider.state.sequence
		return type(sequence) == 'table'
			and sequence.kind == 'geo_create'
			and sequence.step == 'geo_spell'
			and sequence.atomic == true
			and sequence.target_kind == 'current_enemy'
			and sequence.awaiting_enemy_target == true
	end

	function provider.runtime_active()
		return provider.state.pending ~= nil
			or provider.state.sequence ~= nil
			or provider.state.bolster_armed == true
	end

	function provider.status_snapshot()
		return {
			state = provider.status.state,
			reason = provider.status.reason,
			detail = provider.status.detail,
			owned_geo_spell = provider.state.owned_geo_spell,
			owned_geo_blaze_enhanced = provider.state.owned_geo_blaze_enhanced == true,
			owned_indi_spell = provider.state.owned_indi_spell,
			owned_entrust_spell = provider.state.owned_entrust_spell,
			owned_entrust_target_id = provider.state.owned_entrust_target_id,
			enemy_target_id = provider.state.enemy_target_id,
			sequence = provider.state.sequence and {
				kind = provider.state.sequence.kind,
				step = provider.state.sequence.step,
				atomic = provider.state.sequence.atomic == true,
				replacement = provider.state.sequence.replacement == true,
				target_id = tonumber(provider.state.sequence.target_id) or 0,
				target_kind = tostring(provider.state.sequence.target_kind or ''),
				awaiting_enemy_target = provider.state.sequence.awaiting_enemy_target == true,
				blaze_enhanced = provider.state.sequence.blaze_enhanced == true,
			} or nil,
			next_retry_at = provider.state.next_retry_at,
			bolster_armed = provider.state.bolster_armed == true,
		}
	end

	function provider.reseed()
		reset_identity()
		publish_status('reseeded', 'identity_cleared')
		return true, 'GEO_MAINT_RESEEDED'
	end

	function provider.arm_bolster(armed)
		if type(armed) ~= 'boolean' then
			error('GEO Bolster arm state must be boolean')
		end
		provider.state.bolster_armed = armed
		publish_status(armed and 'bolster_armed' or 'bolster_disarmed', '')
		return true, armed and 'GEO_BOLSTER_ARMED' or 'GEO_BOLSTER_DISARMED'
	end

	function provider.reset(reason)
		reset_identity()
		provider.state.bolster_armed = false
		publish_status('reset', tostring(reason or 'GEO_RESET'))
	end

	return provider
end

M.INDI_COLURE_BUFF_ID = INDI_COLURE_BUFF_ID
M.ENTRUST_BUFF_ID = ENTRUST_BUFF_ID
M.BLAZE_OF_GLORY_BUFF_ID = BLAZE_OF_GLORY_BUFF_ID
M.ENEMY_LUOPAN_EFFECT_RADIUS_YALMS = ENEMY_LUOPAN_EFFECT_RADIUS_YALMS

return M
