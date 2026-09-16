local res = require('resources')
local extension_config = require('uc_combat_extension_config')
local party_action_event = require('uc_party_action_event')

local M = {}

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function canonical(value)
    return trim(value):lower()
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
    return trim(ability and ability.en)
end

local function matching_ability_rule(name)
    local wanted = canonical(name)
    local rules = extension_config.reaction_rules()
    for i = 1, #(rules or {}) do
        local rule = rules[i]
        if type(rule) == 'table'
            and rule.trigger == 'ability_window'
            and canonical(rule.name) == wanted then
            return rule, i
        end
    end
    return nil, nil
end

local function matching_party_rule(event)
    if type(event) ~= 'table' then
        return nil, nil
    end
    local rules = extension_config.reaction_rules()
    for i = 1, #(rules or {}) do
        local rule = rules[i]
        if type(rule) == 'table'
            and rule.trigger == 'party_action_complete'
            and canonical(rule.action_type) == canonical(event.action_type)
            and canonical(rule.name) == canonical(event.action_name) then
            local source_id = party_action_event.party_member_actor_id(rule.source_name)
            if source_id > 0 and source_id == tonumber(event.actor_id) then
                return rule, i
            end
        end
    end
    return nil, nil
end

local function rule_identity(rule, rule_index)
    return table.concat({
        tostring(tonumber(rule_index) or 0),
        canonical(rule and rule.trigger),
        canonical(rule and rule.source_name),
        canonical(rule and rule.action_type),
        canonical(rule and rule.name),
        canonical(rule and rule.response),
        canonical(rule and rule.action_name),
    }, '\031')
end

