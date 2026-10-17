local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_recurring_spells %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_recurring_spells deps.%s must be a function'):format(name))
	end
	return value
end

local function require_number(deps, name)
	local value = tonumber(deps[name])
	if value == nil then
		error(('uc_provider_recurring_spells deps.%s must be numeric'):format(name))
	end
	return value
end

local function valid_enemy_target(target)
	return type(target) == 'table'
		and target.valid_target == true
		and tonumber(target.spawn_type) == 16
		and (tonumber(target.hpp) or 0) > 0
		and (tonumber(target.id) or 0) > 0
end

local function spell_targets_enemy(spell)
	local targets = spell and spell.targets
	if type(targets) == 'number' then
		return (math.floor(targets) % 64) >= 32
	end
	if type(targets) == 'table' then
		return targets.Enemy == true or targets.enemy == true
	end
	return tostring(targets or ''):find('Enemy', 1, true) ~= nil
end

local function configured_names(raw)
	local source = raw
	if type(source) == 'string' then
		source = {}
		for token in raw:gmatch('[^|,]+') do
			source[#source + 1] = token
		end
	end
	if source == nil then
		return {}
	end
	if type(source) ~= 'table' then
		error('config.combat.recurring_spells.list must be a list or pipe-delimited string')
	end
	local out = {}
	local seen = {}
	for i = 1, #source do
		local name = tostring(source[i] or ''):match('^%s*(.-)%s*$') or ''
		if name ~= '' then
			local key = name:lower()
			if seen[key] then
				error('config.combat.recurring_spells.list contains duplicate spell: ' .. name)
			end
			seen[key] = true
			out[#out + 1] = name
		end
	end
	return out
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local get_spell_resource = require_function(deps, 'get_spell_resource')
	local action_ready = require_function(deps, 'action_ready')
	local action_effective_range = require_function(deps, 'action_effective_range')
	local build_friendly_claims = require_function(deps, 'build_friendly_claims')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local combat_domain_enabled = require_function(deps, 'combat_domain_enabled')
	local timeline_log = require_function(deps, 'action_timeline_log')
	local priority_band = require_number(deps, 'priority_band')

	local provider = {}

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then return end
		if not combat_domain_enabled() then return end

		local config = type(ctx.config) == 'table' and ctx.config or {}
		local combat = type(config.combat) == 'table' and config.combat or {}
		local recurring_config = type(combat.recurring_spells) == 'table' and combat.recurring_spells or {}
		if not bool_setting(recurring_config.enabled, false) then return end

		local names = configured_names(recurring_config.list)
		if #names == 0 then
			error('Recurring combat spells are enabled but no spells are configured')
		end

		if ctx.player_present ~= true then return end
		local target = ctx.target
		if ctx.target_present ~= true or not valid_enemy_target(target) then return end
		local _, friendly_claim_set = build_friendly_claims(ctx)
		if type(friendly_claim_set) ~= 'table' then
			error('Recurring combat spell friendly claim builder must return a claim set table')
		end
		local claim_id = tonumber(target.claim_id) or 0
		if claim_id <= 0 or friendly_claim_set[claim_id] ~= true then return end
		local target_id = tonumber(target.id) or 0

		for index, spell_name in ipairs(names) do
			local spell = get_spell_resource(spell_name)
			if type(spell) ~= 'table' then
				error(('Recurring combat spell %q is not present in resources'):format(spell_name))
			end
			if not spell_targets_enemy(spell) then
				error(('Recurring combat spell %q does not target enemies'):format(spell_name))
			end
			local ready, _, kind = action_ready(tostring(spell.en or spell_name), target_id)
			if ready == true and tostring(kind or '') == 'spell' then
				local action_name = tostring(spell.en or spell_name)
				local max_range = tonumber(action_effective_range(spell.range)) or 0
				if max_range <= 0 then max_range = 20.0 end
				out[#out + 1] = {
					proposal_id = ('combat.recurring_spell.%s.%d.%d'):format(
						action_name,
						target_id,
						math.floor((tonumber(ctx.now) or 0) * 1000)
					),
					family_id = 'combat.recurring_spell.primary',
					provider = 'combat',
					action_type = 'spell',
					action_name = action_name,
					target_kind = 'mob',
					target_id = target_id,
					target_name = tostring(target.name or ''),
					priority_band = priority_band,
					urgency = clamp_urgency(0.40),
					starvation_eligible = true,
					created_at = ctx.now,
					expires_at = ctx.now + 0.30,
					commit_deadline = ctx.now + 0.20,
					movement_policy = 'must_stop',
					range_policy = { min = 0.0, max = max_range, los_required = true },
					recast_key = ('spell:%s'):format(action_name),
					duplicate_suppression_key = ('recurring_spell:%s:%d'):format(action_name, target_id),
					lock_class = 'offense_action',
					expected_ack = 'action_start',
					expected_effect = 'spell_effect',
					sticky = false,
					can_preempt_movement = true,
					can_preempt_same_band = false,
					reason_code = 'recurring_spell_ready',
					detail = {
						allow_target_id_send = true,
						require_current_target = true,
						require_friendly_claim = true,
						recurring_spell = true,
						configured_index = index,
					},
					legacy_command = ('input /ma "%s" %d'):format(action_name, target_id),
				}
				timeline_log('RECURRING_SPELL_PROPOSED', {
					spell = action_name,
					target = tostring(target.name or ''),
					target_id = target_id,
					configured_index = index,
					band = priority_band,
				}, ('recurring_spell:%s:%d'):format(action_name, target_id), 0.25)
				return
			end
		end
	end

	provider.configured_names = configured_names
	return provider
end

return M
