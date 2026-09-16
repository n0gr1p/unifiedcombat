local M = {}

local function raw_reaction_rules(settings)
    if type(settings) ~= 'table' then
        return nil
    end
    if type(settings.config) == 'table'
        and type(settings.config.reactions) == 'table'
        and type(settings.config.reactions.rules) == 'table' then
        return settings.config.reactions.rules
    end
    if type(settings.reactions) == 'table' and type(settings.reactions.rules) == 'table' then
        return settings.reactions.rules
    end
    if type(settings.reaction_rules) == 'table' then
        return settings.reaction_rules
    end
    return nil
end

function M.wrap(base)
    if type(base) ~= 'table' or type(base.normalize) ~= 'function' then
        error('uc_config_normalizer_once requires base normalizer')
    end
    local wrapped = {}
    for key, value in pairs(base) do
        wrapped[key] = value
    end
    local original_normalize = base.normalize

    function wrapped.normalize(settings, meta)
        local raw_rules = raw_reaction_rules(settings)
        if type(raw_rules) == 'table' then
            for i = 1, #raw_rules do
                local rule = raw_rules[i]
                if type(rule) == 'table' and rule.once_per_instance ~= nil then
                    if type(rule.once_per_instance) ~= 'boolean' then
                        error(('reactions.rules[%d].once_per_instance must be boolean'):format(i))
                    end
                    if rule.once_per_instance == true and tostring(rule.trigger or '') ~= 'ability_window' then
                        error(('reactions.rules[%d].once_per_instance requires ability_window trigger'):format(i))
                    end
                end
            end
        end

        local config = original_normalize(settings, meta)
        if type(raw_rules) ~= 'table'
            or type(config) ~= 'table'
            or type(config.reactions) ~= 'table'
            or type(config.reactions.rules) ~= 'table' then
            return config
        end

        for i = 1, math.min(#raw_rules, #config.reactions.rules) do
            local raw = raw_rules[i]
            local normalized = config.reactions.rules[i]
            if type(raw) == 'table' and type(normalized) == 'table' then
                normalized.once_per_instance = raw.once_per_instance == true
            end
        end
        return config
    end

    return wrapped
end

return M
