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

local function active_bool_or_flat(path, flat_value)
    local active_value = uc_active_config.get_path(path)
    if active_value == nil then
        return truthy(flat_value)
    end
    return active_value == true
end

function M.active_value_or_flat(path, flat_value)
    local active_value = uc_active_config.get_path(path)
    if active_value ~= nil then
        return active_value
    end
    return flat_value
end

function M.debug_enabled(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.enabled', s.debug)
end

function M.debug_log_combat_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.combat_sched', s.log_combat_sched)
end

function M.debug_log_ja_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.ja_sched', s.log_ja_sched)
end

function M.debug_log_ja_debug(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.ja_debug', s.log_ja_debug)
end

function M.debug_log_def_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.def_sched', s.log_def_sched)
end

function M.debug_log_tank_sched(settings)
    local s = settings_or_default(settings)
    return active_bool_or_flat('config.debug.tank_sched', s.log_tank_sched)
end

function M.combat_autotarget(settings)
    local s = settings_or_default(settings)
    return M.active_value_or_flat('config.combat.autotarget', s.autotarget)
end

function M.combat_prime(settings)
    local s = settings_or_default(settings)
    return M.active_value_or_flat('config.combat.prime', s.prime)
end

function M.ownership_scheduler_dark_launch_combat(settings)
    local s = settings_or_default(settings)
    return M.active_value_or_flat('config.ownership.scheduler_dark_launch_combat', s.scheduler_dark_launch_combat)
end

function M.tank_enabled(settings)
    local s = settings_or_default(settings)
    return M.active_value_or_flat('config.tank.enabled', s.tank)
end

function M.tank_enmity_actions(settings)
    local s = settings_or_default(settings)
    return M.active_value_or_flat('config.tank.enmity.actions', s.tank_enmity_actions)
end

function M.defensive_enemy_buffs_remove(settings)
    local s = settings_or_default(settings)
    return M.active_value_or_flat('config.defensive.enemy_buffs.remove', s.def_remove_enemy_buffs)
end

return M
