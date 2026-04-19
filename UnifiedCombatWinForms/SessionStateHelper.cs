using System.Text.Json;
using System.Text.RegularExpressions;

namespace UnifiedCombatWinForms;

internal static partial class SessionStateHelper
{
    private static readonly Regex TrailingBracketId = MyRegex();

    [GeneratedRegex(@"\[(\d+)\]\s*$", RegexOptions.Compiled)]
    private static partial Regex MyRegex();

    public static List<string> SplitOptions(JsonElement? raw)
    {
        if (raw is not { ValueKind: JsonValueKind.String })
        {
            return [];
        }

        var s = raw.Value.GetString() ?? "";
        return s.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
    }

    public static List<(int Id, string Name)> ParseIgnoreEntriesFrom(JsonElement s, string prop)
    {
        return s.TryGetProperty(prop, out var raw) ? ParseIgnoreEntries(raw) : [];
    }

    public static List<(int Id, string Name)> ParseIgnoreEntries(JsonElement raw)
    {
        var outl = new List<(int, string)>();
        if (raw.ValueKind != JsonValueKind.String)
        {
            return outl;
        }

        var s = raw.GetString() ?? "";
        foreach (var part in s.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var idx = part.IndexOf(':');
            if (idx <= 0)
            {
                continue;
            }

            if (!int.TryParse(part[..idx], out var id))
            {
                continue;
            }

            outl.Add((id, part[(idx + 1)..]));
        }

        return outl;
    }

    public static int? ParseTrailingBracketId(string line)
    {
        var m = TrailingBracketId.Match(line.Trim());
        return m.Success && int.TryParse(m.Groups[1].Value, out var id) ? id : null;
    }

    public static bool AsBool(JsonElement p) =>
        p.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String => p.GetString()?.Trim().ToLowerInvariant() is "true" or "on" or "1" or "yes",
            JsonValueKind.Number => p.GetInt64() != 0,
            _ => false,
        };

    public static bool GetBool(JsonElement s, string name, bool defaultValue = false)
    {
        if (!s.TryGetProperty(name, out var p))
        {
            return defaultValue;
        }

        return AsBool(p);
    }

    public static string GetString(JsonElement s, string name, string defaultValue = "")
    {
        if (!s.TryGetProperty(name, out var p))
        {
            return defaultValue;
        }

        return p.ValueKind switch
        {
            JsonValueKind.String => p.GetString() ?? defaultValue,
            JsonValueKind.Number => p.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => p.GetRawText(),
        };
    }

    public static string AbilitySignature(JsonElement s)
    {
        var job = GetString(s, "job");
        var sub = GetString(s, "sub_job");
        var sync = GetString(s, "level_sync");
        return string.Join("|", job, sub, sync);
    }

    public static string WsKeyForEngine(string eng) => eng == "melee" ? "ws1" : "weaponskill";

    public static string WsFromState(JsonElement s, string eng)
    {
        var key = WsKeyForEngine(eng);
        var v = GetString(s, key);
        if (!string.IsNullOrEmpty(v))
        {
            return v;
        }

        var other = key == "ws1" ? "weaponskill" : "ws1";
        return GetString(s, other);
    }
}
