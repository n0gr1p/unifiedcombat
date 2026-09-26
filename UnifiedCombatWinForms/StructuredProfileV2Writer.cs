using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

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

internal sealed record TargetedBuffEntry(string Character, string Buff);
internal sealed record BardTargetedSongSet(IReadOnlyList<string> Recipients, IReadOnlyList<string> PrioritySongs);
internal sealed record ScholarStormAssignment(string Spell, IReadOnlyList<string> Targets);

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
    private static readonly Regex TrailingDisplayIndex = new(@"\s*\[[^\]]+\]\s*$", RegexOptions.Compiled);

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

        profile.Add("config", BuildConfig(flatProfile, identity));
        return profile;
    }

    private static StructuredProfileNode BuildConfig(JsonObject flatProfile, StructuredProfileV2Identity identity)
    {
        var config = new StructuredProfileNode();
        config.Add("ui", BuildUi(flatProfile));
        config.Add("combat", BuildCombat(flatProfile));
        config.Add("abilities", BuildAbilities(flatProfile));
        config.Add("defensive", BuildDefensive(flatProfile));
        config.Add("encounter", BuildEncounter(flatProfile));
        config.Add("movement", BuildMovement(flatProfile));
        config.Add("follow", BuildFollow(flatProfile));
        config.Add("targeting", BuildTargeting(flatProfile));
        var reactions = BuildReactions(flatProfile);
        if (reactions is not null)
        {
            config.Add("reactions", reactions);
        }
        config.Add("tank", BuildTank(flatProfile));
        config.Add("sleep", BuildSleep(flatProfile));
        config.Add("spells", BuildSpells(flatProfile));
        config.Add("maintenance", BuildMaintenance(flatProfile, identity));
        var summoner = BuildSummoner(flatProfile, identity);
        if (summoner is not null)
        {
            config.Add("summoner", summoner);
        }
        var puppetmaster = BuildPuppetmaster(flatProfile, identity);
        if (puppetmaster is not null)
        {
            config.Add("puppetmaster", puppetmaster);
        }
        var scholar = BuildScholar(flatProfile, identity);
        if (scholar is not null)
        {
            config.Add("sch", scholar);
        }
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

    private static string ReadSkillchainTarget(JsonObject flatProfile)
    {
        var target = ReadString(flatProfile, "skillchain_target", "auto").Trim().ToLowerInvariant();
        return target switch
        {
            "auto" or "compression" or "liquefaction" or "induration" or "reverberation"
                or "transfixion" or "scission" or "detonation" or "impaction"
                or "gravitation" or "fragmentation" or "distortion" or "fusion"
                or "light" or "darkness" or "radiance" or "umbra" => target,
            _ => throw new InvalidDataException($"Unsupported skillchain target: {target}"),
        };
    }

    private static StructuredProfileNode BuildCombat(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadRequiredBool(flatProfile, "domain_combat_enabled"))
            .Add("autotarget", ReadBool(flatProfile, "autotarget", false))
            .Add("auto_engage", ReadBool(flatProfile, "auto_engage", true))
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
                    .Add("minimum_tp", ReadBoundedInt(flatProfile, "weaponskill_min_tp", 1000, 1000, 3000))
                    .Add("allow_aoe", ReadBool(flatProfile, "weaponskill_allow_aoe", true))
                    .Add("fast_skillchain", ReadBool(flatProfile, "fast_skillchain", false))
                    .Add("no_skillchain_targets", ParseNameList(ReadString(flatProfile, "no_skillchain_target_entries", "")))
                    .Add("skillchain_target", ReadSkillchainTarget(flatProfile))
                    .Add("wait_ignore_names", ParseNameList(ReadString(flatProfile, "ignore_entries", "")))
                    .Add("aftermath_enabled", ReadBool(flatProfile, "aftermath_enabled", false))
                    .Add("aftermath_ws", ReadString(flatProfile, "aftermath_ws", ""))
            )
            .Add("pulling", BuildCampPulling(flatProfile));
    }

    private static StructuredProfileNode BuildCampPulling(JsonObject flatProfile)
    {
        var enabled = ReadOptionalBool(flatProfile, "camp_pulling_enabled", false);
        var actionType = ReadString(flatProfile, "camp_pulling_action_type", "spell");
        if (actionType is not ("spell" or "ja"))
        {
            throw new InvalidDataException("Camp pulling action type must be spell or ja.");
        }
        var actionName = ReadString(flatProfile, "camp_pulling_action_name", "");
        var targets = ParseCampPullTargets(ReadString(flatProfile, "camp_pulling_targets", ""));
        var matchMode = ReadString(flatProfile, "camp_pulling_match_mode", "exact");
        if (matchMode is not ("exact" or "substring"))
        {
            throw new InvalidDataException("Camp pulling match mode must be exact or substring.");
        }
        if (enabled && actionName.Length == 0)
        {
            throw new InvalidDataException("Enabled camp pulling requires an action name.");
        }
        if (enabled && targets.Count == 0)
        {
            throw new InvalidDataException("Enabled camp pulling requires at least one target.");
        }
        return new StructuredProfileNode()
            .Add("enabled", enabled)
            .Add("mode", "camp")
            .Add(
                "action",
                new StructuredProfileNode()
                    .Add("type", actionType)
                    .Add("name", NullIfEmpty(actionName))
            )
            .Add("targets", targets)
            .Add("match_mode", matchMode)
            .Add("max_active_mobs", ReadBoundedInt(flatProfile, "camp_pulling_max_active_mobs", 1, 1, 20))
            .Add("replenish_below_hpp", ReadBoundedInt(flatProfile, "camp_pulling_replenish_below_hpp", 20, 0, 100))
            .Add("leash_yalms", ReadBoundedDouble(flatProfile, "camp_pulling_leash_yalms", 35.0, 1.0, 100.0))
            .Add("max_z_delta", ReadBoundedDouble(flatProfile, "camp_pulling_max_z_delta", 2.0, 0.0, 20.0))
            .Add("cast_range_ratio", ReadBoundedDouble(flatProfile, "camp_pulling_cast_range_ratio", 0.90, 0.1, 1.0))
            .Add("settle_seconds", ReadBoundedDouble(flatProfile, "camp_pulling_settle_seconds", 0.40, 0.0, 3.0))
            .Add("reaction_timeout_seconds", ReadBoundedDouble(flatProfile, "camp_pulling_reaction_timeout_seconds", 4.0, 0.5, 30.0))
            .Add("retry_limit", ReadBoundedInt(flatProfile, "camp_pulling_retry_limit", 2, 0, 10))
            .Add("retry_window_seconds", ReadBoundedDouble(flatProfile, "camp_pulling_retry_window_seconds", 2.5, 0.1, 30.0))
            .Add("target_cooldown_seconds", ReadBoundedDouble(flatProfile, "camp_pulling_target_cooldown_seconds", 20.0, 0.0, 300.0))
            .Add("camp_arrival_yalms", ReadBoundedDouble(flatProfile, "camp_pulling_camp_arrival_yalms", 0.75, 0.1, 10.0));
    }

    private static StructuredProfileNode BuildAbilities(JsonObject flatProfile)
    {
        var configured = SplitPipeList(ReadString(flatProfile, "abilities_selected", ""));
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "ability_active", false))
            .Add("allow_unengaged", ReadBool(flatProfile, "ability_allow_unengaged", false))
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
                "resurrection",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_resurrection_enabled", false))
                    .Add(
                        "priority",
                        SplitPipeList(ReadString(flatProfile, "defensive_resurrection_priority", "Arise|Raise III|Raise II|Raise"))
                    )
            )
            .Add(
                "cure",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_cure_enabled", false))
                    .Add("min_tier", ReadInt(flatProfile, "def_heal_min_tier_cure", 3))
                    .Add("max_tier", ReadInt(flatProfile, "def_heal_max_tier_cure", 4))
                    .Add("min_missing_hp", ReadInt(flatProfile, "def_heal_min_missing_hp", 250))
                    .Add("ignore_trusts", ReadBool(flatProfile, "def_heal_ignore_trusts", true))
                    .Add(
                        "curaga",
                        new StructuredProfileNode()
                            .Add("enabled", ReadBool(flatProfile, "defensive_curaga_enabled", false))
                            .Add("min_targets", Math.Clamp(ReadInt(flatProfile, "defensive_curaga_min_targets", 3), 2, 6))
                    )
            )
            .Add(
                "waltz",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_waltz_enabled", false))
                    .Add("tp_reserve", Math.Clamp(ReadInt(flatProfile, "defensive_waltz_tp_reserve", 0), 0, 3000))
                    .Add("divine_min_targets", Math.Clamp(ReadInt(flatProfile, "defensive_divine_waltz_min_targets", 3), 2, 6))
            )
            .Add("doom", new StructuredProfileNode().Add("holy_water_enabled", ReadBool(flatProfile, "defensive_doom_water", false)))
            .Add("charm_sleeper", new StructuredProfileNode().Add("enabled", ReadBool(flatProfile, "def_charm_sleeper_enabled", false)))
            .Add("sleep_waker", new StructuredProfileNode().Add("enabled", ReadBool(flatProfile, "def_sleep_waker_enabled", false)))
            .Add(
                "na",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_na_enabled", false))
                    .Add("limit_enabled", ReadBool(flatProfile, "defensive_na_limit_enabled", false))
                    .Add("priority", ReadString(flatProfile, "defensive_na_priority", ""))
            )
            .Add("enemy_buffs", new StructuredProfileNode().Add("remove", ReadBool(flatProfile, "def_remove_enemy_buffs", false)))
            .Add(
                "enemy_debuffs",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "def_maintain_enemy_debuffs", false))
                    .Add("list", ReadString(flatProfile, "defensive_enemy_debuffs", ""))
            )
            .Add(
                "buffs",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "defensive_buff_enabled", false))
                    .Add("self_only", ReadBool(flatProfile, "defensive_buff_self_only", true))
                    .Add("list", ReadString(flatProfile, "defensive_buffs", ""))
                    .Add("targeted", BuildTargetedBuffs(ReadString(flatProfile, "defensive_targeted_buffs", "")))
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

    private static StructuredProfileNode BuildEncounter(JsonObject flatProfile)
    {
        var enabled = ReadBool(flatProfile, "encounter_enabled", false);
        var encounterId = ReadString(flatProfile, "encounter_id", "").Trim().ToLowerInvariant();
        if (encounterId.Length == 0)
        {
            if (enabled)
            {
                throw new InvalidDataException("enabled encounter requires an encounter ID");
            }
        }
        else if (encounterId is not ("sortie_ghatjot" or "sortie_dhartok" or "kei" or "saved_by_the_bell"))
        {
            throw new InvalidDataException($"unsupported encounter ID: {encounterId}");
        }

        if (encounterId == "saved_by_the_bell")
        {
            return new StructuredProfileNode()
                .Add("enabled", enabled)
                .Add("id", encounterId);
        }

        if (encounterId == "kei")
        {
            var dealerName = StripTrailingDisplayIndex(ReadString(flatProfile, "kei_elemental_dealer_name", ""));
            var waterProbe = ReadString(flatProfile, "kei_water_probe_spell", "").Trim();
            var waterDamageSpell = ReadString(flatProfile, "kei_water_damage_spell", "").Trim();
            var iceProbe = ReadString(flatProfile, "kei_ice_probe_spell", "").Trim();
            var iceDamage = ReadString(flatProfile, "kei_ice_damage_spell", "").Trim();
            if (enabled && string.IsNullOrWhiteSpace(dealerName))
            {
                throw new InvalidDataException("enabled Kei encounter requires an elemental damage dealer");
            }
            if (enabled && new[] { waterProbe, waterDamageSpell, iceProbe, iceDamage }.Any(string.IsNullOrWhiteSpace))
            {
                throw new InvalidDataException("enabled Kei encounter requires all four elemental spell selections");
            }
            return new StructuredProfileNode()
                .Add("enabled", enabled)
                .Add("id", encounterId)
                .Add(
                    "kei",
                    new StructuredProfileNode()
                        .Add(
                            "elemental_damage",
                            new StructuredProfileNode()
                                .Add("dealer_name", dealerName)
                                .Add("water", new StructuredProfileNode().Add("probe_spell", waterProbe).Add("damage_spell", waterDamageSpell))
                                .Add("ice", new StructuredProfileNode().Add("probe_spell", iceProbe).Add("damage_spell", iceDamage))
                                .Add("sustain_interval_s", ReadBoundedDouble(flatProfile, "kei_sustain_interval_s", 2.5, 0.5, 30.0))
                                .Add("probe_timeout_s", ReadBoundedDouble(flatProfile, "kei_probe_timeout_s", 3.0, 0.5, 30.0))
                        )
                        .Add(
                            "fullers",
                            new StructuredProfileNode()
                                .Add("target_distance", ReadBoundedDouble(flatProfile, "kei_fullers_target_distance", 12.0, 0.1, 50.0))
                                .Add("prearm_hpp_margin", ReadBoundedDouble(flatProfile, "kei_fullers_prearm_hpp_margin", 1.0, 0.0, 10.0))
                        )
                );
        }

        var waterDamage = ReadEncounterPolicyMode(flatProfile, "encounter_water_damage", "enforce");
        var waterSkillchain = ReadEncounterPolicyMode(flatProfile, "encounter_water_skillchain", "enforce");
        var repeatDefault = encounterId == "sortie_dhartok" ? "warn" : "off";
        var repeatActionWall = ReadEncounterPolicyMode(flatProfile, "encounter_repeat_action_wall", repeatDefault);
        if (encounterId == "sortie_ghatjot" && repeatActionWall != "off")
        {
            throw new InvalidDataException("Ghatjot repeat-action policy must be off");
        }

        return new StructuredProfileNode()
            .Add("enabled", enabled)
            .Add("id", encounterId)
            .Add(
                "policy",
                new StructuredProfileNode()
                    .Add("water_damage", waterDamage)
                    .Add("water_skillchain", waterSkillchain)
                    .Add("repeat_action_wall", repeatActionWall)
            )
            .Add(
                "tuning",
                new StructuredProfileNode()
                    .Add("repeat_action_guard_s", ReadBoundedDouble(flatProfile, "encounter_repeat_action_guard_s", 10.0, 0.1, 120.0))
            );
    }

    private static string ReadEncounterPolicyMode(JsonObject flatProfile, string key, string defaultValue)
    {
        var mode = ReadString(flatProfile, key, defaultValue).Trim().ToLowerInvariant();
        if (mode is not ("enforce" or "warn" or "off"))
        {
            throw new InvalidDataException($"{key} must be enforce, warn, or off");
        }
        return mode;
    }

    private static StructuredProfileNode BuildMovement(JsonObject flatProfile)
    {
        var movement = new StructuredProfileNode()
            .Add("enabled", ReadRequiredBool(flatProfile, "domain_movement_enabled"))
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
                    .Add("route_type", ReadString(flatProfile, "path_route_type", "unknown"))
                    .Add("distance_to_start", 0)
                    .Add("points", EmptyList())
                    .Add("party_gate_yalms", ReadDouble(flatProfile, "path_party_gate_yalms", 3.0))
                    .Add("resume_index_window", ReadInt(flatProfile, "path_resume_index_window", 12))
                    .Add("hunter_targets", ParseNameList(ReadString(flatProfile, "path_hunter_entries", "")))
                    .Add("hunter_max_z_delta", ReadDouble(flatProfile, "path_hunter_max_z_delta", 2.0))
                    .Add("hunter_max_target_range", ReadDouble(flatProfile, "path_hunter_max_target_range", 20.0))
                    .Add("hunter_claim_timeout_s", ReadDouble(flatProfile, "path_hunter_claim_timeout_s", 4.0))
                    .Add("hunter_ignore_cooldown_s", ReadDouble(flatProfile, "path_hunter_ignore_cooldown_s", 20.0))
                    .Add("pull_action_type", ReadString(flatProfile, "path_pull_action_type", "ja"))
                    .Add("pull_action_name", ReadString(flatProfile, "path_pull_action_name", ""))
            );
        if (ReadFormationBool(flatProfile, "formation_enabled", false))
        {
            movement.Add("formation", BuildFormation(flatProfile));
        }
        var namedFormations = BuildNamedFormations(flatProfile);
        if (namedFormations is not null)
        {
            movement.Add("named_formations", namedFormations);
        }
        return movement;
    }

    private static StructuredProfileNode? BuildNamedFormations(JsonObject flatProfile)
    {
        var enabled = ReadBool(flatProfile, "named_formations_enabled", false);
        var entries = new List<object?>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (flatProfile.TryGetPropertyValue("named_formation_entries", out var node) && node is not null)
        {
            if (node is not JsonArray configuredEntries)
            {
                throw new InvalidDataException("named_formation_entries must be an array");
            }
            foreach (var item in configuredEntries)
            {
                if (item is not JsonObject entry)
                {
                    throw new InvalidDataException("named formation entries must be objects");
                }
                var mobName = ReadString(entry, "mob_name", "").Trim();
                if (mobName.Length == 0)
                {
                    throw new InvalidDataException("named formation requires an exact mob name");
                }
                if (!seen.Add(mobName))
                {
                    throw new InvalidDataException($"duplicate named formation mob: {mobName}");
                }
                entries.Add(BuildGenericFormationGeometry(entry).Add("mob_name", mobName));
            }
        }
        if (enabled && entries.Count == 0)
        {
            throw new InvalidDataException("enabled named formations require at least one mob entry");
        }
        if (!enabled && entries.Count == 0)
        {
            return null;
        }
        if (enabled && !ReadRequiredBool(flatProfile, "domain_movement_enabled"))
        {
            throw new InvalidDataException("enabled named formations require movement domain");
        }
        return new StructuredProfileNode()
            .Add("enabled", enabled)
            .Add("entries", entries);
    }

    private static StructuredProfileNode BuildFormation(JsonObject flatProfile)
    {
        if (!ReadFormationBool(flatProfile, "domain_movement_enabled", true))
        {
            throw new InvalidDataException("enabled formation requires movement domain");
        }

        var encounter = ReadString(flatProfile, "formation_encounter", "lilith_easy").ToLowerInvariant();
        if (encounter is "sortie_ghatjot" or "sortie_dhartok")
        {
            return BuildGenericFormation(flatProfile, encounter);
        }
        if (encounter != "lilith_easy")
        {
            throw new InvalidDataException($"unsupported formation encounter: {encounter}");
        }
        if (ReadFormationBool(flatProfile, "formation_mock_enabled", false))
        {
            throw new InvalidDataException("formation mock is supported only for generic formation");
        }

        var role = ReadString(flatProfile, "formation_role", "disabled").ToLowerInvariant();
        if (role is not ("tank" or "dps" or "healer"))
        {
            throw new InvalidDataException($"enabled formation requires tank, dps, or healer role: {role}");
        }

        var tankName = StripTrailingDisplayIndex(ReadString(flatProfile, "formation_tank_name", ""));
        if (string.IsNullOrWhiteSpace(tankName))
        {
            throw new InvalidDataException("enabled formation requires a tank character name");
        }

        var captureStable = ReadFormationNumber(flatProfile, "formation_capture_stable_s", 0.5, 0.1, 5.0);
        var captureTolerance = ReadFormationNumber(flatProfile, "formation_capture_tolerance", 0.1, 0.01, 1.0);
        var safeRadius = ReadFormationNumber(flatProfile, "formation_safe_radius", 16.0, 5.0, 30.0);
        var tankAccept = ReadFormationNumber(flatProfile, "formation_tank_accept_radius", 1.5, 0.1, 10.0);
        var tankReturn = ReadFormationNumber(flatProfile, "formation_tank_return_radius", 3.0, 0.2, 15.0);
        var dpsFlankAngle = ReadFormationNumber(flatProfile, "formation_dps_flank_angle_deg", 90.0, 1.0, 179.0);
        var dpsMeleeRadius = ReadFormationNumber(flatProfile, "formation_dps_melee_radius", 3.0, 0.5, 8.0);
        var dpsPositionTolerance = ReadFormationNumber(flatProfile, "formation_dps_position_tolerance", 1.5, 0.1, 5.0);
        var healerPreferredRadius = ReadFormationNumber(flatProfile, "formation_healer_preferred_radius", 12.0, 2.0, 25.0);
        var healerMinimumBossDistance = ReadFormationNumber(flatProfile, "formation_healer_minimum_boss_distance", 8.0, 1.0, 20.0);
        var healerMaximumPartyRange = ReadFormationNumber(flatProfile, "formation_healer_maximum_party_range", 18.0, 2.0, 25.0);
        var healerConeHalfAngle = ReadFormationNumber(flatProfile, "formation_healer_cone_half_angle_deg", 50.0, 1.0, 89.0);
        var healerConeSafetyMargin = ReadFormationNumber(flatProfile, "formation_healer_cone_safety_margin_deg", 15.0, 1.0, 45.0);
        var healerSampleStep = ReadFormationNumber(flatProfile, "formation_healer_sample_step_deg", 10.0, 1.0, 45.0);

        if (tankReturn <= tankAccept)
        {
            throw new InvalidDataException("formation tank return radius must exceed accept radius");
        }
        if (healerPreferredRadius >= safeRadius)
        {
            throw new InvalidDataException("formation healer preferred radius must be inside safe radius");
        }

        return new StructuredProfileNode()
            .Add("enabled", true)
            .Add("encounter", encounter)
            .Add("role", role)
            .Add("tank_name", tankName)
            .Add("required_party_names", ParseNameList(ReadString(flatProfile, "formation_required_party_names", "")))
            .Add("capture_stable_s", captureStable)
            .Add("capture_tolerance", captureTolerance)
            .Add("safe_radius", safeRadius)
            .Add(
                "tank",
                new StructuredProfileNode()
                    .Add("accept_radius", tankAccept)
                    .Add("return_radius", tankReturn)
            )
            .Add(
                "dps",
                new StructuredProfileNode()
                    .Add("flank_angle_deg", dpsFlankAngle)
                    .Add("melee_radius", dpsMeleeRadius)
                    .Add("position_tolerance", dpsPositionTolerance)
            )
            .Add(
                "healer",
                new StructuredProfileNode()
                    .Add("preferred_radius", healerPreferredRadius)
                    .Add("minimum_boss_distance", healerMinimumBossDistance)
                    .Add("maximum_party_range", healerMaximumPartyRange)
                    .Add("cone_half_angle_deg", healerConeHalfAngle)
                    .Add("cone_safety_margin_deg", healerConeSafetyMargin)
                    .Add("sample_step_deg", healerSampleStep)
            );
    }

    private static StructuredProfileNode BuildGenericFormation(JsonObject flatProfile, string encounter)
    {
        if (!ReadRequiredBool(flatProfile, "encounter_enabled"))
        {
            throw new InvalidDataException("enabled generic formation requires encounter configuration");
        }
        var configuredEncounter = ReadString(flatProfile, "encounter_id", "").Trim().ToLowerInvariant();
        if (!string.Equals(configuredEncounter, encounter, StringComparison.Ordinal))
        {
            throw new InvalidDataException("generic formation encounter must match encounter policy identity");
        }

        var formation = BuildGenericFormationGeometry(flatProfile)
            .Add("enabled", true)
            .Add("encounter", encounter);
        if (ReadFormationBool(flatProfile, "formation_mock_enabled", false))
        {
            var mockMobName = ReadString(flatProfile, "formation_mock_mob_name", "").Trim();
            if (string.IsNullOrWhiteSpace(mockMobName))
            {
                throw new InvalidDataException("enabled formation mock requires an exact mob name");
            }
            formation.Add(
                "mock",
                new StructuredProfileNode()
                    .Add("enabled", true)
                    .Add("mob_name", mockMobName)
            );
        }
        return formation;
    }

    private static StructuredProfileNode BuildGenericFormationGeometry(JsonObject flatProfile)
    {
        var mode = ReadString(flatProfile, "formation_placement_mode", "").Trim().ToLowerInvariant();
        if (mode is not ("radial_band" or "polar_band"))
        {
            throw new InvalidDataException("formation placement mode must be radial_band or polar_band");
        }
        var anchor = ReadString(flatProfile, "formation_anchor", "").Trim().ToLowerInvariant();
        if (anchor is not ("boss" or "encounter_origin" or "member"))
        {
            throw new InvalidDataException("formation anchor must be boss, encounter_origin, or member");
        }

        var minimumRadius = ReadRequiredFormationNumber(flatProfile, "formation_minimum_radius", 0, 50);
        var maximumRadius = ReadRequiredFormationNumber(flatProfile, "formation_maximum_radius", 0, 50);
        var preferredRadius = ReadRequiredFormationNumber(flatProfile, "formation_preferred_radius", 0, 50);
        if (maximumRadius < minimumRadius)
        {
            throw new InvalidDataException("formation maximum radius must be at least minimum radius");
        }
        if (preferredRadius < minimumRadius || preferredRadius > maximumRadius)
        {
            throw new InvalidDataException("formation preferred radius must be inside the radius band");
        }

        var placement = new StructuredProfileNode()
            .Add("mode", mode)
            .Add("anchor", anchor);
        if (anchor == "member")
        {
            var anchorMember = StripTrailingDisplayIndex(ReadString(flatProfile, "formation_anchor_member", ""));
            if (string.IsNullOrWhiteSpace(anchorMember))
            {
                throw new InvalidDataException("member-anchored formation requires an anchor member");
            }
            placement.Add("anchor_member", anchorMember);
        }

        placement
            .Add("preferred_radius", preferredRadius)
            .Add("minimum_radius", minimumRadius)
            .Add("maximum_radius", maximumRadius);
        if (mode == "polar_band")
        {
            var axisType = ReadString(flatProfile, "formation_axis_type", "").Trim().ToLowerInvariant();
            if (axisType is not ("boss_to_member" or "boss_heading"))
            {
                throw new InvalidDataException("polar formation axis must be boss_to_member or boss_heading");
            }
            var axis = new StructuredProfileNode().Add("type", axisType);
            if (axisType == "boss_to_member")
            {
                var axisMember = StripTrailingDisplayIndex(ReadString(flatProfile, "formation_axis_member", ""));
                if (string.IsNullOrWhiteSpace(axisMember))
                {
                    throw new InvalidDataException("boss-to-member polar formation requires an axis member");
                }
                axis.Add("member", axisMember);
            }
            placement
                .Add("axis", axis)
                .Add("preferred_angle_deg", ReadRequiredFormationNumber(flatProfile, "formation_preferred_angle_deg", -360, 360))
                .Add("allowed_angle_half_width_deg", ReadRequiredFormationNumber(flatProfile, "formation_allowed_angle_half_width_deg", 0, 180));
        }
        placement
            .Add("radius_step", ReadRequiredFormationNumber(flatProfile, "formation_radius_step", 0.1, 10))
            .Add("angle_step_deg", ReadRequiredFormationNumber(flatProfile, "formation_angle_step_deg", 1, 360));

        var hysteresisStart = ReadRequiredFormationNumber(flatProfile, "formation_hysteresis_start_distance", 0, 20);
        var hysteresisStop = ReadRequiredFormationNumber(flatProfile, "formation_hysteresis_stop_distance", 0, 20);
        if (hysteresisStart < hysteresisStop)
        {
            throw new InvalidDataException("formation hysteresis start distance must be at least stop distance");
        }

        var constraints = new StructuredProfileNode()
            .Add("avoid_encounter_hazards", ReadRequiredBool(flatProfile, "formation_avoid_encounter_hazards"))
            .Add("hazard_margin", ReadRequiredFormationNumber(flatProfile, "formation_hazard_margin", 0, 20));
        var safeOriginRadius = ReadRequiredFormationNumber(flatProfile, "formation_safe_origin_radius", 0, 50);
        var minimumBossDistance = ReadRequiredFormationNumber(flatProfile, "formation_minimum_boss_distance", 0, 50);
        var maximumBossDistance = ReadRequiredFormationNumber(flatProfile, "formation_maximum_boss_distance", 0, 50);
        var maximumPartyRange = ReadRequiredFormationNumber(flatProfile, "formation_maximum_party_range", 0, 50);
        if (maximumBossDistance > 0 && maximumBossDistance < minimumBossDistance)
        {
            throw new InvalidDataException("formation maximum boss distance must be at least minimum boss distance");
        }
        if (safeOriginRadius > 0)
        {
            constraints.Add("safe_origin_radius", safeOriginRadius);
        }
        if (minimumBossDistance > 0)
        {
            constraints.Add("minimum_boss_distance", minimumBossDistance);
        }
        if (maximumBossDistance > 0)
        {
            constraints.Add("maximum_boss_distance", maximumBossDistance);
        }
        if (maximumPartyRange > 0)
        {
            var requiredParty = ParseNameList(ReadString(flatProfile, "formation_required_party_names", ""));
            if (requiredParty.Count == 0)
            {
                throw new InvalidDataException("formation maximum party range requires at least one party member");
            }
            constraints
                .Add("maximum_party_range", maximumPartyRange)
                .Add("required_party_names", requiredParty);
        }

        return new StructuredProfileNode()
            .Add("placement", placement)
            .Add(
                "hysteresis",
                new StructuredProfileNode()
                    .Add("start_distance", hysteresisStart)
                    .Add("stop_distance", hysteresisStop)
            )
            .Add("constraints", constraints);
    }

    private static StructuredProfileNode BuildFollow(JsonObject flatProfile)
    {
        var partnerNames = ParseNameList(ReadString(flatProfile, "partner_entries", ""));
        var leashSource = ReadString(flatProfile, "puller_leash_source", "player").Trim().ToLowerInvariant();
        if (leashSource is not ("player" or "camp"))
        {
            throw new InvalidDataException($"puller_leash_source must be player or camp, got '{leashSource}'.");
        }
        var partner = new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "partner", false))
            .Add("secondary_enabled", partnerNames.Count > 1)
            .Add("names", partnerNames)
            .Add("puller", ReadBool(flatProfile, "puller", false))
            .Add("leash_source", leashSource)
            .Add("engage_range", Math.Clamp(ReadDouble(flatProfile, "puller_engage_range", 6.0), 0.1, 50.0))
            .Add("puller_distance_only", ReadBool(flatProfile, "puller_distance_only", false));

        var pullerName = ReadString(flatProfile, "puller_selected", ReadString(flatProfile, "puller_name", ""));
        if (leashSource == "player" && !string.IsNullOrWhiteSpace(pullerName))
        {
            partner.Add("puller_name", pullerName);
        }

        var follow = new StructuredProfileNode()
            .Add("enabled", ReadRequiredBool(flatProfile, "domain_follow_enabled"))
            .Add(
                "party",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "party_follow", false))
                    .Add("leader_name", ReadString(flatProfile, "party_follow_selected", ""))
                    .Add("min", ReadDouble(flatProfile, "party_follow_min", 0.5))
                    .Add("max", ReadDouble(flatProfile, "party_follow_max", 50.0))
            )
            .Add(
                "fight",
                BuildFightLeader(flatProfile)
            )
            .Add("partner", partner);

        var nyzul = BuildNyzul(flatProfile);
        if (nyzul is not null)
        {
            follow.Add("nyzul", nyzul);
        }

        return follow;
    }

    private static StructuredProfileNode? BuildNyzul(JsonObject flatProfile)
    {
        var coordinator = StripTrailingDisplayIndex(ReadString(flatProfile, "nyzul_coordinator_name", ""));
        var anchor = StripTrailingDisplayIndex(ReadString(flatProfile, "nyzul_anchor_name", ""));
        var parkingOrder = ParseNameList(ReadString(flatProfile, "nyzul_parking_order", ""));
        if (coordinator.Length == 0 && anchor.Length == 0 && parkingOrder.Count == 0)
        {
            return null;
        }
        if (coordinator.Length == 0)
        {
            throw new InvalidDataException("configured Nyzul roster requires a coordinator name");
        }
        if (anchor.Length == 0)
        {
            throw new InvalidDataException("configured Nyzul roster requires an anchor name");
        }
        if (parkingOrder.Count == 0)
        {
            throw new InvalidDataException("configured Nyzul roster requires at least one parker");
        }
        if (string.Equals(coordinator, anchor, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Nyzul coordinator and anchor must be different characters");
        }
        foreach (var rawName in parkingOrder)
        {
            var name = rawName?.ToString() ?? "";
            if (string.Equals(name, coordinator, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Nyzul parking order cannot contain the coordinator");
            }
            if (string.Equals(name, anchor, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Nyzul parking order cannot contain the anchor");
            }
        }

        return new StructuredProfileNode()
            .Add("coordinator_name", coordinator)
            .Add("anchor_name", anchor)
            .Add("parking_order", parkingOrder);
    }

    private static StructuredProfileNode BuildFightLeader(JsonObject flatProfile)
    {
        var fightLeaderEnabled = ReadBool(flatProfile, "fight_leader", false);
        var fight = new StructuredProfileNode()
            .Add("leader", fightLeaderEnabled)
            .Add("min", ReadDouble(flatProfile, "fight_follow_min", 3.0))
            .Add("hold_s", ReadDouble(flatProfile, "fight_follow_hold_s", 8.0));

        if (fightLeaderEnabled)
        {
            fight.Add("leader_name", ResolveFightLeaderName(flatProfile));
        }

        return fight;
    }

    private static string ResolveFightLeaderName(JsonObject flatProfile)
    {
        var fightLeaderName = ReadString(flatProfile, "fight_leader_selected", ReadString(flatProfile, "fight_leader_name", ""));
        fightLeaderName = StripTrailingDisplayIndex(fightLeaderName);
        return string.IsNullOrWhiteSpace(fightLeaderName) ? "" : fightLeaderName;
    }

    private static StructuredProfileNode BuildTargeting(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("add_control", ReadBool(flatProfile, "add_control", false))
            .Add("legacy_slots", EmptyList())
            .Add("targets", ParseNameList(ReadString(flatProfile, "add_priority_entries", "")))
            .Add("targetability", new StructuredProfileNode().Add("enabled", false).Add("action", ""))
            .Add("ignore", EmptyList())
            .Add("target_ignore_names", ParseNameList(ReadString(flatProfile, "target_ignore_entries", "")));
    }

    private static StructuredProfileNode? BuildReactions(JsonObject flatProfile)
    {
        var enabled = ReadBool(flatProfile, "reaction_enabled", false);
        var rules = ParseReactionRules(flatProfile);
        if (!enabled && rules.Count == 0)
        {
            return null;
        }
        return new StructuredProfileNode()
            .Add("enabled", enabled)
            .Add("rules", rules);
    }

    private static StructuredProfileNode BuildTank(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "tank", false))
            .Add(
                "enmity",
                new StructuredProfileNode()
                    .Add("actions", SplitPipeList(ReadString(flatProfile, "tank_enmity_actions", "")))
                    .Add("include_pets", ReadBool(flatProfile, "tank_enmity_include_pets", false))
            )
            .Add("run", BuildRunTank(flatProfile));
    }

    private static StructuredProfileNode BuildRunTank(JsonObject flatProfile)
    {
        var runes = SplitPipeList(ReadString(flatProfile, "run_tank_runes", ""));
        var canonicalRunes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Ignis"] = "Ignis", ["Gelus"] = "Gelus", ["Flabra"] = "Flabra", ["Tellus"] = "Tellus",
            ["Sulpor"] = "Sulpor", ["Unda"] = "Unda", ["Lux"] = "Lux", ["Tenebrae"] = "Tenebrae",
        };
        for (var i = 0; i < runes.Count; i++)
        {
            var raw = (runes[i]?.ToString() ?? string.Empty).Trim();
            if (!canonicalRunes.TryGetValue(raw, out var canonical))
            {
                throw new InvalidDataException($"RUN rune '{raw}' is not a Rune Enchantment.");
            }
            runes[i] = canonical;
        }
        if (runes.Count != 0 && runes.Count != 3)
        {
            throw new InvalidDataException("RUN rune list must be empty or contain exactly three runes.");
        }
        var vallation = ReadBool(flatProfile, "run_tank_vallation", false);
        var valiance = ReadBool(flatProfile, "run_tank_valiance", false);
        if (vallation && valiance)
        {
            throw new InvalidDataException("RUN automation cannot enable both Vallation and Valiance.");
        }
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "run_tank_enabled", false))
            .Add("no_tp_mode", ReadBool(flatProfile, "run_tank_no_tp_mode", false))
            .Add("runes", new StructuredProfileNode()
                .Add("maintain", ReadBool(flatProfile, "run_tank_runes_maintain", true))
                .Add("desired", runes))
            .Add("foil", new StructuredProfileNode().Add("enabled", ReadBool(flatProfile, "run_tank_foil", true)))
            .Add("wards", new StructuredProfileNode()
                .Add("vallation", vallation)
                .Add("valiance", valiance)
                .Add("pflug", ReadBool(flatProfile, "run_tank_pflug", false))
                .Add("swordplay", ReadBool(flatProfile, "run_tank_swordplay", false))
                .Add("battuta", ReadBool(flatProfile, "run_tank_battuta", false))
                .Add("one_for_all", ReadBool(flatProfile, "run_tank_one_for_all", false)))
            .Add("magic_support", new StructuredProfileNode()
                .Add("gambit", ReadBool(flatProfile, "run_tank_gambit", false))
                .Add("rayke", ReadBool(flatProfile, "run_tank_rayke", false)));
    }

    private static StructuredProfileNode BuildSleep(JsonObject flatProfile)
    {
        var order = ParseNameList(ReadString(flatProfile, "sleep_spell_entries", ""));
        var legacyPrimary = order.Count > 0 ? order[0]?.ToString() ?? "" : "";
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "sleep", false))
            .Add("order", order)
            .Add("legacy_primary", legacyPrimary)
            .Add("max_target_range", Math.Clamp(ReadDouble(flatProfile, "sleep_max_target_range", 6.0), 0.1, 50.0));
    }

    private static StructuredProfileNode BuildSpells(JsonObject flatProfile)
    {
        var mode = ReadString(flatProfile, "magic_burst_mode", "exact").Trim().ToLowerInvariant();
        var family = ReadString(flatProfile, "magic_burst_family", "spell").Trim().ToLowerInvariant();
        if (mode is not ("exact" or "auto"))
        {
            throw new InvalidDataException($"magic_burst_mode must be exact or auto: {mode}");
        }
        if (family is not ("spell" or "ra" or "helix"))
        {
            throw new InvalidDataException($"magic_burst_family must be spell, ra, or helix: {family}");
        }
        var maxTier = ReadBoundedInt(flatProfile, "magic_burst_max_tier", 0, 0, 5);
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "spell_active", false))
            .Add("configured", ReadString(flatProfile, "spell", ""))
            .Add("magic_burst", ReadBool(flatProfile, "magic_burst_enabled", false))
            .Add("magic_burst_mode", mode)
            .Add("magic_burst_family", family)
            .Add("magic_burst_max_tier", maxTier)
            .Add("dd2_slots", EmptyList());
    }

    private static bool HasConfiguredCorMaintenance(JsonObject flatProfile)
    {
        return ReadString(flatProfile, "cor_roll_1", "") != ""
            || ReadString(flatProfile, "cor_roll_2", "") != ""
            || ReadInt(flatProfile, "cor_crooked_roll_slot", 0) != 0
            || ReadBool(flatProfile, "cor_elevens", false)
            || ReadBool(flatProfile, "cor_luzaf_range_override", false)
            || ReadString(flatProfile, "cor_roll_range_selected", "") != "";
    }

    private static StructuredProfileNode BuildMaintenance(JsonObject flatProfile, StructuredProfileV2Identity identity)
    {
        var maintenance = new StructuredProfileNode()
            .Add("enabled", ReadRequiredBool(flatProfile, "domain_maintenance_enabled"));

        var isCorProfile = string.Equals(SafeJobComponent(identity.MainJob), "COR", StringComparison.Ordinal);
        if (isCorProfile || HasConfiguredCorMaintenance(flatProfile))
        {
            maintenance.Add(
                "cor",
                new StructuredProfileNode()
                    .Add("roll_1", ReadString(flatProfile, "cor_roll_1", ""))
                    .Add("roll_2", ReadString(flatProfile, "cor_roll_2", ""))
                    .Add("crooked_roll_slot", ReadInt(flatProfile, "cor_crooked_roll_slot", 0))
                    .Add("elevens", ReadBool(flatProfile, "cor_elevens", false))
                    .Add("luzaf_range_override", ReadBool(flatProfile, "cor_luzaf_range_override", false))
                    .Add("light_shot_dia", ReadBool(flatProfile, "cor_light_shot_dia", true))
                    .Add("range_selected", ReadString(flatProfile, "cor_roll_range_selected", ""))
                    .Add("range_require_ids", EmptyList())
            );
        }

        var isBrdProfile = string.Equals(SafeJobComponent(identity.MainJob), "BRD", StringComparison.Ordinal)
            || string.Equals(SafeJobComponent(identity.SubJob), "BRD", StringComparison.Ordinal);
        if (isBrdProfile)
        {
            var useNitro = ReadBool(flatProfile, "brd_use_nitro", false);
            var useSoulVoice = ReadBool(flatProfile, "brd_use_soul_voice", false);
            var targetedSongs = ParseBardTargetedSongs(ReadString(flatProfile, "brd_targeted_songs", ""));
            ValidateBardTargetedSongNames(
                targetedSongs,
                SplitPipeList(ReadString(flatProfile, "brd_song_options", ""))
                    .Select(value => value?.ToString() ?? "")
                    .Where(value => value.Length > 0)
                    .ToList()
            );
            if (useSoulVoice && !useNitro)
            {
                throw new InvalidDataException("BRD Soul Voice requires NITRO.");
            }
            maintenance.Add(
                "brd",
                new StructuredProfileNode()
                    .Add("enabled", ReadBool(flatProfile, "brd_maintenance_enabled", false))
                    .Add("songs", SplitPipeList(ReadString(flatProfile, "brd_songs", "")))
                    .Add("dummy_songs", SplitPipeList(ReadString(flatProfile, "brd_dummy_songs", "")))
                    .Add("use_nitro", useNitro)
                    .Add("use_soul_voice", useSoulVoice)
                    .Add("use_clarion_call", ReadBool(flatProfile, "brd_use_clarion_call", false))
                    .Add("use_marcato", ReadBool(flatProfile, "brd_use_marcato", false))
                    .Add("marcato_song", ReadString(flatProfile, "brd_marcato_song", ""))
                    .Add("targeted_songs", BuildBardTargetedSongs(targetedSongs))
                    .Add("recovery_range_yalms", ReadBoundedDouble(flatProfile, "brd_recovery_range_yalms", 9.9, 1.0, 20.0))
                    .Add("reposition_for_party_songs", ReadBool(flatProfile, "brd_reposition_for_party_songs", false))
                    .Add("recovery_ignore_names", SplitPipeList(ReadString(flatProfile, "brd_recovery_ignore_names", "")))
            );
        }

        var foodEnabled = ReadBool(flatProfile, "food_enabled", false);
        var foodItem = ReadString(flatProfile, "food_item", "").Trim();
        if (foodEnabled && foodItem.Length == 0)
        {
            throw new InvalidDataException("Enabled food maintenance requires a food item name.");
        }
        maintenance.Add(
            "food",
            new StructuredProfileNode()
                .Add("enabled", foodEnabled)
                .Add("item", foodItem)
        );

        maintenance.Add("geo", BuildGeoMaintenance(flatProfile));

        return maintenance;
    }

    private static StructuredProfileNode BuildGeoMaintenance(JsonObject flatProfile)
    {
        var enabled = ReadOptionalBool(flatProfile, "geo_maintenance_enabled", false);
        var geoSpell = ReadString(flatProfile, "geo_spell", "");
        var indiSpell = ReadString(flatProfile, "indi_spell", "");
        var targetKind = ReadString(flatProfile, "geo_target_kind", "current_enemy");
        var targetName = ReadString(flatProfile, "geo_target_name", "");
        var ordering = ReadString(flatProfile, "geo_ordering", "geo_first");
        var placement = ReadString(flatProfile, "geo_luopan_placement", "target");
        var requireCamp = ReadOptionalBool(flatProfile, "geo_require_camp", true);
        var entrustEnabled = ReadOptionalBool(flatProfile, "geo_entrust_enabled", false);
        var entrustSpell = ReadString(flatProfile, "geo_entrust_spell", "");
        var entrustTarget = ReadString(flatProfile, "geo_entrust_target_name", "");
        if (enabled && (!geoSpell.StartsWith("Geo-", StringComparison.Ordinal)
            || !indiSpell.StartsWith("Indi-", StringComparison.Ordinal)))
        {
            throw new InvalidDataException("Enabled GEO maintenance requires exact Geo- and Indi- spell names.");
        }
        if (targetKind is not ("current_enemy" or "self" or "party_member"))
        {
            throw new InvalidDataException("GEO target kind must be current_enemy, self, or party_member.");
        }
        if (ordering is not ("geo_first" or "indi_first"))
        {
            throw new InvalidDataException("GEO ordering must be geo_first or indi_first.");
        }
        if (placement is not ("target" or "camp"))
        {
            throw new InvalidDataException("Luopan placement must be target or camp.");
        }
        if (targetKind == "party_member" && targetName.Length == 0)
        {
            throw new InvalidDataException("GEO party-member targeting requires a target name.");
        }
        if (entrustEnabled && (!entrustSpell.StartsWith("Indi-", StringComparison.Ordinal)
            || entrustTarget.Length == 0))
        {
            throw new InvalidDataException("Enabled Entrust requires an Indi- spell and target name.");
        }
        return new StructuredProfileNode()
            .Add("enabled", enabled)
            .Add("geo_spell", NullIfEmpty(geoSpell))
            .Add(
                "geo_target",
                new StructuredProfileNode()
                    .Add("kind", targetKind)
                    .Add("name", targetKind == "party_member" ? targetName : null)
            )
            .Add("indi_spell", NullIfEmpty(indiSpell))
            .Add("ordering", ordering)
            .Add("require_camp", requireCamp)
            .Add("camp_tolerance_yalms", ReadBoundedDouble(flatProfile, "geo_camp_tolerance_yalms", 1.0, 0.0, 50.0))
            .Add("enemy_geo_requires_camp_radius", ReadOptionalBool(flatProfile, "geo_enemy_requires_camp_radius", false))
            .Add("unknown_existing_policy", "wait_for_clear")
            .Add(
                "entrust",
                new StructuredProfileNode()
                    .Add("enabled", entrustEnabled)
                    .Add("spell", NullIfEmpty(entrustSpell))
                    .Add("target_name", NullIfEmpty(entrustTarget))
            )
            .Add(
                "luopan",
                new StructuredProfileNode()
                    .Add("placement", placement)
                    .Add("use_blaze_of_glory", ReadOptionalBool(flatProfile, "geo_use_blaze_of_glory", false))
                    .Add("use_ecliptic_attrition", ReadOptionalBool(flatProfile, "geo_use_ecliptic_attrition", false))
                    .Add("use_life_cycle", ReadOptionalBool(flatProfile, "geo_use_life_cycle", false))
                    .Add("life_cycle_hpp", ReadBoundedInt(flatProfile, "geo_life_cycle_hpp", 50, 1, 99))
                    .Add("replace_out_of_position", ReadOptionalBool(flatProfile, "geo_replace_out_of_position", false))
                    .Add("max_camp_distance_yalms", ReadBoundedDouble(flatProfile, "geo_max_camp_distance_yalms", 6.0, 0.1, 50.0))
            );
    }

    private static bool HasConfiguredSummoner(JsonObject flatProfile)
    {
        return ReadBool(flatProfile, "summoner_enabled", false)
            || ReadString(flatProfile, "summoner_avatar", "") != ""
            || ReadBool(flatProfile, "summoner_avatar_favor", false)
            || ReadBool(flatProfile, "summoner_ward_enabled", false)
            || ReadString(flatProfile, "summoner_ward_action", "") != ""
            || ReadString(flatProfile, "summoner_ward_actions", "") != ""
            || ReadBool(flatProfile, "summoner_engage_on_combat_start", false)
            || ReadBool(flatProfile, "summoner_rage_enabled", false)
            || ReadOptionalBool(flatProfile, "summoner_rage_target_hpp_above_enabled", false)
            || ReadOptionalBool(flatProfile, "summoner_rage_pet_tp_above_enabled", false)
            || ReadString(flatProfile, "summoner_rage_action", "") != "";
    }

    private static StructuredProfileNode? BuildSummoner(
        JsonObject flatProfile,
        StructuredProfileV2Identity identity
    )
    {
        var isSummonerProfile = string.Equals(
            SafeJobComponent(identity.MainJob),
            "SMN",
            StringComparison.Ordinal
        );
        if (!isSummonerProfile && !HasConfiguredSummoner(flatProfile))
        {
            return null;
        }
        var wardActionsText = ReadString(flatProfile, "summoner_ward_actions", "");
        var legacyWardAction = ReadString(flatProfile, "summoner_ward_action", "");
        if (wardActionsText.Length == 0 && legacyWardAction.Length != 0)
        {
            wardActionsText = legacyWardAction;
        }
        var wardActions = SplitPipeList(wardActionsText);
        if (legacyWardAction.Length != 0
            && wardActions.Count > 0
            && !string.Equals(wardActions[0]?.ToString(), legacyWardAction, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                "summoner_ward_action must match the first summoner_ward_actions entry."
            );
        }

        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "summoner_enabled", false))
            .Add("avatar", NullIfEmpty(ReadString(flatProfile, "summoner_avatar", "")))
            .Add(
                "maintenance",
                new StructuredProfileNode()
                    .Add("avatar_favor", ReadBool(flatProfile, "summoner_avatar_favor", false))
                    .Add(
                        "ward",
                        new StructuredProfileNode()
                            .Add("enabled", ReadBool(flatProfile, "summoner_ward_enabled", false))
                            .Add("actions", wardActions)
                    )
            )
            .Add(
                "pet_combat",
                new StructuredProfileNode()
                    .Add(
                        "engage_on_combat_start",
                        ReadBool(flatProfile, "summoner_engage_on_combat_start", false)
                    )
                    .Add(
                        "offensive_action",
                        new StructuredProfileNode()
                            .Add("enabled", ReadBool(flatProfile, "summoner_rage_enabled", false))
                            .Add("action", NullIfEmpty(ReadString(flatProfile, "summoner_rage_action", "")))
                            .Add("usage", ReadString(flatProfile, "summoner_rage_usage", "on_cooldown"))
                            .Add(
                                "target_hpp_above_enabled",
                                ReadOptionalBool(flatProfile, "summoner_rage_target_hpp_above_enabled", false)
                            )
                            .Add(
                                "target_hpp_above",
                                ReadBoundedInt(flatProfile, "summoner_rage_target_hpp_above", 50, 0, 99)
                            )
                            .Add(
                                "pet_tp_above_enabled",
                                ReadOptionalBool(flatProfile, "summoner_rage_pet_tp_above_enabled", false)
                            )
                            .Add(
                                "pet_tp_above",
                                ReadBoundedInt(flatProfile, "summoner_rage_pet_tp_above", 2000, 0, 2999)
                            )
                    )
            );
    }

    private static readonly HashSet<string> PuppetmasterManeuverNames = new(StringComparer.Ordinal)
    {
        "Fire Maneuver",
        "Ice Maneuver",
        "Wind Maneuver",
        "Earth Maneuver",
        "Thunder Maneuver",
        "Water Maneuver",
        "Light Maneuver",
        "Dark Maneuver",
    };

    private static StructuredProfileNode? BuildPuppetmaster(
        JsonObject flatProfile,
        StructuredProfileV2Identity identity
    )
    {
        var isPuppetmasterProfile = string.Equals(
            SafeJobComponent(identity.MainJob),
            "PUP",
            StringComparison.Ordinal
        );
        var enabled = ReadOptionalBool(flatProfile, "puppetmaster_enabled", false);
        if (!isPuppetmasterProfile)
        {
            if (enabled)
            {
                throw new InvalidDataException("Puppetmaster automation configuration requires main job PUP.");
            }
            return null;
        }

        var pattern = SplitPipeList(
            ReadString(flatProfile, "puppetmaster_maneuver_pattern", "Fire Maneuver|Fire Maneuver|Light Maneuver")
        );
        if (pattern.Count is < 1 or > 3)
        {
            throw new InvalidDataException("Puppetmaster maneuver pattern must contain one to three maneuvers.");
        }
        foreach (var entry in pattern)
        {
            var name = entry?.ToString() ?? "";
            if (!PuppetmasterManeuverNames.Contains(name))
            {
                throw new InvalidDataException($"Unsupported Puppetmaster maneuver: {name}");
            }
        }

        return new StructuredProfileNode()
            .Add("enabled", enabled)
            .Add("activate_if_missing", ReadOptionalBool(flatProfile, "puppetmaster_activate_if_missing", true))
            .Add("deploy_on_combat_start", ReadOptionalBool(flatProfile, "puppetmaster_deploy_on_combat_start", true))
            .Add(
                "maneuvers",
                new StructuredProfileNode()
                    .Add("enabled", ReadOptionalBool(flatProfile, "puppetmaster_maneuvers_enabled", true))
                    .Add("pattern", pattern)
                    .Add(
                        "post_activate_quiet_seconds",
                        ReadBoundedInt(flatProfile, "puppetmaster_post_activate_quiet_seconds", 120, 0, 300)
                    )
                    .Add(
                        "safe_burden_ceiling",
                        ReadBoundedInt(flatProfile, "puppetmaster_safe_burden_ceiling", 30, 0, 32)
                    )
            );
    }

    private static readonly HashSet<string> ScholarSkillchainResults = new(StringComparer.Ordinal)
    {
        "Fusion",
        "Fragmentation",
        "Distortion",
        "Gravitation",
    };

    private static readonly IReadOnlyDictionary<string, HashSet<string>> ScholarSkillchainClosers =
        new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        {
            ["Fusion"] = new(StringComparer.Ordinal) { "Thunder", "Thunder II", "Thunder III", "Thunder IV", "Thunder V", "Ionohelix", "Ionohelix II" },
            ["Fragmentation"] = new(StringComparer.Ordinal) { "Water", "Water II", "Water III", "Water IV", "Water V", "Hydrohelix", "Hydrohelix II" },
            ["Distortion"] = new(StringComparer.Ordinal) { "Stone", "Stone II", "Stone III", "Stone IV", "Stone V", "Geohelix", "Geohelix II" },
            ["Gravitation"] = new(StringComparer.Ordinal) { "Noctohelix", "Noctohelix II" },
        };

    private static string DefaultScholarSkillchainCloser(string result)
    {
        return result switch
        {
            "Fragmentation" => "Water V",
            "Distortion" => "Stone V",
            "Gravitation" => "Noctohelix II",
            _ => "Thunder V",
        };
    }

    private static bool HasConfiguredScholar(JsonObject flatProfile)
    {
        return ReadOptionalBool(flatProfile, "sch_enabled", false)
            || ReadOptionalBool(flatProfile, "sch_skillchain_enabled", false);
    }

    private static StructuredProfileNode? BuildScholar(
        JsonObject flatProfile,
        StructuredProfileV2Identity identity
    )
    {
        var isScholarProfile = string.Equals(
            SafeJobComponent(identity.MainJob),
            "SCH",
            StringComparison.Ordinal
        );
        if (!isScholarProfile)
        {
            if (HasConfiguredScholar(flatProfile))
            {
                throw new InvalidDataException("Scholar automation configuration requires main job SCH.");
            }
            return null;
        }

        var sublimationRelease = ReadBoundedInt(
            flatProfile,
            "sch_sublimation_release_when_mpp_at_most",
            45,
            0,
            100
        );
        var skillchainEnabled = ReadOptionalBool(flatProfile, "sch_skillchain_enabled", false);
        var skillchainResult = ReadString(flatProfile, "sch_skillchain_result", "Fusion");
        if (!ScholarSkillchainResults.Contains(skillchainResult))
        {
            throw new InvalidDataException($"Unsupported Scholar skillchain result: {skillchainResult}");
        }
        var skillchainCloser = ReadString(
            flatProfile,
            "sch_skillchain_closer",
            DefaultScholarSkillchainCloser(skillchainResult)
        );
        if (!ScholarSkillchainClosers[skillchainResult].Contains(skillchainCloser))
        {
            throw new InvalidDataException(
                $"Unsupported Scholar {skillchainResult} closer: {skillchainCloser}"
            );
        }
        var skillchainPlans = new List<object?>
        {
            new StructuredProfileNode()
                .Add("result", skillchainResult)
                .Add("closer", skillchainCloser),
        };

        return new StructuredProfileNode()
            .Add("enabled", ReadOptionalBool(flatProfile, "sch_enabled", false))
            .Add("mode", "support")
            .Add(
                "arts",
                new StructuredProfileNode()
                    .Add("default", "light")
                    .Add(
                        "minimum_commit_s",
                        ReadBoundedInt(flatProfile, "sch_arts_minimum_commit_s", 12, 0, 120)
                    )
                    .Add(
                        "emergency_off_art_casts",
                        ReadOptionalBool(flatProfile, "sch_arts_emergency_off_art_casts", true)
                    )
            )
            .Add(
                "sublimation",
                new StructuredProfileNode()
                    .Add("enabled", ReadOptionalBool(flatProfile, "sch_sublimation_enabled", false))
                    .Add("release_when_mpp_at_most", sublimationRelease)
                    .Add(
                        "release_when_complete",
                        ReadOptionalBool(flatProfile, "sch_sublimation_release_when_complete", false)
                    )
                    .Add(
                        "minimum_hpp_to_activate",
                        ReadBoundedInt(
                            flatProfile,
                            "sch_sublimation_minimum_hpp_to_activate",
                            75,
                            1,
                            100
                        )
                    )
            )
            .Add(
                "support",
                new StructuredProfileNode()
                    .Add(
                        "regen",
                        new StructuredProfileNode()
                            .Add("enabled", ReadOptionalBool(flatProfile, "sch_regen_enabled", false))
                            .Add(
                                "spells",
                                ParseScholarAccessionMaintenanceSpells(
                                    ReadString(
                                        flatProfile,
                                        "sch_accession_perpetuance_spells",
                                        "Regen V"
                                    )
                                ).Cast<object?>().ToList()
                            )
                            .Add("recipients", new List<object?> { "party" })
                            .Add("stratagems", new List<object?> { "Accession", "Perpetuance" })
                            .Add(
                                "minimum_coverage",
                                ReadBoundedInt(flatProfile, "sch_regen_minimum_coverage", 4, 1, 6)
                            )
                            .Add(
                                "refresh_before_s",
                                ReadBoundedInt(flatProfile, "sch_regen_refresh_before_s", 25, 1, 300)
                            )
                            .Add("unknown_existing_policy", "wait_for_clear")
                    )
                    .Add(
                        "storms",
                        new StructuredProfileNode()
                            .Add("enabled", ReadOptionalBool(flatProfile, "sch_storms_enabled", false))
                            .Add(
                                "assignments",
                                BuildScholarStormAssignments(
                                    ReadString(flatProfile, "sch_storm_assignments", "")
                                )
                            )
                            .Add(
                                "refresh_before_s",
                                ReadBoundedInt(flatProfile, "sch_storms_refresh_before_s", 30, 1, 300)
                            )
                            .Add("unknown_existing_policy", "wait_for_clear")
                    )
                    .Add(
                        "embrava",
                        new StructuredProfileNode()
                            .Add("enabled", false)
                            .Add("manual_arm_required", true)
                    )
            )
            .Add(
                "defensive",
                new StructuredProfileNode()
                    .Add(
                        "accession_cure",
                        new StructuredProfileNode()
                            .Add(
                                "enabled",
                                ReadOptionalBool(flatProfile, "sch_accession_cure_enabled", false)
                            )
                            .Add("minimum_members", 3)
                            .Add("member_hpp_at_most", 75)
                            .Add("minimum_total_missing_hp", 2500)
                    )
                    .Add(
                        "accession_status_removal",
                        new StructuredProfileNode()
                            .Add(
                                "enabled",
                                ReadOptionalBool(
                                    flatProfile,
                                    "sch_accession_status_removal_enabled",
                                    false
                                )
                            )
                            .Add("minimum_members", 2)
                    )
                    .Add(
                        "rapture",
                        new StructuredProfileNode()
                            .Add(
                                "enabled",
                                ReadOptionalBool(flatProfile, "sch_rapture_enabled", false)
                            )
                            .Add("minimum_missing_hp", 1800)
                    )
                    .Add(
                        "penury",
                        new StructuredProfileNode()
                            .Add(
                                "enabled",
                                ReadOptionalBool(flatProfile, "sch_penury_enabled", false)
                            )
                            .Add("maximum_mpp", 45)
                    )
            )
            .Add(
                "offense",
                new StructuredProfileNode()
                    .Add(
                        "magic_burst",
                        new StructuredProfileNode()
                            .Add("enabled", false)
                            .Add("minimum_mpp", 35)
                            .Add("minimum_target_hpp", 10)
                            .Add("spells", EmptyList())
                    )
                    .Add(
                        "skillchain",
                        new StructuredProfileNode()
                            .Add("enabled", skillchainEnabled)
                            .Add("allow_party_close", false)
                            .Add("plans", skillchainPlans)
                    )
            );
    }

    internal static List<ScholarStormAssignment> ParseScholarStormAssignments(string value)
    {
        var assignments = new List<ScholarStormAssignment>();
        var assignedTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawEntry in value.Split('|', StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = rawEntry.Trim();
            var separatorIndex = entry.IndexOf(':');
            if (separatorIndex <= 0 || separatorIndex >= entry.Length - 1)
            {
                throw new InvalidDataException(
                    $"Scholar storm assignment must be Spell:Target,Target: {entry}"
                );
            }
            var spell = entry[..separatorIndex].Trim();
            if (!ScholarCapabilities.StormNames.Contains(spell, StringComparer.Ordinal))
            {
                throw new InvalidDataException($"Unsupported Scholar storm spell: {spell}");
            }
            var targets = entry[(separatorIndex + 1)..]
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (targets.Length == 0)
            {
                throw new InvalidDataException($"Scholar storm assignment requires a target: {entry}");
            }
            if (targets.Distinct(StringComparer.OrdinalIgnoreCase).Count() != targets.Length)
            {
                throw new InvalidDataException($"Scholar storm assignment repeats a target: {entry}");
            }
            foreach (var target in targets)
            {
                if (!assignedTargets.Add(target))
                {
                    throw new InvalidDataException(
                        $"Scholar storm target appears more than once: {target}"
                    );
                }
            }
            assignments.Add(new ScholarStormAssignment(spell, targets));
        }
        if (!string.IsNullOrWhiteSpace(value) && assignments.Count == 0)
        {
            throw new InvalidDataException("Scholar storm assignments contain no valid entries.");
        }
        return assignments;
    }

    internal static List<string> ParseScholarAccessionMaintenanceSpells(string value)
    {
        var spells = value
            .Split(['|', '\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToList();
        if (spells.Count == 0)
        {
            throw new InvalidDataException(
                "Scholar Accession + Perpetuance maintenance requires at least one spell."
            );
        }
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var exclusiveGroups = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var spell in spells)
        {
            if (!ScholarCapabilities.AccessionMaintenanceSpellNames.Contains(spell, StringComparer.Ordinal))
            {
                throw new InvalidDataException(
                    $"Unsupported Scholar Accession + Perpetuance maintenance spell: {spell}"
                );
            }
            if (!seen.Add(spell))
            {
                throw new InvalidDataException(
                    $"Scholar Accession + Perpetuance maintenance repeats spell: {spell}"
                );
            }
            if (ScholarCapabilities.AccessionExclusiveGroups.TryGetValue(spell, out var group))
            {
                if (exclusiveGroups.TryGetValue(group, out var previous))
                {
                    throw new InvalidDataException(
                        $"Scholar maintenance spells {previous} and {spell} conflict; only one {group} spell may be selected."
                    );
                }
                exclusiveGroups[group] = spell;
            }
        }
        return spells;
    }

    private static List<object?> BuildScholarStormAssignments(string value)
    {
        var list = new List<object?>();
        foreach (var assignment in ParseScholarStormAssignments(value))
        {
            list.Add(
                new StructuredProfileNode()
                    .Add("spell", assignment.Spell)
                    .Add("targets", assignment.Targets.Cast<object?>().ToList())
            );
        }
        return list;
    }

    private static StructuredProfileNode BuildDebug(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("enabled", ReadBool(flatProfile, "debug", false))
            .Add("action_timeline", ReadBool(flatProfile, "log_action_timeline", false))
            .Add("combat_sched", ReadBool(flatProfile, "log_combat_sched", false))
            .Add("ja_sched", ReadBool(flatProfile, "log_ja_sched", false))
            .Add("ja_debug", ReadBool(flatProfile, "log_ja_debug", false))
            .Add("def_sched", ReadBool(flatProfile, "log_def_sched", false))
            .Add("tank_sched", ReadBool(flatProfile, "log_tank_sched", false));
    }

    private static StructuredProfileNode BuildOwnership(JsonObject flatProfile)
    {
        return new StructuredProfileNode()
            .Add("domain_combat_enabled", ReadRequiredBool(flatProfile, "domain_combat_enabled"))
            .Add("domain_defensive_enabled", ReadRequiredBool(flatProfile, "domain_defensive_enabled"))
            .Add("domain_movement_enabled", ReadRequiredBool(flatProfile, "domain_movement_enabled"))
            .Add("domain_maintenance_enabled", ReadRequiredBool(flatProfile, "domain_maintenance_enabled"))
            .Add("domain_follow_enabled", ReadRequiredBool(flatProfile, "domain_follow_enabled"))
            .Add("pause_automation_while_weakened", ReadBool(flatProfile, "pause_automation_while_weakened", false));
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

    private static bool ReadRequiredBool(JsonObject flatProfile, string key)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            throw new InvalidDataException($"required boolean profile field is missing: {key}");
        }
        if (node is JsonValue value && value.TryGetValue<bool>(out var boolValue))
        {
            return boolValue;
        }

        throw new InvalidDataException($"required boolean profile field is invalid: {key}");
    }

    private static bool ReadOptionalBool(JsonObject flatProfile, string key, bool defaultValue)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }
        if (node is JsonValue value && value.TryGetValue<bool>(out var boolValue))
        {
            return boolValue;
        }
        throw new InvalidDataException($"optional boolean profile field is invalid: {key}");
    }

    private static int ReadInt(JsonObject flatProfile, string key, int defaultValue)
    {
        var number = ReadDouble(flatProfile, key, defaultValue);
        return (int)Math.Round(number, MidpointRounding.AwayFromZero);
    }

    private static int ReadBoundedInt(
        JsonObject flatProfile,
        string key,
        int defaultValue,
        int minimum,
        int maximum
    )
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }
        if (node is not JsonValue value || !value.TryGetValue<int>(out var number))
        {
            throw new InvalidDataException($"setting {key} must be an integer");
        }
        if (number < minimum || number > maximum)
        {
            throw new InvalidDataException($"setting {key} is outside {minimum}..{maximum}: {number}");
        }
        return number;
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
            if (value.TryGetValue<int>(out var intValue))
            {
                return intValue;
            }
            if (value.TryGetValue<long>(out var longValue))
            {
                return longValue;
            }
            if (value.TryGetValue<string>(out var text) && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
            {
                return parsed;
            }
            if (double.TryParse(value.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedText))
            {
                return parsedText;
            }
        }

        return defaultValue;
    }

    private static double ReadFormationNumber(JsonObject flatProfile, string key, double defaultValue, double minimum, double maximum)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }
        var raw = ReadString(flatProfile, key, "");
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            throw new InvalidDataException($"formation setting {key} is not numeric: {raw}");
        }
        if (value < minimum || value > maximum)
        {
            throw new InvalidDataException($"formation setting {key} is outside {minimum}..{maximum}: {value}");
        }
        return value;
    }

    private static double ReadRequiredFormationNumber(JsonObject flatProfile, string key, double minimum, double maximum)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            throw new InvalidDataException($"required formation setting is missing: {key}");
        }
        return ReadFormationNumber(flatProfile, key, 0, minimum, maximum);
    }

    private static double ReadBoundedDouble(JsonObject flatProfile, string key, double defaultValue, double minimum, double maximum)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }
        var raw = ReadString(flatProfile, key, "");
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            throw new InvalidDataException($"setting {key} is not numeric: {raw}");
        }
        if (value < minimum || value > maximum)
        {
            throw new InvalidDataException($"setting {key} is outside {minimum}..{maximum}: {value}");
        }
        return value;
    }

    private static bool ReadFormationBool(JsonObject flatProfile, string key, bool defaultValue)
    {
        if (!flatProfile.TryGetPropertyValue(key, out var node) || node is null)
        {
            return defaultValue;
        }
        if (node is JsonValue value && value.TryGetValue<bool>(out var boolValue))
        {
            return boolValue;
        }
        if (node is JsonValue textValue && textValue.TryGetValue<string>(out var text))
        {
            return (text ?? "").Trim().ToLowerInvariant() switch
            {
                "true" or "on" or "1" or "yes" => true,
                "false" or "off" or "0" or "no" => false,
                _ => throw new InvalidDataException($"formation setting {key} is not boolean: {text}"),
            };
        }
        if (node is JsonValue numericValue && numericValue.TryGetValue<long>(out var numeric) && (numeric == 0 || numeric == 1))
        {
            return numeric == 1;
        }
        throw new InvalidDataException($"formation setting {key} is not boolean: {node}");
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

    private static string StripTrailingDisplayIndex(string value)
    {
        return TrailingDisplayIndex.Replace(value, "").Trim();
    }

    private static List<object?> ParseNameList(string value)
    {
        var parts = value.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var list = new List<object?>(parts.Length);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawPart in parts)
        {
            var entry = rawPart.Trim();
            if (entry.Length == 0)
            {
                continue;
            }

            var separatorIndex = entry.IndexOf(':');
            var name = separatorIndex >= 0 ? entry[(separatorIndex + 1)..] : entry;
            name = StripTrailingDisplayIndex(name);
            if (name.Length == 0)
            {
                continue;
            }

            if (seen.Add(name))
            {
                list.Add(name);
            }
        }

        return list;
    }

    internal static List<object?> ParseCampPullTargets(string value)
    {
        var list = new List<object?>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawPart in value.Split('|', StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = rawPart.Trim();
            var separator = entry.LastIndexOf(':');
            if (separator <= 0 || separator >= entry.Length - 1)
            {
                throw new InvalidDataException($"Camp pull target '{entry}' must use Name:priority.");
            }
            var name = entry[..separator].Trim();
            if (!int.TryParse(entry[(separator + 1)..].Trim(), out var priority)
                || priority < -1000
                || priority > 1000)
            {
                throw new InvalidDataException($"Camp pull target '{entry}' has an invalid priority.");
            }
            if (name.Length == 0 || !seen.Add(name))
            {
                throw new InvalidDataException($"Camp pull target '{entry}' is empty or duplicated.");
            }
            list.Add(new StructuredProfileNode()
                .Add("name", name)
                .Add("priority", priority));
        }
        return list;
    }

    internal static List<TargetedBuffEntry> ParseTargetedBuffs(string value)
    {
        var list = new List<TargetedBuffEntry>();
        var parts = value.Split('|', StringSplitOptions.RemoveEmptyEntries);
        foreach (var rawPart in parts)
        {
            var entry = rawPart.Trim();
            if (entry.Length == 0)
            {
                continue;
            }

            var separatorIndex = entry.IndexOf(':');
            if (separatorIndex <= 0 || separatorIndex >= entry.Length - 1)
            {
                continue;
            }

            var character = entry[..separatorIndex].Trim();
            var buff = entry[(separatorIndex + 1)..].Trim();
            if (character.Length == 0 || buff.Length == 0)
            {
                continue;
            }

            list.Add(new TargetedBuffEntry(character, buff));
        }

        return list;
    }

    internal static List<BardTargetedSongSet> ParseBardTargetedSongs(string value)
    {
        var sets = new List<BardTargetedSongSet>();
        var assignedRecipients = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawEntry in value.Split('|', StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = rawEntry.Trim();
            var separatorIndex = entry.IndexOf(':');
            if (separatorIndex <= 0 || separatorIndex >= entry.Length - 1)
            {
                throw new InvalidDataException($"BRD targeted song entry must be Recipients:PrioritySongs: {entry}");
            }
            var recipients = entry[..separatorIndex]
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .ToArray();
            var songs = entry[(separatorIndex + 1)..]
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .ToArray();
            if (recipients.Length == 0 || songs.Length == 0)
            {
                throw new InvalidDataException($"BRD targeted song entry requires recipients and songs: {entry}");
            }
            if (recipients.Distinct(StringComparer.OrdinalIgnoreCase).Count() != recipients.Length)
            {
                throw new InvalidDataException($"BRD targeted song entry repeats a recipient: {entry}");
            }
            if (songs.Distinct(StringComparer.Ordinal).Count() != songs.Length)
            {
                throw new InvalidDataException($"BRD targeted song entry repeats a song: {entry}");
            }
            foreach (var recipient in recipients)
            {
                if (!assignedRecipients.Add(recipient))
                {
                    throw new InvalidDataException($"BRD targeted song recipient appears more than once: {recipient}");
                }
            }
            sets.Add(new BardTargetedSongSet(recipients, songs));
        }
        if (!string.IsNullOrWhiteSpace(value) && sets.Count == 0)
        {
            throw new InvalidDataException("BRD targeted songs contain no valid recipient/song entries.");
        }
        return sets;
    }

    private static void ValidateBardTargetedSongNames(
        IReadOnlyList<BardTargetedSongSet> targetedSongs,
        IReadOnlyList<string> availableSongs
    )
    {
        if (targetedSongs.Count == 0)
        {
            return;
        }
        if (availableSongs.Count == 0)
        {
            throw new InvalidDataException(
                "BRD targeted songs require hydrated BRD song options. Refresh the BRD session before saving."
            );
        }
        var available = new HashSet<string>(availableSongs, StringComparer.Ordinal);
        foreach (var set in targetedSongs)
        {
            foreach (var song in set.PrioritySongs)
            {
                if (!available.Contains(song))
                {
                    throw new InvalidDataException($"BRD targeted song is unavailable or invalid: {song}");
                }
            }
        }
    }

    private static List<object?> BuildBardTargetedSongs(IReadOnlyList<BardTargetedSongSet> sets)
    {
        var list = new List<object?>();
        foreach (var set in sets)
        {
            list.Add(new StructuredProfileNode()
                .Add("recipients", set.Recipients.Cast<object?>().ToList())
                .Add("priority_songs", set.PrioritySongs.Cast<object?>().ToList()));
        }
        return list;
    }

    private static List<object?> BuildTargetedBuffs(string value)
    {
        var entries = ParseTargetedBuffs(value);
        var list = new List<object?>(entries.Count);
        foreach (var entry in entries)
        {
            list.Add(
                new StructuredProfileNode()
                    .Add("character", entry.Character)
                    .Add("buff", entry.Buff)
            );
        }

        return list;
    }

    private static List<object?> ParseReactionRules(JsonObject flatProfile)
    {
        var list = new List<object?>();
        if (!flatProfile.TryGetPropertyValue("reaction_rules", out var node) || node is not JsonArray rules)
        {
            return list;
        }

        foreach (var item in rules)
        {
            if (item is not JsonObject rule)
            {
                continue;
            }
            var trigger = ReadString(rule, "trigger", "").Trim();
            var name = ReadString(rule, "name", "").Trim();
            var response = ReadString(rule, "response", "").Trim();
            var activateEvent = ReadString(rule, "activate_event", "").Trim();
            var valid = (trigger == "ability_window" && (response == "turn_away" || response == "run_away" || response == "move_to_range" || response == "use_action" || response == "use_sequence"))
                || (trigger == "party_action_complete" && response == "use_sequence")
                || (trigger == "enemy_buff" && response == "stop_attacking")
                || (trigger == "event_window" && (response is "stop_attacking" or "turn_away")
                    && activateEvent is "spell_start" or "ability_start" or "buff_gained");
            if (!valid || name.Length == 0)
            {
                continue;
            }
            var serialized = new StructuredProfileNode()
                .Add("trigger", trigger)
                .Add("name", name)
                .Add("response", response);
            if (trigger == "event_window")
            {
                var releaseEvent = ReadString(rule, "release_event", "").Trim();
                var releaseName = ReadString(rule, "release_name", name).Trim();
                if (releaseEvent is not ("spell_end" or "ability_end" or "buff_lost") || releaseName.Length == 0)
                {
                    throw new InvalidDataException("event_window reaction requires release_event and release_name");
                }
                serialized.Add("activate_event", activateEvent);
                serialized.Add("release_event", releaseEvent);
                serialized.Add("release_name", releaseName);
                if (releaseEvent == "buff_lost")
                {
                    var timeout = ReadDouble(rule, "confirmation_timeout_seconds", 1.5);
                    if (!double.IsFinite(timeout) || timeout <= 0 || timeout > 10)
                    {
                        throw new InvalidDataException("event_window confirmation timeout must be > 0 and <= 10 seconds");
                    }
                    serialized.Add("confirmation_timeout_seconds", timeout);
                }
            }
            if (trigger == "party_action_complete")
            {
                var sourceName = ReadString(rule, "source_name", "").Trim();
                var triggerActionType = ReadString(rule, "action_type", "").Trim().ToLowerInvariant();
                if (sourceName.Length == 0 || triggerActionType is not ("spell" or "ja"))
                {
                    throw new InvalidDataException("party_action_complete reaction requires source_name and action_type spell/ja");
                }
                serialized.Add("source_name", sourceName);
                serialized.Add("action_type", triggerActionType);
            }
            if (ReadBool(rule, "once_per_instance", false))
            {
                if (trigger is not ("ability_window" or "party_action_complete"))
                {
                    throw new InvalidDataException("once_per_instance reactions require ability_window or party_action_complete trigger");
                }
                serialized.Add("once_per_instance", true);
            }
            if (ReadBool(rule, "hold_smn_rage_until_sequence_complete", false))
            {
                if (trigger != "party_action_complete" || response != "use_sequence")
                {
                    throw new InvalidDataException("SMN Rage hold requires party_action_complete/use_sequence");
                }
                if (!ReadBool(rule, "once_per_instance", false))
                {
                    throw new InvalidDataException("SMN Rage hold requires once_per_instance=true");
                }
                serialized.Add("hold_smn_rage_until_sequence_complete", true);
            }
            if (response is "run_away" or "move_to_range")
            {
                if (!rule.TryGetPropertyValue("distance", out var distanceNode)
                    || distanceNode is not JsonValue distanceValue
                    || !distanceValue.TryGetValue<double>(out var distance)
                    || !double.IsFinite(distance)
                    || distance <= 0)
                {
                    throw new InvalidDataException($"{response} reaction requires a positive finite distance");
                }
                serialized.Add("distance", distance);
            }
            else if (response == "use_action")
            {
                var actionType = ReadString(rule, "action_type", "").Trim();
                var actionName = ReadString(rule, "action_name", "").Trim();
                if (actionType != "spell" || actionName.Length == 0)
                {
                    throw new InvalidDataException("use_action reaction requires action_type 'spell' and a non-empty action_name");
                }
                serialized.Add("action_type", actionType);
                serialized.Add("action_name", actionName);
            }
            else if (response == "use_sequence")
            {
                var sequence = ReactionSequenceProfileCodec.ParseRule(rule);
                var steps = new List<object?>(sequence.Steps.Count);
                foreach (var step in sequence.Steps)
                {
                    steps.Add(
                        new StructuredProfileNode()
                            .Add("action_type", step.ActionType)
                            .Add("action_name", step.ActionName)
                            .Add("target", step.Target)
                            .Add("optional", step.Optional)
                    );
                }
                serialized.Add("steps", steps);
            }
            list.Add(serialized);
        }
        return list;
    }

    private static List<object?> EmptyList() => [];

    private static string? NullIfEmpty(string value) => value.Length == 0 ? null : value;

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
