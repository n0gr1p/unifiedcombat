local M = {}

local REACTION_PET_ACTIONS = {
    assault = true,
    deploy = true,
}

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function deep_copy(value, seen)
    if type(value) ~= 'table' then
        return value
    end
    local visited = seen or {}
    if visited[value] then
        error('reaction sequence config must not contain cycles')
    end
    visited[value] = true
    local out = {}
    for key, inner in pairs(value) do
        out[deep_copy(key, visited)] = deep_copy(inner, visited)
    end
    visited[value] = nil
    return out
end

local function raw_reaction_rules(settings)
    if type(settings) ~= 'table' then
        return nil
    end
    if type(settings.config) == 'table'
        and type(settings.config.reactions) == 'table'
        and type(settings.config.reactions.rules) == 'table' then
        return settings.config.reactions.rules
    end
    if type(settings.reactions) == 'table' and type(settings.reactions.rules) == 'table' then
        return settings.reactions.rules
    end
    if type(settings.reaction_rules) == 'table' then
        return settings.reaction_rules
    end
    return nil
end

local function has_sequence(rules)
    for i = 1, #(rules or {}) do
        if type(rules[i]) == 'table' and rules[i].response == 'use_sequence' then
            return true
        end
    end
    return false
end

local function placeholder_rules(rules)
    if type(rules) ~= 'table' then
        return
    end
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == 'table' and rule.response == 'use_sequence' then
            rules[i] = {
                trigger = 'ability_window',
                name = rule.name,
                response = 'turn_away',
            }
        end
    end
end

local function replace_sequence_rules_with_placeholders(settings)
    if type(settings) ~= 'table' then
        return
    end
    if type(settings.config) == 'table'
        and type(settings.config.reactions) == 'table' then
        placeholder_rules(settings.config.reactions.rules)
    end
    if type(settings.reactions) == 'table' then
        placeholder_rules(settings.reactions.rules)
    end
    placeholder_rules(settings.reaction_rules)
end

local function normalize_sequence_step(step, index, count)
    if type(step) ~= 'table' then
        error(('reactions sequence step %d must be a table'):format(index))
    end
    local action_type = trim(step.action_type):lower()
    if action_type ~= 'spell' and action_type ~= 'ja' and action_type ~= 'pet' then
        error(('reactions sequence step %d action_type must be spell, ja, or pet'):format(index))
    end
    local action_name = trim(step.action_name)
    if action_name == '' then
        error(('reactions sequence step %d requires action_name'):format(index))
    end
    local target = trim(step.target):lower()
    if target ~= 'self' and target ~= 'actor' then
        error(('reactions sequence step %d target must be self or actor'):format(index))
    end
    if action_type == 'pet' then
        if target ~= 'actor' then
            error(('reactions sequence step %d pet actions currently require actor target'):format(index))
        end
        if REACTION_PET_ACTIONS[action_name:lower()] ~= true then
            error(('reactions sequence step %d unsupported pet action: %s'):format(index, action_name))
        end
    end
    if step.optional ~= nil and type(step.optional) ~= 'boolean' then
        error(('reactions sequence step %d optional must be boolean'):format(index))
    end
    local optional = step.optional == true
    if index == count and optional then
        error('reactions use_sequence final step must be required')
    end
    return {
        action_type = action_type,
        action_name = action_name,
        target = target,
        optional = optional,
    }
end

local function normalize_sequence_rule(rule, index)
    local trigger = trim(rule.trigger)
    if trigger ~= 'ability_window' and trigger ~= 'party_action_complete' then
        error(('reactions.rules[%d] use_sequence requires ability_window or party_action_complete trigger'):format(index))
    end
    local name = trim(rule.name)
    if name == '' then
        error(('reactions.rules[%d] use_sequence requires name'):format(index))
    end
    if type(rule.steps) ~= 'table' or #rule.steps == 0 then
        error(('reactions.rules[%d] use_sequence requires at least one step'):format(index))
    end
    local normalized = {
        trigger = trigger,
        name = name,
        response = 'use_sequence',
        steps = {},
    }
    if rule.hold_smn_rage_until_sequence_complete ~= nil
        and type(rule.hold_smn_rage_until_sequence_complete) ~= 'boolean' then
        error(('reactions.rules[%d].hold_smn_rage_until_sequence_complete must be boolean'):format(index))
    end
    if rule.hold_smn_rage_until_sequence_complete == true then
        if trigger ~= 'party_action_complete' then
            error(('reactions.rules[%d] SMN Rage hold requires party_action_complete trigger'):format(index))
        end
        if rule.once_per_instance ~= true then
            error(('reactions.rules[%d] SMN Rage hold requires once_per_instance=true'):format(index))
        end
        normalized.hold_smn_rage_until_sequence_complete = true
    end
    if trigger == 'party_action_complete' then
        local source_name = trim(rule.source_name)
        if source_name == '' then
            error(('reactions.rules[%d] party_action_complete requires source_name'):format(index))
        end
        local trigger_action_type = trim(rule.action_type):lower()
        if trigger_action_type ~= 'spell' and trigger_action_type ~= 'ja' then
            error(('reactions.rules[%d] party_action_complete action_type must be spell or ja'):format(index))
        end
        normalized.source_name = source_name
        normalized.action_type = trigger_action_type
    end
    for step_index = 1, #rule.steps do
        normalized.steps[step_index] = normalize_sequence_step(rule.steps[step_index], step_index, #rule.steps)
    end
    return normalized
end

function M.wrap(base)
    if type(base) ~= 'table' or type(base.normalize) ~= 'function' then
        error('uc_config_normalizer_sequence requires base normalizer')
    end
    local wrapped = {}
    for key, value in pairs(base) do
        wrapped[key] = value
    end
    local original_normalize = base.normalize

    function wrapped.normalize(settings, meta)
        local original_rules = raw_reaction_rules(settings)
        if not has_sequence(original_rules) then
            return original_normalize(settings, meta)
        end

        local source = deep_copy(settings)
        replace_sequence_rules_with_placeholders(source)
        local config = original_normalize(source, meta)
        if type(config.reactions) ~= 'table' then
            error('normalized config missing reactions domain')
        end
        local base_rules = type(config.reactions.rules) == 'table' and config.reactions.rules or {}
        local restored = {}
        for i = 1, #original_rules do
            local raw = original_rules[i]
            if type(raw) == 'table' and raw.response == 'use_sequence' then
                restored[i] = normalize_sequence_rule(raw, i)
            else
                restored[i] = base_rules[i]
            end
        end
        config.reactions.rules = restored
        return config
    end

    return wrapped
end

return M
