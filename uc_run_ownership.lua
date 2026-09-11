local run_config = require('uc_run_config')

local M = {}

local RUNE_NAMES = {}
for _, name in ipairs(run_config.rune_names()) do
    RUNE_NAMES[name:lower()] = true
end

local function owned_set(settings)
    local cfg = run_config.active(settings)
    if cfg.enabled ~= true then
        return {}
    end
    local out = {}
    for name in pairs(RUNE_NAMES) do
        out[name] = true
    end
    local wards = cfg.wards or {}
    if wards.vallation then out.vallation = true end
    if wards.valiance then out.valiance = true end
    if wards.pflug then out.pflug = true end
    if wards.swordplay then out.swordplay = true end
    if wards.battuta then out.battuta = true end
    if wards.one_for_all then out['one for all'] = true end
    local magic = cfg.magic_support or {}
    if magic.gambit then out.gambit = true end
    if magic.rayke then out.rayke = true end
    return out
end

function M.owns_ja(settings, name)
    local key = tostring(name or ''):lower()
    return owned_set(settings)[key] == true
end

function M.filter_generic_abilities(settings, abilities)
    if type(abilities) ~= 'table' then
        return {}
    end
    local owned = owned_set(settings)
    if next(owned) == nil then
        local copy = {}
        for i = 1, #abilities do copy[i] = abilities[i] end
        return copy
    end
    local out = {}
    for i = 1, #abilities do
        local name = abilities[i]
        if owned[tostring(name or ''):lower()] ~= true then
            out[#out + 1] = name
        end
    end
    return out
end

return M
