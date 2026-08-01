local M = {}

local REQUIRED_TOP_LEVEL = {
    fixture_id = "string",
    input = "table",
    expected = "table",
}

local REQUIRED_INPUT = {
    old_normalized = "table",
    new_normalized = "table",
}

local REQUIRED_EXPECTED = {
    same_structure = "boolean",
    side_effects_forbidden = "boolean",
}

local OPTIONAL_TOP_LEVEL = {
    description = "string",
    tags = "table",
}

local OPTIONAL_EXPECTED = {
    notes = "string",
    runner_ok = "boolean",
}

local function add_error(errors, path, message)
    errors[#errors + 1] = path .. ": " .. message
end

local function validate_allowed_keys(obj, allowed_map, path, errors)
    for k, _ in pairs(obj) do
        if allowed_map[k] == nil then
            add_error(errors, path .. "." .. tostring(k), "unexpected key")
        end
    end
end

local function validate_required_fields(obj, field_map, path, errors)
    for field, expected_type in pairs(field_map) do
        local value = rawget(obj, field)
        if value == nil then
            add_error(errors, path .. "." .. field, "missing required field")
        elseif type(value) ~= expected_type then
            add_error(
                errors,
                path .. "." .. field,
                "expected type " .. expected_type .. ", got " .. type(value)
            )
        end
    end
end

local function validate_optional_fields(obj, field_map, path, errors)
    for field, expected_type in pairs(field_map) do
        local value = rawget(obj, field)
        if value ~= nil and type(value) ~= expected_type then
            add_error(
                errors,
                path .. "." .. field,
                "expected type " .. expected_type .. ", got " .. type(value)
            )
        end
    end
end

local function merged_keys(a, b)
    local out = {}
    for k, v in pairs(a) do
        out[k] = v
    end
    for k, v in pairs(b) do
        out[k] = v
    end
    return out
end

function M.validate(fixture)
    local errors = {}

    if type(fixture) ~= "table" then
        return {
            ok = false,
            errors = { "$: expected fixture table, got " .. type(fixture) },
        }
    end

    validate_required_fields(fixture, REQUIRED_TOP_LEVEL, "$", errors)
    validate_optional_fields(fixture, OPTIONAL_TOP_LEVEL, "$", errors)
    validate_allowed_keys(fixture, merged_keys(REQUIRED_TOP_LEVEL, OPTIONAL_TOP_LEVEL), "$", errors)

    local fixture_id = rawget(fixture, "fixture_id")
    if type(fixture_id) == "string" and fixture_id == "" then
        add_error(errors, "$.fixture_id", "must not be empty")
    end

    local input = rawget(fixture, "input")
    if type(input) == "table" then
        validate_required_fields(input, REQUIRED_INPUT, "$.input", errors)
        validate_allowed_keys(input, REQUIRED_INPUT, "$.input", errors)
    end

    local expected = rawget(fixture, "expected")
    if type(expected) == "table" then
        validate_required_fields(expected, REQUIRED_EXPECTED, "$.expected", errors)
        validate_optional_fields(expected, OPTIONAL_EXPECTED, "$.expected", errors)
        validate_allowed_keys(expected, merged_keys(REQUIRED_EXPECTED, OPTIONAL_EXPECTED), "$.expected", errors)
    end

    local tags = rawget(fixture, "tags")
    if tags ~= nil and type(tags) == "table" then
        for i, tag in pairs(tags) do
            if type(i) ~= "number" then
                add_error(errors, "$.tags", "tags must be an array-like table")
                break
            end
            if type(tag) ~= "string" or tag == "" then
                add_error(errors, "$.tags[" .. tostring(i) .. "]", "tag must be a non-empty string")
            end
        end
    end

    return {
        ok = #errors == 0,
        errors = errors,
    }
end

function M.assert_valid(fixture)
    local result = M.validate(fixture)
    if not result.ok then
        error("fixture validation failed: " .. table.concat(result.errors, "; "))
    end
    return true
end

return M
