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
    local enabled
    local spell
    local mode
    local family
    local max_tier
    if type(spells) == 'table' and spells.magic_burst ~= nil then
        enabled = spells.magic_burst == true
        spell = trim(spells.configured)
        mode = trim(spells.magic_burst_mode):lower()
        family = trim(spells.magic_burst_family):lower()
        max_tier = tonumber(spells.magic_burst_max_tier)
    else
        enabled = flat_value(settings, 'magic_burst_enabled') == true
        spell = trim(flat_value(settings, 'spell'))
        mode = trim(flat_value(settings, 'magic_burst_mode')):lower()
        family = trim(flat_value(settings, 'magic_burst_family')):lower()
        max_tier = tonumber(flat_value(settings, 'magic_burst_max_tier'))
    end
    if mode == '' then mode = 'exact' end
    if family == '' then family = 'spell' end
    if mode ~= 'exact' and mode ~= 'auto' then mode = 'exact' end
    if family ~= 'spell' and family ~= 'ra' and family ~= 'helix' then family = 'spell' end
    max_tier = math.floor(max_tier or 0)
    if max_tier < 0 then max_tier = 0 end
    if max_tier > 5 then max_tier = 5 end
    return {
        enabled = enabled,
        spell = spell,
        mode = mode,
        family = family,
        max_tier = max_tier,
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
