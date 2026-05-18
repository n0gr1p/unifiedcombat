local M = {}

function M.copy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end

    local out = {}
    seen[value] = out

    for k, v in pairs(value) do
        local copied_key = M.copy(k, seen)
        local copied_value = M.copy(v, seen)
        out[copied_key] = copied_value
    end

    return out
end

return M
