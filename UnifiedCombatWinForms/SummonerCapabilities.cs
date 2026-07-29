using System.Collections.ObjectModel;
using System.Globalization;
using System.Reflection;

namespace UnifiedCombatWinForms;

internal sealed record SummonerActionCapability(
    int Id,
    string Name,
    string Category,
    string Avatar,
    int? EffectId,
    string? EffectName
);

internal sealed class SummonerAvatarCapability
{
    internal SummonerAvatarCapability(string name, int summonSpellId, string summonSpell)
    {
        Name = name;
        SummonSpellId = summonSpellId;
        SummonSpell = summonSpell;
    }

    internal string Name { get; }
    internal int SummonSpellId { get; }
    internal string SummonSpell { get; }
    internal List<SummonerActionCapability> Wards { get; } = [];
    internal List<SummonerActionCapability> Rages { get; } = [];
}

internal static class SummonerCapabilities
{
    private const string ResourceName = "UnifiedCombatWinForms.summoner_capabilities.tsv";
    private const string ExpectedHeader =
        "avatar\tsummon_spell_id\tsummon_spell\taction_category\taction_id\taction_name\teffect_id\teffect_name";

    private static readonly IReadOnlyList<SummonerAvatarCapability> LoadedAvatars = Load();
    private static readonly IReadOnlyDictionary<string, SummonerAvatarCapability> LoadedByName =
        new ReadOnlyDictionary<string, SummonerAvatarCapability>(
            LoadedAvatars.ToDictionary(avatar => avatar.Name, StringComparer.Ordinal)
        );

    internal static IReadOnlyList<SummonerAvatarCapability> Avatars => LoadedAvatars;

    internal static SummonerAvatarCapability? FindAvatar(string? name)
    {
        if (string.IsNullOrEmpty(name))
        {
            return null;
        }
        return LoadedByName.TryGetValue(name, out var avatar) ? avatar : null;
    }

    internal static bool IsCompatible(string? avatarName, string category, string? actionName)
    {
        var avatar = FindAvatar(avatarName);
        if (avatar is null || string.IsNullOrEmpty(actionName))
        {
            return false;
        }
        var actions = category switch
        {
            "ward" => avatar.Wards,
            "rage" => avatar.Rages,
            _ => throw new ArgumentOutOfRangeException(nameof(category), category, "Category must be ward or rage."),
        };
        return actions.Any(action => string.Equals(action.Name, actionName, StringComparison.Ordinal));
    }

    private static IReadOnlyList<SummonerAvatarCapability> Load()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidDataException($"Embedded Summoner capability catalog '{ResourceName}' is missing.");
        using var reader = new StreamReader(stream);

        var avatars = new List<SummonerAvatarCapability>();
        var byName = new Dictionary<string, SummonerAvatarCapability>(StringComparer.Ordinal);
        var actionIds = new HashSet<int>();
        var headerSeen = false;
        var lineNumber = 0;

        while (reader.ReadLine() is { } line)
        {
            lineNumber++;
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }
            if (!headerSeen)
            {
                if (!string.Equals(line, ExpectedHeader, StringComparison.Ordinal))
                {
                    throw new InvalidDataException($"Summoner capability catalog line {lineNumber} has an unexpected header.");
                }
                headerSeen = true;
                continue;
            }

            var fields = line.Split('\t');
            if (fields.Length != 8)
            {
                throw new InvalidDataException($"Summoner capability catalog line {lineNumber} must have 8 fields.");
            }

            var avatarName = RequiredText(fields[0], "avatar", lineNumber);
            var summonSpellId = RequiredPositiveInteger(fields[1], "summon_spell_id", lineNumber);
            var summonSpell = RequiredText(fields[2], "summon_spell", lineNumber);
            var category = RequiredText(fields[3], "action_category", lineNumber);
            if (category is not ("ward" or "rage"))
            {
                throw new InvalidDataException(
                    $"Summoner capability catalog line {lineNumber} has unsupported category '{category}'."
                );
            }
            var actionId = RequiredPositiveInteger(fields[4], "action_id", lineNumber);
            var actionName = RequiredText(fields[5], "action_name", lineNumber);
            int? effectId = null;
            string? effectName = null;
            if (category == "ward")
            {
                effectId = RequiredPositiveInteger(fields[6], "effect_id", lineNumber);
                effectName = RequiredText(fields[7], "effect_name", lineNumber);
            }
            else if (fields[6].Length != 0 || fields[7].Length != 0)
            {
                throw new InvalidDataException(
                    $"Summoner capability catalog line {lineNumber} defines a maintained effect for a Rage."
                );
            }

            if (!byName.TryGetValue(avatarName, out var avatar))
            {
                avatar = new SummonerAvatarCapability(avatarName, summonSpellId, summonSpell);
                byName.Add(avatarName, avatar);
                avatars.Add(avatar);
            }
            else if (avatar.SummonSpellId != summonSpellId
                || !string.Equals(avatar.SummonSpell, summonSpell, StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    $"Summoner capability catalog line {lineNumber} has an inconsistent summon identity for {avatarName}."
                );
            }

            if (!actionIds.Add(actionId))
            {
                throw new InvalidDataException(
                    $"Summoner capability catalog line {lineNumber} duplicates action id {actionId}."
                );
            }
            var destination = category == "ward" ? avatar.Wards : avatar.Rages;
            if (destination.Any(action => string.Equals(action.Name, actionName, StringComparison.Ordinal)))
            {
                throw new InvalidDataException(
                    $"Summoner capability catalog line {lineNumber} duplicates {category} '{actionName}' for {avatarName}."
                );
            }
            destination.Add(new SummonerActionCapability(
                actionId,
                actionName,
                category,
                avatarName,
                effectId,
                effectName
            ));
        }

        if (!headerSeen)
        {
            throw new InvalidDataException("Summoner capability catalog is missing its header.");
        }
        if (avatars.Count == 0)
        {
            throw new InvalidDataException("Summoner capability catalog contains no supported avatars.");
        }
        return avatars.AsReadOnly();
    }

    private static string RequiredText(string value, string field, int lineNumber)
    {
        if (value.Length == 0)
        {
            throw new InvalidDataException(
                $"Summoner capability catalog line {lineNumber} requires {field}."
            );
        }
        return value;
    }

    private static int RequiredPositiveInteger(string value, string field, int lineNumber)
    {
        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed)
            || parsed <= 0)
        {
            throw new InvalidDataException(
                $"Summoner capability catalog line {lineNumber} requires positive integer {field}."
            );
        }
        return parsed;
    }
}
