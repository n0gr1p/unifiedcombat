local uc_active_config = require('uc_active_config')

local M = {}

local function settings_or_default(settings)
    if type(settings) == 'table' then
        return settings
    end
    return rawget(_G, 'UC_SETTINGS') or {}
end

local function truthy(value)
    if value == true or value == 1 then
        return true
    end
    if type(value) == 'string' then
        local lowered = value:lower()
        return lowered == 'true' or lowered == 'on' or lowered == '1' or lowered == 'yes'
    end
    return false
end

local function trim_string(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function clone_array(source)
    local out = {}
    if type(source) ~= 'table' then
        return out
    end
    for i = 1, #source do
        out[i] = source[i]
    end
    return out
end

local function normalize_name_list(values, legacy_single)
    local out = {}
    local seen = {}

    local function append_name(raw)
        local name = trim_string(raw)
        if name == '' then
            return
        end
        local key = name:lower()
        if seen[key] then
            return
        end
        seen[key] = true
        out[#out + 1] = name
    end

    if type(values) == 'table' then
        for i = 1, #values do
            append_name(values[i])
        end
    elseif type(values) == 'string' then
        append_name(values)
    end

    if #out == 0 then
        append_name(legacy_single)
    end

    return out
end

function M.fight_leader_enabled(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'fight_leader')
    if flat_value ~= nil then
        return truthy(flat_value)
    end
    local active_value = uc_active_config.get_path('config.follow.fight.leader')
    if active_value ~= nil then
        return active_value == true
    end
    return truthy(s.fight_leader)
end

function M.fight_leader_id(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'fight_leader_id')
    if flat_value ~= nil then
        return tonumber(flat_value) or 0
    end
    local active_value = uc_active_config.get_path('config.follow.fight.leader_id')
    if active_value ~= nil then
        return tonumber(active_value) or 0
    end
    return tonumber(s.fight_leader_id) or 0
end

function M.add_priority_names(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'add_priority_names')
    if flat_value ~= nil then
        return normalize_name_list(flat_value, nil)
    end
    local active_value = uc_active_config.get_path('config.targeting.add_priority_names')
    if active_value ~= nil then
        return normalize_name_list(clone_array(active_value), nil)
    end
    return normalize_name_list(s.add_priority_names, nil)
end

function M.sleep_enabled(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'sleep')
    if flat_value ~= nil then
        return truthy(flat_value)
    end
    local active_value = uc_active_config.get_path('config.sleep.enabled')
    if active_value ~= nil then
        return active_value == true
    end
    return truthy(s.sleep)
end

function M.sleep_spell_names(settings)
    local s = settings_or_default(settings)
    if rawget(s, 'sleepspells') ~= nil or rawget(s, 'sleepspell') ~= nil then
        return normalize_name_list(rawget(s, 'sleepspells'), rawget(s, 'sleepspell'))
    end

    local active_order = uc_active_config.get_path('config.sleep.order')
    local active_primary = uc_active_config.get_path('config.sleep.legacy_primary')
    if active_order ~= nil or active_primary ~= nil then
        return normalize_name_list(clone_array(active_order), active_primary)
    end

    return normalize_name_list(s.sleepspells, s.sleepspell)
end

return M
