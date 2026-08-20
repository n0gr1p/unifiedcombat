local capabilities = require('uc_sch_capabilities')
local sch_config = require('uc_sch_config')
local sch_duration = require('uc_sch_duration')

local M = {}

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar runtime state must not contain cycles')
	end
	visited[value] = true
	local out = {}
	for key, inner in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner, visited)
	end
	visited[value] = nil
	return out
end

local function now_number(value, name)
	local number_value = tonumber(value)
	if number_value == nil then
		error((name or 'time') .. ' must be numeric')
	end
	return number_value
end

local function has_buff(buffs, buff_id)
	if type(buffs) ~= 'table' then
		return false
	end
	for i = 1, #buffs do
		if tonumber(buffs[i]) == tonumber(buff_id) then
			return true
		end
	end
	return false
end

local function action_key(name)
	local value = tostring(name or ''):lower():gsub('[^%w]+', '_')
	return (value:gsub('^_+', ''):gsub('_+$', ''))
end

local function new_state()
	return {
		enabled = false,
		eligibility = 'disabled',
		mode = 'support',
		profile_generation = 0,
		sequence_generation = 0,
		environment = {
			observed = false,
			observed_at = 0,
			engine_enabled = false,
			maintenance_enabled = false,
			defensive_enabled = false,
			main_job = '',
			player_hpp = 0,
			party_generation = 0,
			party_members = {},
		},
		active_sequence = nil,
		pending = nil,
		lane = {
			reserved = false,
			atomic = false,
			class = 'none',
			reason = '',
		},
		arts = {
			observed = 'unknown',
			desired = 'light',
			commit_until = 0,
			observed_at = 0,
		},
		stratagem = {
			estimated_available = 0,
			maximum = 0,
			recast_present = false,
			observed_recast = nil,
			observed_at = 0,
			confidence = 'unknown',
			model_key = '',
			decoder_source = '',
			reason = 'not_observed',
			last_used_at = 0,
			tabula_rasa_active = false,
		},
		owned_buffs = {},
		sublimation = {
			observed = 'unknown',
			observed_at = 0,
			activated_at = 0,
		},
		next_retry_at = 0,
		last_transition = 'init',
		last_blocker = '',
		last_reset_reason = 'init',
		last_sequence = nil,
		unexpected_recipients = {},
	}
end

local state = new_state()
local active_config = sch_config.default_config()

local function copy_state_fields(target, source)
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(source) do
		target[key] = value
	end
end

local function set_lane(class, reason)
	local lane_class = tostring(class or 'none')
	local atomic = state.active_sequence ~= nil and state.active_sequence.atomic == true
	state.lane.class = lane_class
	state.lane.atomic = atomic
	state.lane.reserved = lane_class ~= 'none' and (lane_class ~= 'planning' or atomic)
	state.lane.reason = tostring(reason or '')
end

local function update_lane()
	local sequence = state.active_sequence
	if sequence == nil then
		set_lane('none', '')
		return
	end
	if state.pending ~= nil then
		set_lane('dispatched', tostring(state.pending.phase or 'sch_action_pending'))
		return
	end
	if next(sequence.prepared_stratagems or {}) ~= nil then
		set_lane('prepared_support', tostring(sequence.phase or 'prepared_stratagem'))
		return
	end
	set_lane('planning', tostring(sequence.phase or 'planning'))
end

local function finish_sequence(result, reason, at)
	local sequence = state.active_sequence
	state.last_sequence = {
		id = sequence and sequence.id or '',
		generation = sequence and sequence.generation or 0,
		purpose = sequence and sequence.purpose or '',
		result = tostring(result or 'failed'),
		reason = tostring(reason or ''),
		finished_at = now_number(at, 'sequence finish time'),
	}
	state.last_transition = ('sequence_%s:%s'):format(
		tostring(result or 'failed'),
		tostring(reason or '')
	)
	state.last_blocker = result == 'complete' and '' or tostring(reason or '')
	state.active_sequence = nil
	state.pending = nil
	set_lane('none', '')
end

local function abort_sequence(reason, at, retry_delay)
	local delay = tonumber(retry_delay) or 0
	local now = now_number(at, 'sequence abort time')
	state.next_retry_at = math.max(tonumber(state.next_retry_at) or 0, now + delay)
	finish_sequence('aborted', reason, now)
	return false, tostring(reason or 'sequence_aborted')
end

local function complete_sequence(at)
	finish_sequence('complete', 'postconditions_confirmed', at)
	return true, 'complete'
end

local function art_is_compatible(required_art)
	if required_art == nil then
		return true
	end
	if required_art == 'light' then
		return state.arts.observed == 'light' or state.arts.observed == 'addendum_white'
	end
	if required_art == 'dark' then
		return state.arts.observed == 'dark' or state.arts.observed == 'addendum_black'
	end
	error('Unsupported Scholar required_art: ' .. tostring(required_art))
end

local function addendum_is_confirmed(required_addendum)
	if required_addendum == nil then
		return true
	end
	if required_addendum == 'white' then
		return state.arts.observed == 'addendum_white'
	end
	if required_addendum == 'black' then
		return state.arts.observed == 'addendum_black'
	end
	error('Unsupported Scholar required_addendum: ' .. tostring(required_addendum))
end

local function phase_for(prefix, action_name)
	return tostring(prefix) .. '_' .. action_key(action_name)
end

local function set_sequence_phase(phase, reason)
	local sequence = state.active_sequence
	if sequence == nil then
		error('Scholar sequence phase transition requires an active sequence')
	end
	sequence.phase = tostring(phase)
	state.last_transition = ('%s:%s'):format(sequence.phase, tostring(reason or ''))
	update_lane()
end

local function next_stratagem_phase(reason)
	local sequence = state.active_sequence
	local index = tonumber(sequence.next_stratagem_index) or 1
	local action_name = sequence.stratagems[index]
	if action_name == nil then
		set_sequence_phase('cast_spell', reason or 'stratagems_confirmed')
		return
	end
	set_sequence_phase(phase_for('use', action_name), reason or 'next_stratagem')
