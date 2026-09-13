local M = {}

local function read_raw(settings)
    if type(settings) ~= 'table' then
        return nil
    end
    if type(settings.config) == 'table'
        and type(settings.config.maintenance) == 'table'
        and type(settings.config.maintenance.cor) == 'table'
        and settings.config.maintenance.cor.light_shot_dia ~= nil then
        return settings.config.maintenance.cor.light_shot_dia
    end
    if type(settings.maintenance) == 'table'
        and type(settings.maintenance.cor) == 'table'
        and settings.maintenance.cor.light_shot_dia ~= nil then
        return settings.maintenance.cor.light_shot_dia
    end
    return settings.cor_light_shot_dia
end

local function ensure_field(config, value)
    if type(config) ~= 'table' then
        error('COR config wrapper expected normalized config table')
    end
    config.maintenance = type(config.maintenance) == 'table' and config.maintenance or {}
    config.maintenance.cor = type(config.maintenance.cor) == 'table' and config.maintenance.cor or {}
    if value == nil then
        value = config.maintenance.cor.light_shot_dia
    end
    if value == nil then
        value = true
    end
    if type(value) ~= 'boolean' then
        error('config.maintenance.cor.light_shot_dia must be boolean')
    end
    config.maintenance.cor.light_shot_dia = value
    return config
end

function M.wrap(base)
    if type(base) ~= 'table' or type(base.normalize) ~= 'function' then
        error('uc_config_normalizer_cor requires base normalizer')
    end
    local wrapped = {}
    for key, value in pairs(base) do
        wrapped[key] = value
    end

    local original_normalize = base.normalize
    function wrapped.normalize(settings, meta)
        return ensure_field(original_normalize(settings, meta), read_raw(settings))
    end

    if type(base.default_config) == 'function' then
        local original_default = base.default_config
        function wrapped.default_config(meta)
            return ensure_field(original_default(meta), true)
        end
    end

    return wrapped
end

return M
