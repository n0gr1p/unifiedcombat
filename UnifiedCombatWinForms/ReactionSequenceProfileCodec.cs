using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal sealed record ReactionSequenceStep(
    string ActionType,
    string ActionName,
    string Target,
    bool Optional
);

internal sealed record ReactionSequenceRule(
    string Name,
    IReadOnlyList<ReactionSequenceStep> Steps
);

internal static class ReactionSequenceProfileCodec
{
    internal static ReactionSequenceRule ParseRule(JsonObject rule)
    {
        var trigger = ReadString(rule, "trigger");
        var response = ReadString(rule, "response");
        var name = ReadString(rule, "name");
        if (trigger != "ability_window" || response != "use_sequence")
        {
            throw new InvalidDataException("reaction sequence rule must use ability_window/use_sequence");
        }
        if (name.Length == 0)
        {
            throw new InvalidDataException("use_sequence reaction requires a non-empty ability name");
        }
        if (!rule.TryGetPropertyValue("steps", out var stepsNode) || stepsNode is not JsonArray steps || steps.Count == 0)
        {
            throw new InvalidDataException("use_sequence reaction requires at least one step");
        }

        var parsed = new List<ReactionSequenceStep>(steps.Count);
        for (var i = 0; i < steps.Count; i++)
        {
            if (steps[i] is not JsonObject step)
            {
                throw new InvalidDataException($"use_sequence step {i + 1} must be an object");
            }
            var actionType = ReadString(step, "action_type").ToLowerInvariant();
            var actionName = ReadString(step, "action_name");
            var target = ReadString(step, "target").ToLowerInvariant();
            var optional = ReadOptionalBool(step, "optional", false);
            parsed.Add(new ReactionSequenceStep(actionType, actionName, target, optional));
        }

        var result = new ReactionSequenceRule(name, parsed);
        Validate(result);
        return result;
    }

    internal static List<ReactionSequenceRule> ParseRules(JsonArray? rules)
    {
        var result = new List<ReactionSequenceRule>();
        if (rules is null)
        {
            return result;
        }
        foreach (var node in rules)
        {
            if (node is not JsonObject rule)
            {
                continue;
            }
            if (!string.Equals(ReadString(rule, "response"), "use_sequence", StringComparison.Ordinal))
            {
                continue;
            }
            result.Add(ParseRule(rule));
        }
        return result;
    }

    internal static JsonObject ToJsonRule(ReactionSequenceRule rule)
    {
        Validate(rule);
        var steps = new JsonArray();
        foreach (var step in rule.Steps)
        {
            steps.Add(new JsonObject
            {
                ["action_type"] = step.ActionType,
                ["action_name"] = step.ActionName,
                ["target"] = step.Target,
                ["optional"] = step.Optional,
            });
        }
        return new JsonObject
        {
            ["trigger"] = "ability_window",
            ["name"] = rule.Name,
            ["response"] = "use_sequence",
            ["steps"] = steps,
        };
    }

    internal static void Validate(ReactionSequenceRule rule)
    {
        if (string.IsNullOrWhiteSpace(rule.Name))
        {
            throw new InvalidDataException("use_sequence reaction requires a non-empty ability name");
        }
        if (rule.Steps is null || rule.Steps.Count == 0)
        {
            throw new InvalidDataException("use_sequence reaction requires at least one step");
        }
        for (var i = 0; i < rule.Steps.Count; i++)
        {
            var step = rule.Steps[i];
            if (step.ActionType is not ("spell" or "ja"))
            {
                throw new InvalidDataException($"use_sequence step {i + 1} action_type must be spell or ja");
            }
            if (string.IsNullOrWhiteSpace(step.ActionName))
            {
                throw new InvalidDataException($"use_sequence step {i + 1} requires action_name");
            }
            if (step.Target is not ("self" or "actor"))
            {
                throw new InvalidDataException($"use_sequence step {i + 1} target must be self or actor");
            }
            if (i == rule.Steps.Count - 1 && step.Optional)
            {
                throw new InvalidDataException("use_sequence final step must be required");
            }
        }
    }

    private static string ReadString(JsonObject obj, string key)
    {
        if (!obj.TryGetPropertyValue(key, out var node) || node is null)
        {
            return "";
        }
        if (node is JsonValue value && value.TryGetValue<string>(out var text))
        {
            return (text ?? "").Trim();
        }
        return node.ToString().Trim();
    }

    private static bool ReadOptionalBool(JsonObject obj, string key, bool fallback)
    {
        if (!obj.TryGetPropertyValue(key, out var node) || node is null)
        {
            return fallback;
        }
        if (node is JsonValue value && value.TryGetValue<bool>(out var parsed))
        {
            return parsed;
        }
        throw new InvalidDataException($"{key} must be boolean");
    }
}
