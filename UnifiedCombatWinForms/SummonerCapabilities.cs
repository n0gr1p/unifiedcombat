using System.Collections.ObjectModel;
using System.Globalization;
using System.Reflection;

namespace UnifiedCombatWinForms;

internal sealed record SummonerActionCapability(
    int Id,
    string Name,
    string Category,
    string Avatar,
    IReadOnlyList<int> EffectIds,
    IReadOnlyList<string> EffectNames
)
{
	internal bool IsMaintainable => EffectIds.Count > 0;
	internal int? EffectId => EffectIds.Count == 1 ? EffectIds[0] : null;
	internal string? EffectName => EffectNames.Count == 1 ? EffectNames[0] : null;
}

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
	internal List<SummonerActionCapability> MaintainableWards { get; } = [];
    internal List<SummonerActionCapability> Rages { get; } = [];
}

internal static class SummonerCapabilities
{
    private const string ResourceName = "UnifiedCombatWinForms.summoner_capabilities.tsv";
    private const string ExpectedHeader =
        "avatar\tsummon_spell_id\tsummon_spell\taction_category\taction_id\taction_name\teffect_ids\teffect_names";

    private static readonly IReadOnlyList<SummonerAvatarCapability> LoadedAvatars = Load();
    private static readonly IReadOnlyDictionary<string, SummonerAvatarCapability> LoadedByName =
        new ReadOnlyDictionary<string, SummonerAvatarCapability>(
            LoadedAvatars.ToDictionary(avatar => avatar.Name, StringComparer.Ordinal)
        );
	private static readonly IReadOnlyList<SummonerActionCapability> LoadedWards = LoadedAvatars
		.SelectMany(avatar => avatar.MaintainableWards)
		.ToList()
		.AsReadOnly();
	private static readonly IReadOnlyDictionary<string, SummonerActionCapability> LoadedWardsByName =
		new ReadOnlyDictionary<string, SummonerActionCapability>(
			LoadedWards.ToDictionary(action => action.Name, StringComparer.Ordinal)
		);

    internal static IReadOnlyList<SummonerAvatarCapability> Avatars => LoadedAvatars;
	internal static IReadOnlyList<SummonerActionCapability> Wards => LoadedWards;

    internal static SummonerAvatarCapability? FindAvatar(string? name)
    {
        if (string.IsNullOrEmpty(name))
        {
            return null;
        }
        return LoadedByName.TryGetValue(name, out var avatar) ? avatar : null;
    }

	internal static SummonerActionCapability? FindWard(string? name)
	{
		if (string.IsNullOrEmpty(name))
		{
			return null;
		}
		return LoadedWardsByName.TryGetValue(name, out var ward) ? ward : null;
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
            IReadOnlyList<int> effectIds = Array.Empty<int>();
            IReadOnlyList<string> effectNames = Array.Empty<string>();
            if (category == "ward")
            {
                (effectIds, effectNames) = ParseEffects(fields[6], fields[7], lineNumber);
            }
            else if (fields[6] != "-" || fields[7] != "-")
            {
                throw new InvalidDataException(
                    $"Summoner capability catalog line {lineNumber} defines maintained effects for a Rage."
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
            var action = new SummonerActionCapability(
                actionId,
                actionName,
                category,
                avatarName,
                effectIds,
                effectNames
            );
            destination.Add(action);
            if (category == "ward" && action.IsMaintainable)
            {
				avatar.MaintainableWards.Add(action);
			}
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

	private static (IReadOnlyList<int> Ids, IReadOnlyList<string> Names) ParseEffects(
		string effectIdsValue,
		string effectNamesValue,
		int lineNumber
	)
	{
		if (effectIdsValue == "-" && effectNamesValue == "-")
		{
			return (Array.Empty<int>(), Array.Empty<string>());
		}
		if (effectIdsValue == "-" || effectNamesValue == "-")
		{
			throw new InvalidDataException(
				$"Summoner capability catalog line {lineNumber} requires effect_ids and effect_names to both be populated or '-'."
			);
		}
		var rawIds = effectIdsValue.Split('|');
		var names = effectNamesValue.Split('|');
		if (rawIds.Any(value => value.Length == 0) || names.Any(value => value.Length == 0))
		{
			throw new InvalidDataException(
				$"Summoner capability catalog line {lineNumber} contains an empty maintained-effect entry."
			);
		}
		if (rawIds.Length != names.Length)
		{
			throw new InvalidDataException(
				$"Summoner capability catalog line {lineNumber} requires equal effect_ids and effect_names lengths."
			);
		}
		var ids = new List<int>(rawIds.Length);
		var seenIds = new HashSet<int>();
		for (var index = 0; index < rawIds.Length; index++)
		{
			var effectId = RequiredPositiveInteger(rawIds[index], $"effect_ids[{index + 1}]", lineNumber);
			if (!seenIds.Add(effectId))
			{
				throw new InvalidDataException(
					$"Summoner capability catalog line {lineNumber} duplicates effect id {effectId}."
				);
			}
			ids.Add(effectId);
		}
		return (ids.AsReadOnly(), Array.AsReadOnly(names));
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
