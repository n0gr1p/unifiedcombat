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

-- Preserve flat compatibility only before the owning Profile V2 domain exists.
-- A missing leaf inside a canonical domain must use its canonical default,
-- never a stale legacy value.
local function canonical_or_legacy(path, domain, flat_value, canonical_default)
    local active_value = uc_active_config.get_path(path)
    if active_value ~= nil then
        return active_value
    end
    if type(uc_active_config.get_path('config.' .. domain)) == 'table' then
        return canonical_default
    end
    return flat_value
end

local function active_bool_or_flat(path, domain, flat_value)
    return truthy(canonical_or_legacy(path, domain, flat_value, false))
end

function M.debug_enabled(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.enabled', 'debug', s.debug)
end

function M.debug_action_timeline(settings)
    local active_value = uc_active_config.get_path('config.debug.action_timeline')
    if active_value ~= nil then
        return active_value == true
    end
    if type(uc_active_config.get_path('config.debug')) == 'table' then
        return false
    end
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'log_action_timeline')
    if flat_value ~= nil then
        return truthy(flat_value)
    end
    return rawget(_G, 'UC_DEBUG_ACTION_TIMELINE') == true
end

function M.debug_log_combat_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.combat_sched', 'debug', s.log_combat_sched)
end

function M.debug_log_ja_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.ja_sched', 'debug', s.log_ja_sched)
end

