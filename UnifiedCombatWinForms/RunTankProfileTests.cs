using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class RunTankProfileTests
{
    internal static int Run()
    {
        try
        {
            TestStructuredWriter();
            TestRuntimeAdapter();
            TestInvalidRuneCount();
            TestMutuallyExclusiveWards();
            Console.WriteLine("RunTankProfileTests: OK");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("RunTankProfileTests: FAIL: " + ex);
            return 1;
        }
    }

    private static JsonObject BuildFlatProfile()
    {
        return new JsonObject
        {
            ["domain_combat_enabled"] = true,
            ["domain_defensive_enabled"] = true,
            ["domain_movement_enabled"] = true,
            ["domain_maintenance_enabled"] = true,
            ["domain_follow_enabled"] = true,
            ["tank"] = true,
            ["tank_enmity_actions"] = "Flash",
            ["tank_enmity_include_pets"] = true,
            ["run_tank_enabled"] = true,
            ["run_tank_runes_maintain"] = true,
            ["run_tank_runes"] = "Ignis|Ignis|Ignis",
            ["run_tank_foil"] = true,
            ["run_tank_vallation"] = true,
            ["run_tank_valiance"] = false,
            ["run_tank_pflug"] = true,
            ["run_tank_swordplay"] = false,
            ["run_tank_battuta"] = true,
            ["run_tank_one_for_all"] = false,
            ["run_tank_gambit"] = true,
            ["run_tank_rayke"] = true,
        };
    }

    private static void TestStructuredWriter()
    {
        var lua = StructuredProfileV2Writer.BuildStructuredProfileFile(
            BuildFlatProfile(),
            new StructuredProfileV2Identity("Terrasjr", "RUN", "WAR")
        );

        AssertContains(lua, "tank = {", "tank block");
        AssertContains(lua, "include_pets = true", "tank pet enmity serialization");
        AssertContains(lua, "run = {", "RUN block");
        AssertContains(lua, "desired = {", "rune list");
        AssertContains(lua, "\"Ignis\"", "Ignis rune serialization");
        AssertContains(lua, "foil = {", "Foil block");
        AssertContains(lua, "vallation = true", "Vallation serialization");
        AssertContains(lua, "pflug = true", "Pflug serialization");
        AssertContains(lua, "battuta = true", "Battuta serialization");
        AssertContains(lua, "gambit = true", "Gambit serialization");
        AssertContains(lua, "rayke = true", "Rayke serialization");
    }

    private static void TestRuntimeAdapter()
    {
        var session = new JsonObject();
        var active = new JsonObject
        {
            ["party_follow_leader_name"] = "",
            ["tank_run"] = new JsonObject
            {
                ["enabled"] = true,
                ["runes"] = new JsonObject
                {
                    ["maintain"] = true,
                    ["desired"] = new JsonArray("Ignis", "Ignis", "Ignis"),
                },
                ["foil"] = new JsonObject { ["enabled"] = true },
                ["wards"] = new JsonObject
                {
                    ["vallation"] = true,
                    ["valiance"] = false,
                    ["pflug"] = true,
                    ["swordplay"] = false,
                    ["battuta"] = true,
                    ["one_for_all"] = false,
                },
                ["magic_support"] = new JsonObject
                {
                    ["gambit"] = true,
                    ["rayke"] = true,
                },
            },
        };

        using var sessionDoc = JsonDocument.Parse(session.ToJsonString());
        using var activeDoc = JsonDocument.Parse(active.ToJsonString());
        var profile = RuntimeProfileEditorAdapter.Build(sessionDoc.RootElement, activeDoc.RootElement);

        AssertEqual(profile["run_tank_enabled"]?.GetValue<bool>(), true, "runtime RUN enabled");
        AssertEqual(profile["run_tank_runes_maintain"]?.GetValue<bool>(), true, "runtime rune maintenance");
        AssertEqual(profile["run_tank_runes"]?.GetValue<string>(), "Ignis|Ignis|Ignis", "runtime rune list");
        AssertEqual(profile["run_tank_foil"]?.GetValue<bool>(), true, "runtime Foil");
        AssertEqual(profile["run_tank_vallation"]?.GetValue<bool>(), true, "runtime Vallation");
        AssertEqual(profile["run_tank_pflug"]?.GetValue<bool>(), true, "runtime Pflug");
        AssertEqual(profile["run_tank_battuta"]?.GetValue<bool>(), true, "runtime Battuta");
        AssertEqual(profile["run_tank_gambit"]?.GetValue<bool>(), true, "runtime Gambit");
        AssertEqual(profile["run_tank_rayke"]?.GetValue<bool>(), true, "runtime Rayke");
    }

    private static void TestInvalidRuneCount()
    {
        var flat = BuildFlatProfile();
        flat["run_tank_runes"] = "Ignis|Ignis";
        AssertThrows(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Terrasjr", "RUN", "WAR")
            ),
            "exactly three runes"
        );
    }

    private static void TestMutuallyExclusiveWards()
    {
        var flat = BuildFlatProfile();
        flat["run_tank_valiance"] = true;
        AssertThrows(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Terrasjr", "RUN", "WAR")
            ),
            "both Vallation and Valiance"
        );
    }

    private static void AssertContains(string actual, string expected, string label)
    {
        if (!actual.Contains(expected, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{label}: missing '{expected}'");
        }
    }

    private static void AssertEqual<T>(T actual, T expected, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(actual, expected))
        {
            throw new InvalidOperationException($"{label}: expected={expected}, actual={actual}");
        }
    }

    private static void AssertThrows(Action action, string expectedMessagePart)
    {
        try
        {
            action();
        }
        catch (InvalidDataException ex)
        {
            if (!ex.Message.Contains(expectedMessagePart, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    $"expected failure containing '{expectedMessagePart}', actual='{ex.Message}'"
                );
            }
            return;
        }
        throw new InvalidOperationException($"expected InvalidDataException containing '{expectedMessagePart}'");
    }
}
