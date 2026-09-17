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
            AssertEqual(json.ContainsKey("once_per_instance"), false, "legacy sequence omits once-per-instance field");
            AssertEqual(json.ContainsKey("hold_smn_rage_until_sequence_complete"), false, "legacy sequence omits SMN Rage hold field");
            var parsed = ReactionSequenceProfileCodec.ParseRule(json);
            AssertEqual(parsed.Name, "Just Desserts", "sequence name round-trip");
            AssertEqual(parsed.Trigger, "ability_window", "legacy sequence trigger round-trip");
            AssertEqual(parsed.OncePerInstance, false, "legacy sequence once-per-instance default");
            AssertEqual(parsed.HoldSmnRageUntilSequenceComplete, false, "legacy sequence SMN Rage hold default");
            AssertEqual(parsed.Steps.Count, 2, "sequence step count");
            AssertEqual(parsed.Steps[0].ActionName, "Elemental Seal", "setup action");
            AssertEqual(parsed.Steps[0].Optional, true, "setup optional flag");
            AssertEqual(parsed.Steps[1].ActionName, "Stun", "terminal action");
            AssertEqual(parsed.Steps[1].Target, "actor", "terminal target");
            AssertEqual(parsed.Steps[1].Optional, false, "terminal required flag");

            var onceSequence = new ReactionSequenceRule(
                "Just Desserts",
                new List<ReactionSequenceStep>
                {
                    new("ja", "Astral Flow", "self", false),
                    new("ja", "Astral Conduit", "self", false),
                },
                true
            );
            var onceJson = ReactionSequenceProfileCodec.ToJsonRule(onceSequence);
            AssertEqual(onceJson["once_per_instance"]?.GetValue<bool>(), true, "one-shot JSON flag");
            var onceParsed = ReactionSequenceProfileCodec.ParseRule(onceJson);
            AssertEqual(onceParsed.OncePerInstance, true, "one-shot codec round-trip");

            var partySequence = new ReactionSequenceRule(
                "Indi-Malaise",
                new List<ReactionSequenceStep>
                {
                    new("ja", "Astral Flow", "self", false),
                    new("ja", "Astral Conduit", "self", false),
                },
                true,
                "party_action_complete",
                "Etamame",
                "spell",
                true
            );
            var partyJson = ReactionSequenceProfileCodec.ToJsonRule(partySequence);
            AssertEqual(partyJson["trigger"]?.GetValue<string>(), "party_action_complete", "party trigger JSON");
            AssertEqual(partyJson["source_name"]?.GetValue<string>(), "Etamame", "party source JSON");
            AssertEqual(partyJson["action_type"]?.GetValue<string>(), "spell", "party action type JSON");
            AssertEqual(partyJson["hold_smn_rage_until_sequence_complete"]?.GetValue<bool>(), true, "SMN Rage hold JSON flag");
            var partyParsed = ReactionSequenceProfileCodec.ParseRule(partyJson);
            AssertEqual(partyParsed.Trigger, "party_action_complete", "party trigger round-trip");
            AssertEqual(partyParsed.SourceName, "Etamame", "party source round-trip");
            AssertEqual(partyParsed.TriggerActionType, "spell", "party action type round-trip");
            AssertEqual(partyParsed.OncePerInstance, true, "party one-shot round-trip");
            AssertEqual(partyParsed.HoldSmnRageUntilSequenceComplete, true, "SMN Rage hold round-trip");

            var petSequence = new ReactionSequenceRule(
                "Pet Test Ability",
                new List<ReactionSequenceStep>
                {
                    new("pet", "Assault", "actor", false),
                }
            );
            var petJson = ReactionSequenceProfileCodec.ToJsonRule(petSequence);
            var petParsed = ReactionSequenceProfileCodec.ParseRule(petJson);
            AssertEqual(petParsed.Steps.Count, 1, "pet sequence step count");
            AssertEqual(petParsed.Steps[0].ActionType, "pet", "pet sequence action type");
            AssertEqual(petParsed.Steps[0].ActionName, "Assault", "pet sequence action name");
            AssertEqual(petParsed.Steps[0].Target, "actor", "pet sequence target");

            var flat = new JsonObject
            {
                ["domain_combat_enabled"] = true,
                ["domain_defensive_enabled"] = true,
                ["domain_movement_enabled"] = true,
                ["domain_maintenance_enabled"] = true,
                ["domain_follow_enabled"] = true,
                ["reaction_enabled"] = true,
                ["reaction_rules"] = new JsonArray { onceJson.DeepClone(), partyJson.DeepClone(), petJson.DeepClone() },
            };
            var lua = StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Etamame", "RDM", "BLM")
            );
            AssertContains(lua, "response = \"use_sequence\"", "structured sequence response");
            AssertContains(lua, "once_per_instance = true", "structured one-shot flag");
            AssertContains(lua, "action_name = \"Astral Flow\"", "structured one-shot opener");
            AssertContains(lua, "action_name = \"Astral Conduit\"", "structured one-shot terminal action");
            AssertContains(lua, "trigger = \"party_action_complete\"", "structured party trigger");
            AssertContains(lua, "source_name = \"Etamame\"", "structured party source");
            AssertContains(lua, "action_type = \"spell\"", "structured party trigger action type");
            AssertContains(lua, "name = \"Indi-Malaise\"", "structured party trigger action");
            AssertContains(lua, "hold_smn_rage_until_sequence_complete = true", "structured SMN Rage hold flag");
            AssertContains(lua, "action_type = \"pet\"", "structured pet action type");
            AssertContains(lua, "action_name = \"Assault\"", "structured pet action name");

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

            failed = false;
            try
            {
                ReactionSequenceProfileCodec.Validate(new ReactionSequenceRule(
                    "Just Desserts",
                    new List<ReactionSequenceStep> { new("pet", "Assault", "self", false) }
                ));
            }
            catch (InvalidDataException)
            {
                failed = true;
            }
            AssertEqual(failed, true, "pet self target must fail");

            failed = false;
            try
            {
                ReactionSequenceProfileCodec.Validate(new ReactionSequenceRule(
                    "Just Desserts",
                    new List<ReactionSequenceStep> { new("pet", "Flaming Crush", "actor", false) }
                ));
            }
            catch (InvalidDataException)
            {
                failed = true;
            }
            AssertEqual(failed, true, "unsupported pet action must fail");

            failed = false;
            try
            {
                ReactionSequenceProfileCodec.Validate(new ReactionSequenceRule(
                    "Indi-Malaise",
                    new List<ReactionSequenceStep> { new("ja", "Astral Flow", "self", false) },
                    true,
                    "party_action_complete",
                    "",
                    "spell"
                ));
            }
            catch (InvalidDataException)
            {
                failed = true;
            }
            AssertEqual(failed, true, "party action trigger requires source member");

            failed = false;
            try
            {
                ReactionSequenceProfileCodec.Validate(new ReactionSequenceRule(
                    "Indi-Malaise",
                    new List<ReactionSequenceStep> { new("ja", "Astral Flow", "self", false) },
                    false,
                    "party_action_complete",
                    "Etamame",
                    "spell",
                    true
                ));
            }
            catch (InvalidDataException)
            {
                failed = true;
            }
            AssertEqual(failed, true, "SMN Rage hold requires once-per-instance");

            failed = false;
            try
            {
                ReactionSequenceProfileCodec.Validate(new ReactionSequenceRule(
                    "Just Desserts",
                    new List<ReactionSequenceStep> { new("ja", "Astral Flow", "self", false) },
                    true,
                    "ability_window",
                    "",
                    "",
                    true
                ));
            }
            catch (InvalidDataException)
            {
                failed = true;
            }
            AssertEqual(failed, true, "SMN Rage hold requires party-action trigger");

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
