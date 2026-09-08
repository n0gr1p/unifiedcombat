local M = {}

local MAGIC_BURST_MIN_WINDOW_S = 6.0
local REACTION_PRIORITY_BAND = 240
local MAGIC_BURST_PRIORITY_BAND = 170

local function require_function(deps, name)
    local value = deps[name]
    if type(value) ~= 'function' then
        error(('uc_combat_extensions deps.%s must be a function'):format(name))
    end
    return value
end

local function extension_config()
    return require('uc_combat_extension_config')
end

local function spell_resource(name)
    local res = require('resources')
    if type(res.spells) ~= 'table' or type(res.spells.with) ~= 'function' then
        return nil
    end
    return res.spells:with('en', tostring(name or ''))
end

local function spell_element(spell)
    if type(spell) ~= 'table' then
        return ''
    end
    if type(spell.element) == 'string' then
        return spell.element
    end
    local res = require('resources')
    local element_id = tonumber(spell.element)
    local element = element_id and res.elements and res.elements[element_id] or nil
    return tostring(element and element.en or '')
end

local function valid_target(target)
    return type(target) == 'table'
        and target.valid_target == true
        and tonumber(target.spawn_type) == 16
        and (tonumber(target.hpp) or 0) > 0
        and (tonumber(target.id) or 0) > 0
end

local function copy_detail(detail)
    local out = { allow_target_id_send = true }
    for key, value in pairs(type(detail) == 'table' and detail or {}) do
        out[key] = value
    end
    return out
end

local function append_spell(out, ctx, options)
    local spell = spell_resource(options.spell_name)
    if not spell then
        return false
    end
    local ok_ready, _, kind = options.action_ready(options.spell_name, options.target_id)
    if ok_ready ~= true or kind ~= 'spell' then
        return false
    end
    local max_range = options.action_effective_range(spell.range)
    out[#out + 1] = {
        proposal_id = ('combat.%s.%s.%d.%d'):format(
            options.id_prefix,
            tostring(options.spell_name),
            tonumber(options.target_id) or 0,
            math.floor((tonumber(ctx.now) or 0) * 1000)
        ),
        family_id = options.family_id,
        provider = 'combat',
        action_type = 'spell',
        action_name = tostring(options.spell_name),
        target_kind = 'mob',
        target_id = tonumber(options.target_id) or 0,
        target_name = tostring(options.target_name or ''),
        priority_band = options.priority_band,
        urgency = options.urgency or 1.0,
        starvation_eligible = false,
        created_at = ctx.now,
        expires_at = ctx.now + 0.30,
        commit_deadline = ctx.now + 0.20,
        movement_policy = 'must_stop',
        range_policy = { min = 0.0, max = max_range, los_required = true },
        recast_key = ('spell:%s'):format(tostring(options.spell_name)),
        duplicate_suppression_key = ('%s:%s:%d'):format(
            options.id_prefix,
            tostring(options.spell_name),
            tonumber(options.target_id) or 0
        ),
        lock_class = 'offense_action',
        expected_ack = 'action_start',
        expected_effect = 'spell_effect',
        sticky = false,
        can_preempt_movement = true,
        can_preempt_same_band = true,
        reason_code = options.reason_code,
        detail = copy_detail(options.detail),
        legacy_command = ('input /ma \"%s\" %d'):format(
            tostring(options.spell_name),
            tonumber(options.target_id) or 0
        ),
    }
    return true
end

local function action_reaction_configured(rules)
    if type(rules) ~= 'table' then
        return false
    end
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == 'table' and rule.response == 'use_action' then
            return true
        end
    end
    return false
end

function M.new(deps)
    local action_ready = require_function(deps, 'action_ready')
    local action_effective_range = require_function(deps, 'action_effective_range')
    local api = {}

    function api.auto_engage_enabled(settings)
        return extension_config().auto_engage_enabled(settings)
    end

    function api.collect_priority_offense(ctx, out)
        local config = extension_config()
        local reaction_rules = config.reaction_rules()
        if action_reaction_configured(reaction_rules) then
            local reaction_runtime = require('uc_reaction_runtime')
            local action_lock = reaction_runtime.get_action_lock()
            if type(action_lock) == 'table' then
                local action_type = tostring(action_lock.action_type or ''):lower()
                local action_name = tostring(action_lock.action_name or '')
                if action_type == 'spell' and action_name ~= '' then
                    if append_spell(out, ctx, {
                        action_ready = action_ready,
                        action_effective_range = action_effective_range,
                        spell_name = action_name,
                        target_id = tonumber(action_lock.actor_id) or 0,
                        target_name = tostring(action_lock.actor_name or action_lock.name or ''),
                        family_id = 'combat.reaction.action',
                        id_prefix = 'reaction',
                        priority_band = REACTION_PRIORITY_BAND,
                        urgency = 1.0,
                        reason_code = 'reaction_action',
                        detail = {
                            reaction_name = tostring(action_lock.name or ''),
                            reaction_key = tostring(action_lock.key or ''),
                        },
                    }) then
                        return true
                    end
                end
            end
        end

        local burst = config.magic_burst(ctx.settings)
        if burst.enabled ~= true or burst.spell == '' then
            return false
        end
        local target = ctx.target_present == true and ctx.target or nil
        if not valid_target(target) then
            return false
        end
        local combat_core = require('unified_combat_core')
        local state = combat_core.get_skillchain_snapshot(tonumber(target.id) or 0)
        if type(state) ~= 'table' then
            return false
        end
        local mb_expires = tonumber(state.magic_burst_expires_at) or 0
        local remaining = mb_expires - (tonumber(ctx.now) or 0)
        if remaining < MAGIC_BURST_MIN_WINDOW_S then
            return false
        end
        local property = tostring(state.last_confirmed_result or '')
        if property == '' and type(state.active_properties) == 'table' then
            property = tostring(state.active_properties[1] or '')
        end
        if property == '' then
            return false
        end
        local spell = spell_resource(burst.spell)
        if not spell then
            return false
        end
        local element = spell_element(spell)
        local skillchain_elements = require('uc_skillchain_elements')
        if element == '' or not skillchain_elements.contains(property, element) then
            return false
        end
        return append_spell(out, ctx, {
            action_ready = action_ready,
            action_effective_range = action_effective_range,
            spell_name = burst.spell,
            target_id = tonumber(target.id) or 0,
            target_name = tostring(target.name or ''),
            family_id = 'combat.magic_burst',
            id_prefix = 'magic_burst',
            priority_band = MAGIC_BURST_PRIORITY_BAND,
            urgency = 1.0 - math.min(1.0, remaining / 10.0),
            reason_code = 'magic_burst_window',
            detail = {
                skillchain_property = property,
                spell_element = element,
                magic_burst_expires_at = mb_expires,
                window_remaining_s = remaining,
            },
        })
    end

    return api
end

return M
