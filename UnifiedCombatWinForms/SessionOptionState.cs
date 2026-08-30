using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class SessionOptionState
{
    internal static bool InvalidateWeaponSkillsForJobChange(JsonObject currentState, JsonObject incomingState)
    {
        if (!IdentityValueChanged(currentState, incomingState, "job")
            && !IdentityValueChanged(currentState, incomingState, "sub_job"))
        {
            return false;
        }

        currentState.Remove("weaponskill_options");
        return true;
    }

    private static bool IdentityValueChanged(JsonObject currentState, JsonObject incomingState, string key)
    {
        if (!currentState.TryGetPropertyValue(key, out var currentNode) || currentNode is null
            || !incomingState.TryGetPropertyValue(key, out var incomingNode) || incomingNode is null)
        {
            return false;
        }

        return !string.Equals(
            currentNode.GetValue<string>(),
            incomingNode.GetValue<string>(),
            StringComparison.OrdinalIgnoreCase
        );
    }
}
