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

local function legacy_show(settings)
    if type(settings) ~= "table" then
        return true
    end
    return settings.show_ingame_ui ~= false
end

local function main()
    package.loaded["uc_config_runtime"] = nil
    package.loaded["uc_config_normalizer"] = nil
    local runtime = require("uc_config_runtime")
    local normalizer = require("uc_config_normalizer")

    for _, case in ipairs({
        { name = "enabled", settings = { show_ingame_ui = true } },
        { name = "disabled", settings = { show_ingame_ui = false } },
        { name = "missing", settings = {} },
        { name = "nil-settings", settings = nil },
    }) do
        assert_equal(
            runtime.ingame_ui_enabled(case.settings, { source = "UC_SETTINGS" }, normalizer),
            legacy_show(case.settings),
            "ui parity mismatch: " .. case.name
        )
    end

    assert_equal(
        runtime.ingame_ui_enabled({ show_ingame_ui = false }, { source = "UC_SETTINGS" }, false),
        false,
        "normalizer unavailable must preserve disabled legacy behavior"
    )
    assert_equal(
        runtime.ingame_ui_enabled({}, { source = "UC_SETTINGS" }, false),
        true,
        "normalizer unavailable must preserve missing legacy behavior"
    )
    assert_equal(
        runtime.ingame_ui_enabled({ show_ingame_ui = true }, { source = "UC_SETTINGS" }, {
            normalize = function()
                error("forced normalizer failure")
            end,
        }),
        true,
        "normalizer failure must preserve legacy behavior"
    )

    local addon_source = read_file("UnifiedCombat.lua")
    local bridge_source = read_file("remote_bridge.lua")
    local export_source = read_file("uc_config_status_export.lua")
    local scheduler_source = read_file("unified_scheduler.lua")
    local melee_source = read_file("melee_engine.lua")
    local dd2_source = read_file("dd2_module.lua")

    assert_contains(melee_source, "require('uc_config_runtime').ingame_ui_enabled(_G.UC_SETTINGS)", "melee UI consumer must use normalized config accessor")
    assert_contains(dd2_source, "require('uc_config_runtime').ingame_ui_enabled(_G.UC_SETTINGS)", "dd2 UI consumer must use normalized config accessor")
    assert_not_contains(addon_source, "_G.UC_CONFIG =", "addon must not expose full normalized config")
    assert_not_contains(bridge_source, "normalized_config =", "bridge must not expose full normalized config")
    assert_not_contains(export_source, "settings", "export must not include UC_SETTINGS")
    assert_not_contains(export_source, "config = ", "export must not include full normalized config")
    assert_not_contains(scheduler_source, "config.ui.show_ingame_ui", "scheduler must not consume migrated UI config")
    assert_not_contains(scheduler_source, "uc_config_runtime", "scheduler/provider code must not use first-consumer runtime helper")
    assert_contains(bridge_source, "apply_set(set_path, set_value)", "bridge write behavior must remain apply_set based")

    io.stdout:write("selftest_config_first_consumer: OK\n")
end

main()
