local M = {}

local RUNE_NAMES = {
    Ignis = true,
    Gelus = true,
    Flabra = true,
    Tellus = true,
    Sulpor = true,
    Unda = true,
    Lux = true,
    Tenebrae = true,
}

local RUNE_CANONICAL = {}
for name in pairs(RUNE_NAMES) do
    RUNE_CANONICAL[name:lower()] = name
end

local function clone(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for key, inner in pairs(value) do
        out[key] = clone(inner)
    end
    return out
end

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function bool(value, default_value, path)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'boolean' then
        error(path .. ' must be boolean')
    end
    return value
end

local function split_pipe(value)
    if type(value) ~= 'string' then
        return value
    end
    local out = {}
    for token in value:gmatch('[^|]+') do
        local entry = trim(token)
        if entry ~= '' then
            out[#out + 1] = entry
        end
    end
    return out
end

local function normalize_runes(value)
    value = split_pipe(value or {})
    if type(value) ~= 'table' then
        error('config.tank.run.runes.desired must be an array or pipe-delimited string')
    end
    local out = {}
    for i = 1, #value do
        local raw = trim(value[i])
        local canonical = RUNE_CANONICAL[raw:lower()]
        if canonical == nil then
            error(('config.tank.run.runes.desired[%d] is not a Rune Enchantment'):format(i))
        end
        out[#out + 1] = canonical
    end
    if #out ~= 0 and #out ~= 3 then
        error('config.tank.run.runes.desired must be empty or contain exactly three runes')
    end
    return out
end

function M.default_config()
    return {
        enabled = false,
        runes = {
            maintain = true,
            desired = {},
        },
        foil = {
            enabled = true,
        },
        wards = {
            vallation = false,
            valiance = false,
            pflug = false,
            swordplay = false,
            battuta = false,
            one_for_all = false,
        },
        magic_support = {
            gambit = false,
            rayke = false,
        },
    }
end

local function flat_value(source, key)
    if type(source) ~= 'table' then
        return nil
    end
    return source[key]
end

function M.normalize(value, flat_source)
    local out = M.default_config()
    local structured = type(value) == 'table' and value or nil
    if structured ~= nil then
        out.enabled = bool(structured.enabled, out.enabled, 'config.tank.run.enabled')
        local runes = type(structured.runes) == 'table' and structured.runes or {}
        out.runes.maintain = bool(runes.maintain, out.runes.maintain, 'config.tank.run.runes.maintain')
        out.runes.desired = normalize_runes(runes.desired)
        local foil = type(structured.foil) == 'table' and structured.foil or {}
        out.foil.enabled = bool(foil.enabled, out.foil.enabled, 'config.tank.run.foil.enabled')
        local wards = type(structured.wards) == 'table' and structured.wards or {}
        out.wards.vallation = bool(wards.vallation, out.wards.vallation, 'config.tank.run.wards.vallation')
        out.wards.valiance = bool(wards.valiance, out.wards.valiance, 'config.tank.run.wards.valiance')
        out.wards.pflug = bool(wards.pflug, out.wards.pflug, 'config.tank.run.wards.pflug')
        out.wards.swordplay = bool(wards.swordplay, out.wards.swordplay, 'config.tank.run.wards.swordplay')
        out.wards.battuta = bool(wards.battuta, out.wards.battuta, 'config.tank.run.wards.battuta')
        out.wards.one_for_all = bool(wards.one_for_all, out.wards.one_for_all, 'config.tank.run.wards.one_for_all')
        local magic = type(structured.magic_support) == 'table' and structured.magic_support or {}
        out.magic_support.gambit = bool(magic.gambit, out.magic_support.gambit, 'config.tank.run.magic_support.gambit')
        out.magic_support.rayke = bool(magic.rayke, out.magic_support.rayke, 'config.tank.run.magic_support.rayke')
    else
        out.enabled = bool(flat_value(flat_source, 'run_tank_enabled'), out.enabled, 'run_tank_enabled')
        out.runes.maintain = bool(flat_value(flat_source, 'run_tank_runes_maintain'), out.runes.maintain, 'run_tank_runes_maintain')
        out.runes.desired = normalize_runes(flat_value(flat_source, 'run_tank_runes') or {})
        out.foil.enabled = bool(flat_value(flat_source, 'run_tank_foil'), out.foil.enabled, 'run_tank_foil')
        out.wards.vallation = bool(flat_value(flat_source, 'run_tank_vallation'), out.wards.vallation, 'run_tank_vallation')
        out.wards.valiance = bool(flat_value(flat_source, 'run_tank_valiance'), out.wards.valiance, 'run_tank_valiance')
        out.wards.pflug = bool(flat_value(flat_source, 'run_tank_pflug'), out.wards.pflug, 'run_tank_pflug')
        out.wards.swordplay = bool(flat_value(flat_source, 'run_tank_swordplay'), out.wards.swordplay, 'run_tank_swordplay')
        out.wards.battuta = bool(flat_value(flat_source, 'run_tank_battuta'), out.wards.battuta, 'run_tank_battuta')
        out.wards.one_for_all = bool(flat_value(flat_source, 'run_tank_one_for_all'), out.wards.one_for_all, 'run_tank_one_for_all')
        out.magic_support.gambit = bool(flat_value(flat_source, 'run_tank_gambit'), out.magic_support.gambit, 'run_tank_gambit')
        out.magic_support.rayke = bool(flat_value(flat_source, 'run_tank_rayke'), out.magic_support.rayke, 'run_tank_rayke')
    end
    if out.wards.vallation and out.wards.valiance then
        error('config.tank.run.wards cannot enable both Vallation and Valiance')
    end
    return out
end

function M.active(settings)
    if type(settings) == 'table' and type(settings.tank_run) == 'table' then
        return M.normalize(settings.tank_run)
    end
    local ok, active_config = pcall(require, 'uc_active_config')
    if ok and type(active_config) == 'table' and type(active_config.get_path) == 'function' then
        local active = active_config.get_path('config.tank.run')
        if type(active) == 'table' then
            return M.normalize(active)
        end
    end
    return M.normalize(nil, settings)
end

function M.is_rune_name(name)
    return RUNE_CANONICAL[trim(name):lower()] ~= nil
end

function M.rune_names()
    local out = {}
    for _, name in ipairs({ 'Ignis', 'Gelus', 'Flabra', 'Tellus', 'Sulpor', 'Unda', 'Lux', 'Tenebrae' }) do
        out[#out + 1] = name
    end
    return out
end

function M.copy(config)
    return clone(config)
end

return M
