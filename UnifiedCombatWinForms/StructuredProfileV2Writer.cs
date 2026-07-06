using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal sealed record StructuredProfileV2Identity(string Character, string MainJob, string SubJob)
{
    public string Source { get; init; } = "ui";
}

internal sealed record StructuredProfileV2WriteResult(
    bool Ok,
    string Path,
    string? Error,
    string? Detail,
    string? Stage,
    string? TempPath,
    string? BackupPath
);

internal interface IStructuredProfileV2FileSystem
{
    bool DirectoryExists(string path);
    void CreateDirectory(string path);
    bool FileExists(string path);
    void WriteAllText(string path, string content);
    void Move(string sourcePath, string destinationPath);
    void Delete(string path);
}

internal sealed class PhysicalStructuredProfileV2FileSystem : IStructuredProfileV2FileSystem
{
    public bool DirectoryExists(string path) => Directory.Exists(path);

    public void CreateDirectory(string path) => Directory.CreateDirectory(path);

    public bool FileExists(string path) => File.Exists(path);

    public void WriteAllText(string path, string content) => File.WriteAllText(path, content, new UTF8Encoding(false));

    public void Move(string sourcePath, string destinationPath) => File.Move(sourcePath, destinationPath);

    public void Delete(string path)
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }
}

internal sealed class StructuredProfileV2FileWriteException : Exception
{
    public StructuredProfileV2FileWriteException(string message, Exception? innerException = null)
        : base(message, innerException)
    {
    }
}

internal static class StructuredProfileV2Writer
{
    private static readonly IStructuredProfileV2FileSystem PhysicalFileSystem = new PhysicalStructuredProfileV2FileSystem();

    internal static string? FindAddonRootFrom(string startDir)
    {
        try
        {
            var dir = new DirectoryInfo(startDir);
            while (dir is not null)
            {
                var hasUcLua = File.Exists(Path.Combine(dir.FullName, "UnifiedCombat.lua"));
                var hasBridge = File.Exists(Path.Combine(dir.FullName, "remote_bridge.lua"));
                var hasData = Directory.Exists(Path.Combine(dir.FullName, "data"));
                if (hasUcLua && hasBridge && hasData)
                {
                    return dir.FullName;
                }

                dir = dir.Parent;
            }
        }
        catch
        {
            // fail fast via null
        }

        return null;
    }

    internal static string SafeCharacterComponent(string? value)
    {
        var trimmed = (value ?? "").Trim().ToLowerInvariant();
        var builder = new StringBuilder(trimmed.Length);
        var lastWasUnderscore = false;
        foreach (var ch in trimmed)
        {
            var keep = char.IsLetterOrDigit(ch) || ch == '-' || ch == '_';
            if (keep)
            {
                builder.Append(ch);
                lastWasUnderscore = false;
                continue;
            }

            if (!lastWasUnderscore)
            {
                builder.Append('_');
                lastWasUnderscore = true;
            }
        }

        var result = builder.ToString().Trim('_');
        return result.Length == 0 ? "unknown" : result;
    }

    internal static string SafeJobComponent(string? value)
    {
        var trimmed = (value ?? "").Trim().ToUpperInvariant();
        var builder = new StringBuilder(trimmed.Length);
        var lastWasUnderscore = false;
        foreach (var ch in trimmed)
        {
            var keep = char.IsLetterOrDigit(ch) || ch == '-' || ch == '_';
            if (keep)
            {
                builder.Append(ch);
                lastWasUnderscore = false;
                continue;
            }

            if (!lastWasUnderscore)
            {
                builder.Append('_');
                lastWasUnderscore = true;
            }
        }

        var result = builder.ToString().Trim('_');
        return result.Length == 0 ? "UNKNOWN" : result;
    }

    internal static string BuildFinalPath(string addonRoot, StructuredProfileV2Identity identity)
    {
        var safeCharacter = SafeCharacterComponent(identity.Character);
        var safeMainJob = SafeJobComponent(identity.MainJob);
        var safeSubJob = SafeJobComponent(identity.SubJob);
        return Path.Combine(addonRoot, "data", "profiles_v2", $"{safeCharacter}_{safeMainJob}_{safeSubJob}.lua");
    }

