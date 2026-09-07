local base = require('uc_provider_combat_base')
local reaction_runtime = require('uc_reaction_runtime')
local combat_core = require('unified_combat_core')
local skillchain_elements = require('uc_skillchain_elements')
local res = require('resources')

local M = {}

local function active_config()
    local profile = rawget(_G, 'UC_ACTIVE_PROFILE')
    return type(profile) == 'table' and type(profile.config) == 'table' and profile.config or {}
end

local function auto_engage_enabled()
    local combat = active_config().combat
    if type(combat) ~= 'table' or combat.auto_engage == nil then return true end
    return combat.auto_engage == true
end

local function configured_burst_spell()
    local spells = active_config().spells
    if type(spells) ~= 'table' or spells.magic_burst ~= true then return nil end
    local name = tostring(spells.configured or ''):match('^%s*(.-)%s*$')
    if name == '' then return nil end
    return res.spells:with('en', name)
end

local function spell_element(spell)
    if type(spell) ~= 'table' then return '' end
    if type(spell.element) == 'string' then return spell.element end
    local element = res.elements and res.elements[tonumber(spell.element) or 0] or nil
    return tostring(element and element.en or '')
end

local function append_spell_proposal(out, ctx, id_prefix, family, name, target_id, target_name, band, reason)
    out[#out + 1] = {
        proposal_id = ('%s.%s.%d.%d'):format(id_prefix, name, target_id, math.floor(ctx.now * 1000)),
        family_id = family,
        provider = 'combat',
        action_type = 'spell',
        action_name = name,
        target_kind = 'mob',
        target_id = target_id,
        target_name = target_name,
        priority_band = band,
        urgency = 1,
        starvation_eligible = false,
        created_at = ctx.now,
        expires_at = ctx.now + 0.25,
        commit_deadline = ctx.now + 0.20,
        movement_policy = 'must_stop',
        range_policy = { min = 0.0, max = 20.9, los_required = true },
        recast_key = ('spell:%s'):format(name),
        duplicate_suppression_key = ('%s:%s:%d'):format(family, name, target_id),
        lock_class = 'offense_action',
        expected_ack = 'action_start',
        expected_effect = 'spell_effect',
        sticky = true,
        can_preempt_movement = true,
        can_preempt_same_band = true,
        reason_code = reason,
        detail = { allow_target_id_send = true },
        legacy_command = ('input /ma "%s" %d'):format(name, target_id),
    }
end

function M.new(deps)
    local provider = base.new(deps)
    local base_collect_offense = provider.collect_offense
    local base_collect_engage = provider.collect_engage
    local action_ready = assert(deps.action_ready, 'uc_provider_combat requires action_ready')
    local action_effective_range = assert(deps.action_effective_range, 'uc_provider_combat requires action_effective_range')

    function provider.collect_engage(ctx, out)
        if not auto_engage_enabled() then return end
        return base_collect_engage(ctx, out)
    end

    function provider.collect_offense(ctx, out)
        local before = #out
        local reaction = reaction_runtime.get_action_lock and reaction_runtime.get_action_lock() or nil
        if type(reaction) == 'table' and reaction.action_type == 'spell' then
            local name = tostring(reaction.action_name or '')
            local target_id = tonumber(reaction.actor_id) or 0
            local ready, _, kind = action_ready(name, target_id)
            if ready == true and kind == 'spell' and target_id > 0 then
                append_spell_proposal(out, ctx, 'combat.reaction', 'combat.reaction.action', name,
                    target_id, tostring(reaction.name or ''), 180, 'reaction_action')
                return
            end
        end

        local target = ctx.target_present == true and ctx.target or nil
        if target and (tonumber(target.hpp) or 0) > 0 then
            local spell = configured_burst_spell()
            if spell then
                local state = combat_core.get_skillchain_snapshot(tonumber(target.id) or 0)
                local remaining = state and ((tonumber(state.magic_burst_expires_at) or 0) - ctx.now) or 0
                local property = state and type(state.active_properties) == 'table' and state.active_properties[1] or nil
                if remaining >= 6.0
                    and skillchain_elements.contains(property, spell_element(spell)) then
                    local ready, _, kind = action_ready(spell.en, tonumber(target.id) or 0)
                    if ready == true and kind == 'spell' then
                        append_spell_proposal(out, ctx, 'combat.magic_burst', 'combat.magic_burst', spell.en,
                            tonumber(target.id) or 0, tostring(target.name or ''), 132, 'magic_burst')
                        out[#out].range_policy.max = action_effective_range(spell.range)
                        return
                    end
                end
            end
        end

        base_collect_offense(ctx, out)
        if #out < before then error('combat provider output shrank unexpectedly') end
    end

    return provider
end

return M
