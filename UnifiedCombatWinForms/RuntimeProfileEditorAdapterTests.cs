using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class RuntimeProfileEditorAdapterTests
{
    internal static void Run()
    {
        TestCanonicalReconnectPreservesDurableConfiguration();
        TestCanonicalRuntimeDefaultsMissingLuopanPlacement();
        TestLegacyProjectedSnapshotStillLoads();
        TestConfiguredAbilitiesSurviveOptionHydrationDelay();
        TestCorSelectionSurvivesOptionReplacement();
        TestMalformedRuntimeProjectionFailsFast();
        TestMalformedRuntimeLuopanPlacementFailsFast();
    }

    private static void TestCanonicalRuntimeDefaultsMissingLuopanPlacement()
    {
        var active = BuildCanonicalActiveProfile();
        var config = active["config"]?.AsObject()
            ?? throw new InvalidOperationException("test canonical config fixture is missing");
        var maintenance = config["maintenance"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance fixture is missing");
        var geo = maintenance["geo"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance.geo fixture is missing");
        var luopan = geo["luopan"]?.AsObject()
            ?? throw new InvalidOperationException("test luopan fixture is missing");
        luopan.Remove("placement");

        using var activeDocument = JsonDocument.Parse(active.ToJsonString());
        using var sessionDocument = JsonDocument.Parse("{}");
        var editor = RuntimeProfileEditorAdapter.Build(sessionDocument.RootElement, activeDocument.RootElement);

        AssertEqual(
            editor["geo_luopan_placement"]?.GetValue<string>(),
            "target",
            "older runtime Luopan placement projection"
        );
    }

    private static void TestCanonicalReconnectPreservesDurableConfiguration()
    {
        var active = BuildCanonicalActiveProfile();
        var session = new JsonObject
        {
            ["engine"] = "UC",
            ["Start_Engine"] = true,
            ["ability_options"] = "Bolster|Entrust|Ecliptic Attrition",
            ["weaponskill_options"] = "Savage Blade",
            ["cor_roll_options"] = "Chaos Roll|Samurai Roll",
            ["brd_song_options"] = "Honor March|Victory March|Bewitching Etude",
            ["party_options"] = "Redrogue|Niightsiide|Terrasjr|Ponponponponpon",
        };

        using var activeDocument = JsonDocument.Parse(active.ToJsonString());
        using var sessionDocument = JsonDocument.Parse(session.ToJsonString());
        var editor = RuntimeProfileEditorAdapter.Build(sessionDocument.RootElement, activeDocument.RootElement);

        AssertEqual(editor["abilities_selected"]?.GetValue<string>(), "Bolster|Entrust", "ability projection");
        AssertEqual(editor["Start_Engine"]?.GetValue<bool>(), true, "runtime engine state hydration");
        AssertEqual(editor["party_follow_selected"]?.GetValue<string>(), "Leader", "party follow projection");
        AssertEqual(editor["brd_songs"]?.GetValue<string>(), "Honor March|Victory March", "BRD song projection");
        AssertEqual(editor["brd_dummy_songs"]?.GetValue<string>(), "Bewitching Etude", "BRD dummy projection");
        AssertEqual(editor["geo_maintenance_enabled"]?.GetValue<bool>(), true, "GEO enabled projection");
        AssertEqual(editor["geo_spell"]?.GetValue<string>(), "Geo-Fury", "GEO spell projection");
        AssertEqual(editor["indi_spell"]?.GetValue<string>(), "Indi-Frailty", "Indi spell projection");
        AssertEqual(editor["geo_target_kind"]?.GetValue<string>(), "self", "GEO target projection");
        AssertEqual(editor["geo_luopan_placement"]?.GetValue<string>(), "camp", "Luopan placement projection");
        AssertEqual(editor["camp_pulling_targets"]?.GetValue<string>(), "Apex Bat:100|Apex Crab:50", "camp target projection");
        AssertEqual(editor["tank_enmity_actions"]?.GetValue<string>(), "Provoke|Flash", "tank action projection");
        AssertEqual(editor["nyzul_parking_order"]?.GetValue<string>(), "Redrogue|Niightsiide", "Nyzul projection");
        AssertEqual(editor["formation_required_party_names"]?.GetValue<string>(), "Redrogue", "formation roster projection");
        AssertEqual(editor["cor_roll_1"]?.GetValue<string>(), "Chaos Roll", "COR roll projection");
        AssertEqual(editor["puller_selected"]?.GetValue<string>(), "Niightsiide", "puller identity projection");
        AssertEqual(editor["fight_leader_selected"]?.GetValue<string>(), "Terrasjr", "fight leader identity projection");
        AssertEqual(editor["partner_entries"]?.GetValue<string>(), "1:Ponponponponpon", "partner durable-name projection");
        AssertEqual(editor["defensive_targeted_buffs"]?.GetValue<string>(), "Terrasjr:Haste", "targeted buff projection");
        AssertEqual(editor["formation_enabled"]?.GetValue<bool>(), true, "formation enabled projection");
        AssertEqual(editor["formation_required_party_names"]?.GetValue<string>(), "Redrogue", "formation required roster projection");
        AssertEqual(editor["path_pull_attack_fallback_enabled"]?.GetValue<bool>(), true, "path pull fallback projection");
        AssertEqual(editor["food_item"]?.GetValue<string>(), "Grape Daifuku", "food projection");
        AssertEqual(editor["target_ignore_entries"]?.GetValue<string>(), "1:Apex Crab", "target ignore projection");
        AssertEqual(editor["add_priority_entries"]?.GetValue<string>(), "1:Apex Bat", "add priority projection");
        AssertEqual(editor["sleep_spell_entries"]?.GetValue<string>(), "1:Horde Lullaby II", "sleep order projection");
        AssertEqual(editor["tank_enmity_include_pets"]?.GetValue<bool>(), true, "tank pet-enmity projection");
        AssertEqual(editor["domain_follow_enabled"]?.GetValue<bool>(), true, "ownership projection");

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            editor,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );
        AssertContains(content, "configured = {", "ability save round-trip shape");
        AssertContains(content, "\"Bolster\",", "Bolster save round-trip");
        AssertContains(content, "\"Entrust\",", "Entrust save round-trip");
        AssertContains(content, "geo_spell = \"Geo-Fury\"", "GEO save round-trip");
        AssertContains(content, "placement = \"camp\"", "Luopan placement save round-trip");
        AssertContains(content, "\"Honor March\",", "Honor March save round-trip");
        AssertContains(content, "\"Victory March\",", "Victory March save round-trip");
        AssertContains(content, "roll_1 = \"Chaos Roll\"", "COR save round-trip");
    }

    private static void TestConfiguredAbilitiesSurviveOptionHydrationDelay()
    {
        using var document = JsonDocument.Parse("""
            {"abilities_selected":"Bolster|Entrust"}
            """);
        var selected = MainForm.ComputeSelectedAbilitiesFromState(document.RootElement);
        AssertEqual(string.Join("|", selected), "Bolster|Entrust", "delayed ability option hydration");
    }

    private static void TestCorSelectionSurvivesOptionReplacement()
    {
        var options = MainForm.BuildCorRollOptions(["Chaos Roll", "Samurai Roll"], "Monk's Roll");
        AssertEqual(string.Join("|", options), "|Monk's Roll|Chaos Roll|Samurai Roll", "COR option replacement");
    }

    private static void TestMalformedRuntimeProjectionFailsFast()
    {
        var active = BuildCanonicalActiveProfile();
        var config = active["config"]?.AsObject()
            ?? throw new InvalidOperationException("test canonical config fixture is missing");
        var maintenance = config["maintenance"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance fixture is missing");
        var brd = maintenance["brd"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance.brd fixture is missing");
        brd["songs"] = "Honor March";
        using var activeDocument = JsonDocument.Parse(active.ToJsonString());
        using var sessionDocument = JsonDocument.Parse("{}");
        try
        {
            _ = RuntimeProfileEditorAdapter.Build(sessionDocument.RootElement, activeDocument.RootElement);
        }
        catch (InvalidDataException)
        {
            return;
        }
        throw new InvalidOperationException("malformed runtime projection did not fail fast");
    }

    private static void TestMalformedRuntimeLuopanPlacementFailsFast()
    {
        var active = BuildCanonicalActiveProfile();
        var config = active["config"]?.AsObject()
            ?? throw new InvalidOperationException("test canonical config fixture is missing");
        var maintenance = config["maintenance"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance fixture is missing");
        var geo = maintenance["geo"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance.geo fixture is missing");
        var luopan = geo["luopan"]?.AsObject()
            ?? throw new InvalidOperationException("test luopan fixture is missing");
        luopan["placement"] = "caster";

        using var activeDocument = JsonDocument.Parse(active.ToJsonString());
        using var sessionDocument = JsonDocument.Parse("{}");
        try
        {
            _ = RuntimeProfileEditorAdapter.Build(sessionDocument.RootElement, activeDocument.RootElement);
        }
        catch (InvalidDataException)
        {
            return;
        }
        throw new InvalidOperationException("invalid runtime Luopan placement did not fail fast");
    }

    private static void TestLegacyProjectedSnapshotStillLoads()
    {
        var active = new JsonObject
        {
            ["party_follow_leader_name"] = "Leader",
            ["abilities"] = new JsonArray("Bolster", "Entrust"),
            ["maintenance_geo"] = BuildGeoMaintenance(),
        };
        using var activeDocument = JsonDocument.Parse(active.ToJsonString());
        using var sessionDocument = JsonDocument.Parse("""{"Start_Engine":false}""");
        var editor = RuntimeProfileEditorAdapter.Build(sessionDocument.RootElement, activeDocument.RootElement);

        AssertEqual(editor["party_follow_selected"]?.GetValue<string>(), "Leader", "legacy party-follow projection");
        AssertEqual(editor["abilities_selected"]?.GetValue<string>(), "Bolster|Entrust", "legacy ability projection");
        AssertEqual(editor["Start_Engine"]?.GetValue<bool>(), false, "legacy runtime engine hydration");
    }

    private static JsonObject BuildCanonicalActiveProfile()
    {
        return new JsonObject
        {
            ["version"] = 2,
            ["profile"] = new JsonObject
            {
                ["schema_version"] = 2,
                ["engine"] = "UC",
                ["character"] = "Redrogue",
                ["main_job"] = "BRD",
                ["sub_job"] = "WHM",
                ["source"] = "SELFTEST",
            },
            ["config"] = new JsonObject
            {
                ["ui"] = new JsonObject
                {
                    ["show_ingame_ui"] = true,
                },
                ["combat"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["autotarget"] = true,
                    ["auto_engage"] = true,
                    ["spam"] = false,
                    ["closer"] = false,
                    ["manual"] = false,
                    ["prime"] = false,
                    ["static"] = false,
                    ["face"] = true,
                    ["weaponskill"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["primary"] = "Savage Blade",
                        ["mode"] = "smart",
                        ["minimum_tp"] = 1000,
                        ["allow_aoe"] = true,
                        ["fast_skillchain"] = false,
                        ["no_skillchain_targets"] = new JsonArray(),
                        ["skillchain_target"] = "auto",
                        ["wait_ignore_names"] = new JsonArray(),
                        ["aftermath_enabled"] = false,
                        ["aftermath_ws"] = "",
                    },
                    ["recurring_spells"] = new JsonObject
                    {
                        ["enabled"] = false,
                        ["list"] = new JsonArray(),
                    },
                    ["pulling"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["mode"] = "camp",
                        ["action"] = new JsonObject { ["type"] = "spell", ["name"] = "Dia II" },
                        ["targets"] = new JsonArray(
                            new JsonObject { ["name"] = "Apex Bat", ["priority"] = 100 },
                            new JsonObject { ["name"] = "Apex Crab", ["priority"] = 50 }
                        ),
                        ["match_mode"] = "exact",
                        ["max_active_mobs"] = 1,
                        ["replenish_below_hpp"] = 20,
                        ["leash_yalms"] = 35.0,
                        ["max_z_delta"] = 2.0,
                        ["cast_range_ratio"] = 0.9,
                        ["settle_seconds"] = 0.4,
                        ["reaction_timeout_seconds"] = 4.0,
                        ["retry_limit"] = 2,
                        ["retry_window_seconds"] = 2.5,
                        ["target_cooldown_seconds"] = 20.0,
                        ["camp_arrival_yalms"] = 0.75,
                    },
                },
                ["abilities"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["allow_unengaged"] = false,
                    ["configured"] = new JsonArray("Bolster", "Entrust"),
                    ["legacy_slots"] = new JsonArray(),
                    ["wsabilities"] = new JsonArray(),
                },
                ["defensive"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["provider"] = "internal",
                    ["resurrection"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["priority"] = new JsonArray("Arise", "Raise III"),
                    },
                    ["cure"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["min_tier"] = 3,
                        ["max_tier"] = 4,
                        ["min_missing_hp"] = 250,
                        ["ignore_trusts"] = true,
                        ["curaga"] = new JsonObject { ["enabled"] = true, ["min_targets"] = 3 },
                    },
                    ["waltz"] = new JsonObject
                    {
                        ["enabled"] = false,
                        ["tp_reserve"] = 0,
                        ["divine_min_targets"] = 3,
                    },
                    ["doom"] = new JsonObject { ["holy_water_enabled"] = true },
                    ["charm_sleeper"] = new JsonObject { ["enabled"] = false },
                    ["sleep_waker"] = new JsonObject { ["enabled"] = false },
                    ["na"] = new JsonObject { ["enabled"] = true, ["limit_enabled"] = false, ["priority"] = "Poison|Paralyze" },
                    ["enemy_buffs"] = new JsonObject { ["remove"] = true },
                    ["enemy_debuffs"] = new JsonObject { ["enabled"] = false, ["list"] = "" },
                    ["buffs"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["self_only"] = false,
                        ["list"] = "Haste|Refresh",
                        ["targeted"] = new JsonArray(
                            new JsonObject { ["character"] = "Terrasjr", ["buff"] = "Haste" }
                        ),
                        ["overwrite_enabled"] = true,
                        ["overwrite_interval"] = 150,
                    },
                    ["thresholds"] = new JsonObject { ["critical_hpp"] = 35, ["medium_hpp"] = 55 },
                },
                ["movement"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["move"] = true,
                    ["spacing"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["band_min"] = -0.9,
                        ["band_max"] = 0.4,
                        ["model_size_floor"] = 0.9,
                        ["use_prediction"] = true,
                        ["lookahead_s"] = 0.25,
                        ["repel_hold_ticks"] = 5,
                        ["overlap_deadband"] = 0.1,
                        ["repel_weight"] = 0.35,
                        ["band_deadband"] = 0.2,
                    },
                    ["path"] = new JsonObject
                    {
                        ["recording"] = false,
                        ["follow_enabled"] = false,
                        ["party_gate_yalms"] = 3.0,
                        ["resume_index_window"] = 12,
                        ["hunter_targets"] = new JsonArray(),
                        ["hunter_max_z_delta"] = 2.0,
                        ["hunter_max_target_range"] = 20.0,
                        ["hunter_claim_timeout_s"] = 4.0,
                        ["hunter_ignore_cooldown_s"] = 20.0,
                        ["pull_action_type"] = "ja",
                        ["pull_action_name"] = "Provoke",
                        ["pull_attack_fallback_enabled"] = true,
                    },
                    ["formation"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["encounter"] = "sortie_ghatjot",
                        ["role"] = "dps",
                        ["tank_name"] = "Terrasjr",
                        ["required_party_names"] = new JsonArray("Redrogue"),
                        ["capture_stable_s"] = 1.0,
                        ["capture_tolerance"] = 0.5,
                        ["safe_radius"] = 2.0,
                        ["mock"] = new JsonObject { ["enabled"] = false, ["mob_name"] = "" },
                        ["tank"] = new JsonObject { ["accept_radius"] = 1.0, ["return_radius"] = 2.0 },
                        ["dps"] = new JsonObject { ["flank_angle_deg"] = 90.0, ["melee_radius"] = 2.5, ["position_tolerance"] = 0.5 },
                        ["healer"] = new JsonObject
                        {
                            ["preferred_radius"] = 15.0,
                            ["minimum_boss_distance"] = 8.0,
                            ["maximum_party_range"] = 20.0,
                            ["cone_half_angle_deg"] = 45.0,
                            ["cone_safety_margin_deg"] = 5.0,
                            ["sample_step_deg"] = 5.0,
                        },
                        ["placement"] = new JsonObject
                        {
                            ["mode"] = "polar",
                            ["anchor"] = "target",
                            ["anchor_member"] = "",
                            ["axis"] = new JsonObject { ["type"] = "party_member", ["member"] = "Terrasjr" },
                            ["preferred_radius"] = 2.5,
                            ["minimum_radius"] = 1.0,
                            ["maximum_radius"] = 4.0,
                            ["preferred_angle_deg"] = 90.0,
                            ["allowed_angle_half_width_deg"] = 30.0,
                            ["radius_step"] = 0.25,
                            ["angle_step_deg"] = 5.0,
                        },
                        ["hysteresis"] = new JsonObject { ["start_distance"] = 1.0, ["stop_distance"] = 0.5 },
                        ["constraints"] = new JsonObject
                        {
                            ["avoid_encounter_hazards"] = true,
                            ["hazard_margin"] = 0.5,
                            ["safe_origin_radius"] = 0.0,
                            ["minimum_boss_distance"] = 0.0,
                            ["maximum_boss_distance"] = 0.0,
                            ["maximum_party_range"] = 0.0,
                            ["required_party_names"] = new JsonArray("Redrogue"),
                        },
                    },
                },
                ["follow"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["party"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["leader_name"] = "Leader",
                        ["min"] = 1.0,
                        ["max"] = 25.0,
                    },
                    ["fight"] = new JsonObject
                    {
                        ["leader"] = true,
                        ["leader_name"] = "Terrasjr",
                        ["min"] = 3.0,
                        ["hold_s"] = 8.0,
                    },
                    ["partner"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["secondary_enabled"] = false,
                        ["names"] = new JsonArray("Ponponponponpon"),
                        ["puller"] = true,
                        ["puller_name"] = "Niightsiide",
                        ["leash_source"] = "player",
                        ["engage_range"] = 6.0,
                        ["puller_distance_only"] = false,
                    },
                    ["nyzul"] = new JsonObject
                    {
                        ["coordinator_name"] = "Terrasjr",
                        ["anchor_name"] = "Ponponponponpon",
                        ["parking_order"] = new JsonArray("Redrogue", "Niightsiide"),
                    },
                },
                ["targeting"] = new JsonObject
                {
                    ["add_control"] = true,
                    ["targets"] = new JsonArray("Apex Bat"),
                    ["target_ignore_names"] = new JsonArray("Apex Crab"),
                },
                ["tank"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["enmity"] = new JsonObject
                    {
                        ["actions"] = new JsonArray("Provoke", "Flash"),
                        ["include_pets"] = true,
                    },
                },
                ["sleep"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["order"] = new JsonArray("Horde Lullaby II"),
                    ["legacy_primary"] = "Horde Lullaby II",
                    ["max_target_range"] = 6.0,
                },
                ["spells"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["configured"] = "Thunder V",
                    ["magic_burst"] = true,
                    ["magic_burst_mode"] = "exact",
                    ["magic_burst_family"] = "spell",
                    ["magic_burst_max_tier"] = 5,
                    ["dd2_slots"] = new JsonArray(),
                },
                ["maintenance"] = new JsonObject
                {
                    ["enabled"] = true,
                    ["cor"] = new JsonObject
                    {
                        ["roll_1"] = "Chaos Roll",
                        ["roll_2"] = "Samurai Roll",
                        ["crooked_roll_slot"] = 1,
                        ["elevens"] = false,
                        ["luzaf_range_override"] = true,
                        ["light_shot_dia"] = true,
                        ["range_selected"] = "Redrogue",
                        ["range_require_ids"] = new JsonArray(),
                    },
                    ["brd"] = new JsonObject
                    {
                        ["enabled"] = true,
                        ["songs"] = new JsonArray("Honor March", "Victory March"),
                        ["dummy_songs"] = new JsonArray("Bewitching Etude"),
                        ["use_nitro"] = true,
                        ["use_soul_voice"] = true,
                        ["use_clarion_call"] = true,
                        ["use_marcato"] = true,
                        ["marcato_song"] = "Honor March",
                        ["targeted_songs"] = new JsonArray(),
                        ["recovery_range_yalms"] = 9.9,
                        ["reposition_for_party_songs"] = true,
                        ["recovery_ignore_names"] = new JsonArray("Puller"),
                    },
                    ["food"] = new JsonObject { ["enabled"] = true, ["item"] = "Grape Daifuku" },
                    ["geo"] = BuildGeoMaintenance(),
                },
                ["debug"] = new JsonObject
                {
                    ["enabled"] = false,
                    ["action_timeline"] = false,
                    ["combat_sched"] = false,
                    ["ja_sched"] = false,
                    ["ja_debug"] = false,
                    ["def_sched"] = false,
                    ["tank_sched"] = false,
                },
                ["ownership"] = new JsonObject
                {
                    ["domain_combat_enabled"] = true,
                    ["domain_defensive_enabled"] = true,
                    ["domain_movement_enabled"] = true,
                    ["domain_maintenance_enabled"] = true,
                    ["domain_follow_enabled"] = true,
                    ["auto_accept_raise"] = true,
                    ["pause_automation_while_weakened"] = false,
                },
                ["legacy"] = new JsonObject
                {
                    ["sub"] = false,
                    ["sub2"] = false,
                    ["solo"] = false,
                    ["aeonic"] = false,
                    ["color"] = false,
                    ["command"] = false,
                    ["hunter"] = false,
                },
            },
        };
    }

    private static JsonObject BuildGeoMaintenance()
    {
        return new JsonObject
        {
            ["enabled"] = true,
            ["geo_spell"] = "Geo-Fury",
            ["geo_target"] = new JsonObject { ["kind"] = "self", ["name"] = null },
            ["indi_spell"] = "Indi-Frailty",
            ["ordering"] = "geo_first",
            ["require_camp"] = true,
            ["camp_tolerance_yalms"] = 1.0,
            ["enemy_geo_requires_camp_radius"] = false,
            ["unknown_existing_policy"] = "wait_for_clear",
            ["entrust"] = new JsonObject { ["enabled"] = false, ["spell"] = null, ["target_name"] = null },
            ["luopan"] = new JsonObject
            {
                ["placement"] = "camp",
                ["use_blaze_of_glory"] = false,
                ["use_ecliptic_attrition"] = false,
                ["use_life_cycle"] = false,
                ["life_cycle_hpp"] = 50,
                ["replace_out_of_position"] = false,
                ["max_camp_distance_yalms"] = 6.0,
            },
        };
    }

    private static void AssertEqual<T>(T actual, T expected, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(actual, expected))
        {
            throw new InvalidOperationException($"{message}: expected '{expected}', got '{actual}'");
        }
    }

    private static void AssertContains(string actual, string expected, string message)
    {
        if (!actual.Contains(expected, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{message}: missing '{expected}'");
        }
    }
}
