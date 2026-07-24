local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local scheduler = read("unified_scheduler.lua")
    local packet = read("docs/scheduler_ownership_field_test_packet.md")
    local template = read("docs/scheduler_ownership_field_test_results_template.md")
    assert(not scheduler:find("UC_SCHED_P1_ENABLE_DISPATCHER_", 1, true), "retired field flags must not return to runtime")
    assert(packet:find("Historical Phase 1", 1, true), "field packet must be marked historical")
    assert(template:find("Historical Phase 1", 1, true), "field result template must be marked historical")
    assert(packet:find("RFC/UnifiedCombat_scheduler_refactor_tracking.md", 1, true), "historical packet must point to current RFC tracking")
    assert(template:find("RFC/UnifiedCombat_scheduler_refactor_tracking.md", 1, true), "historical template must point to current RFC tracking")
    io.stdout:write("selftest_scheduler_ownership_field_docs_static: OK\n")
end

main()
