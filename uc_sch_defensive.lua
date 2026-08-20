local area_planner = require('uc_sch_area_planner')

local M = {}

local ACCESSION_STATUS_SPELLS = {
	Erase = true,
	Blindna = true,
	Paralyna = true,
	Poisona = true,
	Silena = true,
	Stona = true,
	Cursna = true,
	Viruna = true,
}

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

local function missing_hp(member)
	local hp = tonumber(member.hp)
	local max_hp = tonumber(member.max_hp)
	if hp == nil or max_hp == nil or max_hp <= 0 or hp < 0 or hp > max_hp then
		return nil
	end
	return math.max(0, math.ceil(max_hp - hp))
end

local function members_by_id(members)
	local out = {}
	for i = 1, #members do
		local member = require_table(members[i], 'Scholar defensive party member')
		local id = tonumber(member.id)
		if id == nil or id <= 0 or id % 1 ~= 0 then
			error('Scholar defensive party member id must be positive')
		end
		if out[id] ~= nil then
			error('Scholar defensive party member ids must be unique')
		end
		out[id] = member
	end
	return out
end

local function recipients_for_ids(index, ids)
	local recipients = {}
	for i = 1, #ids do
		local member = index[ids[i]]
		if member == nil then
			error('Scholar defensive selected recipient is not in the party snapshot')
		end
		recipients[#recipients + 1] = { id = member.id, name = member.name }
	end
	return recipients
end

local function plan_candidate(plan, action_name, target_id, target_name, reason)
	return {
		action_type = 'job_ability',
		action_name = action_name,
		target_id = target_id,
		target_name = target_name,
		reason = reason,
		family = 'defensive',
		plan = plan,
	}
end

local function base_plan(ctx, purpose, spell, anchor, recipients, stratagems, addendum, mp_multiplier)
	return {
		purpose = purpose,
		domain = 'defensive',
		required_art = 'light',
		required_addendum = addendum,
		stratagems = stratagems,
		spell = spell,
		anchor_id = anchor.id,
		anchor_name = anchor.name,
		expected_recipients = recipients,
		party_generation = ctx.party_generation,
		effect_kind = purpose == 'accession_status_removal' and 'status_removal' or 'cure',
		spell_mp_multiplier = mp_multiplier,
	}
end

local function evaluate_accession_status(config, ctx, members, index)
	local result = { enabled = config.enabled, state = config.enabled and 'evaluating' or 'disabled', blocker = '' }
	if not config.enabled then return result end
	local groups = {}
	for i = 1, #members do
		local member = members[i]
		local hpp = tonumber(member.hpp)
		if hpp and hpp > 0 and member.charmed ~= true then
			if type(member.buffs) ~= 'table' then
				result.state = 'blocked'
				result.blocker = 'party_buff_state_unknown'
				return result
			end
			for buff_index = 1, #member.buffs do
				local info = ctx.status_removal_for_buff(member.buffs[buff_index])
				if type(info) == 'table' and ACCESSION_STATUS_SPELLS[info.spell]
					and info.status_key ~= 'doom' then
					local key = tostring(info.buff_id) .. '|' .. info.spell
					local group = groups[key]
					if group == nil then
						group = { info = info, ids = {}, priority = tonumber(info.priority) or 5 }
						groups[key] = group
					end
					group.ids[#group.ids + 1] = member.id
				end
			end
		end
	end
	local ordered = {}
	for _, group in pairs(groups) do
		if #group.ids >= config.minimum_members then
			ordered[#ordered + 1] = group
		end
	end
	table.sort(ordered, function(left, right)
		if left.priority ~= right.priority then return left.priority < right.priority end
		if #left.ids ~= #right.ids then return #left.ids > #right.ids end
		return left.info.buff_id < right.info.buff_id
	end)
	for i = 1, #ordered do
		local group = ordered[i]
		local geometry = area_planner.select({
			now = ctx.now,
			members = members,
			eligible_recipient_ids = group.ids,
			unsafe_recipient_ids = {},
			minimum_coverage = config.minimum_members,
			mechanics = ctx.area_mechanics,
		})
		if geometry.state == 'ready' then
			local selected = geometry.selected
			local anchor = index[selected.anchor_id]
			local ready, reason = ctx.spell_ready(group.info.spell, anchor.id, 2.0)
			if ready then
				local addendum = group.info.spell == 'Erase' and nil or 'white'
				local plan = base_plan(
					ctx,
					'accession_status_removal',
					group.info.spell,
					anchor,
					recipients_for_ids(index, selected.expected_recipient_ids),
					{ 'Accession' },
					addendum,
					2.0
				)
				plan.status_buff_id = group.info.buff_id
				plan.status_key = group.info.status_key
				plan.minimum_members = config.minimum_members
				result.state = 'actionable'
				result.geometry = geometry
				result.plan = plan
				result.candidate = plan_candidate(
					plan, 'Accession', ctx.player.id, ctx.player.name,
					'sch_accession_status_removal'
				)
				return result
			end
			result.blocker = reason
		else
			result.blocker = geometry.blocker
		end
	end
	result.state = result.blocker ~= '' and 'blocked' or 'not_required'
	return result
end

local function evaluate_accession_cure(config, ctx, members, index)
	local result = { enabled = config.enabled, state = config.enabled and 'evaluating' or 'disabled', blocker = '' }
	if not config.enabled then return result end
	local eligible_ids = {}
	for i = 1, #members do
		local member = members[i]
		local hpp = tonumber(member.hpp)
		local missing = missing_hp(member)
		if hpp == nil or missing == nil then
			result.state = 'blocked'
			result.blocker = 'party_hp_state_unknown'
			return result
		end
		if hpp > 0 and hpp <= ctx.critical_hpp then
			result.state = 'blocked'
			result.blocker = 'critical_direct_cure_required'
			return result
		end
		if hpp > 0 and hpp <= config.member_hpp_at_most
			and missing > 0 and member.charmed ~= true then
			eligible_ids[#eligible_ids + 1] = member.id
		end
	end
	if #eligible_ids < config.minimum_members then
		result.state = 'not_required'
		return result
	end
	local geometry = area_planner.select({
		now = ctx.now,
		members = members,
		eligible_recipient_ids = eligible_ids,
		unsafe_recipient_ids = {},
		minimum_coverage = config.minimum_members,
		mechanics = ctx.area_mechanics,
	})
	result.geometry = geometry
	if geometry.state ~= 'ready' then
		result.state = 'blocked'
		result.blocker = geometry.blocker
		return result
	end
	local selected = geometry.selected
	local recipients = recipients_for_ids(index, selected.expected_recipient_ids)
	local total_missing = 0
	local worst = nil
	for i = 1, #selected.expected_recipient_ids do
		local member = index[selected.expected_recipient_ids[i]]
		local missing = missing_hp(member)
		total_missing = total_missing + missing
		if worst == nil or missing > missing_hp(worst) then worst = member end
	end
	result.total_missing_hp = total_missing
	if total_missing < config.minimum_total_missing_hp then
		result.state = 'not_required'
		return result
	end
	local spell, spell_reason = ctx.select_cure_spell(worst, 2.0)
	if spell == nil then
		result.state = 'blocked'
		result.blocker = spell_reason
		return result
	end
	local anchor = index[selected.anchor_id]
	local plan = base_plan(ctx, 'accession_cure', spell, anchor, recipients, { 'Accession' }, nil, 2.0)
	plan.total_missing_hp = total_missing
	plan.minimum_members = config.minimum_members
	plan.member_hpp_at_most = config.member_hpp_at_most
	plan.minimum_total_missing_hp = config.minimum_total_missing_hp
	result.state = 'actionable'
	result.plan = plan
	result.candidate = plan_candidate(
		plan, 'Accession', ctx.player.id, ctx.player.name, 'sch_accession_cure'
	)
	return result
end

local function best_noncritical_member(ctx, members, minimum_missing)
	local best = nil
	local best_missing = 0
	for i = 1, #members do
		local member = members[i]
		local hpp = tonumber(member.hpp)
		local missing = missing_hp(member)
		if hpp == nil or missing == nil then return nil, 'party_hp_state_unknown' end
		if hpp > ctx.critical_hpp and hpp > 0 and missing >= minimum_missing
			and member.charmed ~= true and missing > best_missing then
			best = member
			best_missing = missing
		end
	end
	return best, ''
end

local function evaluate_single_cure(config, ctx, members, purpose, stratagem, mp_multiplier)
	local result = { enabled = config.enabled, state = config.enabled and 'evaluating' or 'disabled', blocker = '' }
	if not config.enabled then return result end
	if ctx.critical_cure_present then
		result.state = 'blocked'
		result.blocker = 'critical_direct_cure_required'
		return result
	end
	if purpose == 'penury_cure' and ctx.player.vitals.mpp > config.maximum_mpp then
		result.state = 'not_required'
		return result
	end
	local minimum_missing = purpose == 'rapture_cure' and config.minimum_missing_hp or 1
	local member, member_reason = best_noncritical_member(ctx, members, minimum_missing)
	if member == nil then
		result.state = member_reason ~= '' and 'blocked' or 'not_required'
		result.blocker = member_reason
		return result
	end
	local spell, spell_reason = ctx.select_cure_spell(member, mp_multiplier)
	if spell == nil then
		result.state = 'blocked'
		result.blocker = spell_reason
		return result
	end
	local plan = base_plan(
		ctx, purpose, spell, member,
		{ { id = member.id, name = member.name } }, { stratagem }, nil, mp_multiplier
	)
	plan.minimum_missing_hp = minimum_missing
	result.state = 'actionable'
	result.plan = plan
	result.candidate = plan_candidate(
		plan, stratagem, ctx.player.id, ctx.player.name, 'sch_' .. purpose
	)
	return result
end

function M.evaluate(config, ctx, runtime_snapshot)
	require_table(config, 'Scholar defensive config')
	require_table(ctx, 'Scholar defensive context')
	require_table(runtime_snapshot, 'Scholar defensive runtime snapshot')
	local result = {
		enabled = config.accession_cure.enabled
			or config.accession_status_removal.enabled
			or config.rapture.enabled or config.penury.enabled,
		state = 'not_required',
		blocker = '',
		candidate = nil,
	}
	if not result.enabled then
		result.state = 'disabled'
		return result
	end
	require_function(ctx.status_removal_for_buff, 'Scholar defensive status_removal_for_buff')
	require_function(ctx.spell_ready, 'Scholar defensive spell_ready')
	require_function(ctx.select_cure_spell, 'Scholar defensive select_cure_spell')
	if ctx.defensive_enabled ~= true then
		result.state = 'blocked'
		result.blocker = 'defensive_domain_disabled'
		return result
	end
	if ctx.critical_cure_present then
		result.state = 'blocked'
		result.blocker = 'critical_direct_cure_required'
		return result
	end
	local members = require_table(ctx.party_members, 'Scholar defensive party members')
	local index = members_by_id(members)
	result.accession_status_removal = evaluate_accession_status(
		config.accession_status_removal, ctx, members, index
	)
	result.accession_cure = evaluate_accession_cure(config.accession_cure, ctx, members, index)
	result.rapture = evaluate_single_cure(
		config.rapture, ctx, members, 'rapture_cure', 'Rapture', 1.0
	)
	result.penury = evaluate_single_cure(
		config.penury, ctx, members, 'penury_cure', 'Penury', 0.5
	)
	local ordered = {
		result.accession_status_removal,
		result.accession_cure,
		result.rapture,
		result.penury,
	}
	for i = 1, #ordered do
		if ordered[i].candidate ~= nil then
			result.state = 'actionable'
			result.candidate = ordered[i].candidate
			return result
		end
	end
	for i = 1, #ordered do
		if ordered[i].blocker ~= '' then
			result.state = 'blocked'
			result.blocker = ordered[i].blocker
			break
		end
	end
	return result
end

return M
