local M = {}

local STATUS_FIELDS = {
    'schema_version',
    'ok',
    'available',
    'normalizer_version',
    'source',
    'character',
    'main_job',
    'sub_job',
    'profile_key',
    'domains',
    'warnings',
    'errors',
    'updated_at',
    'profile_v2',
    'summoner',
    'puppetmaster',
}

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

local function clone_value(source, seen)
    if type(source) ~= 'table' then
        return source
    end
    local visited = seen or {}
    if visited[source] then
        return {}
    end
    visited[source] = true
    local out = {}
    for key, value in pairs(source) do
        out[clone_value(key, visited)] = clone_value(value, visited)
    end
    visited[source] = nil
    return out
end

local function clone_array(source)
    local out = {}
    if type(source) ~= 'table' then
        return out
    end
    for i, value in ipairs(source) do
        out[i] = value
    end
    return out
end

local function clone_status(status)
    if type(status) ~= 'table' then
        return nil
    end
    local out = {}
    for _, key in ipairs(STATUS_FIELDS) do
        local value = status[key]
        if type(value) == 'table' then
            out[key] = clone_value(value)
        elseif value ~= nil then
            out[key] = value
        end
    end
    return out
end

local function config_domain_names(config)
    local out = {}
    if type(config) ~= 'table' then
        return out
    end
    for _, domain in ipairs({
        'profile',
        'ui',
        'command',
        'combat',
        'abilities',
        'defensive',
        'movement',
        'follow',
        'targeting',
        'tank',
        'sleep',
        'spells',
        'maintenance',
        'summoner',
        'puppetmaster',
        'sch',
        'debug',
        'ownership',
        'legacy',
    }) do
        if type(config[domain]) == 'table' then
            out[#out + 1] = domain
        end
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

function M.config_contract_status(settings, meta, normalizer, current_status)
    local status = clone_status(current_status)
    if status then
        return status
    end
    status = clone_status(rawget(_G, 'UC_CONFIG_CONTRACT_STATUS'))
    if status then
        return status
    end

    local resolved = normalizer_from_arg(normalizer)
    local out = {
        schema_version = 1,
        ok = false,
        available = resolved ~= nil,
        normalizer_version = type(resolved) == 'table' and type(resolved.version) == 'function' and resolved.version() or nil,
        source = 'UC_SETTINGS',
        domains = {},
        warnings = {},
        errors = {},
    }
    local resolved_meta = meta or current_meta()
    if type(resolved_meta) == 'table' then
        out.source = resolved_meta.source or out.source
        out.character = resolved_meta.character
        out.main_job = resolved_meta.main_job
        out.sub_job = resolved_meta.sub_job
        out.profile_key = resolved_meta.profile_key
    end
    if not resolved then
        out.warnings[#out.warnings + 1] = 'config normalizer unavailable'
        out.errors[#out.errors + 1] = 'config normalizer unavailable'
        return out
    end
    local ok, config = pcall(resolved.normalize, settings, resolved_meta)
    if ok and type(config) == 'table' then
        local summoner_validator = require('uc_smn_config')
        local summoner = summoner_validator.validate(config.summoner)
        local puppetmaster_validator = require('uc_pup_config')
        local puppetmaster = puppetmaster_validator.validate(config.puppetmaster, config.profile)
        out.ok = summoner.valid and puppetmaster.valid
        out.summoner = {
            enabled = summoner.enabled,
            valid = summoner.valid,
            avatar_valid = summoner.avatar_valid,
            ward_valid = summoner.ward_valid,
            rage_valid = summoner.rage_valid,
        }
        for _, issue in ipairs(summoner.errors) do
            out.errors[#out.errors + 1] = issue.message
        end
        for _, issue in ipairs(summoner.warnings) do
            out.warnings[#out.warnings + 1] = issue.message
        end
        out.puppetmaster = {
            enabled = puppetmaster.enabled,
            valid = puppetmaster.valid,
        }
        for _, issue in ipairs(puppetmaster.errors) do
            out.errors[#out.errors + 1] = issue.message
        end
        for _, issue in ipairs(puppetmaster.warnings) do
            out.warnings[#out.warnings + 1] = issue.message
        end
        out.domains = config_domain_names(config)
        if type(config.profile) == 'table' then
            out.character = out.character or config.profile.character
            out.main_job = out.main_job or config.profile.main_job
            out.sub_job = out.sub_job or config.profile.sub_job
            out.source = config.profile.source or out.source
        end
    else
        out.errors[#out.errors + 1] = tostring(config)
    end
    return out
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
