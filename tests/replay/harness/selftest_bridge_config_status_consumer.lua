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

local function read_file(path)
    local fh, err = io.open(path, "r")
    if not fh then
        error("failed to open " .. tostring(path) .. ": " .. tostring(err))
    end
    local content = fh:read("*a")
    fh:close()
    return content
end

local function assert_contains(source, needle, message)
    assert_true(source:find(needle, 1, true) ~= nil, message .. ": missing " .. needle)
end

local function assert_not_contains(source, needle, message)
    assert_true(source:find(needle, 1, true) == nil, message .. ": unexpected " .. needle)
end

local function list_has(list, expected)
    for _, value in ipairs(list or {}) do
        if value == expected then
            return true
        end
    end
    return false
end

local function main()
    package.loaded["uc_config_runtime"] = nil
    package.loaded["uc_config_normalizer"] = nil
    local runtime = require("uc_config_runtime")
    local normalizer = require("uc_config_normalizer")

    local previous_global_status = _G.UC_CONFIG_CONTRACT_STATUS
    _G.UC_CONFIG_CONTRACT_STATUS = nil

    local current_status = {
        schema_version = 1,
        ok = true,
        available = true,
        normalizer_version = 1,
        source = "UC_SETTINGS",
        character = "Tester",
        main_job = "BRD",
        sub_job = "WHM",
        profile_key = "Tester|BRD|WHM",
        domains = { "profile", "ui" },
        warnings = { "sample warning" },
        errors = {},
        updated_at = 123.5,
        profile_v2 = {
            path = "data/profiles_v2/test.lua",
            state = "valid_diff",
            valid = true,
            diff_count = 2,
            reason = "runtime differs from file",
            source = "ui",
            character = "Tester",
            main_job = "BRD",
            sub_job = "WHM",
        },
        config = { should_not_escape = true },
        settings = { should_not_escape = true },
    }
    local cloned = runtime.config_contract_status({ show_ingame_ui = false }, { source = "UC_SETTINGS" }, normalizer, current_status)
    assert_true(cloned ~= current_status, "status accessor must not return the source table")
    assert_true(cloned.domains ~= current_status.domains, "status accessor must clone domain array")
    assert_equal(cloned.ok, true, "status ok mismatch")
    assert_equal(cloned.available, true, "status availability mismatch")
    assert_equal(cloned.normalizer_version, 1, "status normalizer version mismatch")
    assert_equal(cloned.source, "UC_SETTINGS", "status source mismatch")
    assert_equal(cloned.character, "Tester", "status character mismatch")
    assert_equal(cloned.main_job, "BRD", "status main job mismatch")
    assert_equal(cloned.sub_job, "WHM", "status sub job mismatch")
    assert_equal(cloned.profile_key, "Tester|BRD|WHM", "status profile key mismatch")
    assert_equal(cloned.updated_at, 123.5, "status updated_at mismatch")
    assert_true(type(cloned.profile_v2) == "table", "status accessor must preserve profile_v2")
    assert_equal(cloned.profile_v2.path, "data/profiles_v2/test.lua", "status profile_v2 path mismatch")
    assert_equal(cloned.profile_v2.state, "valid_diff", "status profile_v2 state mismatch")
    assert_equal(cloned.profile_v2.diff_count, 2, "status profile_v2 diff count mismatch")
    assert_equal(cloned.profile_v2.reason, "runtime differs from file", "status profile_v2 reason mismatch")
    assert_true(list_has(cloned.domains, "profile"), "status domains must be preserved")
    assert_true(list_has(cloned.domains, "ui"), "status domains must be preserved")
    assert_equal(cloned.config, nil, "status accessor must not return full config")
    assert_equal(cloned.settings, nil, "status accessor must not return settings")

    local from_normalizer = runtime.config_contract_status({
        engine_mode = "UC",
        show_ingame_ui = true,
        ability_active = true,
    }, {
        source = "UC_SETTINGS",
        character = "Tester",
        main_job = "WAR",
    }, normalizer)
    assert_equal(from_normalizer.ok, true, "normalizer-backed status should be ok")
    assert_equal(from_normalizer.available, true, "normalizer-backed status should be available")
    assert_equal(from_normalizer.normalizer_version, normalizer.version(), "normalizer-backed version mismatch")
    assert_true(list_has(from_normalizer.domains, "profile"), "normalizer-backed status must include profile domain")
    assert_true(list_has(from_normalizer.domains, "legacy"), "normalizer-backed status must include legacy domain")
    assert_equal(from_normalizer.config, nil, "normalizer-backed status must not expose full config")
    assert_equal(from_normalizer.settings, nil, "normalizer-backed status must not expose settings")

    local unavailable = runtime.config_contract_status({}, { source = "UC_SETTINGS" }, false)
    assert_equal(unavailable.ok, false, "unavailable normalizer status should not be ok")
    assert_equal(unavailable.available, false, "unavailable normalizer status should report unavailable")
    assert_true(list_has(unavailable.warnings, "config normalizer unavailable"), "unavailable status warning mismatch")
    assert_true(list_has(unavailable.errors, "config normalizer unavailable"), "unavailable status error mismatch")

    _G.UC_CONFIG_CONTRACT_STATUS = previous_global_status

    local bridge_source = read_file("remote_bridge.lua")
    local runtime_source = read_file("uc_config_runtime.lua")
    local export_source = read_file("uc_config_status_export.lua")
    local scheduler_source = read_file("unified_scheduler.lua")

    assert_contains(bridge_source, "local uc_config_runtime = require('uc_config_runtime')", "bridge must require config runtime helper")
    assert_contains(bridge_source, "config_contract_status = uc_config_runtime.config_contract_status(_G.UC_SETTINGS)", "bridge state/options must use runtime status accessor")
    assert_not_contains(bridge_source, "config_contract_status = _G.UC_CONFIG_CONTRACT_STATUS", "bridge must not publish config status through direct global coupling")
    assert_contains(bridge_source, "profile_contract_status = _G.UC_PROFILE_CONTRACT_STATUS", "bridge must keep profile status")
    assert_not_contains(bridge_source, "cfg_version", "retired generic bridge set version gate must stay removed")
    assert_not_contains(bridge_source, "apply_set(", "retired generic bridge flat writer must stay removed")
    assert_not_contains(bridge_source, "op == 'set'", "retired generic bridge set receiver must stay removed")
    assert_not_contains(bridge_source, "normalized_config =", "bridge must not expose full normalized config")
    assert_not_contains(bridge_source, "UC_SETTINGS =", "bridge snapshots must not expose settings as a field")

    assert_contains(runtime_source, "function M.config_contract_status(settings, meta, normalizer, current_status)", "runtime helper must expose compact status accessor")
    assert_not_contains(runtime_source, "M.config_contract_status = M.normalize_current_config", "status accessor must not return full normalized config")
    assert_contains(runtime_source, "'profile_v2'", "runtime helper must preserve nested profile v2 status")
    assert_not_contains(export_source, "config = ", "export must not include full normalized config")
    assert_not_contains(export_source, "settings", "export must not include UC_SETTINGS")
    assert_not_contains(scheduler_source, "uc_config_runtime", "scheduler/provider code must not use config runtime helper")

    io.stdout:write("selftest_bridge_config_status_consumer: OK\n")
end

main()