end

local function normalize_recipient(value)
	if type(value) == 'number' then
		if value <= 0 or value % 1 ~= 0 then
			return nil
		end
		return { id = value, name = '' }
	end
	if type(value) ~= 'table' then
		return nil
	end
	local id = value.id
	if type(id) ~= 'number' or id <= 0 or id % 1 ~= 0 then
		return nil
	end
	local name = value.name
	if name ~= nil and type(name) ~= 'string' then
		return nil
	end
	return { id = id, name = name or '' }
end

local function validate_plan(plan, at)
	if type(plan) ~= 'table' then
		return nil, 'sequence_plan_must_be_table'
	end
	local required_strings = { 'id', 'purpose', 'domain' }
	for i = 1, #required_strings do
		local key = required_strings[i]
		if type(plan[key]) ~= 'string' or plan[key] == '' then
			return nil, 'sequence_' .. key .. '_required'
		end
	end
	if plan.domain ~= 'maintenance' and plan.domain ~= 'defensive' then
		return nil, 'sequence_domain_unsupported'
	end
	local party_generation = tonumber(plan.party_generation)
	if party_generation == nil or party_generation < 0 or party_generation % 1 ~= 0 then
		return nil, 'sequence_party_generation_required'
	end
	local deadline = tonumber(plan.deadline)
	if deadline == nil or deadline <= at then
		return nil, 'sequence_deadline_invalid'
	end
	local copy = clone_value(plan)
	copy.party_generation = party_generation
	copy.deadline = deadline
	if plan.purpose == 'ensure_light_arts'
		or plan.purpose == 'sublimation_activate'
		or plan.purpose == 'sublimation_release' then
		if plan.action_type ~= 'job_ability' then
			return nil, 'sequence_direct_action_type_unsupported'
		end
		local expected_name = plan.purpose == 'ensure_light_arts' and 'Light Arts' or 'Sublimation'
		if plan.action_name ~= expected_name then
			return nil, 'sequence_direct_action_name_mismatch'
		end
		local target_id = tonumber(plan.target_id)
		if target_id == nil or target_id <= 0 or target_id % 1 ~= 0 then
			return nil, 'sequence_target_id_required'
		end
		if type(plan.target_name) ~= 'string' or plan.target_name == '' then
			return nil, 'sequence_target_name_required'
		end
		copy.anchor_id = target_id
		copy.anchor_name = plan.target_name
		copy.target_id = target_id
		copy.direct_action_type = 'job_ability'
		copy.direct_action_name = expected_name
		copy.required_art = nil
		copy.required_addendum = nil
		copy.stratagems = {}
		copy.expected_recipients = {
			{ id = target_id, name = plan.target_name },
		}
		copy.expected_recipient_set = { [target_id] = true }
		if plan.purpose == 'ensure_light_arts' then
			copy.expected_buff_id = capabilities.abilities.light_arts.buff_id
		elseif plan.purpose == 'sublimation_activate' then
			copy.expected_buff_id = capabilities.abilities.sublimation.activated_buff_id
		else
			copy.expected_buff_id = 0
		end
		return copy, ''
	end
	local defensive_purposes = {
		accession_cure = true,
		accession_status_removal = true,
		rapture_cure = true,
		penury_cure = true,
	}
	if plan.purpose ~= 'party_accession_maintenance' and plan.purpose ~= 'targeted_storm'
		and defensive_purposes[plan.purpose] ~= true then
		return nil, 'sequence_purpose_unsupported'
	end
	if defensive_purposes[plan.purpose] == true and plan.domain ~= 'defensive' then
		return nil, 'sequence_domain_mismatch'
	end
	if type(plan.spell) ~= 'string' or plan.spell == '' then
		return nil, 'sequence_spell_required'
	end
	if plan.required_art ~= 'light' then
		return nil, 'sequence_required_art_unsupported'
	end
	if plan.required_addendum ~= nil and plan.required_addendum ~= 'white' then
		return nil, 'sequence_required_addendum_unsupported'
	end
	local anchor_id = tonumber(plan.anchor_id or plan.target_id)
	local anchor_name = plan.anchor_name or plan.target_name
	if anchor_id == nil or anchor_id <= 0 or anchor_id % 1 ~= 0 then
		return nil, 'sequence_anchor_id_required'
	end
	if type(anchor_name) ~= 'string' or anchor_name == '' then
		return nil, 'sequence_anchor_name_required'
	end
	local spell
	if plan.purpose == 'party_accession_maintenance' then
		if plan.atomic ~= true then
			return nil, 'sequence_atomic_policy_required'
		end
		spell = capabilities.accession_maintenance_spell(plan.spell)
		if spell == nil then
			return nil, 'sequence_spell_unsupported'
		end
		if type(plan.stratagems) ~= 'table'
			or #plan.stratagems ~= 2
			or plan.stratagems[1] ~= 'Accession'
			or plan.stratagems[2] ~= 'Perpetuance' then
			return nil, 'sequence_stratagem_policy_unsupported'
		end
	elseif plan.purpose == 'targeted_storm' then
		spell = capabilities.storm_spell(plan.spell)
		if spell == nil then
			return nil, 'sequence_spell_unsupported'
		end
		if type(plan.stratagems) ~= 'table' or #plan.stratagems ~= 0 then
			return nil, 'sequence_stratagem_policy_unsupported'
		end
	else
		local cure_spells = {
			['Cure'] = true, ['Cure II'] = true,
			['Cure III'] = true, ['Cure IV'] = true,
		}
		local status_spells = {
			Erase = true, Blindna = true, Paralyna = true, Poisona = true,
			Silena = true, Stona = true, Cursna = true, Viruna = true,
		}
		local expected_stratagem = plan.purpose == 'rapture_cure' and 'Rapture'
			or (plan.purpose == 'penury_cure' and 'Penury' or 'Accession')
		if type(plan.stratagems) ~= 'table' or #plan.stratagems ~= 1
			or plan.stratagems[1] ~= expected_stratagem then
			return nil, 'sequence_stratagem_policy_unsupported'
		end
		if plan.purpose == 'accession_status_removal' then
			if status_spells[plan.spell] ~= true then
				return nil, 'sequence_spell_unsupported'
			end
			copy.effect_kind = 'status_removal'
			copy.status_buff_id = tonumber(plan.status_buff_id)
			copy.minimum_members = tonumber(plan.minimum_members)
			if copy.status_buff_id == nil or copy.status_buff_id <= 0
				or copy.minimum_members == nil or copy.minimum_members < 2 then
				return nil, 'sequence_status_policy_invalid'
			end
		elseif cure_spells[plan.spell] ~= true then
			return nil, 'sequence_spell_unsupported'
		else
			copy.effect_kind = 'cure'
		end
		spell = { status_id = 0 }
	end
	if type(plan.expected_recipients) ~= 'table' or #plan.expected_recipients == 0 then
		return nil, 'sequence_expected_recipients_required'
	end
	local recipients = {}
	local recipient_set = {}
	for i = 1, #plan.expected_recipients do
		local recipient = normalize_recipient(plan.expected_recipients[i])
		if recipient == nil then
			return nil, 'sequence_expected_recipient_invalid'
		end
		if recipient_set[recipient.id] then
			return nil, 'sequence_expected_recipient_duplicate'
		end
		recipient_set[recipient.id] = true
		recipients[#recipients + 1] = recipient
	end
	copy.anchor_id = anchor_id
	copy.anchor_name = anchor_name
	copy.expected_recipients = recipients
	copy.expected_recipient_set = recipient_set
	if plan.purpose == 'party_accession_maintenance' then
		local expected_family = capabilities.accession_ownership_family(plan.spell)
		if plan.buff_family ~= expected_family
			or plan.duration_family ~= 'accession_maintenance' then
			return nil, 'sequence_buff_family_invalid'
		end
		copy.buff_family = expected_family
		copy.duration_family = 'accession_maintenance'
	elseif plan.purpose == 'targeted_storm' then
		copy.buff_family = 'storm'
		copy.duration_family = 'storm'
	end
	copy.status_id = spell.status_id
	if plan.purpose == 'accession_cure' then
		copy.minimum_members = tonumber(plan.minimum_members)
		copy.member_hpp_at_most = tonumber(plan.member_hpp_at_most)
		copy.minimum_total_missing_hp = tonumber(plan.minimum_total_missing_hp)
		if copy.minimum_members == nil or copy.minimum_members < 2
			or copy.member_hpp_at_most == nil or copy.member_hpp_at_most <= 0
			or copy.minimum_total_missing_hp == nil or copy.minimum_total_missing_hp <= 0 then
			return nil, 'sequence_cure_policy_invalid'
		end
	elseif plan.purpose == 'rapture_cure' or plan.purpose == 'penury_cure' then
		copy.minimum_missing_hp = tonumber(plan.minimum_missing_hp)
		if copy.minimum_missing_hp == nil or copy.minimum_missing_hp <= 0 then
			return nil, 'sequence_cure_policy_invalid'
		end
	end
	local expected_mp_multiplier = plan.purpose == 'party_accession_maintenance' and 2.0
		or (plan.purpose == 'accession_cure' and 2.0)
		or (plan.purpose == 'accession_status_removal' and 2.0)
		or (plan.purpose == 'penury_cure' and 0.5) or 1.0
	if plan.spell_mp_multiplier ~= nil
		and tonumber(plan.spell_mp_multiplier) ~= expected_mp_multiplier then
		return nil, 'sequence_spell_mp_multiplier_invalid'
	end
	copy.spell_mp_multiplier = expected_mp_multiplier
	return copy, ''
end

local function required_charge_count(plan)
	local count = #plan.stratagems
	if plan.required_addendum ~= nil and not addendum_is_confirmed(plan.required_addendum) then
		count = count + 1
	end
	return count
end

local function active_environment_blocker(sequence)
	local environment = state.environment
	if environment.observed ~= true then
		return 'runtime_environment_unobserved'
	end
	if environment.engine_enabled ~= true then
		return 'engine_stopped'
	end
	if sequence == nil or sequence.domain == 'maintenance' then
		if environment.maintenance_enabled ~= true then
			return 'maintenance_domain_disabled'
		end
	elseif sequence.domain == 'defensive' and environment.defensive_enabled ~= true then
		return 'defensive_domain_disabled'
	end
	if environment.main_job ~= capabilities.JOB_SHORT_NAME then
		return 'job_changed'
	end
	if environment.player_hpp <= 0 then
		return 'player_incapacitated'
	end
	if sequence ~= nil then
		if environment.party_generation ~= sequence.party_generation then
			return 'party_generation_changed'
		end
		local anchor = nil
		for i = 1, #environment.party_members do
			local member = environment.party_members[i]
			if member.id == sequence.anchor_id then
				anchor = member
				break
			end
		end
		if anchor == nil or anchor.name ~= sequence.anchor_name or anchor.hpp <= 0 then
			return 'target_unavailable'
		end
		local pending_spell = state.pending ~= nil and state.pending.action_type == 'spell'
		if sequence.domain == 'defensive' and not pending_spell then
			local by_id = {}
			for i = 1, #environment.party_members do
				by_id[environment.party_members[i].id] = environment.party_members[i]
			end
			local qualifying = 0
			local total_missing = 0
			for i = 1, #sequence.expected_recipients do
				local member = by_id[sequence.expected_recipients[i].id]
				if member == nil or member.hpp <= 0 or member.charmed == true then
					return 'defensive_recipient_unavailable'
				end
				if sequence.effect_kind == 'status_removal' then
					if type(member.buffs) ~= 'table' then return 'party_buff_state_unknown' end
					if has_buff(member.buffs, sequence.status_buff_id) then
						qualifying = qualifying + 1
					end
				else
					if type(member.max_hp) ~= 'number' or type(member.hp) ~= 'number'
						or member.max_hp <= 0 or member.hp < 0 or member.hp > member.max_hp then
						return 'party_hp_state_unknown'
					end
					local missing = math.max(0, member.max_hp - member.hp)
					total_missing = total_missing + missing
					if sequence.purpose ~= 'accession_cure'
						or member.hpp <= sequence.member_hpp_at_most then
						qualifying = qualifying + (missing > 0 and 1 or 0)
					end
				end
			end
			if sequence.purpose == 'accession_status_removal'
				and qualifying < sequence.minimum_members then
				return 'defensive_group_condition_cleared'
			elseif sequence.purpose == 'accession_cure' then
				if qualifying < sequence.minimum_members
					or total_missing < sequence.minimum_total_missing_hp then
					return 'defensive_group_condition_cleared'
				end
			elseif total_missing < sequence.minimum_missing_hp then
				return 'defensive_cure_condition_cleared'
			end
		end
	end
	return ''
end

local function revalidate_active_environment(at)
	if state.active_sequence == nil then
		return true, ''
	end
	local reason = active_environment_blocker(state.active_sequence)
	if reason == '' then
		return true, ''
	end
	return abort_sequence(reason, at, 0)
end

function M.check_invariants()
	local sequence = state.active_sequence
	local pending = state.pending
	if pending ~= nil and sequence == nil then
		return false, 'pending_without_active_sequence'
	end
	if sequence == nil then
		if state.lane.class ~= 'none' or state.lane.reserved ~= false
			or state.lane.atomic ~= false then
			return false, 'idle_lane_not_released'
		end
		return true, ''
	end
	if type(sequence.id) ~= 'string' or sequence.id == ''
		or type(sequence.generation) ~= 'number' or sequence.generation <= 0 then
		return false, 'active_sequence_identity_invalid'
	end
	if type(sequence.prepared_stratagems) ~= 'table' then
		return false, 'prepared_stratagem_state_invalid'
	end
	if pending ~= nil then
		if pending.sequence_id ~= sequence.id
			or pending.sequence_generation ~= sequence.generation then
			return false, 'pending_sequence_identity_mismatch'
		end
		if state.lane.class ~= 'dispatched' or state.lane.reserved ~= true then
			return false, 'pending_lane_invalid'
		end
	elseif next(sequence.prepared_stratagems) ~= nil then
		if state.lane.class ~= 'prepared_support' or state.lane.reserved ~= true then
			return false, 'prepared_lane_invalid'
		end
	elseif state.lane.class ~= 'planning'
		or state.lane.reserved ~= (sequence.atomic == true) then
		return false, 'planning_lane_invalid'
	end
	return true, ''
end

function M.enforce_invariants(at)
	local valid, reason = M.check_invariants()
	if valid then
		return true, ''
	end
	local now = now_number(at, 'Scholar invariant check time')
	if state.active_sequence ~= nil then
		abort_sequence('invariant_violation:' .. reason, now, 0)
	else
		state.pending = nil
		set_lane('none', '')
		state.last_blocker = 'invariant_violation:' .. reason
		state.last_transition = state.last_blocker
	end
	return false, reason
end

function M.configure(config, meta, profile_generation, at)
	local validation = sch_config.validate(config, meta)
	if validation.valid ~= true then
		local first = validation.errors[1]
		error(first and first.message or 'Scholar configuration is invalid')
	end
	local now = now_number(at, 'Scholar configure time')
	local generation = tonumber(profile_generation)
	if generation == nil or generation < 0 or generation % 1 ~= 0 then
		error('Scholar profile generation must be a non-negative integer')
	end
	local main_job = tostring(type(meta) == 'table' and (meta.main_job or meta.job) or ''):upper()
	local eligibility = 'disabled'
	if config.enabled == true then
		eligibility = main_job == capabilities.JOB_SHORT_NAME and 'eligible' or 'ineligible'
	end
	local changed = state.profile_generation ~= generation
		or state.enabled ~= (config.enabled == true)
		or state.mode ~= config.mode
		or state.eligibility ~= eligibility
	if changed and state.active_sequence ~= nil then
		abort_sequence('configuration_changed', now, 0)
	end
	active_config = clone_value(config)
	state.enabled = config.enabled == true
	state.eligibility = eligibility
	state.mode = config.mode
	state.profile_generation = generation
	state.arts.desired = config.arts.default
	state.last_transition = changed and 'configured' or state.last_transition
	if state.eligibility ~= 'eligible' then
		state.pending = nil
		state.active_sequence = nil
		set_lane('none', '')
	end
	return M.snapshot()
end

function M.reset(reason, at)
	local now = now_number(at, 'Scholar reset time')
	local enabled = state.enabled
	local eligibility = state.eligibility
	local mode = state.mode
	local profile_generation = state.profile_generation
	local desired_art = state.arts.desired
	local replacement = new_state()
	replacement.enabled = enabled
	replacement.eligibility = eligibility
	replacement.mode = mode
	replacement.profile_generation = profile_generation
	replacement.arts.desired = desired_art
	replacement.last_reset_reason = tostring(reason or 'reset')
	replacement.last_transition = 'reset:' .. replacement.last_reset_reason
	replacement.stratagem.observed_at = now
	copy_state_fields(state, replacement)
	return true
end

function M.observe_environment(observation, at)
	if type(observation) ~= 'table' then
		error('Scholar runtime environment observation must be a table')
	end
	if type(observation.engine_enabled) ~= 'boolean' then
		error('Scholar runtime engine_enabled must be a boolean')
	end
	if type(observation.maintenance_enabled) ~= 'boolean' then
		error('Scholar runtime maintenance_enabled must be a boolean')
	end
	if type(observation.defensive_enabled) ~= 'boolean' then
		error('Scholar runtime defensive_enabled must be a boolean')
	end
	if type(observation.main_job) ~= 'string' then
		error('Scholar runtime main_job must be a string')
	end
	if type(observation.player_hpp) ~= 'number'
		or observation.player_hpp < 0
		or observation.player_hpp > 100 then
		error('Scholar runtime player_hpp must be a number from 0 through 100')
	end
	if type(observation.party_generation) ~= 'number'
		or observation.party_generation <= 0
		or observation.party_generation % 1 ~= 0 then
		error('Scholar runtime party_generation must be a positive integer')
	end
	if type(observation.party_members) ~= 'table' then
		error('Scholar runtime party_members must be a table')
	end
	local members = {}
	local seen_ids = {}
	for i = 1, #observation.party_members do
		local member = observation.party_members[i]
		if type(member) ~= 'table' then
			error('Scholar runtime party member must be a table')
		end
		if type(member.id) ~= 'number' or member.id <= 0 or member.id % 1 ~= 0 then
			error('Scholar runtime party member id must be a positive integer')
		end
		if seen_ids[member.id] then
			error('Scholar runtime party member ids must be unique')
		end
		seen_ids[member.id] = true
		if type(member.name) ~= 'string' or member.name == '' then
			error('Scholar runtime party member name must be a non-empty string')
		end
		if type(member.hpp) ~= 'number' or member.hpp < 0 or member.hpp > 100 then
			error('Scholar runtime party member hpp must be a number from 0 through 100')
		end
		if member.hp ~= nil and (type(member.hp) ~= 'number' or member.hp < 0) then
			error('Scholar runtime party member hp must be non-negative when present')
		end
		if member.max_hp ~= nil and (type(member.max_hp) ~= 'number' or member.max_hp < 0) then
			error('Scholar runtime party member max_hp must be non-negative when present')
		end
		if member.buffs ~= nil and type(member.buffs) ~= 'table' then
			error('Scholar runtime party member buffs must be a table when present')
		end
		members[i] = {
			id = member.id,
			name = member.name,
			hpp = member.hpp,
			hp = member.hp,
			max_hp = member.max_hp,
			buffs = member.buffs and clone_value(member.buffs) or nil,
			charmed = member.charmed == true,
		}
	end
	for key in pairs(observation.party_members) do
		if type(key) ~= 'number'
			or key < 1
			or key > #observation.party_members
			or key % 1 ~= 0 then
			error('Scholar runtime party_members must be a contiguous array')
		end
	end
	local now = now_number(at, 'Scholar runtime environment observation time')
	state.environment = {
		observed = true,
		observed_at = now,
		engine_enabled = observation.engine_enabled,
		maintenance_enabled = observation.maintenance_enabled,
		defensive_enabled = observation.defensive_enabled,
		main_job = observation.main_job:upper(),
		player_hpp = observation.player_hpp,
		party_generation = observation.party_generation,
		party_members = members,
	}
	return revalidate_active_environment(now)
end

function M.observe_charge(observation, at)
	if type(observation) ~= 'table' then
		error('Scholar charge observation must be a table')
	end
	local now = now_number(at, 'Scholar charge observation time')
	local confidence = observation.confidence
	if confidence ~= 'confirmed' and confidence ~= 'unknown' then
		error('Scholar charge confidence must be confirmed or unknown')
	end
	if type(observation.recast_present) ~= 'boolean' then
		error('Scholar charge recast_present must be a boolean')
	end
	local recast = observation.observed_recast
	if observation.recast_present then
		if type(recast) ~= 'number' or recast < 0 then
			error('Scholar observed stratagem recast must be a non-negative number')
		end
	elseif recast ~= nil then
		error('Scholar observed stratagem recast must be nil when unavailable')
	end
	if confidence == 'confirmed' and observation.recast_present ~= true then
		error('Scholar confirmed charge state requires present recast data')
	end
	local available = observation.available
	local maximum = observation.maximum
	if type(available) ~= 'number' or available < 0 or available % 1 ~= 0 then
		error('Scholar available charge count must be a non-negative integer')
	end
	if type(maximum) ~= 'number' or maximum < 0 or maximum % 1 ~= 0 or available > maximum then
		error('Scholar maximum charge count must be an integer not less than available')
	end
	if type(observation.tabula_rasa_active) ~= 'boolean' then
		error('Scholar charge Tabula Rasa state must be a boolean')
	end
	if type(observation.model_key) ~= 'string' or observation.model_key == '' then
		error('Scholar charge model_key must be a non-empty string')
	end
	if type(observation.decoder_source) ~= 'string' then
		error('Scholar charge decoder_source must be a string')
	end
	if type(observation.reason) ~= 'string' then
		error('Scholar charge reason must be a string')
	end
	state.stratagem.estimated_available = available
	state.stratagem.maximum = maximum
	state.stratagem.recast_present = observation.recast_present
	state.stratagem.observed_recast = recast
	state.stratagem.observed_at = now
	state.stratagem.confidence = confidence
	state.stratagem.model_key = observation.model_key
	state.stratagem.decoder_source = observation.decoder_source
	state.stratagem.reason = observation.reason
	state.stratagem.tabula_rasa_active = observation.tabula_rasa_active
	state.last_transition = 'charge_observed:' .. confidence
	return true
end

function M.observe_player_buffs(buffs, at)
	if type(buffs) ~= 'table' then
		error('Scholar player buffs must be a table')
	end
	local now = now_number(at, 'Scholar player buff observation time')
	local light = has_buff(buffs, capabilities.abilities.light_arts.buff_id)
	local dark = has_buff(buffs, capabilities.abilities.dark_arts.buff_id)
	local addendum_white = has_buff(buffs, capabilities.abilities.addendum_white.buff_id)
	local addendum_black = has_buff(buffs, capabilities.abilities.addendum_black.buff_id)
	local observed_art = 'none'
	local art_count = (light and 1 or 0) + (dark and 1 or 0) + (addendum_white and 1 or 0) + (addendum_black and 1 or 0)
	if art_count > 1 then
		observed_art = 'unknown'
	elseif addendum_white then
		observed_art = 'addendum_white'
	elseif addendum_black then
		observed_art = 'addendum_black'
	elseif light then
		observed_art = 'light'
	elseif dark then
		observed_art = 'dark'
	end
	state.arts.observed = observed_art
	state.arts.observed_at = now
	local sublimation_activated = has_buff(buffs, capabilities.abilities.sublimation.activated_buff_id)
	local sublimation_complete = has_buff(buffs, capabilities.abilities.sublimation.complete_buff_id)
	if sublimation_activated and sublimation_complete then
		state.sublimation.observed = 'unknown'
	elseif sublimation_complete then
		state.sublimation.observed = 'complete'
	elseif sublimation_activated then
		state.sublimation.observed = 'activated'
	else
		state.sublimation.observed = 'none'
	end
	state.sublimation.observed_at = now
	state.stratagem.tabula_rasa_active = has_buff(buffs, capabilities.abilities.tabula_rasa.buff_id)

	local sequence = state.active_sequence
	local pending = state.pending
	if sequence ~= nil and pending ~= nil and pending.action_type == 'job_ability' then
		local direct_confirmed = false
		if sequence.direct_action_type == 'job_ability' then
			if sequence.purpose == 'sublimation_release' then
				direct_confirmed = pending.action_result_observed == true
					and state.sublimation.observed == 'none'
			else
				local direct_buff_id = tonumber(sequence.expected_buff_id) or 0
				direct_confirmed = direct_buff_id > 0 and has_buff(buffs, direct_buff_id)
			end
		end
		if direct_confirmed then
			if sequence.purpose == 'sublimation_activate' then
				state.sublimation.activated_at = now
			end
			state.pending = nil
			return complete_sequence(now)
		end
		local expected_buff_id = tonumber(pending.expected_buff_id) or 0
		if expected_buff_id > 0 and has_buff(buffs, expected_buff_id) then
			local action_name = pending.action_name
			state.pending = nil
			if action_name == 'Light Arts' or action_name == 'Addendum: White' then
				if action_name == 'Addendum: White' then
					sequence.reserved_charges_remaining = math.max(
						0,
						(tonumber(sequence.reserved_charges_remaining) or 0) - 1
					)
				end
				if action_name == 'Light Arts' then
					set_sequence_phase('ensure_addendum', 'art_confirmed')
				else
					next_stratagem_phase('addendum_confirmed')
				end
			else
				sequence.prepared_stratagems[action_name] = true
				sequence.reserved_charges_remaining = math.max(
					0,
					(tonumber(sequence.reserved_charges_remaining) or 0) - 1
				)
				sequence.next_stratagem_index = (tonumber(sequence.next_stratagem_index) or 1) + 1
				state.stratagem.last_used_at = now
				next_stratagem_phase(action_key(action_name) .. '_confirmed')
			end
		end
	end
	update_lane()
	return true
end

function M.start_sequence(plan, at)
	local now = now_number(at, 'Scholar sequence start time')
	if state.enabled ~= true or state.eligibility ~= 'eligible' then
		state.last_blocker = 'sch_not_eligible'
		return false, state.last_blocker
	end
	if state.active_sequence ~= nil or state.pending ~= nil then
		state.last_blocker = 'sequence_already_active'
		return false, state.last_blocker
	end
	if now < (tonumber(state.next_retry_at) or 0) then
		state.last_blocker = 'sequence_retry_backoff'
		return false, state.last_blocker
	end
	local validated, reason = validate_plan(plan, now)
	if validated == nil then
		state.last_blocker = reason
		return false, reason
	end
	local environment_reason = active_environment_blocker(validated)
	if environment_reason ~= '' then
		state.last_blocker = environment_reason
		return false, environment_reason
	end
	local charges = required_charge_count(validated)
	if charges > 0 and state.stratagem.confidence ~= 'confirmed' then
		state.last_blocker = 'charge_confidence_unknown'
		return false, state.last_blocker
	end
	if state.stratagem.estimated_available < charges then
		state.last_blocker = 'insufficient_confirmed_charges'
		return false, state.last_blocker
	end
	state.sequence_generation = state.sequence_generation + 1
	validated.generation = state.sequence_generation
	validated.profile_generation = state.profile_generation
	validated.created_at = now
	validated.phase = validated.direct_action_type ~= nil and 'dispatch_action' or 'ensure_art'
	validated.next_stratagem_index = 1
	validated.prepared_stratagems = {}
	validated.reserved_charges_initial = charges
	validated.reserved_charges_remaining = charges
	state.active_sequence = validated
	state.last_transition = 'sequence_started:' .. validated.id
	state.last_blocker = ''
	update_lane()
	return true, validated.generation
end

local function action_step(sequence, action_type, action_name, target_id, target_name, expected_buff_id)
	local ability = action_type == 'job_ability' and capabilities.ability(action_name) or nil
	return {
		provider = sequence.domain == 'defensive' and 'defensive_sch' or 'maintenance_sch',
		domain = sequence.domain,
		action_type = action_type,
		action_name = action_name,
		target_id = tonumber(target_id) or 0,
		target_name = tostring(target_name or ''),
		sequence_id = sequence.id,
		sequence_generation = sequence.generation,
		phase = sequence.phase,
		deadline = sequence.deadline,
		expected_buff_id = tonumber(expected_buff_id) or 0,
		uses_reserved_charge = ability ~= nil
			and ability.recast_id == capabilities.STRATAGEM_RECAST_ID,
		spell_mp_multiplier = tonumber(sequence.spell_mp_multiplier) or 1.0,
		duplicate_suppression_key = table.concat({
			'sch', tostring(sequence.generation), tostring(sequence.phase),
		}, ':'),
		reason_code = 'sch_' .. action_key(sequence.purpose) .. '_' .. action_key(sequence.phase),
	}
end

function M.reserved_charge_step_ready(step)
	if type(step) ~= 'table' then
		error('Scholar reserved-charge readiness requires a runtime step')
	end
	local sequence = state.active_sequence
	if sequence == nil then
		return false, 'no_active_sequence'
	end
	if state.pending ~= nil then
		return false, 'sequence_action_pending'
	end
	if step.uses_reserved_charge ~= true
		or step.action_type ~= 'job_ability' then
		return false, 'step_does_not_use_reserved_charge'
	end
	if tostring(step.sequence_id or '') ~= sequence.id
		or tonumber(step.sequence_generation) ~= sequence.generation
		or tostring(step.phase or '') ~= sequence.phase then
		return false, 'stale_sequence_step'
	end
	local ability = capabilities.ability(step.action_name)
	if ability == nil or ability.recast_id ~= capabilities.STRATAGEM_RECAST_ID then
		return false, 'reserved_charge_action_invalid'
	end
	local remaining = tonumber(sequence.reserved_charges_remaining)
	if remaining == nil or remaining <= 0 or remaining % 1 ~= 0 then
		return false, 'reserved_charge_exhausted'
	end
	if state.stratagem.confidence ~= 'confirmed' then
		return false, 'charge_confidence_unknown'
	end
	local available = tonumber(state.stratagem.estimated_available)
	if available == nil or available < remaining then
		return false, 'reserved_charge_observation_contradiction'
	end
	return true, ''
end

function M.next_step(at)
	local now = now_number(at, 'Scholar next-step time')
	local invariants_valid = M.enforce_invariants(now)
	if not invariants_valid then
		return nil, 'invariant_violation'
	end
	local sequence = state.active_sequence
	if sequence == nil then
		return nil, 'no_active_sequence'
	end
	local environment_valid, environment_reason = revalidate_active_environment(now)
	if not environment_valid then
		return nil, environment_reason
	end
	sequence = state.active_sequence
	if state.pending ~= nil then
		return nil, 'sequence_action_pending'
	end
	if now > sequence.deadline then
		abort_sequence('sequence_deadline_expired', now, 1.0)
		return nil, 'sequence_deadline_expired'
	end
	if sequence.profile_generation ~= state.profile_generation then
		abort_sequence('configuration_changed', now, 0)
		return nil, 'configuration_changed'
	end
	if sequence.phase == 'ensure_art' then
		if art_is_compatible(sequence.required_art) then
			set_sequence_phase('ensure_addendum', 'art_already_confirmed')
			return M.next_step(now)
		end
		return action_step(
			sequence,
			'job_ability',
			'Light Arts',
			0,
			'<me>',
			capabilities.abilities.light_arts.buff_id
		), ''
	end
	if sequence.phase == 'dispatch_action' then
		return action_step(
			sequence,
			sequence.direct_action_type,
			sequence.direct_action_name,
			0,
			'<me>',
			sequence.expected_buff_id
		), ''
	end
	if sequence.phase == 'ensure_addendum' then
		if addendum_is_confirmed(sequence.required_addendum) then
			next_stratagem_phase('addendum_not_required_or_confirmed')
			return M.next_step(now)
		end
		return action_step(
			sequence,
			'job_ability',
			'Addendum: White',
			0,
			'<me>',
			capabilities.abilities.addendum_white.buff_id
		), ''
	end
	local stratagem_index = tonumber(sequence.next_stratagem_index) or 1
	local stratagem_name = sequence.stratagems[stratagem_index]
	if stratagem_name ~= nil and sequence.phase == phase_for('use', stratagem_name) then
		local ability = capabilities.ability(stratagem_name)
		if ability == nil then
			error('Scholar runtime stratagem capability is missing: ' .. tostring(stratagem_name))
		end
		return action_step(
			sequence,
			'job_ability',
			stratagem_name,
			0,
			'<me>',
			ability.buff_id
		), ''
	end
	if sequence.phase == 'cast_spell' then
		return action_step(
			sequence,
			'spell',
			sequence.spell,
			sequence.anchor_id,
			sequence.anchor_name,
			sequence.status_id
		), ''
	end
	return nil, 'sequence_waiting_for_evidence'
end

function M.note_dispatched(step, at)
	if type(step) ~= 'table' then
		error('Scholar dispatched step must be a table')
	end
	local now = now_number(at, 'Scholar dispatch time')
	local sequence = state.active_sequence
	if sequence == nil then
		return false, 'no_active_sequence'
	end
	if state.pending ~= nil then
		return false, 'sequence_action_pending'
	end
	if tostring(step.sequence_id or '') ~= sequence.id
		or tonumber(step.sequence_generation) ~= sequence.generation
		or tostring(step.phase or '') ~= sequence.phase then
		return false, 'stale_sequence_step'
	end
	if step.action_type ~= 'job_ability' and step.action_type ~= 'spell' then
		return false, 'unsupported_action_type'
	end
	if type(step.action_name) ~= 'string' or step.action_name == '' then
		return false, 'action_name_required'
	end
	state.pending = {
		sequence_id = sequence.id,
		sequence_generation = sequence.generation,
		phase = sequence.phase,
		action_type = step.action_type,
		action_name = step.action_name,
		target_id = tonumber(step.target_id) or 0,
		expected_buff_id = tonumber(step.expected_buff_id) or 0,
		dispatched_at = now,
		confirmation_deadline = math.min(
			sequence.deadline,
			now + (step.action_type == 'spell' and 8.0 or 2.0)
		),
		action_result_observed = false,
	}
	set_sequence_phase(phase_for('wait_for', step.action_name), 'dispatched')
	state.pending.phase = sequence.phase
	update_lane()
	return true, ''
end

local function record_spell_recipients(sequence, recipients, at)
	local expected = sequence.expected_recipient_set
	local normalized_recipients = {}
	local seen_recipient_ids = {}
	local unexpected_recipients = {}
	for i = 1, #recipients do
		local recipient = normalize_recipient(recipients[i])
		if recipient == nil then
			return false, 'spell_recipient_invalid'
		end
		if seen_recipient_ids[recipient.id] then
			return false, 'spell_recipient_duplicate'
		end
		seen_recipient_ids[recipient.id] = true
		normalized_recipients[#normalized_recipients + 1] = recipient
		if expected[recipient.id] ~= true then
			unexpected_recipients[#unexpected_recipients + 1] = recipient.id
		end
	end
	state.unexpected_recipients = unexpected_recipients
	if sequence.effect_kind == 'cure' or sequence.effect_kind == 'status_removal' then
		return true, ''
	end
	local duration = sch_duration.estimate({
		family = sequence.duration_family,
		spell = sequence.spell,
		cast_at = at,
		applied_modifiers = sequence.stratagems,
		evidence = sch_duration.production_evidence(
			sequence.duration_family,
			sequence.spell,
			sequence.stratagems
		),
	})
	for i = 1, #normalized_recipients do
		local recipient = normalized_recipients[i]
		state.owned_buffs[recipient.id] = state.owned_buffs[recipient.id] or {}
		state.owned_buffs[recipient.id][sequence.buff_family] = {
			target_id = recipient.id,
			target_name = recipient.name,
			family = sequence.buff_family,
			exact_spell = sequence.spell,
			status_id = sequence.status_id,
			source_sequence_id = sequence.id,
			cast_at = at,
			estimated_expires_at = duration.estimated_expires_at,
			duration_confidence = duration.duration_confidence,
			duration_reason = duration.duration_reason,
			duration_source = duration.duration_source,
			duration_model_key = duration.duration_model_key,
			applied_modifiers = clone_value(duration.applied_modifiers),
			presence = 'present',
			last_observed_at = at,
		}
	end
	return true, ''
end

function M.observe_local_action(event, at)
	if type(event) ~= 'table' then
		error('Scholar local action observation must be a table')
	end
	local now = now_number(at, 'Scholar local action observation time')
	local action_type = tostring(event.action_type or '')
	local action_name = tostring(event.action_name or '')
	local sequence = state.active_sequence
	if sequence ~= nil and action_type == 'spell'
		and next(sequence.prepared_stratagems or {}) ~= nil
		and event.recognized == false then
		state.stratagem.confidence = 'unknown'
		return abort_sequence('unrecognized_local_spell', now, 1.0)
	end
	if sequence ~= nil and action_type == 'spell'
		and next(sequence.prepared_stratagems or {}) ~= nil
		and action_name ~= sequence.spell then
		state.stratagem.confidence = 'unknown'
		return abort_sequence('manual_action_contamination', now, 1.0)
	end
	local pending = state.pending
	if pending == nil then
		return false, 'no_pending_sch_action'
	end
	if action_type ~= pending.action_type or action_name ~= pending.action_name then
		if action_type == 'spell' and sequence ~= nil and next(sequence.prepared_stratagems or {}) ~= nil then
			state.stratagem.confidence = 'unknown'
			return abort_sequence('manual_action_contamination', now, 1.0)
		end
		return false, 'unrelated_local_action'
	end
	if event.interrupted == true or event.success == false then
		return abort_sequence(event.interrupted == true and 'action_interrupted' or 'action_rejected', now, 1.0)
	end
	if event.result_unclassified == true then
		return abort_sequence('action_result_unclassified', now, 1.0)
	end
	if event.success ~= true then
		return false, 'action_result_unclassified'
	end
	pending.action_result_observed = true
	if action_type == 'job_ability' then
		state.last_transition = 'action_result_observed:' .. action_key(action_name)
		return true, 'waiting_for_buff_confirmation'
	end
	if type(event.successful_recipients) ~= 'table' or #event.successful_recipients == 0 then
		return abort_sequence('no_successful_recipients', now, 1.0)
	end
	local recorded, reason = record_spell_recipients(sequence, event.successful_recipients, now)
	if not recorded then
		return abort_sequence(reason, now, 1.0)
	end
	state.pending = nil
	sequence.prepared_stratagems = {}
	set_sequence_phase('reconcile_recipients', 'spell_recipients_confirmed')
	return complete_sequence(now)
end

function M.observe_party_buffs(members, at)
	if type(members) ~= 'table' then
		error('Scholar party buff observation must be a table')
	end
	local now = now_number(at, 'Scholar party buff observation time')
	for i = 1, #members do
		local member = members[i]
		if type(member) ~= 'table' then
			error('Scholar party buff member must be a table')
		end
		local member_id = tonumber(member.id)
		if member_id == nil or member_id <= 0 then
			error('Scholar party buff member id must be positive')
		end
		local owners = state.owned_buffs[member_id]
		if type(owners) == 'table' then
			for _, owner in pairs(owners) do
				if type(member.buffs) ~= 'table' then
					owner.presence = 'unknown'
				else
					owner.presence = has_buff(member.buffs, owner.status_id) and 'present' or 'absent'
				end
				owner.last_observed_at = now
			end
		end
	end
	state.last_transition = 'party_buffs_reconciled'
	return true
end

function M.cancel(reason, at, retry_delay)
	if state.active_sequence == nil then
		return false, 'no_active_sequence'
	end
	return abort_sequence(reason or 'manual_cancellation', at, retry_delay or 0)
end

function M.preempt(reason, at)
	if state.active_sequence == nil then
		return false, 'no_active_sequence'
	end
	if type(reason) ~= 'string' or reason == '' then
		error('Scholar preemption reason must be a non-empty string')
	end
	state.stratagem.confidence = 'unknown'
	return abort_sequence(reason, at, 0)
end

function M.tick(at)
	local now = now_number(at, 'Scholar tick time')
	local invariants_valid = M.enforce_invariants(now)
	if not invariants_valid then
		return false, 'invariant_violation'
	end
	local sequence = state.active_sequence
	if sequence == nil then
		return false, 'idle'
	end
	local environment_valid, environment_reason = revalidate_active_environment(now)
	if not environment_valid then
		return false, environment_reason
	end
	sequence = state.active_sequence
	if now > sequence.deadline then
		return abort_sequence('sequence_deadline_expired', now, 1.0)
	end
	if state.pending ~= nil and now > state.pending.confirmation_deadline then
		return abort_sequence('confirmation_timeout', now, 1.0)
	end
	return false, 'waiting'
end

function M.requires_fast_tick()
	return state.active_sequence ~= nil or state.pending ~= nil
end

function M.lane_status()
	return clone_value(state.lane)
end

function M.snapshot()
	return clone_value(state)
end

function M.active_config()
	return clone_value(active_config)
end

function M._test_state()
	return state
end

return M
