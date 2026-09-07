local base = require('uc_config_normalizer_base')

local M = {}
for key, value in pairs(base) do
    M[key] = value
end

local function clone(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[clone(key, seen)] = clone(item, seen) end
    return out
end

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function bool_value(value, default)
    if value == nil then return default end
    if value == true or value == false then return value end
    if value == 1 or value == '1' then return true end
    if value == 0 or value == '0' then return false end
    if type(value) == 'string' then
        local lower = value:lower()
        if lower == 'true' or lower == 'on' or lower == 'yes' then return true end
        if lower == 'false' or lower == 'off' or lower == 'no' then return false end
    end
    error('boolean configuration value expected')
end

local function reaction_source(source)
    if type(source) ~= 'table' then return nil end
    if type(source.reactions) == 'table' then return source.reactions end
    if type(source.reaction_rules) == 'table' then
        return { enabled = source.reaction_enabled, rules = source.reaction_rules }
    end
    return nil
end

local function mutable_reaction_rules(source)
    if type(source) ~= 'table' then return nil end
    if type(source.reactions) == 'table' and type(source.reactions.rules) == 'table' then
        return source.reactions.rules
    end
    if type(source.reaction_rules) == 'table' then return source.reaction_rules end
    return nil
end

local function prepare_source(source)
    local copied = clone(source or {})
    local rules = mutable_reaction_rules(copied)
    if type(rules) == 'table' then
        for index = 1, #rules do
            local rule = rules[index]
            if type(rule) == 'table' and trim(rule.response) == 'use_action' then
                if trim(rule.trigger) ~= 'ability_window' then
                    error(('reactions.rules[%d] use_action requires trigger=ability_window'):format(index))
                end
                local action_type = trim(rule.action_type):lower()
                local action_name = trim(rule.action_name)
                if action_type ~= 'spell' then
                    error(('reactions.rules[%d].action_type currently supports only spell'):format(index))
                end
                if action_name == '' then
                    error(('reactions.rules[%d].action_name is required for use_action'):format(index))
                end
                rule.response = 'turn_away'
            end
        end
    end
    return copied
end

function M.default_config(context)
    local config = base.default_config(context)
    config.combat = type(config.combat) == 'table' and config.combat or {}
    config.combat.auto_engage = true
    config.spells = type(config.spells) == 'table' and config.spells or {}
    config.spells.magic_burst = false
    return config
end

local function restore_extensions(source, normalized)
    if type(normalized) ~= 'table' then return normalized end

    normalized.combat = type(normalized.combat) == 'table' and normalized.combat or {}
    local combat_source = type(source.combat) == 'table' and source.combat or nil
    local auto_engage = combat_source and combat_source.auto_engage or source.auto_engage
    normalized.combat.auto_engage = bool_value(auto_engage, true)

    if type(normalized.spells) == 'table' then
        local spells_source = type(source.spells) == 'table' and source.spells or nil
        local mb_value = spells_source and spells_source.magic_burst or source.magic_burst_enabled
        normalized.spells.magic_burst = bool_value(mb_value, false)
    end

    local raw_reactions = reaction_source(source)
    if type(raw_reactions) == 'table' and type(raw_reactions.rules) == 'table'
        and type(normalized.reactions) == 'table' and type(normalized.reactions.rules) == 'table' then
        local action_by_key = {}
        for index = 1, #raw_reactions.rules do
            local raw_rule = raw_reactions.rules[index]
            if type(raw_rule) == 'table' and trim(raw_rule.response) == 'use_action' then
                local key = trim(raw_rule.trigger) .. ':' .. trim(raw_rule.name):lower()
                action_by_key[key] = raw_rule
            end
        end
        for index = 1, #normalized.reactions.rules do
            local normalized_rule = normalized.reactions.rules[index]
            local key = type(normalized_rule) == 'table'
                and (trim(normalized_rule.trigger) .. ':' .. trim(normalized_rule.name):lower()) or ''
            local raw_rule = action_by_key[key]
            if raw_rule then
                normalized_rule.response = 'use_action'
                normalized_rule.action_type = trim(raw_rule.action_type):lower()
                normalized_rule.action_name = trim(raw_rule.action_name)
                normalized_rule.distance = nil
            end
        end
    end
    return normalized
end

function M.normalize(source, context)
    local prepared = prepare_source(source)
    local normalized = base.normalize(prepared, context)
    return restore_extensions(source or {}, normalized)
end

return M
