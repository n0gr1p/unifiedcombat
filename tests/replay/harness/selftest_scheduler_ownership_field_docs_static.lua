local scheduler_path = "unified_scheduler.lua"
local packet_path = "docs/scheduler_ownership_field_test_packet.md"
local template_path = "docs/scheduler_ownership_field_test_results_template.md"

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
    local packet_source = read_file(packet_path)
    local template_source = read_file(template_path)
    local flags = collect_flags(scheduler_source)

    if #flags == 0 then
        error("expected at least one ownership flag in unified_scheduler.lua")
    end

    for _, flag in ipairs(flags) do
        assert_contains(packet_source, flag, "field-test packet must include ownership flag: " .. flag)
    end

    assert_contains(packet_source, "unset/remove", "field-test packet must include rollback language")
    assert_contains(packet_source, "set it to `false`/`nil`", "field-test packet must include explicit false/nil rollback instruction")
    assert_contains(packet_source, "reload", "field-test packet must mention reload during rollback")
    assert_contains(packet_source, "rerun the same scenario with the flag off", "field-test packet must require rerunning the same scenario with the flag off")
    assert_contains(packet_source, "Do not enable all 21 flags at once", "field-test packet must warn against enabling all flags at once")
    assert_contains(packet_source, "Do not make any flag default-on", "field-test packet must warn against default-on changes")
    assert_contains(packet_source, "Do not remove fallback paths", "field-test packet must warn against removing fallback paths during field testing")

    local required_stages = {
        "Stage 1 - Target and Turn Ownership",
        "Stage 2 - Isolated Command Ownership Paths",
        "Stage 3 - Combat Command Families",
        "Stage 4 - Isolated Run-Stop Paths",
        "Stage 5 - Movement-Coordinator Run-Stop Paths",
        "Stage 6 - Tank and Combat-Spell Run-Stop Paths",
        "Stage 7 - Vector Run Ownership",
    }
    for _, stage in ipairs(required_stages) do
        assert_contains(packet_source, stage, "field-test packet must include stage heading: " .. stage)
    end

    assert_contains(template_source, "Enabled Flags", "results template must include enabled flags section")
    assert_contains(template_source, "Expected Behavior", "results template must include expected behavior section")
    assert_contains(template_source, "Observed Behavior", "results template must include observed behavior section")
    assert_contains(template_source, "Pass/Fail", "results template must include pass/fail field")
    assert_contains(template_source, "Rollback Needed", "results template must include rollback needed field")

    io.stdout:write("selftest_scheduler_ownership_field_docs_static: OK\n")
end

main()
