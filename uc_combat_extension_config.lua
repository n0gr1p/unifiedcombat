local M = {}

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function active_config()
    return require('uc_active_config')
end

local function global_settings()
    local settings = rawget(_G, 'UC_SETTINGS')
    return type(settings) == 'table' and settings or {}
end

local function flat_value(settings, key)
    if type(settings) == 'table' and settings[key] ~= nil then
        return settings[key]
    end
    return global_settings()[key]
end

local function has_action_rule(rules)
    if type(rules) ~= 'table' then
        return false
    end
    for i = 1, #rules do
        if type(rules[i]) == 'table' and rules[i].response == 'use_action' then
            return true
        end
    end
    return false
end

function M.auto_engage_enabled(settings)
    local active_value = active_config().get_path('config.combat.auto_engage')
    if active_value ~= nil then
        return active_value ~= false
    end
    local flat = flat_value(settings, 'auto_engage')
    if flat ~= nil then
        return flat ~= false
    end
    return true
end

function M.magic_burst(settings)
    local spells = active_config().get_path('config.spells')
    if type(spells) == 'table' and spells.magic_burst ~= nil then
        return {
            enabled = spells.magic_burst == true,
            spell = trim(spells.configured),
        }
    end
    return {
        enabled = flat_value(settings, 'magic_burst_enabled') == true,
        spell = trim(flat_value(settings, 'spell')),
    }
end

function M.reaction_rules()
    local active = active_config().get_path('config.reactions')
    local active_rules = type(active) == 'table' and active.enabled == true and type(active.rules) == 'table'
        and active.rules or nil
    local flat = global_settings()
    local flat_rules = flat.reaction_enabled == true and type(flat.reaction_rules) == 'table'
        and flat.reaction_rules or nil

    -- Structured v2 is authoritative when it contains the new action-rule shape.
    -- During legacy flat-settings startup, the old normalizer can legitimately
    -- project the older reaction subset into active config. Preserve the full
    -- flat rule list in that case instead of silently dropping use_action.
    if has_action_rule(active_rules) then
        return active_rules
    end
    if has_action_rule(flat_rules) then
        return flat_rules
    end
    return active_rules or flat_rules
end

function M.validate_action_rule(rule)
    if type(rule) ~= 'table' or rule.response ~= 'use_action' then
        return true
    end
    if rule.trigger ~= 'ability_window' then
        return false, 'use_action reactions require ability_window trigger'
    end
    if trim(rule.action_type):lower() ~= 'spell' then
        return false, 'use_action currently supports only spell actions'
    end
    if trim(rule.action_name) == '' then
        return false, 'use_action reactions require action_name'
    end
    return true
end

return M
