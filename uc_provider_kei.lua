local M = {}

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error('uc_provider_kei requires function dependency: ' .. tostring(name))
	end
	return value
end

local function require_number(deps, name)
	local value = tonumber(deps[name])
	if value == nil then
		error('uc_provider_kei requires numeric dependency: ' .. tostring(name))
	end
	return value
end

local function canonical(value)
	if type(value) ~= 'string' then
		return ''
	end
	return (value:match('^%s*(.-)%s*$') or ''):lower()
end

function M.new(deps)
	if type(deps) ~= 'table' then
		error('uc_provider_kei.new requires dependencies')
	end
	local snapshot = require_function(deps, 'snapshot')
	local spell_for = require_function(deps, 'spell_for')
	local action_ready = require_function(deps, 'action_ready')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local reaction_active = require_function(deps, 'reaction_active')
	local keepalive_priority = require_number(deps, 'keepalive_priority')
	local opportunistic_priority = require_number(deps, 'opportunistic_priority')

	local provider = {}

	local function ready_spell(name, target_id)
		local ready, _, action_kind = action_ready(name, target_id)
		return ready == true and action_kind == 'spell'
	end

	local function emit(out, ctx, state, element, purpose, spell_name, priority_band, urgency)
		out[#out + 1] = {
			proposal_id = ('kei.%s.%s.%d.%d'):format(element, purpose, tonumber(state.boss.id), math.floor(ctx.now * 1000)),
			family_id = 'encounter.kei.elemental',
			provider = 'encounter_kei',
			action_type = 'spell',
			action_name = spell_name,
			target_kind = 'mob',
			target_id = tonumber(state.boss.id),
			target_name = 'Kei',
			priority_band = priority_band,
			urgency = clamp_urgency(urgency),
			starvation_eligible = false,
			created_at = ctx.now,
			expires_at = ctx.now + 0.30,
			commit_deadline = ctx.now + 0.20,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 21.0, los_required = true },
			recast_key = ('spell:%s'):format(spell_name),
			duplicate_suppression_key = ('kei:%s:%d'):format(spell_name, tonumber(state.boss.id)),
			lock_class = 'offense_action',
			expected_ack = 'action_start',
			expected_effect = 'spell_effect',
			sticky = false,
			can_preempt_movement = false,
			can_preempt_same_band = false,
			reason_code = 'kei_' .. purpose,
			detail = {
				allow_target_id_send = true,
				kei_elemental = true,
				kei_element = element,
				kei_purpose = purpose,
			},
			legacy_command = ('input /ma "%s" %d'):format(spell_name, tonumber(state.boss.id)),
		}
	end

	function provider.collect(ctx, out)
		if type(ctx) ~= 'table' or type(out) ~= 'table' then
			error('uc_provider_kei.collect requires ctx and out tables')
		end
		local state = snapshot()
		if state.enabled ~= true or state.phase ~= 'active' or type(state.boss) ~= 'table' then
			return
		end
		if ctx.player_present ~= true or canonical(ctx.player_name) == '' then
			return
		end
		if canonical(ctx.player_name) ~= canonical(state.elemental_dealer_name) then
			return
		end
		if type(state.pending_spell) == 'table' or reaction_active() then
			return
		end
		if type(state.fullers) == 'table' and state.fullers.prearmed == true then
			return
		end
		local element = tostring(state.weak_element or 'unknown')
		if element == 'unknown' then
			local spell_name = spell_for('water', 'probe')
			if ready_spell(spell_name, state.boss.id) then
				emit(out, ctx, state, 'water', 'probe', spell_name, keepalive_priority, 0.75)
			end
			return
		end
		if element ~= 'water' and element ~= 'ice' then
			error('Kei provider received unsupported weak element: ' .. element)
		end
		local last_hit = tonumber(state.last_correct_element_hit_at)
		local interval = tonumber(state.sustain_interval_s)
		if interval == nil then
			error('Kei provider requires sustain_interval_s')
		end
		local remaining = last_hit and ((last_hit + interval) - ctx.now) or 0
		if remaining > 1.25 then
			return
		end
		local damage_spell = spell_for(element, 'damage')
		if ready_spell(damage_spell, state.boss.id) then
			local near_deadline = remaining <= 0.50
			emit(
				out,
				ctx,
				state,
				element,
				near_deadline and 'damage_keepalive' or 'damage',
				damage_spell,
				near_deadline and keepalive_priority or opportunistic_priority,
				near_deadline and 1.0 or 0.55
			)
			return
		end
		if remaining <= 0.50 then
			local probe_spell = spell_for(element, 'probe')
			if ready_spell(probe_spell, state.boss.id) then
				emit(out, ctx, state, element, 'probe_keepalive', probe_spell, keepalive_priority, 1.0)
			end
		end
	end

	return provider
end

return M
