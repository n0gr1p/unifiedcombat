local M = {}

local function combat(config)
    local value = type(config) == 'table' and config.combat or nil
    return type(value) == 'table' and value or nil
end

local function movement(config)
    local value = type(config) == 'table' and config.movement or nil
    return type(value) == 'table' and value or nil
end

local function ownership(config)
    local value = type(config) == 'table' and config.ownership or nil
    return type(value) == 'table' and value or nil
end

local function tank(config)
    local value = type(config) == 'table' and config.tank or nil
    return type(value) == 'table' and value or nil
end

local function targeting(config)
    local value = type(config) == 'table' and config.targeting or nil
    return type(value) == 'table' and value or nil
end

local function legacy(config)
    local value = type(config) == 'table' and config.legacy or nil
    return type(value) == 'table' and value or nil
end

local function follow_partner(config)
    local follow = type(config) == 'table' and config.follow or nil
    local partner = type(follow) == 'table' and follow.partner or nil
    return type(partner) == 'table' and partner or nil
end

local function path(config)
    local mv = movement(config)
    local value = type(mv) == 'table' and mv.path or nil
    return type(value) == 'table' and value or nil
end

local function formation_enabled(config)
    local mv = movement(config)
    local value = type(mv) == 'table' and mv.formation or nil
    return type(value) == 'table' and value.enabled == true
end

local function named_formations_enabled(config)
    local mv = movement(config)
    local value = type(mv) == 'table' and mv.named_formations or nil
    return type(value) == 'table' and value.enabled == true
end

local function spacing_enabled(config)
    local mv = movement(config)
    local value = type(mv) == 'table' and mv.spacing or nil
    return type(value) == 'table' and value.enabled == true
end

local function hunter_path_enabled(config)
    local legacy_cfg = legacy(config)
    local path_cfg = path(config)
    return type(legacy_cfg) == 'table'
        and legacy_cfg.hunter == true
        and type(path_cfg) == 'table'
        and path_cfg.follow_enabled == true
end

function M.move_enabled(config)
    local mv = movement(config)
    return type(mv) == 'table' and mv.move == true
end

function M.manual_enabled(config)
    local cfg = combat(config)
    return type(cfg) == 'table' and cfg.manual == true
end

function M.static_enabled(config)
    local cfg = combat(config)
    return type(cfg) == 'table' and cfg.static == true
end

function M.face_enabled(config)
    local cfg = combat(config)
    return type(cfg) == 'table' and cfg.face == true
end

function M.controls(config)
    return {
        move = M.move_enabled(config),
        manual = M.manual_enabled(config),
        static = M.static_enabled(config),
        face = M.face_enabled(config),
    }
end

local function common_participant(config)
    local combat_cfg = combat(config)
    local tank_cfg = tank(config)
    local targeting_cfg = targeting(config)
    local partner_cfg = follow_partner(config)
    return (type(combat_cfg) == 'table' and combat_cfg.autotarget == true)
        or M.move_enabled(config)
        or formation_enabled(config)
        or named_formations_enabled(config)
        or (type(tank_cfg) == 'table' and tank_cfg.enabled == true)
        or hunter_path_enabled(config)
        or (type(partner_cfg) == 'table' and partner_cfg.puller == true)
        or (type(targeting_cfg) == 'table' and targeting_cfg.add_control == true)
end

function M.combat_participant(config)
    local owner = ownership(config)
    return type(owner) == 'table'
        and owner.domain_combat_enabled == true
        and common_participant(config)
end

function M.movement_participant(config)
    local owner = ownership(config)
    return type(owner) == 'table'
        and owner.domain_movement_enabled == true
        and (common_participant(config) or spacing_enabled(config))
end

return M
