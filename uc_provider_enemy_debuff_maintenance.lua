local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_enemy_debuff_maintenance %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_enemy_debuff_maintenance deps.%s must be a function'):format(name))
	end
	return value
end

local function spell_targets_enemy(spell)
	local targets = spell and spell.targets
	if type(targets) == 'number' then
		return targets == 32
	end
	if type(targets) == 'table' then
		return targets.Enemy == true or targets.enemy == true
	end
	return tostring(targets or ''):find('Enemy', 1, true) ~= nil
end

local function spell_overwrites(spell, action_id)
	local wanted = tonumber(action_id) or 0
	for _, overwritten_id in ipairs((spell and spell.overwrites) or {}) do
		if tonumber(overwritten_id) == wanted then
			return true
		end
	end
	return false
end

local function normalized_actions(raw, get_spell_resource)
	local actions = {}
	local seen_effects = {}
	for token in tostring(raw or ''):gmatch('[^|,]+') do
		local action_name = tostring(token):gsub('^%s+', ''):gsub('%s+$', '')
		if action_name ~= '' then
			local spell = get_spell_resource(action_name)
			if type(spell) ~= 'table' then
				error(('Enemy debuff maintenance spell %q is not present in resources'):format(action_name))
			end
			if not spell_targets_enemy(spell) then
				error(('Enemy debuff maintenance spell %q does not target enemies'):format(action_name))
			end
			local effect_id = tonumber(spell.status) or 0
			if effect_id <= 0 then
				error(('Enemy debuff maintenance spell %q has no authoritative status id'):format(action_name))
			end
			if seen_effects[effect_id] then
				error(('Enemy debuff maintenance spells %q and %q share status effect %d'):format(
				seen_effects[effect_id],
				tostring(spell.en or action_name),
				effect_id
			))
			end
			local row = {
				name = tostring(spell.en or action_name),
				action_id = tonumber(spell.id) or 0,
				effect_id = effect_id,
				spell = spell,
				order = #actions + 1,
			}
			if row.action_id <= 0 then
				error(('Enemy debuff maintenance spell %q has no authoritative action id'):format(action_name))
			end
			for _, existing in ipairs(actions) do
				if spell_overwrites(row.spell, existing.action_id)
					or spell_overwrites(existing.spell, row.action_id) then
					error(('Enemy debuff maintenance spells %q and %q overwrite one another'):format(
					existing.name,
					row.name
				))
				end
			end
			actions[#actions + 1] = row
			seen_effects[effect_id] = row.name
		end
	end
	return actions
end

local function observed_satisfies(desired, observed, get_spell_by_id)
	if type(observed) ~= 'table' then
		return false, 'MISSING'
	end
	local observed_action_id = tonumber(observed.action_id) or 0
	if observed_action_id <= 0 then
		return true, 'UNKNOWN_IDENTITY_BLOCKED'
	end
	if observed_action_id == desired.action_id then
		return true, 'EXACT'
	end
	local observed_spell = get_spell_by_id(observed_action_id)
	if type(observed_spell) ~= 'table' then
		error(('Observed enemy effect action id %d is absent from spell resources'):format(observed_action_id))
	end
	if tonumber(observed_spell.status) ~= desired.effect_id then
		error(('Observed action %d status does not match tracked effect %d'):format(
			observed_action_id,
			desired.effect_id
		))
	end
	if spell_overwrites(observed_spell, desired.action_id) then
		return true, 'STRONGER'
	end
	return false, 'WEAKER'
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local active_value_or_flat = require_function(deps, 'active_value_or_flat')
	local get_spell_resource = require_function(deps, 'get_spell_resource')
	local get_spell_by_id = require_function(deps, 'get_spell_by_id')
	local build_friendly_claims = require_function(deps, 'build_friendly_claims')
	local claim_valid = require_function(deps, 'claim_valid')
	local effect_map = require_function(deps, 'effect_map')
	local prune_expired = require_function(deps, 'prune_expired')
	local can_attempt = require_function(deps, 'can_attempt')
	local action_ready = require_function(deps, 'action_ready')
	local build_action_command = require_function(deps, 'build_action_command')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local log = require_function(deps, 'log')

	local provider = {}

	function provider.collect(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(active_value_or_flat(
			'config.defensive.enemy_debuffs.enabled',
			ctx.settings.def_maintain_enemy_debuffs
		), false) then
			return
		end
		if not bool_setting(active_value_or_flat(
			'config.defensive.enabled',
			ctx.settings.defensive_enabled
		), false) then
			return
		end

		local configured = active_value_or_flat(
			'config.defensive.enemy_debuffs.list',
			ctx.settings.defensive_enemy_debuffs
		)
		local actions = normalized_actions(configured, get_spell_resource)
		if #actions == 0 then
			error('Enemy debuff maintenance is enabled but no debuffs are configured')
		end

		prune_expired(ctx.now)
		local tracked = effect_map()
		local _, claims_set = build_friendly_claims()
		local preferred_target_id = tonumber(ctx.target_id_snapshot) or 0

		for _, action in ipairs(actions) do
			local ready, ready_reason, action_kind = action_ready(action.name, 0)
			if action_kind ~= 'spell' then
				error(('Enemy debuff maintenance action %q did not resolve as a spell'):format(action.name))
			end
			if ready then
				local best = nil
				for _, mob in pairs(ctx.mobs_by_id) do
					local target_id = tonumber(mob and mob.id) or 0
					local distance = mob and mob.distance and mob.distance:sqrt() or 999
					if target_id > 0
						and mob.valid_target == true
						and tonumber(mob.spawn_type) == 16
						and (tonumber(mob.hpp) or 0) > 0
						and claim_valid(mob.claim_id, claims_set)
						and distance <= 20.9 then
						local observed = type(tracked[target_id]) == 'table'
							and tracked[target_id][action.effect_id]
							or nil
						local satisfied, evidence = observed_satisfies(action, observed, get_spell_by_id)
						if satisfied then
							log(('ENEMY_DEBUFF_PRESENT action="%s" target="%s" evidence=%s'):format(
								action.name,
								tostring(mob.name or ''),
								evidence
							))
						else
							local attempt_ok, attempt_key = can_attempt(
								action.name,
								target_id,
								action.effect_id,
								ctx.now
							)
							if attempt_ok then
								local pick = {
									target_id = target_id,
									target_name = tostring(mob.name or ''),
									distance = distance,
									preferred = target_id == preferred_target_id,
									attempt_key = attempt_key,
									evidence = evidence,
								}
								if not best
									or (pick.preferred and not best.preferred)
									or (pick.preferred == best.preferred and pick.distance < best.distance)
									or (pick.preferred == best.preferred and pick.distance == best.distance
										and pick.target_id < best.target_id) then
									best = pick
								end
							else
								log(('ENEMY_DEBUFF_BLOCK action="%s" target="%s" reason=ATTEMPT_GATE'):format(
									action.name,
									tostring(mob.name or '')
								))
							end
						end
					end
				end
				if best then
					local target = {
						id = best.target_id,
						name = best.target_name,
						is_self = false,
						is_mob = true,
					}
					out[#out + 1] = {
						proposal_id = ('def.enemy_debuff.%s.%d.%d'):format(
							action.name,
							best.target_id,
							math.floor(ctx.now * 1000)
						),
						family_id = 'def.enemy_debuff.primary',
						provider = 'defensive_internal',
						action_type = 'spell',
						action_name = action.name,
						target_kind = 'mob',
						target_id = best.target_id,
						target_name = best.target_name,
						priority_band = 99,
						urgency = clamp_urgency(0.60),
						starvation_eligible = true,
						created_at = ctx.now,
						expires_at = ctx.now + 0.40,
						commit_deadline = ctx.now + 0.25,
						movement_policy = 'must_stop',
						range_policy = { min = 0.0, max = 20.9, los_required = true },
						recast_key = ('spell:%s'):format(action.name),
						duplicate_suppression_key = ('enemy_debuff:%s:%d'):format(action.name, best.target_id),
						lock_class = 'support_action',
						expected_ack = 'action_start',
						expected_effect = 'enemy_debuff_gain',
						sticky = false,
						can_preempt_movement = true,
						can_preempt_same_band = false,
						reason_code = 'enemy_debuff_maintain',
						detail = {
							def_action_type = 'enemy_debuff',
							enemy_debuff_effect_id = action.effect_id,
							enemy_debuff_action_id = action.action_id,
							enemy_debuff_attempt_key = best.attempt_key,
							enemy_debuff_evidence = best.evidence,
						},
						legacy_command = build_action_command(action.name, 'spell', target),
					}
					log(('ENEMY_DEBUFF_EMIT action="%s" target="%s" evidence=%s'):format(
						action.name,
						best.target_name,
						best.evidence
					))
					return
				end
			else
				log(('ENEMY_DEBUFF_BLOCK action="%s" reason=%s'):format(action.name, tostring(ready_reason or 'NOT_READY')))
			end
		end
	end

	provider.normalized_actions = function(raw)
		return normalized_actions(raw, get_spell_resource)
	end

	provider.observed_satisfies = function(desired, observed)
		return observed_satisfies(desired, observed, get_spell_by_id)
	end

	return provider
end

return M
