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
    'domains',
    'warnings',
    'errors',
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

local function escape_string(value)
    return string.format('%q', tostring(value))
end

local function serialize_value(value, indent)
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
    for key, inner_value in ipairs(value) do
        parts[#parts + 1] = '\n' .. next_pad .. '[' .. tostring(key) .. '] = ' .. serialize_value(inner_value, next_indent) .. ','
    end
    for _, key in ipairs(EXPORT_FIELDS) do
        if type(key) == 'string' and value[key] ~= nil then
            parts[#parts + 1] = '\n' .. next_pad .. key .. ' = ' .. serialize_value(value[key], next_indent) .. ','
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
        domains = clone_array(status.domains),
        warnings = clone_array(status.warnings),
        errors = clone_array(status.errors),
    }
end

function M.render_config_status_export(status, meta)
    local payload = M.build_config_status_export_payload(status, meta)
    return 'return ' .. serialize_value(payload, 0) .. '\n'
end

return M
