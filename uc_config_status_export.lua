local M = {}

local EXPORT_FIELDS = {
    'exported_at',
    'ok',
    'available',
    'normalizer_version',
    'source',
    'character',
    'main_job',
    'sub_job',
    'profile_key',
    'profile_v2',
    'domains',
    'warnings',
    'errors',
}

local KEY_TYPE_ORDER = {
    number = 1,
    string = 2,
    boolean = 3,
    table = 4,
}

local function clone_array(value)
    local out = {}
    if type(value) ~= 'table' then
        return out
    end
    for i, entry in ipairs(value) do
        out[i] = entry
    end
    return out
end

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        local left_type = type(left)
        local right_type = type(right)
        if left_type ~= right_type then
            return (KEY_TYPE_ORDER[left_type] or 99) < (KEY_TYPE_ORDER[right_type] or 99)
        end
        if left_type == 'number' then
            return left < right
        end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function clone_value(value, seen)
    if type(value) ~= 'table' then
        return value
    end
    local visited = seen or {}
    if visited[value] then
        return {}
    end
    visited[value] = true
    local out = {}
    for key, inner_value in pairs(value) do
        out[clone_value(key, visited)] = clone_value(inner_value, visited)
    end
    visited[value] = nil
    return out
end

local function escape_string(value)
    return string.format('%q', tostring(value))
end

local function serialize_value(value, indent, field_order)
    indent = indent or 0
    local value_type = type(value)
    if value_type == 'nil' then
        return 'nil'
    elseif value_type == 'number' or value_type == 'boolean' then
        return tostring(value)
    elseif value_type == 'string' then
        return escape_string(value)
    elseif value_type ~= 'table' then
        return escape_string(value)
    end

    local next_indent = indent + 2
    local pad = string.rep(' ', indent)
    local next_pad = string.rep(' ', next_indent)
    local parts = { '{' }
    local keys = field_order or sorted_keys(value)
    for i = 1, #keys do
        local key = keys[i]
        local inner_value = value[key]
        if inner_value ~= nil then
            local serialized_key
            if type(key) == 'string' and key:match('^[_%a][_%w]*$') ~= nil then
                serialized_key = key
            else
                serialized_key = '[' .. serialize_value(key, next_indent) .. ']'
            end
            parts[#parts + 1] = '\n' .. next_pad .. serialized_key .. ' = ' .. serialize_value(inner_value, next_indent) .. ','
        end
    end
    parts[#parts + 1] = '\n' .. pad .. '}'
    return table.concat(parts)
end

function M.build_config_status_export_payload(status, meta)
    status = type(status) == 'table' and status or {}
    meta = type(meta) == 'table' and meta or {}
    return {
        exported_at = meta.exported_at,
        ok = status.ok == true,
        available = status.available == true,
        normalizer_version = status.normalizer_version,
        source = status.source,
        character = status.character,
        main_job = status.main_job,
        sub_job = status.sub_job,
        profile_key = status.profile_key,
        profile_v2 = clone_value(status.profile_v2),
        domains = clone_array(status.domains),
        warnings = clone_array(status.warnings),
        errors = clone_array(status.errors),
    }
end

function M.render_config_status_export(status, meta)
    local payload = M.build_config_status_export_payload(status, meta)
    return 'return ' .. serialize_value(payload, 0, EXPORT_FIELDS) .. '\n'
end

return M
