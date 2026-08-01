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

local function load_export(content)
    local chunk, err = loadstring(content)
    if not chunk then
        error("export content should compile: " .. tostring(err))
    end
    local ok, value = pcall(chunk)
    if not ok then
        error("export content should load: " .. tostring(value))
    end
    return value
end

local function main()
    package.loaded["uc_config_status_export"] = nil
    local exporter = require("uc_config_status_export")

    local status = {
        ok = true,
        available = true,
        normalizer_version = 1,
        source = "UC_SETTINGS",
        character = "Peter",
        main_job = "BRD",
        sub_job = "WHM",
        profile_key = "Peter|BRD|WHM",
        domains = { "profile", "sleep", "legacy" },
        warnings = { "diagnostic warning" },
        errors = {},
        profile_v2 = {
            path = "data/profiles_v2/redrogue_PLD_WAR.lua",
            state = "valid_match",
            valid = true,
            diff_count = 0,
            reason = "runtime matches file",
            source = "ui",
            character = "Redrogue",
            main_job = "PLD",
            sub_job = "WAR",
        },
        config = { profile = { character = "must not export" } },
        settings = { engine_enabled = true },
        scheduler_summary = { action = "must not export" },
    }

    local payload = exporter.build_config_status_export_payload(status, { exported_at = 42.5 })
    assert_equal(payload.exported_at, 42.5, "exported_at mismatch")
    assert_equal(payload.ok, true, "ok mismatch")
    assert_equal(payload.available, true, "available mismatch")
    assert_equal(payload.normalizer_version, 1, "normalizer version mismatch")
    assert_equal(payload.character, "Peter", "character mismatch")
    assert_equal(payload.main_job, "BRD", "main_job mismatch")
    assert_equal(payload.sub_job, "WHM", "sub_job mismatch")
    assert_equal(payload.profile_key, "Peter|BRD|WHM", "profile_key mismatch")
    assert_true(type(payload.profile_v2) == "table", "profile v2 status must be included")
    assert_equal(payload.profile_v2.path, "data/profiles_v2/redrogue_PLD_WAR.lua", "profile v2 path mismatch")
    assert_equal(payload.profile_v2.state, "valid_match", "profile v2 state mismatch")
    assert_equal(payload.profile_v2.valid, true, "profile v2 validity mismatch")
    assert_equal(payload.profile_v2.diff_count, 0, "profile v2 diff count mismatch")
    assert_equal(payload.profile_v2.reason, "runtime matches file", "profile v2 reason mismatch")
    assert_equal(#payload.domains, 3, "domains count mismatch")
    assert_true(payload.config == nil, "full config must not be in payload")
    assert_true(payload.settings == nil, "settings must not be in payload")
    assert_true(payload.scheduler_summary == nil, "scheduler state must not be in payload")
    assert_true(payload.profile_v2.config == nil, "profile v2 payload must not include nested config internals")

    local content = exporter.render_config_status_export(status, { exported_at = 42.5 })
    assert_contains(content, "return {", "export must be Lua table content")
    assert_contains(content, "exported_at = 42.5", "export must include exported_at")
    assert_contains(content, "domains = {", "export must include domains")
    assert_contains(content, "profile_v2 = {", "export must include profile v2 status")
    assert_not_contains(content, "must not export", "export must omit non-status internals")
    assert_not_contains(content, "engine_enabled", "export must omit UC_SETTINGS")
    local loaded = load_export(content)
    assert_equal(loaded.character, "Peter", "loaded character mismatch")
    assert_equal(loaded.domains[2], "sleep", "loaded domains mismatch")
    assert_equal(loaded.profile_v2.state, "valid_match", "loaded profile v2 state mismatch")

    local missing_content = exporter.render_config_status_export(nil, { exported_at = 100 })
    local missing = load_export(missing_content)
    assert_equal(missing.ok, false, "missing status must export ok=false")
    assert_equal(missing.available, false, "missing status must export available=false")
    assert_equal(#missing.domains, 0, "missing status domains should be empty")
    assert_true(missing.profile_v2 == nil, "missing status should not synthesize profile v2 data")

    local addon_source = read_file("UnifiedCombat.lua")
    assert_contains(addon_source, "local uc_config_status_export = require('uc_config_status_export')", "addon must require export helper")
    assert_contains(addon_source, "local function uc_config_status_file_path(char_name)", "addon must define status file path")
    assert_contains(addon_source, "return 'data/status/' .. uc_safe_filename(char_name) .. '_config_contract_status.lua'", "status export path mismatch")
    assert_contains(addon_source, "local function uc_write_config_status_export(status, meta)", "addon must define export writer")
    assert_contains(addon_source, "elseif a == 'configstatus' then", "command route missing")
    assert_contains(addon_source, "if sub == 'export' then", "export subcommand missing")
    assert_contains(addon_source, "UC config status exported:", "success chat must be terse")
    assert_contains(addon_source, "UC config status export failed", "failure chat must be terse")
    assert_not_contains(addon_source, "windower.add_to_chat(207, uc_config_status_export", "command must not chat the payload")

    io.stdout:write("selftest_config_status_export: OK\n")
end

main()
