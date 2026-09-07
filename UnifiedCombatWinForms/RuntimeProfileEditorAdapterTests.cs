using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class RuntimeProfileEditorAdapterTests
{
    internal static void Run()
    {
        TestReconnectProjectionPreservesDurableConfiguration();
        TestOlderRuntimeProjectionDefaultsMissingLuopanPlacement();
        TestConfiguredAbilitiesSurviveOptionHydrationDelay();
        TestCorSelectionSurvivesOptionReplacement();
        TestMalformedRuntimeProjectionFailsFast();
        TestMalformedRuntimeLuopanPlacementFailsFast();
    }

    private static void TestOlderRuntimeProjectionDefaultsMissingLuopanPlacement()
    {
        var active = BuildRuntimeProjection();
        var maintenance = active["maintenance_geo"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance_geo fixture is missing");
        var luopan = maintenance["luopan"]?.AsObject()
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

    private static void TestReconnectProjectionPreservesDurableConfiguration()
    {
        var active = BuildRuntimeProjection();
        var session = new JsonObject
        {
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
        var active = BuildRuntimeProjection();
        active["brd_songs"] = "Honor March";
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
        var active = BuildRuntimeProjection();
        var maintenance = active["maintenance_geo"]?.AsObject()
            ?? throw new InvalidOperationException("test maintenance_geo fixture is missing");
        var luopan = maintenance["luopan"]?.AsObject()
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

    private static JsonObject BuildRuntimeProjection()
    {
        return new JsonObject
        {
            ["engine"] = "UC",
            ["domain_combat_enabled"] = true,
            ["domain_defensive_enabled"] = true,
            ["domain_movement_enabled"] = true,
            ["domain_maintenance_enabled"] = true,
            ["domain_follow_enabled"] = true,
            ["ability_active"] = true,
            ["abilities"] = new JsonArray("Bolster", "Entrust"),
            ["party_follow"] = true,
            ["party_follow_leader_name"] = "Leader",
            ["party_follow_min"] = 1.0,
            ["party_follow_max"] = 25.0,
            ["fight_follow_min"] = 3.0,
            ["fight_follow_hold_s"] = 8.0,
            ["tank_enmity_actions"] = new JsonArray("Provoke", "Flash"),
            ["nyzul_coordinator_name"] = "Terrasjr",
            ["nyzul_anchor_name"] = "Ponponponponpon",
            ["nyzul_parking_order"] = new JsonArray("Redrogue", "Niightsiide"),
            ["formation_required_party_names"] = new JsonArray("Redrogue"),
            ["brd_maintenance_enabled"] = true,
            ["brd_songs"] = new JsonArray("Honor March", "Victory March"),
            ["brd_dummy_songs"] = new JsonArray("Bewitching Etude"),
            ["brd_recovery_ignore_names"] = new JsonArray("Puller"),
            ["brd_use_nitro"] = true,
            ["brd_use_soul_voice"] = true,
            ["brd_use_clarion_call"] = true,
            ["brd_use_marcato"] = true,
            ["brd_marcato_song"] = "Honor March",
            ["brd_targeted_songs"] = "",
            ["brd_recovery_range_yalms"] = 9.9,
            ["brd_reposition_for_party_songs"] = true,
            ["cor_roll_1"] = "Chaos Roll",
            ["cor_roll_2"] = "Samurai Roll",
            ["cor_crooked_roll_slot"] = 1,
            ["cor_elevens"] = false,
            ["cor_luzaf_range_override"] = true,
            ["cor_roll_range_selected"] = "Redrogue",
            ["camp_pulling"] = new JsonObject
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
            ["maintenance_geo"] = new JsonObject
            {
                ["enabled"] = true,
                ["geo_spell"] = "Geo-Fury",
                ["geo_target"] = new JsonObject { ["kind"] = "self" },
                ["indi_spell"] = "Indi-Frailty",
                ["ordering"] = "geo_first",
                ["require_camp"] = true,
                ["camp_tolerance_yalms"] = 1.0,
                ["enemy_geo_requires_camp_radius"] = false,
                ["unknown_existing_policy"] = "wait_for_clear",
                ["entrust"] = new JsonObject { ["enabled"] = false },
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
