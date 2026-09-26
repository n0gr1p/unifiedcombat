local M = {}

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error('uc_provider_saved_by_bell requires function dependency: ' .. tostring(name))
	end
	return value
end

function M.new(deps)
	if type(deps) ~= 'table' then
		error('uc_provider_saved_by_bell.new requires dependencies')
	end
	local snapshot = require_function(deps, 'snapshot')
	local action_ready = require_function(deps, 'action_ready')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local get_mob_by_id = require_function(deps, 'get_mob_by_id')
	local priority_band = tonumber(deps.priority_band) or 140

	local provider = {}

	local function live_luopans(state)
		local out = {}
		for id, row in pairs(state.luopans or {}) do
			local target_id = tonumber(id) or tonumber(row and row.id) or 0
			if target_id > 0 and type(row) == 'table' then
				local mob = get_mob_by_id(target_id)
				if type(mob) == 'table'
					and tostring(mob.name or '') == 'Luopan'
					and (tonumber(mob.hpp) or 0) > 0
					and mob.valid_target ~= false then
					out[#out + 1] = {
						id = target_id,
						row = row,
						mob = mob,
					}
				end
			end
		end
		table.sort(out, function(left, right)
			local left_at = tonumber(left.row.bound_at) or 0
			local right_at = tonumber(right.row.bound_at) or 0
			if left_at ~= right_at then
				return left_at < right_at
			end
			return left.id < right.id
		end)
		return out
	end

	local function ready_spell(row, target_id)
		for i = 1, #(row.weakness_spells or {}) do
			local spell_name = tostring(row.weakness_spells[i] or '')
			if spell_name ~= '' then
				local ready, _, action_kind = action_ready(spell_name, target_id)
				if ready == true and action_kind == 'spell' then
					return spell_name
				end
			end
		end
		return nil
	end

	function provider.collect(ctx, out)
		if type(ctx) ~= 'table' or type(out) ~= 'table' then
			error('uc_provider_saved_by_bell.collect requires ctx and out tables')
		end
		local state = snapshot()
		if state.enabled ~= true or state.phase ~= 'active' or type(state.boss) ~= 'table' then
			return
		end
		for _, candidate in ipairs(live_luopans(state)) do
			local spell_name = ready_spell(candidate.row, candidate.id)
			if spell_name ~= nil then
				local age = math.max(0, (tonumber(ctx.now) or 0) - (tonumber(candidate.row.bound_at) or tonumber(ctx.now) or 0))
				out[#out + 1] = {
					proposal_id = ('saved_bell.%d.%s.%d'):format(
						candidate.id,
						spell_name:lower():gsub('[^%w]+', '_'),
						math.floor((tonumber(ctx.now) or 0) * 1000)
					),
					family_id = 'encounter.saved_by_the_bell.luopan',
					provider = 'encounter_saved_by_bell',
					action_type = 'spell',
					action_name = spell_name,
					target_kind = 'mob',
					target_id = candidate.id,
					target_name = 'Luopan',
					priority_band = priority_band,
					urgency = clamp_urgency(math.min(1.0, 0.80 + (age / 20.0))),
					starvation_eligible = false,
					created_at = ctx.now,
					expires_at = ctx.now + 0.30,
					commit_deadline = ctx.now + 0.20,
					movement_policy = 'must_stop',
					range_policy = { min = 0.0, max = 21.0, los_required = true },
					recast_key = ('spell:%s'):format(spell_name),
					duplicate_suppression_key = ('saved_bell:%d:%s'):format(candidate.id, spell_name),
					lock_class = 'offense_action',
					expected_ack = 'action_start',
					expected_effect = 'spell_effect',
					sticky = false,
					can_preempt_movement = false,
					can_preempt_same_band = false,
					reason_code = 'saved_bell_luopan_weakness',
					detail = {
						allow_target_id_send = true,
						saved_by_bell = true,
						geo_spell = candidate.row.geo_spell,
						weakness_spell = spell_name,
						luopan_id = candidate.id,
					},
					legacy_command = ('input /ma "%s" %d'):format(spell_name, candidate.id),
				}
				return
			end
		end
	end

	return provider
end

return M
