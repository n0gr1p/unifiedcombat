local M = {}

local MANEUVERS = {
    ['Fire Maneuver'] = true,
    ['Ice Maneuver'] = true,
    ['Wind Maneuver'] = true,
    ['Earth Maneuver'] = true,
    ['Thunder Maneuver'] = true,
    ['Water Maneuver'] = true,
    ['Light Maneuver'] = true,
    ['Dark Maneuver'] = true,
}

local function clone_value(value, seen)
    if type(value) ~= 'table' then return value end
    local visited = seen or {}
    if visited[value] then error('Puppetmaster configuration must not contain cycles') end
    visited[value] = true
    local out = {}
    for key, inner in pairs(value) do out[clone_value(key, visited)] = clone_value(inner, visited) end
    visited[value] = nil
    return out
end

local function add_issue(result, code, path, message)
    result.valid = false
    result.errors[#result.errors + 1] = { code = code, path = path, message = message }
end

local function reject_unknown_keys(result, value, path, allowed)
    if type(value) ~= 'table' then return end
    local set = {}
    for i = 1, #allowed do set[allowed[i]] = true end
    for key in pairs(value) do
        if type(key) ~= 'string' or set[key] ~= true then
            add_issue(result, 'pup_unknown_key', path, ('%s contains unknown key %q.'):format(path, tostring(key)))
        end
    end
end

local function validate_bool(result, value, path)
    if type(value) ~= 'boolean' then add_issue(result, 'pup_shape_invalid', path, path .. ' must be boolean.') end
end

local function validate_integer(result, value, path, minimum, maximum)
    if type(value) ~= 'number' or value % 1 ~= 0 or value < minimum or value > maximum then
        add_issue(result, 'pup_shape_invalid', path, ('%s must be an integer from %d to %d.'):format(path, minimum, maximum))
    end
end

local function validate_pattern(result, pattern)
    if type(pattern) ~= 'table' then
        add_issue(result, 'pup_shape_invalid', 'puppetmaster.maneuvers.pattern', 'puppetmaster.maneuvers.pattern must be an array.')
        return
    end
    local length = #pattern
    for key in pairs(pattern) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > length then
            add_issue(result, 'pup_shape_invalid', 'puppetmaster.maneuvers.pattern', 'puppetmaster.maneuvers.pattern must be a contiguous array.')
            return
        end
    end
    if length < 1 or length > 3 then
        add_issue(result, 'pup_shape_invalid', 'puppetmaster.maneuvers.pattern', 'puppetmaster.maneuvers.pattern must contain one to three maneuvers.')
    end
    for i = 1, length do
        if type(pattern[i]) ~= 'string' or MANEUVERS[pattern[i]] ~= true then
            add_issue(result, 'pup_maneuver_invalid', ('puppetmaster.maneuvers.pattern[%d]'):format(i), ('unsupported Puppetmaster maneuver: %s'):format(tostring(pattern[i])))
        end
    end
end

function M.default_config()
    return {
        enabled = false,
        activate_if_missing = true,
        deploy_on_combat_start = true,
        maneuvers = {
            enabled = true,
            pattern = { 'Fire Maneuver', 'Fire Maneuver', 'Light Maneuver' },
            post_activate_quiet_seconds = 120,
            safe_burden_ceiling = 30,
        },
    }
end

function M.validate(config, meta)
    local result = { valid = true, enabled = false, errors = {}, warnings = {} }
    if config == nil then return result end
    if type(config) ~= 'table' then
        add_issue(result, 'pup_shape_invalid', 'puppetmaster', 'puppetmaster must be a table.')
        return result
    end
    reject_unknown_keys(result, config, 'puppetmaster', { 'enabled', 'activate_if_missing', 'deploy_on_combat_start', 'maneuvers' })
    validate_bool(result, config.enabled, 'puppetmaster.enabled')
    validate_bool(result, config.activate_if_missing, 'puppetmaster.activate_if_missing')
    validate_bool(result, config.deploy_on_combat_start, 'puppetmaster.deploy_on_combat_start')
    result.enabled = config.enabled == true

    local maneuvers = config.maneuvers
    if type(maneuvers) ~= 'table' then
        add_issue(result, 'pup_shape_invalid', 'puppetmaster.maneuvers', 'puppetmaster.maneuvers must be a table.')
    else
        reject_unknown_keys(result, maneuvers, 'puppetmaster.maneuvers', { 'enabled', 'pattern', 'post_activate_quiet_seconds', 'safe_burden_ceiling' })
        validate_bool(result, maneuvers.enabled, 'puppetmaster.maneuvers.enabled')
        validate_pattern(result, maneuvers.pattern)
        validate_integer(result, maneuvers.post_activate_quiet_seconds, 'puppetmaster.maneuvers.post_activate_quiet_seconds', 0, 300)
        validate_integer(result, maneuvers.safe_burden_ceiling, 'puppetmaster.maneuvers.safe_burden_ceiling', 0, 32)
    end

    local main_job = type(meta) == 'table' and meta.main_job or nil
    if result.enabled and type(main_job) == 'string' and main_job ~= '' and main_job:upper() ~= 'PUP' then
        add_issue(result, 'pup_job_mismatch', 'puppetmaster.enabled', 'Puppetmaster automation requires main job PUP.')
    end
    return result
end

function M.copy_validated(config, meta)
    local source = config == nil and M.default_config() or config
    local validation = M.validate(source, meta)
    if validation.valid ~= true then
        return nil, validation
    end
    return clone_value(source), validation
end

function M.maneuver_names()
    local out = {}
    for name in pairs(MANEUVERS) do out[#out + 1] = name end
    table.sort(out)
    return out
end

return M
