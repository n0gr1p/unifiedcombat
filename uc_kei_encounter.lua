local res = require('resources')

local M = {}

local FULLERS_THRESHOLDS = { 75, 50, 25, 10 }

local function copy(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copy(item)
	end
	return out
end

local function canonical(value)
	if type(value) ~= 'string' then
		return ''
	end
	return (value:match('^%s*(.-)%s*$') or ''):lower()
end

local function require_number(value, path_name, minimum)
	if type(value) ~= 'number' or value < minimum then
		error(path_name .. ' must be a number >= ' .. tostring(minimum))
	end
	return value
end

local function require_name(value, path_name)
	if type(value) ~= 'string' then
		error(path_name .. ' must be a string')
	end
	local trimmed = value:match('^%s*(.-)%s*$') or ''
	if trimmed == '' then
		error(path_name .. ' must not be empty')
	end
	return trimmed
end

local function spell_by_name(name)
	for _, spell in pairs(res.spells or {}) do
		if canonical(spell and spell.en) == canonical(name) then
			return spell
		end
	end
	return nil
end

local function message_template(message_id)
	local message = res.action_messages and res.action_messages[tonumber(message_id) or 0] or nil
	return tostring(message and message.en or '')
end

local function classify_magic_result(action)
	if type(action) ~= 'table' then
		return 'ambiguous', 0, 0
	end
	local message_id = tonumber(action.message or action.message_id) or 0
	local amount = tonumber(action.param) or 0
	if message_id == 16 then
		return 'interrupted', message_id, amount
	end
	local template = message_template(message_id)
	if template == '' then
		return 'ambiguous', message_id, amount
	end
	if template:find('${target} recovers ${number} HP', 1, true)
		or template:find('${target} recovers ${number} hit points', 1, true) then
		if amount > 0 then
			return 'absorbed', message_id, amount
		end
		return 'ambiguous', message_id, amount
	end
	if template:find('${target} takes ${number} points of damage', 1, true) then
		if amount > 0 then
			return 'damage', message_id, amount
		end
		return 'ambiguous', message_id, amount
	end
	return 'ambiguous', message_id, amount
end

local function target_result(act, target_id)
	if type(act.targets) ~= 'table' then
		return 'ambiguous', 0, 0
	end
	for _, target in ipairs(act.targets) do
		if tonumber(target and target.id) == tonumber(target_id) then
			if type(target.actions) ~= 'table' then
				return 'ambiguous', 0, 0
			end
			local saw_interrupted = false
			for _, action in ipairs(target.actions) do
				local kind, message_id, amount = classify_magic_result(action)
				if kind == 'damage' or kind == 'absorbed' then
					return kind, message_id, amount
				end
				if kind == 'interrupted' then
					saw_interrupted = true
				end
			end
			return saw_interrupted and 'interrupted' or 'ambiguous', 0, 0
		end
	end
	return 'unrelated_target', 0, 0
end

local function ability_name_from_action(act, category)
	local ability_id = 0
	if category == 7 then
		local target = type(act.targets) == 'table' and act.targets[1] or nil
		local action = target and type(target.actions) == 'table' and target.actions[1] or nil
		ability_id = tonumber(action and action.param) or 0
	elseif category == 11 then
		ability_id = tonumber(act.param) or 0
	end
	local ability = ability_id > 0 and res.monster_abilities and res.monster_abilities[ability_id] or nil
	return tostring(ability and ability.en or ''), ability_id
end

local function job_ability_name_from_action(act, category)
	if category ~= 6 then
		return '', 0
	end
	local ability_id = tonumber(act.param) or 0
	local ability = ability_id > 0 and res.job_abilities and res.job_abilities[ability_id] or nil
	return tostring(ability and ability.en or ''), ability_id
end

local function next_threshold(consumed)
	for i = 1, #FULLERS_THRESHOLDS do
		local threshold = FULLERS_THRESHOLDS[i]
		if consumed[threshold] ~= true then
			return threshold
		end
	end
	return nil
end

local function new_state()
	return {
		enabled = false,
		configured = false,
		phase = 'idle',
		error = '',
		config_signature = '',
		config = nil,
		boss = nil,
		player_id = 0,
		player_name = '',
		spike_mode = 'unknown',
		weak_element = 'unknown',
		element_source = 'none',
		last_correct_element_hit_at = nil,
		last_correct_element_spell = '',
		pending_spell = nil,
		fullers = {
			consumed = { [75] = false, [50] = false, [25] = false, [10] = false },
			next_threshold = 75,
			prearmed = false,
			in_progress = false,
			last_completed_at = 0,
		},
		last_benediction_at = nil,
		last_transition = 'initial',
		last_observed_at = 0,
		last_reset_reason = 'initial',
	}
end

local state = new_state()

local function emit(event_code, fields, key, interval)
	local logger = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(logger) == 'function' then
		logger(event_code, fields, key, interval or 0)
	end
end

local function transition(text, event_code, fields)
	state.last_transition = text
	emit(event_code, fields or {}, 'kei:' .. event_code .. ':' .. text, 0.05)
end

local function clear_combat(reason)
	local enabled = state.enabled
	local configured = state.configured
	local signature = state.config_signature
	local config = state.config
	state = new_state()
	state.enabled = enabled
	state.configured = configured
	state.config_signature = signature
	state.config = config
	state.phase = enabled and 'awaiting_boss' or 'idle'
	state.last_reset_reason = tostring(reason)
	state.last_transition = 'reset:' .. tostring(reason)
end

local function normalized_config(config)
	if type(config) ~= 'table' then
		error('uc_kei_encounter.configure requires config')
	end
	if config.enabled ~= true or tostring(config.id or '') ~= 'kei' then
		return nil
	end
	if type(config.kei) ~= 'table' then
		error('enabled Kei encounter requires config.encounter.kei')
	end
	local elemental = config.kei.elemental_damage
	if type(elemental) ~= 'table' then
		error('enabled Kei encounter requires config.encounter.kei.elemental_damage')
	end
	if type(elemental.water) ~= 'table' or type(elemental.ice) ~= 'table' then
		error('Kei elemental damage requires water and ice spell tables')
	end
	if type(config.kei.fullers) ~= 'table' then
		error('enabled Kei encounter requires config.encounter.kei.fullers')
	end
	local out = {
		dealer_name = require_name(elemental.dealer_name, 'config.encounter.kei.elemental_damage.dealer_name'),
		water_probe_spell = require_name(elemental.water.probe_spell, 'config.encounter.kei.elemental_damage.water.probe_spell'),
		water_damage_spell = require_name(elemental.water.damage_spell, 'config.encounter.kei.elemental_damage.water.damage_spell'),
		ice_probe_spell = require_name(elemental.ice.probe_spell, 'config.encounter.kei.elemental_damage.ice.probe_spell'),
		ice_damage_spell = require_name(elemental.ice.damage_spell, 'config.encounter.kei.elemental_damage.ice.damage_spell'),
		sustain_interval_s = require_number(elemental.sustain_interval_s, 'config.encounter.kei.elemental_damage.sustain_interval_s', 0.5),
		probe_timeout_s = require_number(elemental.probe_timeout_s, 'config.encounter.kei.elemental_damage.probe_timeout_s', 0.5),
		fullers_prearm_hpp_margin = require_number(config.kei.fullers.prearm_hpp_margin, 'config.encounter.kei.fullers.prearm_hpp_margin', 0),
	}
	local spell_fields = {
		'water_probe_spell', 'water_damage_spell', 'ice_probe_spell', 'ice_damage_spell',
	}
	for i = 1, #spell_fields do
		local field = spell_fields[i]
		local spell = spell_by_name(out[field])
		if spell == nil then
			out.invalid_spell = out[field]
			break
		end
		out[field .. '_id'] = tonumber(spell.id)
	end
	return out
end

local function config_signature(config)
	return table.concat({
		config.dealer_name,
		config.water_probe_spell,
		config.water_damage_spell,
		config.ice_probe_spell,
		config.ice_damage_spell,
		('%.3f'):format(config.sustain_interval_s),
		('%.3f'):format(config.probe_timeout_s),
		('%.3f'):format(config.fullers_prearm_hpp_margin),
	}, '\031')
end

function M.configure(config)
	local normalized = normalized_config(config)
	if normalized == nil then
		if state.enabled or state.configured then
			state.enabled = false
			state.configured = false
			state.config = nil
			state.config_signature = ''
			clear_combat('encounter_disabled_or_changed')
		end
		return false, 'DISABLED'
	end
	local signature = config_signature(normalized)
	if state.config_signature ~= signature or state.enabled ~= true then
		state.enabled = true
		state.configured = true
		state.config_signature = signature
		state.config = normalized
		clear_combat('configuration_changed')
	end
	state.enabled = true
	state.configured = true
	state.config = normalized
	if normalized.invalid_spell ~= nil then
		state.phase = 'error'
		state.error = 'INVALID_SPELL:' .. normalized.invalid_spell
		return false, state.error
	end
	return true, 'CONFIGURED'
end

local function update_prearm()
	local threshold = next_threshold(state.fullers.consumed)
	state.fullers.next_threshold = threshold
	local prearmed = false
	if threshold ~= nil and state.boss ~= nil and state.fullers.in_progress ~= true then
		prearmed = tonumber(state.boss.hpp) <= (threshold + state.config.fullers_prearm_hpp_margin)
	end
	if prearmed ~= state.fullers.prearmed then
		state.fullers.prearmed = prearmed
		if prearmed then
			transition(
				('Fullers threshold %d armed'):format(threshold),
				'KEI_FULLERS_THRESHOLD_ARMED',
				{ threshold = threshold, boss_hpp = state.boss.hpp }
			)
		else
			transition('Fullers prearm cleared', 'KEI_FULLERS_PREARM_CLEARED', {})
		end
	end
end

function M.observe_snapshot(snapshot)
	if type(snapshot) ~= 'table' or type(snapshot.actors) ~= 'table' then
		error('uc_kei_encounter.observe_snapshot requires snapshot.actors')
	end
	if state.enabled ~= true or state.configured ~= true then
		return false, 'DISABLED'
	end
	local now = tonumber(snapshot.now)
	if now == nil then
		error('uc_kei_encounter.observe_snapshot requires snapshot.now')
	end
	state.player_id = tonumber(snapshot.player_id) or 0
	state.player_name = tostring(snapshot.player_name or '')
	state.last_observed_at = now
	local matches = {}
	for _, actor in ipairs(snapshot.actors) do
		if type(actor) == 'table' and tostring(actor.name or '') == 'Kei' then
			matches[#matches + 1] = actor
		end
	end
	if #matches > 1 then
		clear_combat('multiple_kei_actors')
		state.phase = 'error'
		state.error = 'MULTIPLE_KEI_ACTORS'
		return false, state.error
	end
	if #matches == 0 then
		if state.boss ~= nil then
			clear_combat('kei_despawned')
		end
		state.phase = 'awaiting_boss'
		return false, 'KEI_NOT_FOUND'
	end
	local actor = matches[1]
	local boss = {
		id = tonumber(actor.id),
		name = tostring(actor.name or ''),
		hpp = tonumber(actor.hpp),
		status = tonumber(actor.status),
		x = tonumber(actor.x),
		y = tonumber(actor.y),
		z = tonumber(actor.z),
	}
	if boss.id == nil or boss.id <= 0 or boss.hpp == nil or boss.status == nil then
		state.phase = 'error'
		state.error = 'INCOMPLETE_KEI_ACTOR'
		return false, state.error
	end
	if state.boss ~= nil and tonumber(state.boss.id) ~= boss.id then
		clear_combat('kei_actor_replaced')
		state.player_id = tonumber(snapshot.player_id) or 0
		state.player_name = tostring(snapshot.player_name or '')
	end
	state.boss = boss
	if boss.hpp <= 0 then
		clear_combat('kei_defeated')
		return false, 'KEI_DEFEATED'
	end
	state.phase = 'active'
	state.error = ''
	M.expire_pending(now)
	update_prearm()
	return true, 'ACTIVE'
end

local function set_expected(spike_mode, weak_element, now, spell_name)
	local changed = state.spike_mode ~= spike_mode or state.weak_element ~= weak_element
	state.spike_mode = spike_mode
	state.weak_element = weak_element
	state.element_source = 'inferred_from_kei_cast'
	state.last_correct_element_hit_at = nil
	state.last_correct_element_spell = ''
	state.pending_spell = nil
	if changed then
		transition(
			('successful Kei %s cast -> expected %s'):format(spell_name, weak_element),
			'KEI_ELEMENT_INFERRED',
			{ spike_mode = spike_mode, weak_element = weak_element, spell = spell_name, observed_at = now }
		)
	end
end

local function other_element(element)
	if element == 'water' then
		return 'ice'
	end
	if element == 'ice' then
		return 'water'
	end
	error('unsupported Kei element: ' .. tostring(element))
end

local function observe_local_spell_result(act, now)
	local pending = state.pending_spell
	if type(pending) ~= 'table' then
		return false, 'NO_PENDING_SPELL'
	end
	if tonumber(act.actor_id) ~= tonumber(state.player_id) or tonumber(act.category) ~= 4 then
		return false, 'UNRELATED_ACTOR_OR_CATEGORY'
	end
	if tonumber(act.param) ~= tonumber(pending.spell_id) then
		return false, 'SPELL_MISMATCH'
	end
	local kind, message_id, amount = target_result(act, pending.target_id)
	if kind == 'unrelated_target' then
		return false, 'TARGET_MISMATCH'
	end
	if kind == 'damage' then
		state.weak_element = pending.element
		state.spike_mode = pending.element == 'water' and 'blaze' or 'wind'
		state.element_source = 'confirmed_from_damage'
		state.last_correct_element_hit_at = now
		state.last_correct_element_spell = pending.spell_name
		transition(
			('%s confirmed by damage'):format(pending.element),
			'KEI_ELEMENT_CONFIRMED',
			{ element = pending.element, spell = pending.spell_name, message_id = message_id, amount = amount }
		)
	elseif kind == 'absorbed' then
		local contradicted = pending.element
		local inferred = other_element(pending.element)
		state.weak_element = inferred
		state.spike_mode = inferred == 'water' and 'blaze' or 'wind'
		state.element_source = 'inferred_from_absorption'
		state.last_correct_element_hit_at = nil
		state.last_correct_element_spell = ''
		transition(
			('%s contradicted by explicit absorption; inferred %s'):format(contradicted, inferred),
			'KEI_ELEMENT_CONTRADICTED',
			{ contradicted = contradicted, inferred = inferred, spell = pending.spell_name, message_id = message_id, amount = amount }
		)
	elseif kind == 'interrupted' then
		transition(
			pending.spell_name .. ' interrupted; element unchanged',
			'KEI_SPELL_INTERRUPTED',
			{ spell = pending.spell_name }
		)
	else
		transition(
			pending.spell_name .. ' result ambiguous; element unchanged',
			'KEI_SPELL_AMBIGUOUS',
			{ spell = pending.spell_name, message_id = message_id, amount = amount }
		)
	end
	state.pending_spell = nil
	return true, kind
end

local function consume_fullers(now, phase)
	local threshold = next_threshold(state.fullers.consumed)
	if threshold == nil then
		return false
	end
	state.fullers.consumed[threshold] = true
	state.fullers.next_threshold = next_threshold(state.fullers.consumed)
	state.fullers.prearmed = false
	transition(
		('Dancing Fullers %s; threshold %d consumed'):format(phase, threshold),
		'KEI_FULLERS_THRESHOLD_CONSUMED',
		{ threshold = threshold, phase = phase, observed_at = now }
	)
	return true
end

function M.on_action(act, now)
	if type(act) ~= 'table' then
		error('uc_kei_encounter.on_action requires act')
	end
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('uc_kei_encounter.on_action requires now')
	end
	if state.enabled ~= true or state.boss == nil then
		return false, 'KEI_UNRESOLVED'
	end
	state.last_observed_at = observed_at
	observe_local_spell_result(act, observed_at)
	if tonumber(act.actor_id) ~= tonumber(state.boss.id) then
		return false, 'UNRELATED_ACTOR'
	end
	local category = tonumber(act.category) or 0
	if category == 4 then
		local spell = res.spells and res.spells[tonumber(act.param) or 0] or nil
		local element = tonumber(spell and spell.element)
		if element ~= 0 and element ~= 2 then
			return false, 'KEI_SPELL_ELEMENT_NOT_TRACKED'
		end
		local completed = false
		for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
			local kind = target_result(act, tonumber(target and target.id) or 0)
			if kind == 'damage' or kind == 'absorbed' then
				completed = true
				break
			end
		end
		if not completed then
			return false, 'KEI_SPELL_NOT_SUCCESSFUL'
		end
		local spell_name = tostring(spell and spell.en or '')
		if element == 0 then
			set_expected('blaze', 'water', observed_at, spell_name)
		else
			set_expected('wind', 'ice', observed_at, spell_name)
		end
		return true, 'KEI_SPELL_MODE_INFERRED'
	end
	local ability_name = ''
	if category == 7 or category == 11 then
		ability_name = ability_name_from_action(act, category)
	elseif category == 6 then
		ability_name = job_ability_name_from_action(act, category)
	end
	if ability_name == 'Dancing Fullers' then
		if category == 7 then
			if state.fullers.in_progress ~= true then
				state.fullers.in_progress = true
				consume_fullers(observed_at, 'readied')
			end
			return true, 'FULLERS_READIED'
		end
		if state.fullers.in_progress ~= true
			and (tonumber(state.fullers.last_completed_at) or 0) > 0
			and (observed_at - state.fullers.last_completed_at) <= 2.0 then
			return true, 'FULLERS_DUPLICATE_COMPLETION'
		end
		if state.fullers.in_progress ~= true then
			consume_fullers(observed_at, 'completed_without_ready')
		end
		state.fullers.in_progress = false
		state.fullers.last_completed_at = observed_at
		update_prearm()
		return true, 'FULLERS_COMPLETED'
	end
	if ability_name == 'Benediction' then
		state.last_benediction_at = observed_at
		transition('Benediction observed', 'KEI_BENEDICTION_OBSERVED', { observed_at = observed_at })
		return true, 'BENEDICTION_OBSERVED'
	end
	return false, 'KEI_ACTION_NOT_TRACKED'
end

function M.note_spell_dispatched(proposal, now, player_id)
	if type(proposal) ~= 'table' or type(proposal.detail) ~= 'table'
		or proposal.detail.kei_elemental ~= true then
		return false, 'NOT_KEI_ELEMENTAL'
	end
	if state.boss == nil or tonumber(proposal.target_id) ~= tonumber(state.boss.id) then
		return false, 'KEI_TARGET_MISMATCH'
	end
	if state.pending_spell ~= nil then
		return false, 'KEI_SPELL_ALREADY_PENDING'
	end
	local spell = spell_by_name(tostring(proposal.action_name or ''))
	if spell == nil then
		error('dispatched Kei spell resource is unresolved: ' .. tostring(proposal.action_name))
	end
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('uc_kei_encounter.note_spell_dispatched requires now')
	end
	state.player_id = tonumber(player_id) or state.player_id
	state.last_observed_at = observed_at
	state.pending_spell = {
		spell_name = tostring(spell.en),
		spell_id = tonumber(spell.id),
		target_id = tonumber(state.boss.id),
		element = tostring(proposal.detail.kei_element or ''),
		purpose = tostring(proposal.detail.kei_purpose or ''),
		dispatched_at = observed_at,
		expires_at = observed_at + state.config.probe_timeout_s,
	}
	transition(
		('%s %s dispatched'):format(state.pending_spell.element, state.pending_spell.purpose),
		'KEI_ELEMENTAL_DISPATCHED',
		copy(state.pending_spell)
	)
	return true, 'PENDING_RECORDED'
end

function M.expire_pending(now)
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('uc_kei_encounter.expire_pending requires now')
	end
	if type(state.pending_spell) == 'table' and observed_at >= state.pending_spell.expires_at then
		state.last_observed_at = observed_at
		local spell_name = state.pending_spell.spell_name
		state.pending_spell = nil
		transition(spell_name .. ' timed out; element unchanged', 'KEI_PROBE_TIMEOUT', { spell = spell_name })
		return true
	end
	return false
end

function M.observe_boss_defeat(target_id)
	if state.boss == nil or tonumber(target_id) ~= tonumber(state.boss.id) then
		return false, 'UNRELATED_TARGET'
	end
	clear_combat('kei_defeated_action_message')
	return true, 'KEI_DEFEATED'
end

function M.reset(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('uc_kei_encounter.reset requires a non-empty reason')
	end
	clear_combat(reason)
end

function M.snapshot()
	local snapshot = copy(state)
	if snapshot.config ~= nil then
		snapshot.elemental_dealer_name = snapshot.config.dealer_name
		snapshot.sustain_interval_s = snapshot.config.sustain_interval_s
		snapshot.probe_timeout_s = snapshot.config.probe_timeout_s
	end
	return snapshot
end

function M.spell_for(element, purpose)
	if state.config == nil then
		return nil
	end
	local field = tostring(element) .. '_' .. tostring(purpose) .. '_spell'
	local value = state.config[field]
	if type(value) ~= 'string' or value == '' then
		error('unsupported Kei spell selection: ' .. field)
	end
	return value
end

M.FULLERS_THRESHOLDS = FULLERS_THRESHOLDS
M.classify_magic_result = classify_magic_result

return M
