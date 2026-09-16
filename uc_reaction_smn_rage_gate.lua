local extension_config = require('uc_combat_extension_config')

local M = {}

local released_by_actor = {}
local last_transition = 'none'

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function canonical(value)
    return trim(value):lower()
end

local function hold_enabled(rule)
    return type(rule) == 'table'
        and rule.trigger == 'party_action_complete'
        and rule.response == 'use_sequence'
        and rule.once_per_instance == true
        and rule.hold_smn_rage_until_sequence_complete == true
end

local function rule_identity(rule, rule_index)
    return table.concat({
        tostring(tonumber(rule_index) or 0),
        canonical(rule and rule.trigger),
        canonical(rule and rule.source_name),
        canonical(rule and rule.action_type),
        canonical(rule and rule.name),
        canonical(rule and rule.response),
    }, '\031')
end

local function actor_bucket(actor_id, create)
    local id = tonumber(actor_id) or 0
    if id <= 0 then
        return nil
    end
    local bucket = released_by_actor[id]
    if bucket == nil and create then
        bucket = {}
        released_by_actor[id] = bucket
    end
    return bucket
end

local function configured_rule(rule_index)
    local rules = extension_config.reaction_rules()
    local index = tonumber(rule_index) or 0
    local rule = index > 0 and type(rules) == 'table' and rules[index] or nil
    if hold_enabled(rule) then
        return rule, index
    end
    return nil, 0
end

local function lock_rule(lock)
    if type(lock) ~= 'table' then
        return nil, 0
    end
    local rule, index = configured_rule(lock.rule_index)
    if type(rule) ~= 'table' then
        return nil, 0
    end
    if canonical(rule.name) ~= canonical(lock.name)
        or canonical(rule.source_name) ~= canonical(lock.event_actor_name)
        or canonical(rule.action_type) ~= canonical(lock.completed_action_type) then
        return nil, 0
    end
    return rule, index
end

local function mark_released(lock, reason)
    local rule, index = lock_rule(lock)
    local actor_id = tonumber(type(lock) == 'table' and lock.actor_id) or 0
    if type(rule) ~= 'table' or actor_id <= 0 then
        return false
    end
    local bucket = actor_bucket(actor_id, true)
    bucket[rule_identity(rule, index)] = true
    last_transition = ('release:%d:%s:%s'):format(actor_id, tostring(rule.name or ''), tostring(reason or 'complete'))
    return true
end

local function mark_armed(lock)
    local rule, index = lock_rule(lock)
    local actor_id = tonumber(type(lock) == 'table' and lock.actor_id) or 0
    if type(rule) ~= 'table' or actor_id <= 0 then
        return false
    end
    local bucket = actor_bucket(actor_id, false)
    if type(bucket) == 'table' then
        bucket[rule_identity(rule, index)] = nil
        if next(bucket) == nil then
            released_by_actor[actor_id] = nil
        end
    end
    last_transition = ('active:%d:%s'):format(actor_id, tostring(rule.name or ''))
    return true
end

function M.should_hold(actor_id)
    local id = tonumber(actor_id) or 0
    if id <= 0 then
        return false, 'no_target', nil
    end
    local rules = extension_config.reaction_rules()
    if type(rules) ~= 'table' then
        return false, 'no_hold_rule', nil
    end
    local bucket = actor_bucket(id, false)
    local configured = 0
    for i = 1, #rules do
        local rule = rules[i]
        if hold_enabled(rule) then
            configured = configured + 1
            local identity = rule_identity(rule, i)
            if type(bucket) ~= 'table' or bucket[identity] ~= true then
                return true, 'reaction_pretrigger_hold', {
                    actor_id = id,
                    rule_index = i,
                    source_name = trim(rule.source_name),
                    action_type = trim(rule.action_type):lower(),
                    action_name = trim(rule.name),
                }
            end
        end
    end
    if configured > 0 then
        return false, 'reaction_sequence_released', nil
    end
    return false, 'no_hold_rule', nil
end

function M.extend(base)
    if type(base) ~= 'table' then
        error('uc_reaction_smn_rage_gate requires reaction runtime table')
    end
    if base._smn_rage_gate_extension_installed == true then
        return base
    end

    local base_on_action = base.on_action
    local base_cancel = base.cancel
    local base_prune = base.prune_invalid_ability_windows
    local base_reset = base.reset
    local base_status = base.status

    function base.on_action(act, current_target_id, now, actor_is_valid_enemy)
        local result = base_on_action(act, current_target_id, now, actor_is_valid_enemy)
        if type(result) == 'table' then
            if type(result.released) == 'table' then
                mark_released(result.released, result.sequence_step_completed == true and 'sequence_complete' or 'released')
            end
            if type(result.activated) == 'table'
                and tostring(result.activated.trigger or '') == 'party_action_complete' then
                mark_armed(result.activated)
            end
        end
        return result
    end

    function base.cancel(key_value, reason)
        local released, extra = base_cancel(key_value, reason)
        if type(released) == 'table' then
            mark_released(released, reason or 'cancelled')
        end
        return released, extra
    end

    function base.prune_invalid_ability_windows(actor_is_valid_enemy)
        local released = base_prune(actor_is_valid_enemy)
        if type(actor_is_valid_enemy) == 'function' then
            for actor_id in pairs(released_by_actor) do
                if actor_is_valid_enemy(actor_id) ~= true then
                    released_by_actor[actor_id] = nil
                end
            end
        end
        return released
    end

    function base.reset(reason)
        released_by_actor = {}
        last_transition = 'reset:' .. tostring(reason or 'manual')
        return base_reset(reason)
    end

    function base.status()
        local status = base_status()
        local actor_count = 0
        local released_count = 0
        for _, bucket in pairs(released_by_actor) do
            actor_count = actor_count + 1
            for _ in pairs(bucket) do
                released_count = released_count + 1
            end
        end
        status.smn_rage_gate = {
            actor_count = actor_count,
            released_count = released_count,
            last_transition = last_transition,
        }
        return status
    end

    base._smn_rage_gate_extension_installed = true
    return base
end

return M
