local capabilities = require('uc_sch_capabilities')
local sch_config = require('uc_sch_config')
local sch_area_planner = require('uc_sch_area_planner')
local sch_duration = require('uc_sch_duration')
local sch_defensive = require('uc_sch_defensive')
local sch_sublimation = require('uc_sch_sublimation')

local M = {}

local STORM_STATUS_IDS = {}
for _, spell in pairs(capabilities.storm_spells) do
	STORM_STATUS_IDS[spell.status_id] = true
end

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

local function has_buff(buffs, buff_id)
	if type(buffs) ~= 'table' then
		return false
	end
	local found = false
	for i = 1, #buffs do
		if type(buffs[i]) ~= 'number' then
			error('Scholar maintenance buff ids must be numeric')
		end
		if buffs[i] == buff_id then
			found = true
		end
	end
	return found
end

local function action(action_type, action_name, target_id, target_name, reason_code, subsystem)
	if type(action_type) ~= 'string' or action_type == ''
		or type(action_name) ~= 'string' or action_name == ''
		or type(reason_code) ~= 'string' or reason_code == ''
		or type(subsystem) ~= 'string' or subsystem == '' then
		error('Scholar maintenance action identity fields must be non-empty strings')
	end
	if type(target_id) ~= 'number' or target_id <= 0 or target_id % 1 ~= 0 then
		error('Scholar maintenance action target id must be a positive integer')
	end
	if type(target_name) ~= 'string' or target_name == '' then
		error('Scholar maintenance action target name must be a non-empty string')
	end
	return {
		provider = 'maintenance_sch',
		action_type = action_type,
		action_name = action_name,
		target_id = target_id,
		target_name = target_name,
		reason_code = reason_code,
		subsystem = subsystem,
	}
end

