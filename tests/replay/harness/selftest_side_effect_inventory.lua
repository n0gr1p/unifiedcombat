local allowlist = dofile("tests/replay/fixtures/shared/side_effect_allowlist.lua")

if type(allowlist) ~= "table" or tonumber(allowlist.schema_version) ~= 1 then
    error("side-effect allowlist schema_version must be 1")
end
if type(allowlist.patterns) ~= "table" or #allowlist.patterns == 0 then
    error("side-effect allowlist patterns must be a non-empty array")
end
if type(allowlist.files) ~= "table" then
    error("side-effect allowlist files must be a table")
end

local function normalize_path(path)
    return tostring(path or ""):gsub("\\", "/"):gsub("^%./", "")
end

local function discover_runtime_lua_files()
    local pipe = io.popen('rg --files -g "*.lua" -g "!tests/**"', "r")
    if not pipe then
        error("side-effect inventory requires rg for repository-wide discovery")
    end
    local files = {}
    for line in pipe:lines() do
        local path = normalize_path(line)
        if path ~= "" then
            files[#files + 1] = path
        end
    end
    pipe:close()
    if #files == 0 then
        error("side-effect inventory discovered no runtime Lua files")
    end
    table.sort(files)
    return files
end

local function read_lines(path)
    local fh, err = io.open(path, "r")
    if not fh then
        error("failed to open " .. tostring(path) .. ": " .. tostring(err))
    end
    local lines = {}
    for line in fh:lines() do
        lines[#lines + 1] = line
    end
    fh:close()
    return lines
end

local function is_comment_line(line)
    return line:match("^%s*%-%-") ~= nil
end

local function collect_counts(path)
    local counts = {}
    for _, pattern in ipairs(allowlist.patterns) do
        if type(pattern.key) ~= "string" or pattern.key == "" then
            error("side-effect allowlist pattern key must be non-blank")
        end
        if type(pattern.literal) ~= "string" or pattern.literal == "" then
            error("side-effect allowlist pattern literal must be non-blank")
        end
        counts[pattern.key] = 0
    end

    for _, line in ipairs(read_lines(path)) do
        if not is_comment_line(line) then
            for _, pattern in ipairs(allowlist.patterns) do
                local haystack = line
                local needle = pattern.literal
                if pattern.case_insensitive == true then
                    haystack = haystack:lower()
                    needle = needle:lower()
                end
                if haystack:find(needle, 1, true) then
                    counts[pattern.key] = counts[pattern.key] + 1
                end
            end
        end
    end
    return counts
end

local function has_any_count(counts)
    for _, count in pairs(counts) do
        if tonumber(count) and count > 0 then
            return true
        end
    end
    return false
end

local function sorted_keys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function main()
    local failures = {}
    local discovered = discover_runtime_lua_files()
    local discovered_set = {}
    local checked_pattern_count = 0
    local observed_hit_count = 0

    io.stdout:write("selftest_side_effect_inventory: scanning all runtime Lua files\n")

    for _, path in ipairs(discovered) do
        discovered_set[path] = true
        local actual = collect_counts(path)
        local expected = allowlist.files[path]
        if has_any_count(actual) and type(expected) ~= "table" then
            failures[#failures + 1] = path .. " contains side-effect patterns but is not allowlisted"
        elseif type(expected) == "table" then
            for _, pattern in ipairs(allowlist.patterns) do
                local expected_count = tonumber(expected[pattern.key]) or 0
                local actual_count = tonumber(actual[pattern.key]) or 0
                checked_pattern_count = checked_pattern_count + 1
                observed_hit_count = observed_hit_count + actual_count
                if actual_count ~= expected_count then
                    failures[#failures + 1] = (
                        "%s | %s expected=%d actual=%d"
                    ):format(path, pattern.key, expected_count, actual_count)
                end
            end
        end
    end

    for _, path in ipairs(sorted_keys(allowlist.files)) do
        if discovered_set[path] ~= true then
            failures[#failures + 1] = path .. " is allowlisted but was not discovered"
        end
    end

    if #failures > 0 then
        io.stdout:write("selftest_side_effect_inventory: FAIL\n")
        for _, failure in ipairs(failures) do
            io.stdout:write("- " .. failure .. "\n")
        end
        error("side-effect inventory mismatch: " .. tostring(#failures) .. " difference(s)")
    end

    io.stdout:write(
        "selftest_side_effect_inventory: OK (runtime_files="
            .. tostring(#discovered)
            .. ", allowlisted_files="
            .. tostring(#sorted_keys(allowlist.files))
            .. ", pattern_checks="
            .. tostring(checked_pattern_count)
            .. ", observed_hits="
            .. tostring(observed_hit_count)
            .. ")\n"
    )
end

main()
