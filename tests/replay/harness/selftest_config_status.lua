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
    for _, value in ipairs(list) do
        if value == expected then
            return true
        end
    end
    return false
end

local function main()
    local addon_source = read_file("UnifiedCombat.lua")
    local bridge_source = read_file("remote_bridge.lua")

    assert_contains(addon_source, "local UC_CONFIG_NORMALIZER = nil", "addon must keep normalizer load status local")
    assert_contains(addon_source, "pcall(require, 'uc_config_normalizer')", "normalizer require must fail safely")
    assert_contains(addon_source, "_G.UC_CONFIG_CONTRACT_STATUS = {", "addon must publish read-only config status")
    assert_contains(addon_source, "function uc_update_config_contract_status(context)", "addon must build config status snapshots")
    assert_contains(addon_source, "profile_v2 = uc_update_profile_v2_contract_status(context)", "addon must publish profile v2 status in config snapshots")
    assert_contains(addon_source, "local config = uc_current_profile_v2_config(context, meta)", "config status must consume canonical active config")
    assert_not_contains(addon_source, "pcall(UC_CONFIG_NORMALIZER.normalize, settings, meta)", "config status must not rebuild canonical state from flat settings")
    assert_contains(addon_source, "status.domains = uc_config_domain_names(config)", "status must expose domain names")
    assert_contains(addon_source, "status.errors[#status.errors + 1] = UC_CONFIG_NORMALIZER_LOAD_ERROR", "missing normalizer must publish an error")
    assert_contains(addon_source, "uc_update_config_contract_status({", "profile load/reload must refresh config status")
    assert_not_contains(addon_source, "_G.UC_CONFIG =", "full normalized config must not be stored globally")
    assert_not_contains(addon_source, "_G.UC_NORMALIZED_CONFIG", "full normalized config must not be stored globally")

    assert_contains(bridge_source, "config_contract_status = uc_config_runtime.config_contract_status(nil, nil, nil, _G.UC_CONFIG_CONTRACT_STATUS)", "bridge snapshots must clone the published config status without flat settings input")
    assert_not_contains(bridge_source, "config_contract_status(_G.UC_SETTINGS)", "bridge config status must not depend on flat settings")
    assert_contains(bridge_source, "profile_contract_status = _G.UC_PROFILE_CONTRACT_STATUS", "bridge must keep profile status")
    assert_not_contains(bridge_source, "cfg_version", "retired generic bridge set version gate must stay removed")
    assert_not_contains(bridge_source, "apply_set(", "retired generic bridge flat writer must stay removed")
    assert_not_contains(bridge_source, "op == 'set'", "retired generic bridge set receiver must stay removed")
    assert_not_contains(bridge_source, "config = _G.UC_CONFIG_CONTRACT_STATUS", "bridge must not expose status as full config")
    assert_not_contains(bridge_source, "normalized_config =", "bridge must not expose full normalized config")
    assert_not_contains(bridge_source, "config = UC_CONFIG_NORMALIZER", "bridge must not expose the normalizer output")

    package.loaded["uc_config_normalizer"] = nil
    local normalizer = require("uc_config_normalizer")
    local config = normalizer.normalize({
        engine_mode = "UC",
        character = "Peter",
        main_job = "BRD",
        sub_job = "WHM",
        ability_active = true,
        sleepspells = { "Horde Lullaby II" },
    }, {
        source = "UC_SETTINGS",
    })
    local domains = {
        "profile",
        "ui",
        "command",
        "combat",
        "abilities",
        "defensive",
        "movement",
        "follow",
        "targeting",
        "tank",
        "sleep",
        "spells",
        "maintenance",
        "debug",
        "ownership",
        "legacy",
    }
    for _, domain in ipairs(domains) do
        assert_equal(type(config[domain]), "table", "normalizer domain missing: " .. domain)
    end

    local status_domains = {}
    for _, domain in ipairs(domains) do
        if type(config[domain]) == "table" then
            status_domains[#status_domains + 1] = domain
        end
    end
    assert_equal(#status_domains, #domains, "status domain summary should include each canonical top-level domain")
    assert_true(list_has(status_domains, "profile"), "status domain summary should include profile")
    assert_true(list_has(status_domains, "legacy"), "status domain summary should include legacy")
    assert_equal(normalizer.version(), 1, "normalizer version mismatch")

    io.stdout:write("selftest_config_status: OK\n")
end

main()
