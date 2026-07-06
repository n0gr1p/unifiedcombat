local INVENTORY_BASELINE = {
    ["unified_scheduler.lua"] = {
        ["windower.send_command("] = {},
        ["windower.ffxi.run("] = {},
        ["uc_settarget.select_by_id("] = {},
    },
    ["unified_combat_core.lua"] = {
        ["windower.send_command("] = { 1820, 1841, 2007, 2018, 2951, 2965, 3637 },
        ["windower.ffxi.run("] = { 1426, 1435, 1440, 1793, 1812, 1895, 1921, 1930, 1981, 2086, 2209, 2228, 2242, 2248, 2288, 2327, 2347, 2352, 2386, 3204, 3220 },
        ["uc_settarget.select_by_id("] = { 1919, 2055 },
    },
    ["UnifiedCombat.lua"] = {
        ["windower.ffxi.run("] = { 401 },
    },
    ["uc_party_follow.lua"] = {
        ["windower.ffxi.run("] = { 906, 937, 947, 960, 965, 970 },
    },
    ["uc_pathing.lua"] = {
        ["windower.ffxi.run("] = { 895, 905 },
    },
    ["uc_add_control.lua"] = {
        ["windower.send_command("] = { 433, 474, 476 },
    },
    ["remote_bridge.lua"] = {
        ["windower.send_command("] = { 1575 },
    },
    ["melee_engine.lua"] = {
        ["windower.send_command("] = { 377, 382, 661, 667, 814, 820, 1040, 1042, 1922, 2005, 2029, 2104, 2126, 2131, 2196, 2226, 2346, 2419, 2524, 2591, 2600, 2623, 2640, 2649 },
        ["windower.ffxi.run("] = { 1796, 1806, 1831 },
    },
    ["dd2_engine.lua"] = {
        ["windower.send_command("] = { 209, 939, 1090, 1094, 1304, 1312, 1402, 1405, 1465, 1508, 1511, 1607, 1608, 1610, 1635, 1637, 1639, 1678, 1683, 1697, 1701, 1739, 1741, 1781, 1783, 1796, 2211, 2217, 2224, 2234, 2235, 2238 },
        ["windower.ffxi.run("] = { 1103, 1106, 1115, 1118, 1305, 1335, 1346, 1370, 1777, 1789 },
    },
    ["dd2_module.lua"] = {
        ["windower.send_command("] = { 219, 1103, 1253, 1257, 1495, 1503, 1594, 1597, 1660, 1706, 1709, 1805, 1806, 1808, 1835, 1837, 1839, 1875, 1880, 1894, 1898, 1936, 1938, 1978, 1980, 1993, 2415, 2421, 2428, 2438, 2439, 2442 },
        ["windower.ffxi.run("] = { 1266, 1269, 1278, 1281, 1496, 1526, 1537, 1561, 1974, 1986 },
    },
    ["lor/lor_actor.lua"] = {
        ["windower.send_command("] = { 86 },
        ["windower.ffxi.run("] = { 194, 205 },
    },
    ["lor/lor_chat.lua"] = {
        ["windower.send_command("] = { 131 },
    },
}

local PATTERNS = {
    "windower.send_command(",
    "windower.ffxi.run(",
    "uc_settarget.select_by_id(",
}

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

local function collect_lines(path)
    local lines = read_lines(path)
    local found = {}
    for _, pattern in ipairs(PATTERNS) do
        found[pattern] = {}
    end

    for idx, line in ipairs(lines) do
        if not is_comment_line(line) then
            for _, pattern in ipairs(PATTERNS) do
                if line:find(pattern, 1, true) then
                    found[pattern][#found[pattern] + 1] = idx
                end
            end
        end
    end

    return found
end

local function join_numbers(nums)
    if #nums == 0 then
        return "(none)"
    end
    local out = {}
    for i = 1, #nums do
        out[i] = tostring(nums[i])
    end
    return table.concat(out, ",")
end

local function same_numbers(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function main()
    local failures = {}
    local checked_files = 0
    local checked_patterns = 0

    io.stdout:write("selftest_side_effect_inventory: checking baseline callsites\n")

    for path, expected_patterns in pairs(INVENTORY_BASELINE) do
        checked_files = checked_files + 1
        local actual_patterns = collect_lines(path)

        for _, pattern in ipairs(PATTERNS) do
            local expected = expected_patterns[pattern] or {}
            local actual = actual_patterns[pattern] or {}
            checked_patterns = checked_patterns + 1
            if not same_numbers(expected, actual) then
                failures[#failures + 1] = {
                    path = path,
                    pattern = pattern,
                    expected = join_numbers(expected),
                    actual = join_numbers(actual),
                }
            end
        end
    end

    if #failures > 0 then
        io.stdout:write("selftest_side_effect_inventory: FAIL\n")
        for _, failure in ipairs(failures) do
            io.stdout:write("- " .. failure.path .. " | " .. failure.pattern .. "\n")
            io.stdout:write("  expected: " .. failure.expected .. "\n")
            io.stdout:write("  actual:   " .. failure.actual .. "\n")
        end
        error("side-effect inventory mismatch: " .. tostring(#failures) .. " difference(s)")
    end

    io.stdout:write(
        "selftest_side_effect_inventory: OK (files="
            .. tostring(checked_files)
            .. ", patterns="
            .. tostring(checked_patterns)
            .. ")\n"
    )
end

main()
