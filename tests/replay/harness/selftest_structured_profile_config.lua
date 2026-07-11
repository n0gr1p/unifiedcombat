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

local function deep_clone(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, inner_value in pairs(value) do
        out[key] = deep_clone(inner_value)
    end
    return out
end

local function deep_equal(actual, expected, seen)
    if actual == expected then
        return true
    end
    if type(actual) ~= type(expected) then
        return false
    end
    if type(actual) ~= "table" then
        return actual == expected
    end

    local pair_seen = seen or {}
    pair_seen[actual] = pair_seen[actual] or {}
    if pair_seen[actual][expected] then
        return true
    end
    pair_seen[actual][expected] = true

    local actual_count = 0
    for key, actual_value in pairs(actual) do
        actual_count = actual_count + 1
        if not deep_equal(actual_value, expected[key], pair_seen) then
            return false
        end
    end

    local expected_count = 0
    for _ in pairs(expected) do
        expected_count = expected_count + 1
    end
    return actual_count == expected_count
end

local function assert_deep_equal(actual, expected, message)
    if not deep_equal(actual, expected) then
        error(message or "tables are not deeply equal")
    end
end

local function read_file(path)
    local file, err = io.open(path, "r")
    if not file then
        error("unable to read " .. tostring(path) .. ": " .. tostring(err))
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function load_lua_fixture(path)
    local chunk, err = loadstring(read_file(path), "@" .. path)
    assert_true(type(chunk) == "function", "fixture must load as Lua: " .. tostring(err))
    local ok, payload = pcall(chunk)
    assert_true(ok == true, "fixture chunk should execute")
    assert_true(type(payload) == "table", "fixture must return a table")
    return payload
end

local function build_flat_settings()
    return {
        character = "Redrogue",
        main_job = "PLD",
        sub_job = "WAR",
        source = "profile-v1",
        show_ingame_ui = true,
        engine_enabled = true,
        domain_combat_enabled = true,
        weaponskill_active = true,
        weaponskill = "Savage Blade",
        ws_mode = "smart",
        defensive_enabled = true,
        defensive_cure_enabled = true,
        def_heal_min_tier_cure = 3,
        def_heal_max_tier_cure = 4,
        def_heal_min_missing_hp = 250,
        def_heal_ignore_trusts = true,
        defensive_targeted_buffs = "Terrasjr:Honor March|Nyoourke:Valor Minuet V",
        tank = true,
        tank_enmity_actions = { "Provoke", "Flash" },
        cor_roll_1 = "Chaos Roll",
        cor_roll_2 = "Samurai Roll",
        move = true,
        spacing = true,
        path_follow_enabled = true,
        path_hunter_targets = { "Apex Bat" },
        party_follow = true,
        party_follow_leader_name = "Leader",
        add_control = true,
        add_priority_names = { "Apex Bat" },
        sleep = true,
        sleepspells = { "Sleep II", "Sleepga" },
        spell_active = true,
        spell = "Dia",
        debug = true,
        log_def_sched = true,
        domain_defensive_enabled = true,
        domain_movement_enabled = true,
        domain_maintenance_enabled = true,
        domain_follow_enabled = true,
        scheduler_dark_launch_combat = true,
        profile_v2_autoload = true,
        sub = true,
        hunter = true,
        profiles = {
            UC = {
                PLD = {
                    marker = true,
                },
            },
        },
    }
end

local function build_structured_payload()
    return {
        version = 2,
        profile = {
            schema_version = 2,
            engine = "UC",
            character = "Redrogue",
            main_job = "PLD",
            sub_job = "WAR",
            source = "profile-v2",
        },
        config = {
            ui = {
                show_ingame_ui = true,
            },
            command = {
                engine_enabled_default = true,
            },
            combat = {
                enabled = true,
                weaponskill = {
                    enabled = true,
                    primary = "Savage Blade",
                    mode = "smart",
                },
            },
            defensive = {
                enabled = true,
                cure = {
                    enabled = true,
                    min_tier = 3,
                    max_tier = 4,
                    min_missing_hp = 250,
                    ignore_trusts = true,
                },
                buffs = {
                    enabled = true,
                    self_only = true,
                    list = "",
                    targeted = {
                        { character = "Terrasjr", buff = "Honor March" },
                        { character = "Nyoourke", buff = "Valor Minuet V" },
                    },
                },
            },
            tank = {
                enabled = true,
                enmity = {
                    actions = { "Provoke", "Flash" },
                },
            },
            maintenance = {
                cor = {
                    roll_1 = "Chaos Roll",
                    roll_2 = "Samurai Roll",
                },
            },
            movement = {
                move = true,
                spacing = {
                    enabled = true,
                },
                path = {
                    follow_enabled = true,
                    hunter_targets = { "Apex Bat" },
                },
            },
            follow = {
                party = {
                    enabled = true,
                    leader_name = "Leader",
                },
            },
            targeting = {
                add_control = true,
                add_priority_names = { "Apex Bat" },
            },
            sleep = {
                enabled = true,
                order = { "Sleep II", "Sleepga" },
            },
            spells = {
                enabled = true,
                configured = "Dia",
            },
            debug = {
                enabled = true,
                def_sched = true,
            },
            ownership = {
                domain_combat_enabled = true,
                domain_defensive_enabled = true,
                domain_movement_enabled = true,
                domain_maintenance_enabled = true,
                domain_follow_enabled = true,
                scheduler_dark_launch_combat = true,
                profile_v2_autoload = true,
            },
            legacy = {
                sub = true,
                hunter = true,
                profiles = {
                    UC = {
                        PLD = {
                            marker = true,
                        },
                    },
                },
            },
        },
    }
end

local function assert_common_config(config, source)
    assert_equal(config.profile.character, "Redrogue", source .. " profile character mismatch")
    assert_equal(config.profile.main_job, "PLD", source .. " profile main job mismatch")
    assert_equal(config.profile.sub_job, "WAR", source .. " profile sub job mismatch")
    assert_equal(config.ui.show_ingame_ui, true, source .. " UI flag mismatch")
    assert_equal(config.command.engine_enabled_default, true, source .. " command default mismatch")
    assert_equal(config.combat.enabled, true, source .. " combat enabled mismatch")
    assert_equal(config.combat.weaponskill.enabled, true, source .. " WS enabled mismatch")
    assert_equal(config.combat.weaponskill.primary, "Savage Blade", source .. " WS primary mismatch")
    assert_equal(config.combat.weaponskill.mode, "smart", source .. " WS mode mismatch")
    assert_equal(config.defensive.enabled, true, source .. " defensive enabled mismatch")
    assert_equal(config.defensive.cure.enabled, true, source .. " cure enabled mismatch")
    assert_equal(config.defensive.cure.min_tier, 3, source .. " cure min tier mismatch")
    assert_equal(config.defensive.cure.max_tier, 4, source .. " cure max tier mismatch")
    assert_equal(config.defensive.cure.min_missing_hp, 250, source .. " cure min missing HP mismatch")
    assert_equal(config.defensive.cure.ignore_trusts, true, source .. " cure ignore trusts mismatch")
    assert_equal(config.defensive.buffs.targeted[1].character, "Terrasjr", source .. " targeted buff character mismatch")
    assert_equal(config.defensive.buffs.targeted[1].buff, "Honor March", source .. " targeted buff name mismatch")
    assert_equal(config.tank.enabled, true, source .. " tank enabled mismatch")
    assert_equal(config.tank.enmity.actions[2], "Flash", source .. " tank enmity mismatch")
    assert_equal(config.maintenance.cor.roll_1, "Chaos Roll", source .. " COR roll 1 mismatch")
    assert_equal(config.maintenance.cor.roll_2, "Samurai Roll", source .. " COR roll 2 mismatch")
    assert_equal(config.movement.move, true, source .. " movement move mismatch")
    assert_equal(config.movement.spacing.enabled, true, source .. " spacing mismatch")
    assert_equal(config.movement.path.follow_enabled, true, source .. " path follow mismatch")
    assert_equal(config.movement.path.hunter_targets[1], "Apex Bat", source .. " path hunter mismatch")
    assert_equal(config.follow.party.enabled, true, source .. " party follow mismatch")
    assert_equal(config.follow.party.leader_name, "Leader", source .. " party leader mismatch")
    assert_equal(config.targeting.add_control, true, source .. " targeting add control mismatch")
    assert_equal(config.targeting.add_priority_names[1], "Apex Bat", source .. " add priority mismatch")
    assert_equal(config.sleep.enabled, true, source .. " sleep enabled mismatch")
    assert_equal(config.sleep.order[2], "Sleepga", source .. " sleep order mismatch")
    assert_equal(config.spells.enabled, true, source .. " spells enabled mismatch")
    assert_equal(config.spells.configured, "Dia", source .. " spell configured mismatch")
    assert_equal(config.debug.enabled, true, source .. " debug enabled mismatch")
    assert_equal(config.debug.def_sched, true, source .. " debug defensive scheduler mismatch")
    assert_equal(config.ownership.scheduler_dark_launch_combat, true, source .. " ownership dark launch mismatch")
    assert_equal(config.ownership.profile_v2_autoload, true, source .. " ownership autoload mismatch")
    assert_equal(config.legacy.sub, true, source .. " legacy sub mismatch")
    assert_equal(config.legacy.hunter, true, source .. " legacy hunter mismatch")
    assert_equal(config.legacy.profiles.UC.PLD.marker, true, source .. " legacy profiles mismatch")
end

local function main()
    package.loaded["uc_config_normalizer"] = nil
    package.loaded["uc_config_runtime"] = nil
    package.loaded["uc_profile_contract"] = nil
    local normalizer = require("uc_config_normalizer")
    local runtime = require("uc_config_runtime")
    local contract = require("uc_profile_contract")

    local flat = build_flat_settings()
    local flat_snapshot = deep_clone(flat)
    local flat_config = normalizer.normalize(flat, { source = "profile-v1" })
    assert_deep_equal(flat, flat_snapshot, "flat input should not be mutated")
    assert_common_config(flat_config, "flat")
    assert_equal(flat_config.profile.source, "profile-v1", "flat source mismatch")

    local structured = build_structured_payload()
    local structured_snapshot = deep_clone(structured)
    local structured_config = normalizer.normalize(structured, { source = "meta-source" })
    assert_deep_equal(structured, structured_snapshot, "structured input should not be mutated")
    assert_common_config(structured_config, "structured")
    assert_equal(structured_config.profile.schema_version, 2, "structured schema version mismatch")
    assert_equal(structured_config.profile.source, "meta-source", "structured source mismatch")

    structured_config.tank.enmity.actions[1] = "Changed"
    structured_config.maintenance.cor.roll_1 = "Changed"
    structured_config.legacy.profiles.UC.PLD.marker = false
    assert_deep_equal(structured, structured_snapshot, "output edits should not mutate structured input")

    local direct_config = normalizer.normalize(structured.config, {
        character = "Redrogue",
        main_job = "PLD",
        sub_job = "WAR",
        source = "direct-config",
    })
    assert_common_config(direct_config, "direct canonical")
    assert_equal(direct_config.profile.source, "direct-config", "direct config source mismatch")

    local missing = normalizer.normalize({ version = 2, profile = { character = "Redrogue" }, config = {} })
    assert_equal(missing.profile.character, "Redrogue", "missing structured profile character mismatch")
    assert_equal(missing.combat.weaponskill.enabled, false, "missing structured WS default mismatch")
    assert_equal(missing.defensive.cure.min_tier, 3, "missing structured cure default mismatch")
    assert_equal(missing.maintenance.cor.roll_1, "", "missing structured COR default mismatch")

    assert_true(pcall(function()
        local malformed = normalizer.normalize({ version = 2, profile = "bad", config = "bad" })
        assert_equal(type(malformed), "table", "malformed normalized output should be a table")
        assert_equal(malformed.profile.source, "UC_SETTINGS", "malformed source should use default")
    end), "malformed structured input should not throw")

    local ui_fixture = load_lua_fixture("tests/replay/fixtures/shared/ui_authored_profile_v2_fixture.lua")
    local ui_fixture_snapshot = deep_clone(ui_fixture)
    local ui_fixture_config = normalizer.normalize(ui_fixture, { source = "meta-source" })
    assert_deep_equal(ui_fixture, ui_fixture_snapshot, "UI-authored fixture input should not be mutated")
    assert_equal(ui_fixture_config.profile.source, "meta-source", "UI-authored fixture source mismatch")
    assert_equal(ui_fixture_config.profile.character, "Redrogue", "UI-authored fixture profile character mismatch")
    assert_equal(ui_fixture_config.profile.main_job, "PLD", "UI-authored fixture profile main job mismatch")
    assert_equal(ui_fixture_config.profile.sub_job, "WAR", "UI-authored fixture profile sub job mismatch")
    assert_equal(ui_fixture_config.combat.weaponskill.primary, "Savage Blade", "UI-authored fixture combat mismatch")
    assert_equal(ui_fixture_config.movement.path.file_name, "route-a", "UI-authored fixture path file mismatch")
    assert_equal(#ui_fixture_config.movement.path.hunter_targets, 0, "UI-authored fixture path hunter list mismatch")
    assert_equal(ui_fixture_config.follow.party.leader_name, "Leader", "UI-authored fixture party leader mismatch")
    assert_equal(ui_fixture_config.follow.partner.puller_name, "Niightsiide", "UI-authored fixture puller name mismatch")
    assert_equal(ui_fixture_config.sleep.enabled, false, "UI-authored fixture sleep enabled mismatch")
    assert_equal(ui_fixture_config.sleep.order[1], "Horde Lullaby II", "UI-authored fixture sleep order mismatch")
    assert_equal(ui_fixture_config.legacy.profiles.UC.PLD.marker, true, "UI-authored fixture legacy marker mismatch")
    assert_equal(ui_fixture.profile.source, "ui", "UI-authored fixture metadata source mismatch")
    assert_true(ui_fixture.profile.exported_at == nil, "UI-authored fixture should not require exported_at metadata")
    assert_true(ui_fixture.profile.profile_key == nil, "UI-authored fixture should not require profile_key metadata")

    assert_equal(runtime.ingame_ui_enabled(structured, { source = "profile-v2" }, normalizer), true, "runtime structured UI enabled mismatch")
    local structured_disabled = build_structured_payload()
    structured_disabled.config.ui.show_ingame_ui = false
    assert_equal(runtime.ingame_ui_enabled(structured_disabled, { source = "profile-v2" }, normalizer), false, "runtime structured UI disabled mismatch")
    assert_equal(type(runtime.normalize_current_config({ version = 2, config = "bad" }, nil, normalizer)), "table", "runtime malformed normalize should return config")

    local contract_result = contract.validate_structured_profile_config(structured)
    assert_true(contract_result.ok == true, "structured profile contract should pass")
    assert_equal(contract_result.version, 2, "structured profile contract version mismatch")
    local ui_fixture_contract = contract.validate_structured_profile_config(ui_fixture)
    assert_true(ui_fixture_contract.ok == true, "UI-authored fixture contract should pass")
    local bad_contract = contract.validate_structured_profile_config({ version = 2, profile = "bad", config = {} })
    assert_true(bad_contract.ok == false, "bad structured profile contract should fail safely")
    assert_true(#bad_contract.errors > 0, "bad structured profile contract should report errors")

    io.stdout:write("selftest_structured_profile_config: OK\n")
end

main()
