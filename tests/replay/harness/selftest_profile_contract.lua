local function assert_true(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values are not equal") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function snapshot_globals()
    local snapshot = {}
    for key in pairs(_G) do
        snapshot[key] = true
    end
    return snapshot
end

local function assert_same_globals(before, after)
    for key in pairs(before) do
        assert_true(after[key] == true, "global key disappeared: " .. tostring(key))
    end
    for key in pairs(after) do
        assert_true(before[key] == true, "module introduced unexpected _G key: " .. tostring(key))
    end
end

local function assert_error_entries(result, message)
    assert_true(type(result) == "table", message .. " result must be a table")
    assert_true(result.ok == false, message .. " must fail safely")
    assert_true(type(result.errors) == "table", message .. " errors must be a table")
    assert_true(#result.errors > 0, message .. " must report at least one error")
end

local function main()
    local before_globals = snapshot_globals()
    package.loaded["uc_profile_contract"] = nil
    local contract = require("uc_profile_contract")
    local after_globals = snapshot_globals()

    assert_same_globals(before_globals, after_globals)

    local valid_payload = {
        version = 1,
        profiles = {
            UC = {
                WAR = {
                    ability_active = true,
                    sleepspells = { "Horde Lullaby II" },
                },
            },
        },
    }

    local valid_result = contract.validate_profile_payload(valid_payload)
    assert_true(valid_result.ok == true, "valid profile payload should pass")
    assert_equal(valid_result.version, 1, "valid payload version mismatch")
    assert_true(type(valid_result.warnings) == "table", "valid payload warnings must be a table")
    assert_true(type(valid_result.errors) == "table", "valid payload errors must be a table")

    local valid_uc_result = contract.validate_uc_profile_table(valid_payload.profiles.UC.WAR)
    assert_true(valid_uc_result.ok == true, "valid UC profile table should pass")
    local valid_tree_result = contract.validate_profile_tree(valid_payload.profiles)
    assert_true(valid_tree_result.ok == true, "valid profile tree should pass")

    assert_error_entries(contract.validate_profile_payload("bad"), "string payload")
    assert_error_entries(contract.validate_profile_payload({ version = 1 }), "missing profiles payload")
    assert_error_entries(contract.validate_profile_payload({ version = 1, profiles = "bad" }), "non-table profiles payload")
    assert_error_entries(contract.validate_uc_profile_table("bad"), "non-table UC profile table")
    assert_error_entries(contract.validate_profile_tree("bad"), "non-table profile tree")

    local shape_result = contract.validate_profile_payload({
        version = 1,
        profiles = {
            UC = {
                BRD = {
                    tank = false,
                    cor_roll_1 = "Chaos Roll",
                },
            },
        },
    })
    assert_true(shape_result.ok == true, "UC job profile shape should pass")

    local expected_categories = {
        engine_enabled = "command_owned",
        active_profile_name = "status_output_owned_by_addon",
        character = "status_output_owned_by_addon",
        main_job = "status_output_owned_by_addon",
        sub_job = "status_output_owned_by_addon",
        ability_active = "profile_owned_by_ui",
		defensive_na_limit_enabled = "profile_owned_by_ui",
		defensive_na_priority = "profile_owned_by_ui",
		defensive_curaga_enabled = "profile_owned_by_ui",
		defensive_curaga_min_targets = "profile_owned_by_ui",
		defensive_waltz_enabled = "profile_owned_by_ui",
		defensive_waltz_tp_reserve = "profile_owned_by_ui",
		defensive_divine_waltz_min_targets = "profile_owned_by_ui",
        tank = "profile_owned_by_ui",
        sleepspells = "profile_owned_by_ui",
        cor_roll_1 = "profile_owned_by_ui",
        wait_ignore_names = "profile_owned_by_ui",
        puller_name = "profile_owned_by_ui",
		puller_leash_source = "profile_owned_by_ui",
        fight_leader_name = "profile_owned_by_ui",
        fight_leader_selected = "profile_owned_by_ui",
        puller_id = "runtime_owned_by_addon",
        fight_leader_id = "runtime_owned_by_addon",
        path_points = "profile_owned_by_ui",
        debug = "profile_owned_by_ui",
        profile_v2_autoload = "profile_owned_by_ui",
        profile_v2_auto_reload_on_change = "profile_owned_by_ui",
        encounter_enabled = "profile_owned_by_ui",
        encounter_water_damage = "profile_owned_by_ui",
        local_ownership_flags = "legacy_or_ambiguous",
        scheduler_action_state = "runtime_owned_by_addon",
        pending_lock_state = "runtime_owned_by_addon",
        current_selected_action = "runtime_owned_by_addon",
        overlay_state = "runtime_owned_by_addon",
        unknown_field_name = "legacy_or_ambiguous",
    }
    for field_name, expected in pairs(expected_categories) do
        assert_equal(contract.classify_profile_field(field_name), expected, "classification mismatch for " .. field_name)
    end

    local input_snapshot = {
        character = "Peter",
        main_job = "BRD",
        sub_job = "WHM",
        engine_state = { enabled = true, mode = "UC" },
        zone_suspended = true,
        scheduler_summary = { phase = "combat", action_count = 3 },
        current_action = { kind = "spell", name = "Haste" },
        warnings = { "low battery" },
        errors = { "stale cache" },
        updated_at = 123.5,
    }
    local snapshot = contract.build_status_contract_snapshot(input_snapshot)
    assert_equal(snapshot.schema_version, 1, "status schema version mismatch")
    assert_equal(snapshot.character, "Peter", "status character mismatch")
    assert_equal(snapshot.main_job, "BRD", "status main_job mismatch")
    assert_equal(snapshot.sub_job, "WHM", "status sub_job mismatch")
    assert_equal(snapshot.profile_key, "Peter|BRD|WHM", "status profile_key mismatch")
    assert_true(snapshot.engine_state ~= input_snapshot.engine_state, "engine_state should be cloned")
    assert_true(type(snapshot.engine_state) == "table", "engine_state shape mismatch")
    assert_true(snapshot.zone_suspended == true, "zone_suspended mismatch")
    assert_true(type(snapshot.scheduler_summary) == "table", "scheduler_summary shape mismatch")
    assert_true(type(snapshot.current_action) == "table", "current_action shape mismatch")
    assert_equal(snapshot.updated_at, 123.5, "updated_at mismatch")
    assert_true(type(snapshot.warnings) == "table" and #snapshot.warnings == 1, "warnings shape mismatch")
    assert_true(type(snapshot.errors) == "table" and #snapshot.errors == 1, "errors shape mismatch")

    local profile_tree_result = contract.validate_profile_tree({
        UC = {
            WAR = {
                ability_active = true,
                tank = true,
            },
        },
    })
    assert_true(profile_tree_result.ok == true, "profile tree with UC job profile should pass")

    io.stdout:write("selftest_profile_contract: OK\n")
end

main()
