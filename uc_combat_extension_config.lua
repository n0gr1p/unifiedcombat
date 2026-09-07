local uc_active_config = require('uc_active_config')

local M = {}

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function flat_settings(settings)
    if type(settings) == 'table' then
        return settings
    end
    local global_settings = rawget(_G, 'UC_SETTINGS')
    return type(global_settings) == 'table' and global_settings or {}
end

function M.auto_engage_enabled(settings)
    local active_value = uc_active_config.get_path('config.combat.auto_engage')
    if active_value ~= nil then
        return active_value ~= false
    end
    local flat = flat_settings(settings)
    if flat.auto_engage ~= nil then
        return flat.auto_engage ~= false
    end
    return true
end

function M.magic_burst(settings)
    local spells = uc_active_config.get_path('config.spells')
    if type(spells) == 'table' and spells.magic_burst ~= nil then
        return {
            enabled = spells.magic_burst == true,
            spell = trim(spells.configured),
        }
    end
    local flat = flat_settings(settings)
    return {
        enabled = flat.magic_burst_enabled == true,
        spell = trim(flat.spell),
    }
end

function M.reaction_rules()
    local active = uc_active_config.get_path('config.reactions')
    if type(active) == 'table' and active.enabled == true and type(active.rules) == 'table' then
        return active.rules
    end
    local flat = flat_settings(nil)
    if flat.reaction_enabled == true and type(flat.reaction_rules) == 'table' then
        return flat.reaction_rules
    end
    return nil
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
