local SELFTESTS = {
    "tests/replay/harness/selftest_replay_harness.lua",
    "tests/replay/harness/selftest_fixture_validator.lua",
    "tests/replay/harness/selftest_fixture_runner.lua",
    "tests/replay/harness/selftest_fixture_suite_runner.lua",
    "tests/replay/harness/selftest_runtime_parse.lua",
    "tests/replay/harness/selftest_side_effect_inventory.lua",
    "tests/replay/harness/selftest_dispatcher_fixtures.lua",
    "tests/replay/harness/selftest_movement_priority_arbitration.lua",
    "tests/replay/harness/selftest_zero_hp_actionable_target.lua",
    "tests/replay/harness/selftest_alliance_target_scope.lua",
    "tests/replay/harness/selftest_scheduler_ownership_closure_static.lua",
    "tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua",
    "tests/replay/harness/selftest_scheduler_ownership_flags_static.lua",
    "tests/replay/harness/selftest_scheduler_ownership_field_docs_static.lua",
    "tests/replay/harness/selftest_run_ownership_static.lua",
    "tests/replay/harness/selftest_run_ownership_runtime.lua",
    "tests/replay/harness/selftest_run_stop_ownership_static.lua",
    "tests/replay/harness/selftest_run_stop_ownership_runtime.lua",
    "tests/replay/harness/selftest_turn_ownership_static.lua",
    "tests/replay/harness/selftest_turn_ownership_runtime.lua",
    "tests/replay/harness/selftest_target_ownership_static.lua",
    "tests/replay/harness/selftest_target_ownership_runtime.lua",
    "tests/replay/harness/selftest_command_ownership_static.lua",
    "tests/replay/harness/selftest_command_ownership_runtime.lua",
    "tests/replay/harness/selftest_status_snapshot_063_fixtures.lua",
    "tests/replay/harness/selftest_enemy_effect_utils_fixtures.lua",
    "tests/replay/harness/selftest_text_utils_fixtures.lua",
    "tests/replay/harness/selftest_action_metadata_fixtures.lua",
    "tests/replay/harness/selftest_command_builder_fixtures.lua",
    "tests/replay/harness/selftest_numeric_utils_fixtures.lua",
    "tests/replay/harness/selftest_proposal_keys_fixtures.lua",
    "tests/replay/harness/selftest_maintenance_utils_fixtures.lua",
    "tests/replay/harness/selftest_defensive_utils_fixtures.lua",
    "tests/replay/harness/selftest_action_predicates_fixtures.lua",
    "tests/replay/harness/selftest_geometry_fixtures.lua",
    "tests/replay/harness/selftest_context_utils_fixtures.lua",
    "tests/replay/harness/selftest_target_utils_fixtures.lua",
    "tests/replay/harness/selftest_rank_output_fixtures.lua",
    "tests/replay/harness/selftest_pending_record_fixtures.lua",
    "tests/replay/harness/selftest_reject_history_fixtures.lua",
    "tests/replay/harness/selftest_action_state_fixtures.lua",
    "tests/replay/harness/selftest_locks_fixtures.lua",
    "tests/replay/harness/selftest_dispatch_plan_fixtures.lua",
    "tests/replay/harness/selftest_pending_fixtures.lua",
    "tests/replay/harness/selftest_dryrun_publish_fixtures.lua",
}

local function run_one(path)
    local ok, err = pcall(function()
        dofile(path)
    end)
    return ok, err
end

local function main()
    local failures = {}

    io.stdout:write("selftest_all_replay_fixtures: running " .. tostring(#SELFTESTS) .. " suites\n")

    for i, path in ipairs(SELFTESTS) do
        io.stdout:write(string.format("[%02d/%02d] %s\n", i, #SELFTESTS, path))
        local ok, err = run_one(path)
        if ok then
            io.stdout:write("  PASS\n")
        else
            failures[#failures + 1] = {
                path = path,
                err = tostring(err),
            }
            io.stdout:write("  FAIL\n")
        end
    end

    if #failures > 0 then
        io.stdout:write("selftest_all_replay_fixtures: FAIL\n")
        for _, failure in ipairs(failures) do
            io.stdout:write("- " .. failure.path .. "\n")
            io.stdout:write("  " .. failure.err .. "\n")
        end
        error("aggregate replay selftest failed: " .. tostring(#failures) .. " suite(s) failed")
    end

    io.stdout:write("selftest_all_replay_fixtures: OK\n")
end

main()
