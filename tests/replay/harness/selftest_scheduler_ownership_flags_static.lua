local scheduler_path = "unified_scheduler.lua"
local plan_path = "docs/scheduler_ownership_promotion_plan.md"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function sorted_unique(list)
    table.sort(list)
    local out = {}
    local last = nil
    for _, value in ipairs(list) do
        if value ~= last then
            out[#out + 1] = value
            last = value
        end
    end
    return out
end

local function collect_flags(source)
    local flags = {}
    for flag in source:gmatch("UC_SCHED_P1_ENABLE_DISPATCHER_[A-Z0-9_]+_OWNERSHIP") do
        flags[#flags + 1] = flag
    end
    return sorted_unique(flags)
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local plan_source = read_file(plan_path)
    local flags = collect_flags(scheduler_source)

    if #flags == 0 then
        error("expected at least one ownership flag in unified_scheduler.lua")
    end

    for _, flag in ipairs(flags) do
        assert_contains(
            scheduler_source,
            flag .. " == true",
            "ownership flag must be guarded with explicit == true: " .. flag
        )
        assert_contains(
            plan_source,
            flag,
            "promotion plan must include ownership flag: " .. flag
        )
        if scheduler_source:find("_G%." .. flag .. "%s*=%s*true") then
            error("ownership flag must not be assigned default-on in scheduler: " .. flag)
        end
        if scheduler_source:find("if%s+_G%." .. flag) then
            error("ownership flag must not use truthy if-check in scheduler: " .. flag)
        end
        if scheduler_source:find("_G%." .. flag .. "%s*~=%s*false") then
            error("ownership flag must not use ~= false guard in scheduler: " .. flag)
        end
        if scheduler_source:find("_G%." .. flag .. "%s+or") then
            error("ownership flag must not use or-truthy fallback in scheduler: " .. flag)
        end
    end

    assert_contains(plan_source, "default-off", "promotion plan must state flags remain default-off")
    assert_contains(plan_source, "rollback", "promotion plan must include rollback language")
    assert_contains(plan_source, "unset/remove the flag or set it to `false`/`nil`", "promotion plan must include explicit rollback instruction")

    io.stdout:write("selftest_scheduler_ownership_flags_static: OK\n")
end

main()