    internal static StructuredProfileV2WriteResult TryWriteStructuredProfile(
        string addonRoot,
        JsonObject flatProfile,
        StructuredProfileV2Identity identity,
        IStructuredProfileV2FileSystem? fileSystem = null
    )
    {
        var fs = fileSystem ?? PhysicalFileSystem;
        var finalPath = BuildFinalPath(addonRoot, identity);
        var content = BuildStructuredProfileFile(flatProfile, identity);
        return TryWriteFile(finalPath, content, fs);
    }

    internal static string BuildStructuredProfileFile(JsonObject flatProfile, StructuredProfileV2Identity identity)
    {
        var profile = BuildStructuredProfile(flatProfile, identity);
        return SerializeLua(profile);
    }

    private static StructuredProfileNode BuildStructuredProfile(JsonObject flatProfile, StructuredProfileV2Identity identity)
    {
        var profile = new StructuredProfileNode();
        profile.Add("version", 2);
        profile.Add(
            "profile",
            new StructuredProfileNode()
                .Add("schema_version", 2)
                .Add("engine", "UC")
                .Add("character", identity.Character)
                .Add("main_job", SafeJobComponent(identity.MainJob))
                .Add("sub_job", SafeJobComponent(identity.SubJob))
                .Add("source", identity.Source)
        );

        profile.Add("config", BuildConfig(flatProfile));
        return profile;
    }

    private static StructuredProfileNode BuildConfig(JsonObject flatProfile)
    {
        var config = new StructuredProfileNode();
        config.Add("ui", BuildUi(flatProfile));
        config.Add("command", BuildCommand(flatProfile));
        config.Add("combat", BuildCombat(flatProfile));
        config.Add("abilities", BuildAbilities(flatProfile));
        config.Add("defensive", BuildDefensive(flatProfile));
        config.Add("movement", BuildMovement(flatProfile));
        config.Add("follow", BuildFollow(flatProfile));
        config.Add("targeting", BuildTargeting(flatProfile));
        config.Add("tank", BuildTank(flatProfile));
        config.Add("sleep", BuildSleep(flatProfile));
        config.Add("spells", BuildSpells(flatProfile));
        config.Add("maintenance", BuildMaintenance(flatProfile));
        config.Add("debug", BuildDebug(flatProfile));
        config.Add("ownership", BuildOwnership(flatProfile));
        config.Add("legacy", BuildLegacy(flatProfile));
        return config;
    }

    private static StructuredProfileNode BuildUi(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("show_ingame_ui", ReadBool(flatProfile, "show_ingame_ui", false));
    }

    private static StructuredProfileNode BuildCommand(JsonObject flatProfile)
    {
        _ = flatProfile;
        return new StructuredProfileNode()
            .Add("engine_enabled_default", false);
    }