function M.debug_log_ja_debug(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.ja_debug', 'debug', s.log_ja_debug)
end

function M.debug_log_def_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.def_sched', 'debug', s.log_def_sched)
end

function M.debug_log_tank_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.tank_sched', 'debug', s.log_tank_sched)
end

function M.combat_autotarget_from_config(config)
    local combat = type(config) == 'table' and config.combat or nil
    return type(combat) == 'table' and combat.autotarget == true
end

function M.combat_prime_from_config(config)
    local combat = type(config) == 'table' and config.combat or nil
    return type(combat) == 'table' and combat.prime == true
end

function M.sleep_enabled_from_config(config)
    local sleep = type(config) == 'table' and config.sleep or nil
    return type(sleep) == 'table' and sleep.enabled == true
end

function M.sleep_order_from_config(config)
    local sleep = type(config) == 'table' and config.sleep or nil
    if type(sleep) ~= 'table' then return {} end
    local order = type(sleep.order) == 'table' and sleep.order or nil
    if type(order) == 'table' and #order > 0 then
        local out = {}
        for i = 1, #order do out[i] = order[i] end
        return out
    end
    local primary = tostring(sleep.legacy_primary or ''):match('^%s*(.-)%s*$') or ''
    return primary ~= '' and { primary } or {}
end

function M.sleep_max_target_range_from_config(config)
    local sleep = type(config) == 'table' and config.sleep or nil
    return tonumber(type(sleep) == 'table' and sleep.max_target_range) or 6.0
end

function M.defensive_from_config(config)
    local defensive = type(config) == 'table' and config.defensive or nil
    return type(defensive) == 'table' and defensive or {}
end

function M.defensive_critical_hpp_from_config(config)
    local defensive = M.defensive_from_config(config)
    local thresholds = type(defensive.thresholds) == 'table' and defensive.thresholds or nil
    return tonumber(type(thresholds) == 'table' and thresholds.critical_hpp) or 35
end

function M.defensive_doom_water_enabled_from_config(config)
    local defensive = M.defensive_from_config(config)
    local doom = type(defensive.doom) == 'table' and defensive.doom or nil
    return defensive.enabled == true and type(doom) == 'table' and doom.holy_water_enabled == true
end

function M.combat_autotarget(settings)
    local s = settings_or_default(settings)
    return canonical_or_legacy('config.combat.autotarget', 'combat', s.autotarget, false)
end

function M.combat_weaponskill_enabled_from_config(config)
    local combat = type(config) == 'table' and config.combat or nil
    local weaponskill = type(combat) == 'table' and combat.weaponskill or nil
    return type(weaponskill) == 'table' and weaponskill.enabled == true
end

function M.abilities_enabled_from_config(config)
    local abilities = type(config) == 'table' and config.abilities or nil
    return type(abilities) == 'table' and abilities.enabled == true
end

function M.abilities_allow_unengaged_from_config(config)
    local abilities = type(config) == 'table' and config.abilities or nil
    return type(abilities) == 'table' and abilities.allow_unengaged == true
end

function M.required_setting_value_from_config(config, setting_name)
    local name = tostring(setting_name or '')
    if name == 'autotarget' then
        return M.combat_autotarget_from_config(config)
    end
    if name == 'weaponskill_active' then
        return M.combat_weaponskill_enabled_from_config(config)
    end
    if name == 'ability_active' then
        return M.abilities_enabled_from_config(config)
    end
    if name == 'sleep' then
        return M.sleep_enabled_from_config(config)
    end
    if name == 'tank' then
        return M.tank_enabled_from_config(config)
    end
    return nil
end

function M.combat_prime(settings)
    local s = settings_or_default(settings)
    return canonical_or_legacy('config.combat.prime', 'combat', s.prime, false)
end

function M.movement_spacing_from_config(config)
    local movement = type(config) == 'table' and config.movement or nil
    local spacing = type(movement) == 'table' and movement.spacing or nil
    if type(spacing) ~= 'table' then
        return nil
    end
    return spacing
end

function M.combat_pulling_from_config(config)
    local combat = type(config) == 'table' and config.combat or nil
    local pulling = type(combat) == 'table' and combat.pulling or nil
    if type(pulling) ~= 'table' then
        return nil
    end
    return pulling
end

function M.targeting_add_control_from_config(config)
    local targeting = type(config) == 'table' and config.targeting or nil
    return type(targeting) == 'table' and targeting.add_control == true
end

function M.targeting_priority_names_from_config(config)
    local targeting = type(config) == 'table' and config.targeting or nil
    if type(targeting) ~= 'table' then
        return {}
    end
    local names = targeting.targets
    if type(names) ~= 'table' or #names == 0 then
        names = targeting.add_priority_names
    end
    if type(names) ~= 'table' then
        return {}
    end
    return names
end

function M.targeting_ignore_names_from_config(config)
    local targeting = type(config) == 'table' and config.targeting or nil
    if type(targeting) ~= 'table' or type(targeting.target_ignore_names) ~= 'table' then
        return {}
    end
    return targeting.target_ignore_names
end

function M.tank_enabled_from_config(config)
    local tank = type(config) == 'table' and config.tank or nil
    return type(tank) == 'table' and tank.enabled == true
end

function M.tank_enmity_actions_from_config(config)
    local tank = type(config) == 'table' and config.tank or nil
    local enmity = type(tank) == 'table' and tank.enmity or nil
    if type(enmity) ~= 'table' or type(enmity.actions) ~= 'table' then
        return {}
    end
    return enmity.actions
end

function M.tank_enmity_include_pets_from_config(config)
    local tank = type(config) == 'table' and config.tank or nil
    local enmity = type(tank) == 'table' and tank.enmity or nil
    return type(enmity) == 'table' and enmity.include_pets == true
end

function M.tank_enmity_action_configured_from_config(config, action_name)
    local needle = tostring(action_name or ''):match('^%s*(.-)%s*$') or ''
    if needle == '' then
        return false
    end
    needle = needle:lower()
    for _, entry in ipairs(M.tank_enmity_actions_from_config(config)) do
        local raw = type(entry) == 'table'
            and tostring(entry.name or entry.entry or entry.raw or '')
            or tostring(entry or '')
        local _, explicit_name = raw:match('^(%a+)%s*:%s*(.+)$')
        if explicit_name ~= nil then raw = explicit_name end
        raw = raw:match('^%s*(.-)%s*$') or ''
        if raw:lower() == needle then
            return true
        end
    end
    return false
end

function M.tank_enabled(settings)
    local s = settings_or_default(settings)
    return canonical_or_legacy('config.tank.enabled', 'tank', s.tank, false)
end

function M.tank_enmity_actions(settings)
    local s = settings_or_default(settings)
    return canonical_or_legacy('config.tank.enmity.actions', 'tank', s.tank_enmity_actions, {})
end

function M.tank_enmity_include_pets(settings)
    local canonical = uc_active_config.get_path('config.tank.enmity.include_pets')
    if canonical ~= nil then
        return canonical == true
    end
    if type(uc_active_config.get_path('config.tank')) == 'table' then
        return false
    end
    local s = settings_or_default(settings)
    return truthy(rawget(s, 'tank_enmity_include_pets'))
end

function M.defensive_enemy_buffs_remove(settings)
    local s = settings_or_default(settings)
    return canonical_or_legacy('config.defensive.enemy_buffs.remove', 'defensive', s.def_remove_enemy_buffs, false)
end

return M
