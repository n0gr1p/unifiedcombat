local allowlist = dofile("tests/replay/fixtures/shared/profile_v2_flat_surface_allowlist.lua")

if type(allowlist) ~= "table" or tonumber(allowlist.schema_version) ~= 1 then
    error("profile-v2 flat-surface allowlist schema_version must be 1")
end
if type(allowlist.patterns) ~= "table" or #allowlist.patterns == 0 then
    error("profile-v2 flat-surface patterns must be a non-empty array")
end
if type(allowlist.files) ~= "table" then
    error("profile-v2 flat-surface files must be a table")
end

local function normalize_path(path)
    return tostring(path or ""):gsub("\\", "/"):gsub("^%./", "")
end

local function is_scanned_source(path)
    local normalized = normalize_path(path)
    if not (normalized:match("%.lua$") or normalized:match("%.cs$") or normalized:match("%.py$")) then
        return false
    end
    local excluded_prefixes = {
        "tests/",
        "docs/",
        "RFC/",
        "RFC_",
        "SMN_RFC/",
        "GEO_PULLER_RFC/",
        "UnifiedCombatWinForms/%TEMP%/",
        "UnifiedCombatWinForms/bin/",
        "UnifiedCombatWinForms/obj/",
    }
    for _, prefix in ipairs(excluded_prefixes) do
        if normalized:sub(1, #prefix) == prefix then
            return false
        end
    end
    return true
end

local function discover_source_files()
    local pipe = io.popen("git ls-files", "r")
    if not pipe then
        error("profile-v2 flat-surface guard requires a Git working tree for repository-wide discovery")
    end
    local out = {}
    for line in pipe:lines() do
        local path = normalize_path(line)
        if path ~= "" and is_scanned_source(path) then
            out[#out + 1] = path
        end
    end
    pipe:close()
    table.sort(out)
    if #out == 0 then
        error("profile-v2 flat-surface guard discovered no source files")
    end
    return out
end

local function read_all(path)
    local fh, err = io.open(path, "r")
    if not fh then
        error("failed to open " .. tostring(path) .. ": " .. tostring(err))
    end
    local content = fh:read("*a")
    fh:close()
    return content
end

local function count_literal(content, literal)
    local count = 0
    local from = 1
    while true do
        local first, last = content:find(literal, from, true)
        if first == nil then
            return count
        end
        count = count + 1
        from = last + 1
    end
end

local function has_hits(counts)
    for _, value in pairs(counts) do
        if tonumber(value) and value > 0 then
            return true
        end
    end
    return false
end

local function main()
    local failures = {}
    local discovered = discover_source_files()
    local discovered_set = {}
    local observed_hits = 0

    for _, path in ipairs(discovered) do
        discovered_set[path] = true
        local content = read_all(path)
        local actual = {}
        for _, pattern in ipairs(allowlist.patterns) do
            if type(pattern.key) ~= "string" or pattern.key == "" then
                error("flat-surface pattern key must be non-empty")
            end
            if type(pattern.literal) ~= "string" or pattern.literal == "" then
                error("flat-surface pattern literal must be non-empty")
            end
            actual[pattern.key] = count_literal(content, pattern.literal)
            observed_hits = observed_hits + actual[pattern.key]
        end

        local expected = allowlist.files[path]
        if has_hits(actual) and type(expected) ~= "table" then
            failures[#failures + 1] = path .. " introduced a flat-config surface but is not allowlisted"
        elseif type(expected) == "table" then
            for _, pattern in ipairs(allowlist.patterns) do
                local expected_count = tonumber(expected[pattern.key]) or 0
                local actual_count = tonumber(actual[pattern.key]) or 0
                if actual_count ~= expected_count then
                    failures[#failures + 1] = ("%s | %s expected=%d actual=%d"):format(
                        path, pattern.key, expected_count, actual_count
                    )
                end
            end
        end
    end

    for path in pairs(allowlist.files) do
        if discovered_set[path] ~= true then
            failures[#failures + 1] = path .. " is allowlisted but no longer exists in the source inventory"
        end
    end

    if #failures > 0 then
        io.stdout:write("selftest_profile_v2_flat_surface_guard: FAIL\n")
        for _, failure in ipairs(failures) do
            io.stdout:write("- " .. failure .. "\n")
        end
        error("profile-v2 flat-surface guard mismatch: " .. tostring(#failures) .. " difference(s)")
    end

    io.stdout:write(
        "selftest_profile_v2_flat_surface_guard: OK (source_files="
            .. tostring(#discovered)
            .. ", allowlisted_files="
            .. tostring((function() local n = 0 for _ in pairs(allowlist.files) do n = n + 1 end return n end)())
            .. ", observed_hits="
            .. tostring(observed_hits)
            .. ")\n"
    )
end

main()