    private static StructuredProfileNode BuildCombat(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", true)
            .Add("autotarget", ReadBool(flatProfile, "autotarget", false))
            .Add("spam", ReadBool(flatProfile, "spam", false))
            .Add("closer", ReadBool(flatProfile, "closer", false))
            .Add("manual", ReadBool(flatProfile, "manual", false))
            .Add("prime", ReadBool(flatProfile, "prime", false))
            .Add("static", ReadBool(flatProfile, "static", false))
            .Add("face", ReadBool(flatProfile, "face", false))
            .Add(
                "weaponskill",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "weaponskill_active", false))
                    .Add("primary", ReadString(flatProfile, "weaponskill", ""))
                    .Add("mode", ReadString(flatProfile, "ws_mode", "smart"))
                    .Add("aftermath_enabled", ReadBool(flatProfile, "aftermath_enabled", false))
                    .Add("aftermath_ws", ReadString(flatProfile, "aftermath_ws", ""))
            );
    }

    private static StructuredProfileNode BuildAbilities(JsonObject flatProfile)
    {
        var configured = SplitPipeList(ReadString(flatProfile, "abilities_selected", ""));
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "ability_active", false))
            .Add("configured", configured)
            .Add("legacy_slots", EmptyList())
            .Add("wsabilities", EmptyList());
    }

    private static StructuredProfileNode BuildDefensive(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "defensive_enabled", false))
            .Add("provider", ReadString(flatProfile, "defensive_provider", "internal"))
            .Add(
                "cure",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_cure_enabled", false))
                    .Add("min_tier", ReadInt(flatProfile, "def_heal_min_tier_cure", 3))
                    .Add("max_tier", ReadInt(flatProfile, "def_heal_max_tier_cure", 4))
                    .Add("min_missing_hp", ReadInt(flatProfile, "def_heal_min_missing_hp", 250))
                    .Add("ignore_trusts", ReadBool(flatProfile, "def_heal_ignore_trusts", true))
            )
            .Add("doom", new StructuredProfileNode().Add("holy_water_enabled", ReadBool(flatProfile, "defensive_doom_water", false)))
            .Add("na", new StructuredProfileNode().Add("enabled", ReadBool(flatProfile, "defensive_na_enabled", false)))
            .Add("enemy_buffs", new StructuredProfileNode().Add("remove", ReadBool(flatProfile, "def_remove_enemy_buffs", false)))
            .Add(
                "buffs",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_buff_enabled", false))
                    .Add("self_only", ReadBool(flatProfile, "defensive_buff_self_only", true))
                    .Add("list", ReadString(flatProfile, "defensive_buffs", ""))
                    .Add("overwrite_enabled", ReadBool(flatProfile, "defensive_overwrite_enabled", false))
                    .Add("overwrite_interval", ReadInt(flatProfile, "defensive_overwrite_interval", 150))
            )
            .Add(
                "thresholds",
                new StructuredProfileNode()
                    .Add("critical_hpp", ReadInt(flatProfile, "defensive_critical_hpp", 35))
                    .Add("medium_hpp", ReadInt(flatProfile, "defensive_medium_hpp", 55))
            );
    }

    private static StructuredProfileNode BuildMovement(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", true)
            .Add("move", ReadBool(flatProfile, "move", false))
            .Add(
                "spacing",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "spacing", false))
                    .Add("band_min", ReadDouble(flatProfile, "spacing_band_min", -0.9))
                    .Add("band_max", ReadDouble(flatProfile, "spacing_band_max", 0.4))
                    .Add("model_size_floor", ReadDouble(flatProfile, "spacing_model_size_floor", 0.9))
                    .Add("use_prediction", ReadBool(flatProfile, "spacing_use_prediction", true))
                    .Add("lookahead_s", ReadDouble(flatProfile, "spacing_lookahead_s", 0.25))
                    .Add("repel_hold_ticks", ReadInt(flatProfile, "spacing_repel_hold_ticks", 5))
                    .Add("overlap_deadband", ReadDouble(flatProfile, "spacing_overlap_deadband", 0.1))
                    .Add("repel_weight", ReadDouble(flatProfile, "spacing_repel_weight", 0.35))
                    .Add("band_deadband", ReadDouble(flatProfile, "spacing_band_deadband", 0.2))
            )
            .Add(
                "path",
                new StructuredProfileNode()
                    .Add("recording", ReadBool(flatProfile, "path_recording", false))
                    .Add("follow_enabled", ReadBool(flatProfile, "path_follow_enabled", false))
                    .Add("file_name", ReadString(flatProfile, "path_file_name", ""))
                    .Add("route_type", ReadString(flatProfile, "path_route_type", "unknown"))
                    .Add("distance_to_start", 0)
                    .Add("points", EmptyList())
                    .Add("party_gate_yalms", ReadDouble(flatProfile, "path_party_gate_yalms", 3.0))
                    .Add("resume_index_window", ReadInt(flatProfile, "path_resume_index_window", 12))
                    .Add("hunter_targets", EmptyList())
                    .Add("hunter_max_z_delta", ReadDouble(flatProfile, "path_hunter_max_z_delta", 2.0))
                    .Add("hunter_max_target_range", ReadDouble(flatProfile, "path_hunter_max_target_range", 20.0))
                    .Add("hunter_claim_timeout_s", ReadDouble(flatProfile, "path_hunter_claim_timeout_s", 4.0))
                    .Add("hunter_ignore_cooldown_s", ReadDouble(flatProfile, "path_hunter_ignore_cooldown_s", 20.0))
                    .Add("pull_action_type", ReadString(flatProfile, "path_pull_action_type", "ja"))
                    .Add("pull_action_name", ReadString(flatProfile, "path_pull_action_name", ""))
            );
    }

    private static StructuredProfileNode BuildFollow(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", true)
            .Add(
                "party",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "party_follow", false))
                    .Add("leader_id", 0)
                    .Add("leader_name", ReadString(flatProfile, "party_follow_selected", ""))
                    .Add("min", ReadDouble(flatProfile, "party_follow_min", 0.5))
                    .Add("max", ReadDouble(flatProfile, "party_follow_max", 50.0))
            )
            .Add(
                "fight",
                new StructuredProfileNode()
                    .Add("leader", false)
                    .Add("leader_id", 0)
                    .Add("min", ReadDouble(flatProfile, "fight_follow_min", 3.0))
                    .Add("hold_s", ReadDouble(flatProfile, "fight_follow_hold_s", 8.0))
            )
            .Add(
                "partner",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "partner", false))
                    .Add("secondary_enabled", false)
                    .Add("ids", EmptyList())
                    .Add("puller", ReadBool(flatProfile, "puller", false))
                    .Add("puller_id", 0)
                    .Add("puller_distance_only", ReadBool(flatProfile, "puller_distance_only", false))
            );
    }

    private static StructuredProfileNode BuildTargeting(JsonObject flatProfile)
    {
        _ = flatProfile;
        return new StructuredProfileNode()
            .Add("add_control", ReadBool(flatProfile, "add_control", false))
            .Add("legacy_slots", EmptyList())
            .Add("targets", EmptyList())
            .Add("targetability", new StructuredProfileNode().Add("enabled", false).Add("action", ""))
            .Add("ignore", EmptyList())
            .Add("target_ignore_names", EmptyList());
    }

    private static StructuredProfileNode BuildTank(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "tank", false))
            .Add("enmity", new StructuredProfileNode().Add("actions", SplitPipeList(ReadString(flatProfile, "tank_enmity_actions", ""))));
    }

    private static StructuredProfileNode BuildSleep(JsonObject flatProfile)
    {
        _ = flatProfile;
        return new StructuredProfileNode()
            .Add("enabled", false)
            .Add("order", EmptyList())
            .Add("legacy_primary", "");
    }

    private static StructuredProfileNode BuildSpells(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "spell_active", false))
            .Add("configured", ReadString(flatProfile, "spell", ""))
            .Add("dd2_slots", EmptyList());
    }

    private static StructuredProfileNode BuildMaintenance(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", true)
            .Add(
                "cor",
                new StructuredProfileNode()
                    .Add("roll_1", ReadString(flatProfile, "cor_roll_1", ""))
                    .Add("roll_2", ReadString(flatProfile, "cor_roll_2", ""))
                    .Add("crooked_roll_slot", ReadInt(flatProfile, "cor_crooked_roll_slot", 0))
                    .Add("elevens", ReadBool(flatProfile, "cor_elevens", false))
                    .Add("luzaf_range_override", ReadBool(flatProfile, "cor_luzaf_range_override", false))
                    .Add("range_selected", ReadString(flatProfile, "cor_roll_range_selected", ""))
                    .Add("range_require_ids", EmptyList())
            )
            .Add("brd", EmptyList())
            .Add("geo", EmptyList());
    }

    private static StructuredProfileNode BuildDebug(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "debug", false))
            .Add("combat_sched", ReadBool(flatProfile, "log_combat_sched", false))
            .Add("ja_sched", ReadBool(flatProfile, "log_ja_sched", false))
            .Add("ja_debug", ReadBool(flatProfile, "log_ja_debug", false))
            .Add("def_sched", ReadBool(flatProfile, "log_def_sched", false))
            .Add("tank_sched", ReadBool(flatProfile, "log_tank_sched", false));
    }

    private static StructuredProfileNode BuildOwnership(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("domain_combat_enabled", ReadBool(flatProfile, "domain_combat_enabled", true))
            .Add("domain_defensive_enabled", ReadBool(flatProfile, "domain_defensive_enabled", true))
            .Add("domain_movement_enabled", ReadBool(flatProfile, "domain_movement_enabled", true))
            .Add("domain_maintenance_enabled", ReadBool(flatProfile, "domain_maintenance_enabled", true))
            .Add("domain_follow_enabled", ReadBool(flatProfile, "domain_follow_enabled", true))
            .Add("scheduler_dark_launch_combat", ReadBool(flatProfile, "scheduler_dark_launch_combat", false))
            .Add("scheduler_dark_launch_defensive", ReadBool(flatProfile, "scheduler_dark_launch_defensive", false))
            .Add("scheduler_dark_launch_movement", ReadBool(flatProfile, "scheduler_dark_launch_movement", false))
            .Add("scheduler_dark_launch_maintenance", ReadBool(flatProfile, "scheduler_dark_launch_maintenance", false));
    }

    private static StructuredProfileNode BuildLegacy(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("sub", ReadBool(flatProfile, "sub", false))
            .Add("sub2", ReadBool(flatProfile, "sub2", false))
            .Add("solo", ReadBool(flatProfile, "solo", false))
            .Add("aeonic", ReadBool(flatProfile, "aeonic", false))
            .Add("color", ReadBool(flatProfile, "color", false))
            .Add("command", ReadBool(flatProfile, "command", false))
            .Add("hunter", ReadBool(flatProfile, "hunter", false))
            .Add("profiles", new StructuredProfileNode());
    }

    private static StructuredProfileV2WriteResult TryWriteFile(string finalPath, string content, IStructuredProfileV2FileSystem fs)
    {
        try
        {
            var finalDir = Path.GetDirectoryName(finalPath);
            if (string.IsNullOrWhiteSpace(finalDir))
            {
                return Fail(finalPath, "prepare_dir", "output path unavailable", "missing final directory", null, null);
            }

            var dataDir = Path.GetDirectoryName(finalDir);
            if (string.IsNullOrWhiteSpace(dataDir) || !fs.DirectoryExists(dataDir))
            {
                return Fail(finalPath, "prepare_dir", "addon data directory unavailable", "missing addon data directory", null, null);
            }

            if (!fs.DirectoryExists(finalDir))
            {
                fs.CreateDirectory(finalDir);
            }

            var tempPath = finalPath + "." + Path.GetRandomFileName() + ".tmp";
            fs.WriteAllText(tempPath, content);

            var finalExists = fs.FileExists(finalPath);
            string? backupPath = null;
            try
            {
                if (finalExists)
                {
                    backupPath = finalPath + "." + Path.GetRandomFileName() + ".bak";
                    fs.Move(finalPath, backupPath);
                    fs.Move(tempPath, finalPath);
                    fs.Delete(backupPath);
                }
                else
                {
                    fs.Move(tempPath, finalPath);
                }
            }
            catch (Exception ex)
            {
                if (backupPath is not null && fs.FileExists(backupPath))
                {
                    try
                    {
                        if (!fs.FileExists(finalPath))
                        {
                            fs.Move(backupPath, finalPath);
                        }
                    }
                    catch
                    {
                        // leave the original final path untouched when restore fails
                    }
                }

                if (fs.FileExists(tempPath))
                {
                    fs.Delete(tempPath);
                }

                if (backupPath is not null && fs.FileExists(backupPath))
                {
                    fs.Delete(backupPath);
                }

                return Fail(finalPath, "promote", "temp promote failed", ex.Message, tempPath, backupPath);
            }

            if (fs.FileExists(tempPath))
            {
                fs.Delete(tempPath);
            }

            return new StructuredProfileV2WriteResult(true, finalPath, null, null, "done", tempPath, null);
        }
        catch (StructuredProfileV2FileWriteException ex)
        {
            return Fail(finalPath, "write", "write failed", ex.Message, null, null);
        }
        catch (Exception ex)
        {
            return Fail(finalPath, "write", "write failed", ex.Message, null, null);
        }
    }

    private static StructuredProfileV2WriteResult Fail(string path, string? stage, string error, string detail, string? tempPath, string? backupPath)
    {
        return new StructuredProfileV2WriteResult(false, path, error, detail, stage, tempPath, backupPath);
    }

    private static string SerializeLua(StructuredProfileNode node)
    {
        var builder = new StringBuilder();
        builder.Append("return ");
        AppendValue(builder, node, 0);
        builder.Append('\n');
        return builder.ToString();
    }

    private static void AppendValue(StringBuilder builder, object? value, int indent)
    {
        switch (value)
        {
            case null:
                builder.Append("nil");
                return;
            case bool boolValue:
                builder.Append(boolValue ? "true" : "false");
                return;
            case string stringValue:
                builder.Append(QuoteLuaString(stringValue));
                return;
            case byte or sbyte or short or ushort or int or uint or long or ulong:
                builder.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
                return;
            case float floatValue:
                builder.Append(floatValue.ToString("0.################", CultureInfo.InvariantCulture));
                return;
            case double doubleValue:
                builder.Append(doubleValue.ToString("0.################", CultureInfo.InvariantCulture));
                return;
            case decimal decimalValue:
                builder.Append(decimalValue.ToString(CultureInfo.InvariantCulture));
                return;
            case StructuredProfileNode table:
                AppendTable(builder, table, indent);
                return;
            case List<object?> list:
                AppendList(builder, list, indent);
                return;
            default:
                builder.Append(QuoteLuaString(Convert.ToString(value, CultureInfo.InvariantCulture) ?? ""));
                return;
        }
    }

    private static void AppendTable(StringBuilder builder, StructuredProfileNode table, int indent)
    {
        if (table.Entries.Count == 0)
        {
            builder.Append("{}");
            return;
        }

        builder.Append('{');
        for (var i = 0; i < table.Entries.Count; i++)
        {
            var entry = table.Entries[i];
            builder.Append('\n');
            builder.Append(new string(' ', indent + 4));
            builder.Append(IsIdentifier(entry.Key) ? entry.Key : QuoteLuaString(entry.Key));
            builder.Append(" = ");
            AppendValue(builder, entry.Value, indent + 4);
            builder.Append(',');
        }
        builder.Append('\n');
        builder.Append(new string(' ', indent));
        builder.Append('}');
    }

    private static void AppendList(StringBuilder builder, List<object?> list, int indent)
    {
        if (list.Count == 0)
        {
            builder.Append("{}");
            return;
        }

        builder.Append('{');
        for (var i = 0; i < list.Count; i++)
        {
            builder.Append('\n');
            builder.Append(new string(' ', indent + 4));
            AppendValue(builder, list[i], indent + 4);
            builder.Append(',');
        }
        builder.Append('\n');
        builder.Append(new string(' ', indent));
        builder.Append('}');
    }

    private static bool IsIdentifier(string key)
    {
        return !string.IsNullOrEmpty(key) && (char.IsLetter(key[0]) || key[0] == '_') && key.All(ch => char.IsLetterOrDigit(ch) || ch == '_');
    }

    private static string QuoteLuaString(string value)
    {
        var builder = new StringBuilder();
        builder.Append('"');
        foreach (var ch in value)
        {
            switch (ch)
            {
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\a':
                    builder.Append("\\a");
                    break;
                case '\b':
                    builder.Append("\\b");
                    break;
                case '\f':
                    builder.Append("\\f");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                case '\v':
                    builder.Append("\\v");
                    break;
                default:
                    if (ch < ' ')
                    {
                        builder.Append('\\');
                        builder.Append(((int)ch).ToString("000", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        builder.Append(ch);
                    }
                    break;
            }
        }
        builder.Append('"');
        return builder.ToString();
    }

    private static string ReadString(JsonObject flatProfile, string key, string defaultValue)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }

        return node switch
        {
            JsonValue value when value.TryGetValue<string>(out var text) => (text ?? "").Trim(),
            JsonValue value when value.TryGetValue<bool>(out var boolText) => boolText ? "true" : "false",
            JsonValue value when value.TryGetValue<double>(out var doubleText) => doubleText.ToString(CultureInfo.InvariantCulture),
            JsonValue value when value.TryGetValue<long>(out var longText) => longText.ToString(CultureInfo.InvariantCulture),
            _ => node.ToString().Trim(),
        };
    }

    private static bool ReadBool(JsonObject flatProfile, string key, bool defaultValue)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }

        if (node is JsonValue value)
        {
            if (value.TryGetValue<bool>(out var boolValue))
            {
                return boolValue;
            }
            if (value.TryGetValue<string>(out var text))
            {
                var normalized = (text ?? "").Trim().ToLowerInvariant();
                return normalized is "true" or "on" or "1" or "yes";
            }
            if (value.TryGetValue<long>(out var numeric))
            {
                return numeric != 0;
            }
        }

        return defaultValue;
    }

    private static int ReadInt(JsonObject flatProfile, string key, int defaultValue)
    {
        var number = ReadDouble(flatProfile, key, defaultValue);
        return (int)Math.Round(number, MidpointRounding.AwayFromZero);
    }

    private static double ReadDouble(JsonObject flatProfile, string key, double defaultValue)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }

        if (node is JsonValue value)
        {
            if (value.TryGetValue<double>(out var doubleValue))
            {
                return doubleValue;
            }
            if (value.TryGetValue<long>(out var longValue))
            {
                return longValue;
            }
            if (value.TryGetValue<string>(out var text) && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
            {
                return parsed;
            }
        }

        return defaultValue;
    }

    private static List<object?> SplitPipeList(string value)
    {
        var parts = value.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var list = new List<object?>(parts.Length);
        foreach (var part in parts)
        {
            list.Add(part);
        }
        return list;
    }

    private static List<object?> EmptyList() => [];

    private sealed class StructuredProfileNode
    {
        public List<KeyValuePair<string, object?>> Entries { get; } = [];

        public StructuredProfileNode Add(string key, object? value)
        {
            Entries.Add(new KeyValuePair<string, object?>(key, value));
            return this;
        }
    }
}
