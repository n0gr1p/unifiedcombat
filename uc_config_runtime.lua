local M = {}

local function legacy_ingame_ui_enabled(settings)
    if type(settings) ~= 'table' then
        return true
    end
    return settings.show_ingame_ui ~= false
end

local function clone_shallow(source)
    local out = {}
    if type(source) ~= 'table' then
        return out
    end
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

local function ui_source(settings)
    if type(settings) ~= 'table' then
        return { show_ingame_ui = true }
    end
    if settings.show_ingame_ui ~= nil then
        return settings
    end
    local source = clone_shallow(settings)
    source.show_ingame_ui = true
    return source
end

local function current_meta()
    local meta = {
        source = 'UC_SETTINGS',
    }
    local windower_ref = rawget(_G, 'windower')
    local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
    local get_player = type(ffxi) == 'table' and ffxi.get_player or nil
    if type(get_player) ~= 'function' then
        return meta
    end
    local ok, player = pcall(get_player)
    if not ok or type(player) ~= 'table' then
        return meta
    end
    meta.character = player.name
    meta.main_job = player.main_job
    meta.sub_job = player.sub_job
    if player.name ~= nil then
        meta.profile_key = tostring(player.name)
        if player.main_job ~= nil or player.sub_job ~= nil then
            meta.profile_key = tostring(player.name) .. '|' .. tostring(player.main_job or '') .. '|' .. tostring(player.sub_job or '')
        end
    end
    return meta
end

local function normalizer_from_arg(normalizer)
    if type(normalizer) == 'table' and type(normalizer.normalize) == 'function' then
        return normalizer
    end
    if normalizer ~= nil then
        return nil
    end
    local ok, loaded = pcall(require, 'uc_config_normalizer')
    if ok and type(loaded) == 'table' and type(loaded.normalize) == 'function' then
        return loaded
    end
    return nil
end

function M.normalize_current_config(settings, meta, normalizer)
    local resolved = normalizer_from_arg(normalizer)
    if not resolved then
        return nil
    end
    local ok, config = pcall(resolved.normalize, settings, meta or current_meta())
    if ok and type(config) == 'table' then
        return config
    end
    return nil
end

function M.ingame_ui_enabled(settings, meta, normalizer)
    local source = ui_source(settings)
    local config = M.normalize_current_config(source, meta, normalizer)
    if type(config) == 'table' and type(config.ui) == 'table' and config.ui.show_ingame_ui ~= nil then
        return config.ui.show_ingame_ui == true
    end
    return legacy_ingame_ui_enabled(settings)
end

return M