local function evaluate_accession_maintenance_spell(
	config,
	spell_name,
	members,
	runtime_snapshot,
	now,
	player,
	area_mechanics,
	spell_ready
)
	local spell = capabilities.accession_maintenance_spell(spell_name)
	if spell == nil then
		error('Scholar Accession maintenance spell is not in the capability catalog')
	end
	local ownership_family = capabilities.accession_ownership_family(spell_name)
	local result = {
		spell = spell_name,
		state = 'evaluating',
		missing_recipient_ids = {},
		unknown_recipient_ids = {},
		unowned_existing_recipient_ids = {},
		owned_present_recipient_ids = {},
		blocker = '',
		candidate = nil,
		plan = nil,
		geometry = {
			state = 'not_evaluated',
			blocker = '',
			candidates = {},
			selected = nil,
		},
	}
	local members_by_id = {}
	for i = 1, #members do
		local member = members[i]
		if type(member) ~= 'table' then
			error('Scholar Accession maintenance party member must be a table')
		end
		local member_id = member.id
		if type(member_id) ~= 'number' or member_id <= 0 or member_id % 1 ~= 0 then
			error('Scholar Accession maintenance party member id must be a positive integer')
		end
		if members_by_id[member_id] ~= nil then
			error('Scholar Accession maintenance party member ids must be unique')
		end
		if type(member.hpp) ~= 'number' or member.hpp < 0 or member.hpp > 100 then
			error('Scholar Accession maintenance party member hpp must be numeric from 0 through 100')
		end
		members_by_id[member_id] = member
		if member.hpp > 0 then
			if type(member.buffs) ~= 'table' then
				result.unknown_recipient_ids[#result.unknown_recipient_ids + 1] = member_id
			elseif not has_buff(member.buffs, spell.status_id) then
				result.missing_recipient_ids[#result.missing_recipient_ids + 1] = member_id
			else
				local families = runtime_snapshot.owned_buffs[member_id]
				local owner = type(families) == 'table' and families[ownership_family] or nil
				if type(owner) == 'table'
					and owner.exact_spell == spell_name
					and owner.status_id == spell.status_id
					and owner.presence == 'present' then
					result.owned_present_recipient_ids[#result.owned_present_recipient_ids + 1] = member_id
				else
					result.unowned_existing_recipient_ids[#result.unowned_existing_recipient_ids + 1] = member_id
				end
			end
		end
	end
	if #result.unknown_recipient_ids > 0 then
		result.state = 'blocked'
		result.blocker = 'party_buff_state_unknown'
		return result
	end
	if #result.missing_recipient_ids == 0 then
		result.state = 'satisfied_or_unowned_present'
		return result
	end
	result.geometry = sch_area_planner.select({
		now = now,
		members = members,
		eligible_recipient_ids = result.missing_recipient_ids,
		unsafe_recipient_ids = result.unowned_existing_recipient_ids,
		minimum_coverage = config.minimum_coverage,
		mechanics = require_table(area_mechanics, 'Scholar Accession maintenance area mechanics'),
		anchor_recipient_ids = spell.anchor_policy == 'self' and { player.id } or nil,
	})
	if runtime_snapshot.stratagem.confidence ~= 'confirmed' then
		result.state = 'blocked'
		result.blocker = 'charge_confidence_unknown'
		return result
	end
	local available = runtime_snapshot.stratagem.estimated_available
	if type(available) ~= 'number' or available < 0 or available % 1 ~= 0 then
		error('Scholar runtime available charges must be a non-negative integer')
	end
	if available < 2 then
		result.state = 'blocked'
		result.blocker = 'insufficient_confirmed_charges'
		return result
	end
	if result.geometry.state ~= 'ready' then
		result.state = 'blocked'
		result.blocker = result.geometry.blocker
		return result
	end
	local selected = require_table(result.geometry.selected, 'Scholar Accession maintenance selected geometry')
	local ready, ready_reason, ready_kind = spell_ready(spell_name, selected.anchor_id, 2.0)
	if type(ready) ~= 'boolean' or type(ready_reason) ~= 'string' or ready_kind ~= 'spell' then
		error('Scholar Accession maintenance spell readiness returned invalid evidence')
	end
	if not ready then
		if ready_reason == '' then
			error('Scholar unavailable Accession maintenance spell requires a blocker')
		end
		result.state = 'blocked'
		result.blocker = ready_reason
		return result
	end
	if ready_reason ~= '' then
		error('Scholar ready Accession maintenance spell must not include a blocker')
	end
	local expected_recipients = {}
	for i = 1, #selected.expected_recipient_ids do
		local recipient_id = selected.expected_recipient_ids[i]
		local member = members_by_id[recipient_id]
		if member == nil then
			error('Scholar Accession maintenance selected recipient is not in the party snapshot')
		end
		expected_recipients[i] = {
			id = member.id,
			name = member.name,
		}
	end
	local environment = require_table(
		runtime_snapshot.environment,
		'Scholar runtime environment'
	)
	if type(environment.party_generation) ~= 'number'
		or environment.party_generation < 0
		or environment.party_generation % 1 ~= 0 then
		error('Scholar runtime party generation must be a non-negative integer')
	end
	result.plan = {
		purpose = 'party_accession_maintenance',
		domain = 'maintenance',
		required_art = 'light',
		required_addendum = nil,
		stratagems = { 'Accession', 'Perpetuance' },
		atomic = true,
		spell = spell_name,
		buff_family = ownership_family,
		duration_family = 'accession_maintenance',
		spell_mp_multiplier = 2.0,
		anchor_id = selected.anchor_id,
		anchor_name = selected.anchor_name,
		expected_recipients = expected_recipients,
		party_generation = environment.party_generation,
		minimum_coverage = config.minimum_coverage,
		charge_model_key = runtime_snapshot.stratagem.model_key,
		charge_decoder_source = runtime_snapshot.stratagem.decoder_source,
		geometry_model_key = result.geometry.mechanics_model_key,
		geometry_source = result.geometry.mechanics_source,
		refresh_before_s = config.refresh_before_s,
	}
	result.candidate = action(
		'job_ability',
		'Accession',
		player.id,
		player.name,
		'sch_accession_maintenance_prepare_accession',
		'accession_maintenance'
	)
	result.candidate.plan = result.plan
	result.state = 'actionable'
	return result
end

local function evaluate_regen(config, members, runtime_snapshot, now, player, area_mechanics, spell_ready)
	local result = {
		enabled = config.enabled,
		state = config.enabled and 'evaluating' or 'disabled',
		spells = {},
		blocker = '',
		candidate = nil,
		plan = nil,
	}
	if not config.enabled then
		return result
	end
	require_function(spell_ready, 'Scholar Accession maintenance spell_ready')
	local first_blocked_result = nil
	local first_blocked_spell = nil
	for i = 1, #config.spells do
		local spell_result = evaluate_accession_maintenance_spell(
			config,
			config.spells[i],
			members,
			runtime_snapshot,
			now,
			player,
			area_mechanics,
			spell_ready
		)
		result.spells[i] = spell_result
		if spell_result.candidate ~= nil then
			for key, value in pairs(spell_result) do
				result[key] = value
			end
			result.active_spell = config.spells[i]
			return result
		end
		if spell_result.blocker ~= '' and first_blocked_result == nil then
			first_blocked_result = spell_result
			first_blocked_spell = config.spells[i]
		end
	end
	if first_blocked_result ~= nil then
		for key, value in pairs(first_blocked_result) do
			result[key] = value
		end
		result.active_spell = first_blocked_spell
		return result
	end
	result.state = 'satisfied'
	return result
end

local function storm_party_index(members)
	local by_name = {}
	local by_id = {}
	for i = 1, #members do
		local member = members[i]
		if type(member) ~= 'table' then
			error('Scholar storm party member must be a table')
		end
		if type(member.id) ~= 'number' or member.id <= 0 or member.id % 1 ~= 0 then
			error('Scholar storm party member id must be a positive integer')
		end
		if type(member.name) ~= 'string' or member.name == '' then
			error('Scholar storm party member name must be a non-empty string')
		end
		if type(member.hpp) ~= 'number' or member.hpp < 0 or member.hpp > 100 then
			error('Scholar storm party member hpp must be numeric from 0 through 100')
		end
		local name_key = member.name:lower()
		if by_name[name_key] ~= nil then
			error('Scholar storm party member names must be unique')
		end
		if by_id[member.id] ~= nil then
			error('Scholar storm party member ids must be unique')
		end
		by_name[name_key] = member
		by_id[member.id] = member
	end
	return by_name
end

local function storm_owner(runtime_snapshot, member_id)
	local families = runtime_snapshot.owned_buffs[member_id]
	if families == nil then
		return nil
	end
	if type(families) ~= 'table' then
		error('Scholar runtime owned buff families must be a table')
	end
	local owner = families.storm
	if owner ~= nil and type(owner) ~= 'table' then
		error('Scholar runtime storm ownership must be a table')
	end
	return owner
end

local function evaluate_storms(config, members, runtime_snapshot)
	local result = {
		enabled = config.enabled,
		state = config.enabled and 'evaluating' or 'disabled',
		assignments = {},
		blocker = '',
		candidate = nil,
		plan = nil,
	}
	if not config.enabled then
		return result
	end
	local members_by_name = storm_party_index(members)
	local environment = require_table(
		runtime_snapshot.environment,
		'Scholar runtime environment'
	)
	if type(environment.party_generation) ~= 'number'
		or environment.party_generation < 0
		or environment.party_generation % 1 ~= 0 then
		error('Scholar runtime party generation must be a non-negative integer')
	end
	for assignment_index = 1, #config.assignments do
		local assignment = config.assignments[assignment_index]
		local spell = capabilities.storm_spell(assignment.spell)
		for target_index = 1, #assignment.targets do
			local target_name = assignment.targets[target_index]
			local item = {
				spell = assignment.spell,
				target_name = target_name,
				state = 'evaluating',
				blocker = '',
			}
			result.assignments[#result.assignments + 1] = item
			local member = members_by_name[target_name:lower()]
			if member == nil or member.hpp <= 0 then
				item.state = 'blocked'
				item.blocker = 'storm_target_unavailable'
			elseif type(member.buffs) ~= 'table' then
				item.state = 'blocked'
				item.blocker = 'party_buff_state_unknown'
			else
				item.target_id = member.id
				local desired_storm_present = has_buff(member.buffs, spell.status_id)
				local storm_present = false
				for buff_index = 1, #member.buffs do
					local buff_id = member.buffs[buff_index]
					if type(buff_id) ~= 'number' then
						error('Scholar maintenance buff ids must be numeric')
					end
					if STORM_STATUS_IDS[buff_id] then
						storm_present = true
						break
					end
				end
				local owner = storm_owner(runtime_snapshot, member.id)
				local owned_exact_present = desired_storm_present
					and owner ~= nil
					and owner.exact_spell == assignment.spell
					and owner.status_id == spell.status_id
					and owner.presence == 'present'
				if owned_exact_present then
					item.state = 'satisfied_owned_present'
					item.ownership = 'confirmed'
				elseif storm_present then
					item.state = 'blocked'
					item.blocker = 'unowned_storm_wait_for_clear'
					item.ownership = 'unowned'
				else
					item.state = 'actionable'
					item.ownership = owner == nil and 'none' or 'owned_absent'
					local duration_model_key = sch_duration.model_key(
						'storm',
						assignment.spell,
						{}
					)
					item.plan = {
						purpose = 'targeted_storm',
						domain = 'maintenance',
						required_art = 'light',
						required_addendum = nil,
						stratagems = {},
						spell = assignment.spell,
						status_id = spell.status_id,
						target_id = member.id,
						target_name = member.name,
						expected_recipients = {
							{ id = member.id, name = member.name },
						},
						party_generation = environment.party_generation,
						refresh_before_s = config.refresh_before_s,
						duration_confidence = 'unknown',
						duration_reason = 'phase0_duration_unvalidated',
						duration_model_key = duration_model_key,
					}
					if result.candidate == nil then
						result.candidate = action(
							'spell',
							assignment.spell,
							member.id,
							member.name,
							'sch_storm_assignment_missing',
							'storms'
						)
						result.candidate.plan = item.plan
						result.plan = item.plan
					end
				end
			end
		end
	end
	if result.candidate ~= nil then
		result.state = 'actionable'
	else
		result.state = 'satisfied_or_blocked'
	end
	for i = 1, #result.assignments do
		if result.assignments[i].blocker ~= '' then
			result.blocker = result.assignments[i].blocker
			break
		end
	end
	return result
end

local function job_ability_readiness(ctx, player, ability)
	if type(ability) ~= 'table'
		or type(ability.name) ~= 'string' or ability.name == ''
		or type(ability.recast_id) ~= 'number'
		or ability.recast_id <= 0 or ability.recast_id % 1 ~= 0 then
		error('Scholar JA readiness requires an exact ability identity')
	end
	if type(player.id) ~= 'number' or player.id <= 0 or player.id % 1 ~= 0 then
		error('Scholar JA readiness player id must be a positive integer')
	end
	local action_ready = require_function(
		ctx.action_ready,
		'Scholar JA action_ready'
	)
	if type(ctx.action_readiness_source) ~= 'string' or ctx.action_readiness_source == '' then
		error('Scholar JA action readiness source must be a non-empty string')
	end
	if type(ctx.ability_recasts_present) ~= 'boolean' then
		error('Scholar JA ability_recasts_present must be a boolean')
	end
	if not ctx.ability_recasts_present then
		return {
			recast_present = false,
			recast_id = ability.recast_id,
			observed_recast = nil,
			source = ctx.action_readiness_source,
		}, 'recast_state_unknown'
	end
	local recasts = require_table(
		ctx.ability_recasts,
		'Scholar JA ability recasts'
	)
	local recast = recasts[ability.recast_id]
	if type(recast) ~= 'number' or recast < 0 then
		error(('Scholar %s recast %d must be a non-negative number'):format(
			ability.name,
			ability.recast_id
		))
	end
	if recast > 0 then
		return {
			recast_present = true,
			recast_id = ability.recast_id,
			observed_recast = recast,
			source = ctx.action_readiness_source,
		}, 'recast_unavailable'
	end
	local ready, reason, kind = action_ready(ability.name, player.id)
	if type(ready) ~= 'boolean' then
		error('Scholar JA action_ready must return a boolean')
	end
	if type(reason) ~= 'string' then
		error('Scholar JA action_ready reason must be a string')
	end
	if kind ~= 'ja' then
		error('Scholar JA action_ready must classify the ability as a JA')
	end
	if not ready then
		if reason == '' then
			error('Scholar unavailable JA requires a reason')
		end
		return {
			recast_present = true,
			recast_id = ability.recast_id,
			observed_recast = recast,
			source = ctx.action_readiness_source,
		}, 'action_unavailable:' .. reason
	end
	if reason ~= '' then
		error('Scholar ready JA must not include a blocker')
	end
	return {
		recast_present = true,
		recast_id = ability.recast_id,
		observed_recast = recast,
		source = ctx.action_readiness_source,
	}, ''
end

local function evaluate_arts(ctx, runtime_snapshot)
	local observed = runtime_snapshot.arts.observed
	local valid_states = {
		unknown = true,
		none = true,
		light = true,
		dark = true,
		addendum_white = true,
		addendum_black = true,
	}
	if valid_states[observed] ~= true then
		error('Scholar observed Arts state is invalid')
	end
	local result = {
		state = observed,
		blocker = '',
		candidate = nil,
		plan = nil,
		readiness = nil,
	}
	if observed == 'light' or observed == 'addendum_white' then
		result.state = 'satisfied'
		return result
	end
	if observed == 'unknown' then
		result.state = 'blocked'
		result.blocker = 'arts_state_unknown'
		return result
	end
	local player = require_table(ctx.player, 'Scholar maintenance player')
	local readiness, readiness_blocker = job_ability_readiness(
		ctx,
		player,
		capabilities.abilities.light_arts
	)
	result.readiness = readiness
	if readiness_blocker ~= '' then
		result.state = 'blocked'
		result.blocker = 'arts_' .. readiness_blocker
		return result
	end
	local environment = require_table(
		runtime_snapshot.environment,
		'Scholar runtime environment'
	)
	if type(environment.party_generation) ~= 'number'
		or environment.party_generation < 0
		or environment.party_generation % 1 ~= 0 then
		error('Scholar runtime party generation must be a non-negative integer')
	end
	result.plan = {
		purpose = 'ensure_light_arts',
		domain = 'maintenance',
		action_type = 'job_ability',
		action_name = 'Light Arts',
		target_id = player.id,
		target_name = player.name,
		observed_art = observed,
		desired_art = 'light',
		expected_buff_id = capabilities.abilities.light_arts.buff_id,
		party_generation = environment.party_generation,
		recast_id = readiness.recast_id,
		observed_recast = readiness.observed_recast,
		readiness_source = readiness.source,
	}
	result.candidate = action(
		'job_ability',
		'Light Arts',
		player.id,
		player.name,
		'sch_light_arts_missing',
		'arts'
	)
	result.candidate.plan = result.plan
	result.state = 'actionable'
	return result
end

local function evaluate_sublimation(config, ctx, runtime_snapshot)
	local result = {
		enabled = config.enabled,
		state = config.enabled and runtime_snapshot.sublimation.observed or 'disabled',
		blocker = '',
		candidate = nil,
		plan = nil,
		safety = nil,
		release_capacity = nil,
	}
	if not config.enabled then
		return result
	end
	local observed = runtime_snapshot.sublimation.observed
	if observed ~= 'unknown' and observed ~= 'none'
		and observed ~= 'activated' and observed ~= 'complete' then
		error('Scholar Sublimation observed state is invalid')
	end
	if observed == 'unknown' then
		result.blocker = 'sublimation_state_unknown'
		return result
	end
	local player = require_table(ctx.player, 'Scholar maintenance player')
	local vitals = require_table(player.vitals, 'Scholar maintenance player vitals')
	local hpp = vitals.hpp
	if type(hpp) ~= 'number' or hpp < 0 or hpp > 100 then
		error('Scholar maintenance player HPP must be numeric from 0 through 100')
	end
	local activation_requested = observed == 'none'
		and hpp >= config.minimum_hpp_to_activate
	local release_requested = false
	if observed == 'complete' and config.release_when_complete then
		release_requested = true
	elseif observed == 'activated' or observed == 'complete' then
		local mpp = vitals.mpp
		if type(mpp) ~= 'number' or mpp < 0 or mpp > 100 then
			error('Scholar maintenance player MPP must be numeric from 0 through 100 for Sublimation release')
		end
		release_requested = (observed == 'complete' and mpp <= config.release_when_mpp_at_most)
			or (observed == 'activated' and mpp <= config.release_when_mpp_at_most)
	end
	if not activation_requested and not release_requested then
		result.state = 'no_transition_required'
		return result
	end
	result.safety = sch_sublimation.validate_safety(ctx.sublimation_safety)
	if result.safety.confidence ~= 'confirmed' then
		result.state = 'blocked'
		result.blocker = result.safety.reason
		return result
	end
	if result.safety.critical_defensive_present then
		result.state = 'blocked'
		result.blocker = 'sublimation_critical_defensive_pending'
		return result
	end
	if result.safety.dangerous_local_pressure_present then
		result.state = 'blocked'
		result.blocker = 'sublimation_dangerous_local_pressure'
		return result
	end
	if release_requested then
		local mp = vitals.mp
		local max_mp = vitals.max_mp
		if type(mp) ~= 'number' or type(max_mp) ~= 'number'
			or max_mp <= 0 or mp < 0 or mp > max_mp then
			error('Scholar maintenance player MP values are inconsistent for Sublimation release')
		end
		result.release_capacity = sch_sublimation.evaluate_release_capacity({
			mp = mp,
			max_mp = max_mp,
		}, ctx.sublimation_release_mechanics)
		if result.release_capacity.state ~= 'ready' then
			result.state = 'blocked'
			result.blocker = result.release_capacity.blocker
			return result
		end
	end
	local readiness, readiness_blocker = job_ability_readiness(
		ctx,
		player,
		capabilities.abilities.sublimation
	)
	result.readiness = readiness
	if readiness_blocker ~= '' then
		result.state = 'blocked'
		result.blocker = 'sublimation_' .. readiness_blocker
		return result
	end
	local purpose = activation_requested and 'sublimation_activate' or 'sublimation_release'
	local environment = require_table(
		runtime_snapshot.environment,
		'Scholar runtime environment'
	)
	if type(environment.party_generation) ~= 'number'
		or environment.party_generation < 0
		or environment.party_generation % 1 ~= 0 then
		error('Scholar runtime party generation must be a non-negative integer')
	end
	result.plan = {
		purpose = purpose,
		domain = 'maintenance',
		action_type = 'job_ability',
		action_name = 'Sublimation',
		target_id = player.id,
		target_name = player.name,
		observed_state = observed,
		party_generation = environment.party_generation,
		safety_model_key = result.safety.model_key,
		safety_source = result.safety.source,
		recast_id = readiness.recast_id,
		observed_recast = readiness.observed_recast,
		readiness_source = readiness.source,
	}
	if result.release_capacity ~= nil then
		result.plan.missing_mp = vitals.max_mp - vitals.mp
		result.plan.release_capacity_model_key = result.release_capacity.model_key
		result.plan.release_capacity_source = result.release_capacity.source
		result.plan.minimum_missing_mp = result.release_capacity.minimum_missing_mp
	end
	result.candidate = action(
		'job_ability',
		'Sublimation',
		player.id,
		player.name,
		activation_requested and 'sch_sublimation_activate' or 'sch_sublimation_release',
		'sublimation'
	)
	result.candidate.plan = result.plan
	result.state = 'actionable'
	return result
end

function M.evaluate(config, ctx, runtime_snapshot)
	require_table(config, 'Scholar maintenance config')
	require_table(ctx, 'Scholar maintenance context')
	require_table(runtime_snapshot, 'Scholar runtime snapshot')
	local now = ctx.now
	if type(now) ~= 'number' then
		error('Scholar maintenance context now must be numeric')
	end
	if type(runtime_snapshot.owned_buffs) ~= 'table' then
		error('Scholar runtime owned_buffs must be a table')
	end
	local validation = sch_config.validate(config, {
		main_job = ctx.player and ctx.player.main_job or '',
	})
	if validation.valid ~= true then
		local first = validation.errors[1]
		error(first and first.message or 'Scholar maintenance config is invalid')
	end
	local result = {
		enabled = config.enabled,
		mode = 'live',
		eligibility = runtime_snapshot.eligibility,
		first_blocker = '',
		candidate = nil,
		arts = { state = runtime_snapshot.arts.observed, blocker = '' },
		sublimation = { enabled = false, state = 'disabled', blocker = '' },
		regen = { enabled = false, state = 'disabled', blocker = '' },
		storms = { enabled = false, state = 'disabled', blocker = '' },
		defensive = { enabled = false, state = 'disabled', blocker = '' },
	}
	if config.enabled ~= true then
		result.first_blocker = 'sch_disabled'
		return result
	end
	if runtime_snapshot.eligibility ~= 'eligible' then
		result.first_blocker = 'sch_not_eligible'
		return result
	end
	local members = require_table(ctx.party_members, 'Scholar maintenance party members')
	local player = require_table(ctx.player, 'Scholar maintenance player')
	local player_id = player.id
	if type(player_id) ~= 'number' or player_id <= 0 or player_id % 1 ~= 0 then
		error('Scholar maintenance player id must be a positive integer')
	end
	local player_present_in_party_snapshot = false
	for member_index = 1, #members do
		local member = require_table(members[member_index], 'Scholar maintenance party member')
		if type(member.id) ~= 'number' or member.id <= 0 or member.id % 1 ~= 0 then
			error('Scholar maintenance party member id must be a positive integer')
		end
		if member.id == player_id then
			player_present_in_party_snapshot = true
		end
	end
	if not player_present_in_party_snapshot then
		result.first_blocker = 'party_snapshot_inconsistent'
		return result
	end
	if runtime_snapshot.active_sequence ~= nil then
		result.first_blocker = 'active_sequence_in_progress'
		return result
	end
	result.defensive = sch_defensive.evaluate(config.defensive, ctx, runtime_snapshot)
	result.arts = evaluate_arts(ctx, runtime_snapshot)
	result.candidate = result.defensive.candidate or result.arts.candidate
	result.regen = evaluate_regen(
		config.support.regen,
		members,
		runtime_snapshot,
		now,
		ctx.player,
		ctx.area_mechanics,
		ctx.spell_ready
	)
	result.storms = evaluate_storms(config.support.storms, members, runtime_snapshot)
	result.sublimation = evaluate_sublimation(config.sublimation, ctx, runtime_snapshot)
	local arts_confirmed = result.arts.state == 'satisfied'
	if arts_confirmed and result.candidate == nil and result.regen.candidate ~= nil then
		result.candidate = result.regen.candidate
	end
	if arts_confirmed and result.candidate == nil and result.storms.candidate ~= nil then
		result.candidate = result.storms.candidate
	end
	if arts_confirmed and result.candidate == nil and result.sublimation.candidate ~= nil then
		result.candidate = result.sublimation.candidate
	end
	local blockers = {
		result.defensive.blocker,
		result.arts.blocker,
		result.regen.blocker,
		result.storms.blocker,
		result.sublimation.blocker,
	}
	for i = 1, #blockers do
		if tostring(blockers[i] or '') ~= '' then
			result.first_blocker = blockers[i]
			break
		end
	end
	return result
end

return M
