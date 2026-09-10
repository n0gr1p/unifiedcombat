local M = {}

local REACTION_PRIORITY_BAND = 240

local function require_function(deps, name)
    local value = deps[name]
    if type(value) ~= 'function' then
        error(('uc_combat_extensions_sequence deps.%s must be a function'):format(name))
    end
    return value
end

local function spell_resource(name)
    local res = require('resources')
    if type(res.spells) ~= 'table' or type(res.spells.with) ~= 'function' then
        return nil
    end
    return res.spells:with('en', tostring(name or ''))
end

local function ja_resource(name)
    local res = require('resources')
    if type(res.job_abilities) ~= 'table' or type(res.job_abilities.with) ~= 'function' then
        return nil
    end
    return res.job_abilities:with('en', tostring(name or ''))
end

local function append_sequence_action(out, ctx, action_lock, action_ready, action_effective_range)
    local action_type = tostring(action_lock.action_type or ''):lower()
    local action_name = tostring(action_lock.action_name or '')
    local action_target = tostring(action_lock.action_target or ''):lower()
    local player = type(ctx.player) == 'table' and ctx.player or {}
    local target_id
    local target_name
    local target_kind
    local range_max = 10.0

    if action_target == 'self' then
        target_id = tonumber(player.id) or 0
        target_name = tostring(player.name or '')
        target_kind = 'self'
    elseif action_target == 'actor' then
        target_id = tonumber(action_lock.actor_id) or 0
        target_name = tostring(action_lock.actor_name or action_lock.name or '')
        target_kind = 'mob'
    else
        return false, 'invalid_target'
    end
    if target_id <= 0 then
        return false, 'target_unavailable'
    end

    local ready, ready_reason, ready_kind = action_ready(action_name, target_id)
    if ready ~= true or tostring(ready_kind or '') ~= action_type then
        return false, tostring(ready_reason or 'not_ready')
    end

    if action_type == 'spell' then
        local spell = spell_resource(action_name)
        if not spell then
            return false, 'spell_unresolved'
        end
        range_max = tonumber(action_effective_range(spell.range)) or 0
    elseif action_type == 'ja' then
        local ability = ja_resource(action_name)
        if not ability then
            return false, 'ability_unresolved'
        end
        if target_kind == 'mob' then
            range_max = tonumber(action_effective_range(ability.range)) or 0
        end
    else
        return false, 'unsupported_action_type'
    end

    local command_kind = action_type == 'spell' and 'ma' or 'ja'
    local command_target = target_kind == 'self' and '<me>' or tostring(target_id)
    out[#out + 1] = {
        proposal_id = ('combat.reaction.sequence.%d.%s.%d.%d'):format(
            tonumber(action_lock.step_index) or 1,
            action_name,
            target_id,
            math.floor((tonumber(ctx.now) or 0) * 1000)
        ),
        family_id = 'combat.reaction.sequence',
        provider = 'combat',
        action_type = action_type,
        action_name = action_name,
        target_kind = target_kind,
        target_id = target_id,
        target_name = target_name,
        priority_band = REACTION_PRIORITY_BAND,
        urgency = 1.0,
        starvation_eligible = false,
        created_at = ctx.now,
        expires_at = ctx.now + 0.30,
        commit_deadline = ctx.now + 0.20,
        movement_policy = 'must_stop',
        range_policy = { min = 0.0, max = range_max, los_required = target_kind == 'mob' },
        recast_key = ('%s:%s'):format(action_type, action_name),
        duplicate_suppression_key = ('reaction_sequence:%s:%d:%s:%d'):format(
            tostring(action_lock.key or ''),
            tonumber(action_lock.step_index) or 1,
            action_name,
            target_id
        ),
        lock_class = 'offense_action',
        expected_ack = action_type == 'spell' and 'action_start' or 'action_start',
        expected_effect = action_type == 'spell' and 'spell_effect' or 'ja_effect',
        sticky = false,
        can_preempt_movement = true,
        can_preempt_same_band = true,
        reason_code = 'reaction_sequence',
        detail = {
            allow_target_id_send = true,
            reaction_name = tostring(action_lock.name or ''),
            reaction_key = tostring(action_lock.key or ''),
            reaction_step_index = tonumber(action_lock.step_index) or 1,
            reaction_step_count = tonumber(action_lock.step_count) or 0,
            reaction_step_optional = action_lock.action_optional == true,
        },
        legacy_command = ('input /%s "%s" %s'):format(command_kind, action_name, command_target),
    }
    return true, 'ready'
end

function M.wrap(base)
    if type(base) ~= 'table' or type(base.new) ~= 'function' then
        error('uc_combat_extensions_sequence requires base combat extensions')
    end
    local original_new = base.new
    local wrapped = {}
    for key, value in pairs(base) do
        wrapped[key] = value
    end

    function wrapped.new(deps)
        local action_ready = require_function(deps, 'action_ready')
        local action_effective_range = require_function(deps, 'action_effective_range')
        local api = original_new(deps)
        local original_collect = api.collect_priority_offense
        if type(original_collect) ~= 'function' then
            error('base combat extensions missing collect_priority_offense')
        end

        function api.collect_priority_offense(ctx, out)
            local reaction_runtime = require('uc_reaction_runtime')
            local action_lock = reaction_runtime.get_action_lock()
            if type(action_lock) == 'table' and tostring(action_lock.response or '') == 'use_sequence' then
                local guard = tonumber(action_lock.step_count) or 1
                if guard < 1 then guard = 1 end
                for _ = 1, guard do
                    action_lock = reaction_runtime.get_action_lock()
                    if type(action_lock) ~= 'table' or tostring(action_lock.response or '') ~= 'use_sequence' then
                        return true
                    end
                    if tostring(action_lock.step_state or '') == 'dispatched' then
                        return true
                    end
                    local appended, reason = append_sequence_action(
                        out,
                        ctx,
                        action_lock,
                        action_ready,
                        action_effective_range
                    )
                    if appended then
                        return true
                    end
                    if action_lock.action_optional == true then
                        local next_lock = reaction_runtime.skip_optional_step(action_lock.key, reason)
                        if type(next_lock) ~= 'table' then
                            return true
                        end
                    else
                        -- Required terminal work is never skipped. Keep the sequence
                        -- lane reserved and retry while the enemy ability window lives.
                        return true
                    end
                end
                return true
            end
            return original_collect(ctx, out)
        end

        return api
    end

    return wrapped
end

return M
