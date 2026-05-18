local M = {}

local function append_mismatch(mismatches, path, message)
    mismatches[#mismatches + 1] = string.format("%s: %s", path, message)
end

local function join_path(path, key)
    local key_type = type(key)
    if key_type == "number" then
        return string.format("%s[%s]", path, tostring(key))
    end
    if key_type == "string" and string.match(key, "^[%a_][%w_]*$") then
        return path .. "." .. key
    end
    return string.format("%s[%q]", path, tostring(key))
end

local function compare_value(lhs, rhs, path, mismatches, seen)
    local lhs_type = type(lhs)
    local rhs_type = type(rhs)

    if lhs_type ~= rhs_type then
        append_mismatch(mismatches, path, "type mismatch (" .. lhs_type .. " vs " .. rhs_type .. ")")
        return
    end

    if lhs_type ~= "table" then
        if lhs ~= rhs then
            append_mismatch(
                mismatches,
                path,
                "value mismatch (" .. tostring(lhs) .. " vs " .. tostring(rhs) .. ")"
            )
        end
        return
    end

    seen[lhs] = seen[lhs] or {}
    if seen[lhs][rhs] then
        return
    end
    seen[lhs][rhs] = true

    for k, lhs_value in pairs(lhs) do
        local rhs_value = rawget(rhs, k)
        if rhs_value == nil then
            append_mismatch(mismatches, join_path(path, k), "missing key on right side")
        else
            compare_value(lhs_value, rhs_value, join_path(path, k), mismatches, seen)
        end
    end

    for k, rhs_value in pairs(rhs) do
        local lhs_value = rawget(lhs, k)
        if lhs_value == nil then
            if rhs_value ~= nil then
                append_mismatch(mismatches, join_path(path, k), "unexpected key on right side")
            end
        end
    end
end

function M.compare(lhs, rhs)
    local mismatches = {}
    compare_value(lhs, rhs, "$", mismatches, {})
    return #mismatches == 0, mismatches
end

return M