function M.extend(base)
    if type(base) ~= 'table' then
        error('uc_reaction_once_runtime requires a reaction runtime table')
    end
    if base._once_per_instance_extension_installed == true then
        return base
    end

    local consumed_by_actor = {}
    local pending_by_lock = {}
    local pending_by_actor = {}

    local base_on_action = base.on_action
    local base_note_sequence_action_dispatched = base.note_sequence_action_dispatched
    local base_cancel = base.cancel
    local base_prune = base.prune_invalid_ability_windows
    local base_reset = base.reset
    local base_status = base.status

    local function actor_bucket(store, actor_id, create)
        local id = tonumber(actor_id) or 0
        if id <= 0 then
            return nil
        end
        local bucket = store[id]
        if bucket == nil and create then
            bucket = {}
            store[id] = bucket
        end
        return bucket
    end

    local function is_consumed(rule, rule_index, actor_id)
        if type(rule) ~= 'table' or rule.once_per_instance ~= true then
            return false
        end
        local bucket = actor_bucket(consumed_by_actor, actor_id, false)
        return type(bucket) == 'table' and bucket[rule_identity(rule, rule_index)] == true
    end

    local function is_pending(rule, rule_index, actor_id)
        if type(rule) ~= 'table' or rule.once_per_instance ~= true then
            return false
        end
        local bucket = actor_bucket(pending_by_actor, actor_id, false)
        return type(bucket) == 'table' and bucket[rule_identity(rule, rule_index)] ~= nil
    end

    local function mark_consumed(rule, rule_index, actor_id)
        if type(rule) ~= 'table' or rule.once_per_instance ~= true then
            return false
        end
        local bucket = actor_bucket(consumed_by_actor, actor_id, true)
        bucket[rule_identity(rule, rule_index)] = true
        return true
    end

    local function clear_pending_lock(lock_key)
        local key = tostring(lock_key or '')
        local pending = pending_by_lock[key]
        if type(pending) ~= 'table' then
            return
        end
        pending_by_lock[key] = nil
        local bucket = actor_bucket(pending_by_actor, pending.actor_id, false)
        if type(bucket) == 'table' then
            bucket[pending.identity] = nil
            if next(bucket) == nil then
                pending_by_actor[tonumber(pending.actor_id) or 0] = nil
            end
        end
    end

    local function register_pending(lock_key, rule, rule_index, actor_id)
        local key = tostring(lock_key or '')
        if key == '' or type(rule) ~= 'table' or rule.once_per_instance ~= true then
            return
        end
        local identity = rule_identity(rule, rule_index)
        clear_pending_lock(key)
        pending_by_lock[key] = {
            actor_id = tonumber(actor_id) or 0,
            identity = identity,
            rule = rule,
            rule_index = rule_index,
        }
        local bucket = actor_bucket(pending_by_actor, actor_id, true)
        bucket[identity] = key
    end

    local function clear_invalid_actor_state(actor_is_valid_enemy)
        for actor_id in pairs(consumed_by_actor) do
            if actor_is_valid_enemy(actor_id) ~= true then
                consumed_by_actor[actor_id] = nil
            end
        end
        local pending_keys = {}
        for key, pending in pairs(pending_by_lock) do
            if actor_is_valid_enemy(tonumber(pending.actor_id) or 0) ~= true then
                pending_keys[#pending_keys + 1] = key
            end
        end
        for i = 1, #pending_keys do
            clear_pending_lock(pending_keys[i])
        end
    end

    local function cleanup_released(result)
        if type(result) == 'table' and type(result.released) == 'table' then
            clear_pending_lock(result.released.key)
        end
    end

    function base.on_action(act, current_target_id, now, actor_is_valid_enemy)
        local category = tonumber(type(act) == 'table' and act.category) or 0
        local event_actor_id = tonumber(type(act) == 'table' and act.actor_id) or 0
        local ability_name = (category == 7 or category == 11) and ability_name_from_action(act, category) or ''
        local rule, rule_index = nil, nil
        local instance_actor_id = 0

        if category == 7 and event_actor_id > 0 and ability_name ~= '' then
            rule, rule_index = matching_ability_rule(ability_name)
            instance_actor_id = event_actor_id
        else
            local event = party_action_event.completed(act)
            if type(event) == 'table' then
                rule, rule_index = matching_party_rule(event)
                instance_actor_id = tonumber(current_target_id) or 0
            end
        end

        if type(rule) == 'table' and rule.once_per_instance == true and instance_actor_id > 0
            and (is_consumed(rule, rule_index, instance_actor_id) or is_pending(rule, rule_index, instance_actor_id)) then
            return {
                once_per_instance_suppressed = true,
                actor_id = instance_actor_id,
                event_actor_id = event_actor_id,
                ability_name = ability_name,
                action_name = trim(rule.name),
                trigger = trim(rule.trigger),
            }
        end

        local result = base_on_action(act, current_target_id, now, actor_is_valid_enemy)
        cleanup_released(result)

        if type(rule) == 'table'
            and rule.once_per_instance == true
            and type(result) == 'table'
            and type(result.activated) == 'table' then
            local activated_actor_id = tonumber(result.activated.actor_id) or instance_actor_id
            if tostring(result.activated.response or '') == 'use_sequence' then
                register_pending(result.activated.key, rule, rule_index, activated_actor_id)
            else
                mark_consumed(rule, rule_index, activated_actor_id)
            end
        end
        return result
    end

    if type(base_note_sequence_action_dispatched) == 'function' then
        function base.note_sequence_action_dispatched(key_value, action_type, action_name, target_kind, target_id, action_actor_id, now)
            local marked, reason = base_note_sequence_action_dispatched(
                key_value,
                action_type,
                action_name,
                target_kind,
                target_id,
                action_actor_id,
                now
            )
            if marked == true then
                local pending = pending_by_lock[tostring(key_value or '')]
                if type(pending) == 'table' then
                    mark_consumed(pending.rule, pending.rule_index, pending.actor_id)
                    clear_pending_lock(key_value)
                end
            end
            return marked, reason
        end
    end

    function base.cancel(key_value, reason)
        clear_pending_lock(key_value)
        return base_cancel(key_value, reason)
    end

    function base.prune_invalid_ability_windows(actor_is_valid_enemy)
        if type(actor_is_valid_enemy) ~= 'function' then
            error('reaction once-per-instance pruning requires an enemy-validity function')
        end
        clear_invalid_actor_state(actor_is_valid_enemy)
        return base_prune(actor_is_valid_enemy)
    end

    function base.reset(reason)
        consumed_by_actor = {}
        pending_by_lock = {}
        pending_by_actor = {}
        return base_reset(reason)
    end

    function base.status()
        local status = base_status()
        local consumed_count = 0
        local actor_count = 0
        for _, bucket in pairs(consumed_by_actor) do
            actor_count = actor_count + 1
            for _ in pairs(bucket) do
                consumed_count = consumed_count + 1
            end
        end
        local pending_count = 0
        for _ in pairs(pending_by_lock) do
            pending_count = pending_count + 1
        end
        status.once_per_instance = {
            actor_count = actor_count,
            consumed_count = consumed_count,
            pending_count = pending_count,
        }
        return status
    end

    base._once_per_instance_extension_installed = true
    return base
end

return M
