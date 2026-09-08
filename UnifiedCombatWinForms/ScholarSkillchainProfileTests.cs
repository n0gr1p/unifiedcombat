using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class ScholarSkillchainProfileTests
{
    public static int Run()
    {
        try
        {
            TestSelectedSkillchainSerializes();
            TestHelixSkillchainCloserSerializes();
            TestInvalidSkillchainResultRejected();
            TestNonScholarSkillchainRejected();
            TestEditorProfileMigrationAddsSkillchainDefaults();
            Console.WriteLine("ScholarSkillchainProfileTests: OK");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ScholarSkillchainProfileTests: FAILED");
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    private static JsonObject BaseProfile()
    {
        return new JsonObject
        {
            ["domain_combat_enabled"] = true,
            ["domain_defensive_enabled"] = true,
            ["domain_movement_enabled"] = true,
            ["domain_maintenance_enabled"] = true,
            ["domain_follow_enabled"] = true,
        };
    }

    private static void TestSelectedSkillchainSerializes()
    {
        var flat = BaseProfile();
        flat["sch_enabled"] = true;
        flat["sch_skillchain_enabled"] = true;
        flat["sch_skillchain_result"] = "Fragmentation";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Nyoourke", "SCH", "RDM")
        );

        AssertContains(content, "skillchain = {", "Scholar skillchain block missing");
        AssertContains(content, "enabled = true,", "Scholar skillchain enabled state missing");
        AssertContains(content, "plans = {", "Scholar skillchain plan missing");
        AssertContains(content, "result = \"Fragmentation\",", "selected Scholar skillchain result missing");
        AssertContains(content, "closer = \"Water V\",", "default Fragmentation closer missing");
    }

    private static void TestHelixSkillchainCloserSerializes()
    {
        var flat = BaseProfile();
        flat["sch_enabled"] = true;
        flat["sch_skillchain_enabled"] = true;
        flat["sch_skillchain_result"] = "Fusion";
        flat["sch_skillchain_closer"] = "Ionohelix II";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Nyoourke", "SCH", "RDM")
        );

        AssertContains(content, "result = \"Fusion\",", "Fusion result missing for Helix closer");
        AssertContains(content, "closer = \"Ionohelix II\",", "Ionohelix II closer must serialize");
    }

    private static void TestInvalidSkillchainResultRejected()
    {
        var flat = BaseProfile();
        flat["sch_enabled"] = true;
        flat["sch_skillchain_enabled"] = true;
        flat["sch_skillchain_result"] = "Cosmic Friendship";

        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Nyoourke", "SCH", "RDM")
            ),
            "unsupported Scholar skillchain result must be rejected"
        );
    }

    private static void TestNonScholarSkillchainRejected()
    {
        var flat = BaseProfile();
        flat["sch_enabled"] = false;
        flat["sch_skillchain_enabled"] = true;
        flat["sch_skillchain_result"] = "Fusion";

        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Niightsiide", "GEO", "RDM")
            ),
            "enabled Scholar skillchain on a non-SCH profile must be rejected"
        );
    }

    private static void TestEditorProfileMigrationAddsSkillchainDefaults()
    {
        var profile = BaseProfile();
        profile["profile_schema_version"] = 5;

        var changed = MainForm.MigrateProfileInPlace(profile);
        AssertTrue(changed, "schema-five profile should migrate");
        AssertEqual(profile["profile_schema_version"]?.GetValue<int>() ?? 0, 8, "profile schema must migrate to eight");
        AssertEqual(profile["sch_skillchain_enabled"]?.GetValue<bool>() ?? true, false, "migrated skillchain must default disabled");
        AssertEqual(profile["sch_skillchain_result"]?.GetValue<string>() ?? "", "Fusion", "migrated skillchain must default to Fusion");
        AssertEqual(profile["sch_skillchain_closer"]?.GetValue<string>() ?? "", "Thunder V", "migrated Fusion skillchain must default to Thunder V");
    }

    private static void AssertContains(string value, string expected, string message)
    {
        if (!value.Contains(expected, StringComparison.Ordinal))
        {
            throw new InvalidDataException(message + $"; expected to find: {expected}");
        }
    }

    private static void AssertTrue(bool value, string message)
    {
        if (!value)
        {
            throw new InvalidDataException(message);
        }
    }

    private static void AssertEqual<T>(T actual, T expected, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(actual, expected))
        {
            throw new InvalidDataException($"{message}; expected {expected}, got {actual}");
        }
    }

    private static void AssertThrows<TException>(Action action, string message)
        where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }
        throw new InvalidDataException(message);
    }
}
