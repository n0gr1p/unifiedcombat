using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class ReactionSequenceProfileCodecTests
{
    internal static int Run()
    {
        try
        {
            var sequence = new ReactionSequenceRule(
                "Just Desserts",
                new List<ReactionSequenceStep>
                {
                    new("ja", "Elemental Seal", "self", true),
                    new("spell", "Stun", "actor", false),
                }
            );

            var json = ReactionSequenceProfileCodec.ToJsonRule(sequence);
            var parsed = ReactionSequenceProfileCodec.ParseRule(json);
            AssertEqual(parsed.Name, "Just Desserts", "sequence name round-trip");
            AssertEqual(parsed.Steps.Count, 2, "sequence step count");
            AssertEqual(parsed.Steps[0].ActionName, "Elemental Seal", "setup action");
            AssertEqual(parsed.Steps[0].Optional, true, "setup optional flag");
            AssertEqual(parsed.Steps[1].ActionName, "Stun", "terminal action");
            AssertEqual(parsed.Steps[1].Target, "actor", "terminal target");
            AssertEqual(parsed.Steps[1].Optional, false, "terminal required flag");

            var flat = new JsonObject
            {
                ["domain_combat_enabled"] = true,
                ["domain_defensive_enabled"] = true,
                ["domain_movement_enabled"] = true,
                ["domain_maintenance_enabled"] = true,
                ["domain_follow_enabled"] = true,
                ["reaction_enabled"] = true,
                ["reaction_rules"] = new JsonArray { json.DeepClone() },
            };
            var lua = StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Etamame", "RDM", "BLM")
            );
            AssertContains(lua, "response = \"use_sequence\"", "structured sequence response");
            AssertContains(lua, "action_name = \"Elemental Seal\"", "structured setup action");
            AssertContains(lua, "target = \"self\"", "structured setup target");
            AssertContains(lua, "optional = true", "structured optional setup");
            AssertContains(lua, "action_name = \"Stun\"", "structured terminal action");
            AssertContains(lua, "target = \"actor\"", "structured terminal target");
            AssertContains(lua, "optional = false", "structured required terminal");

            var invalid = new ReactionSequenceRule(
                "Just Desserts",
                new List<ReactionSequenceStep>
                {
                    new("spell", "Stun", "actor", true),
                }
            );
            var failed = false;
            try
            {
                ReactionSequenceProfileCodec.Validate(invalid);
            }
            catch (InvalidDataException)
            {
                failed = true;
            }
            AssertEqual(failed, true, "optional terminal step must fail");

            Console.WriteLine("ReactionSequenceProfileCodecTests: OK");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ReactionSequenceProfileCodecTests: FAIL: " + ex);
            return 1;
        }
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
}
