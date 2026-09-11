using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class RuntimeProfileEditorAdapter
{
    internal static JsonObject Build(JsonElement session, JsonElement activeConfig)
    {
        if (activeConfig.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("Runtime active configuration must be a JSON object.");
        }

        var profile = JsonNode.Parse(activeConfig.GetRawText())?.AsObject()
            ?? throw new InvalidDataException("Runtime active configuration must be a JSON object.");
        foreach (var key in new[]
        {
            "ability_options",
            "weaponskill_options",
            "path_pull_ja_options",
            "path_pull_spell_options",
            "cor_roll_options",
            "brd_song_options",
            "party_options",
        })
        {
            if (session.TryGetProperty(key, out var value))
            {
                profile[key] = JsonNode.Parse(value.GetRawText());
            }
        }

        profile["party_follow_selected"] = RequiredString(profile, "party_follow_leader_name");
        CopyStringArrayAsPipe(profile, "abilities", "abilities_selected");
        CopyStringArrayAsPipe(profile, "tank_enmity_actions", "tank_enmity_actions");
        FlattenRunTank(profile);
        CopyStringArrayAsPipe(profile, "nyzul_parking_order", "nyzul_parking_order");
        CopyStringArrayAsPipe(profile, "formation_required_party_names", "formation_required_party_names");
        CopyStringArrayAsPipe(profile, "brd_songs", "brd_songs");
        CopyStringArrayAsPipe(profile, "brd_dummy_songs", "brd_dummy_songs");
        CopyStringArrayAsPipe(profile, "brd_recovery_ignore_names", "brd_recovery_ignore_names");
        CopyNameArrayAsEntries(profile, "wait_ignore_names", "ignore_entries");
        CopyNameArrayAsEntries(profile, "partner_names", "partner_entries");
        CopyNameArrayAsEntries(profile, "target_ignore_names", "target_ignore_entries");
        CopyNameArrayAsEntries(profile, "add_priority_names", "add_priority_entries");
        CopyNameArrayAsEntries(profile, "sleepspells", "sleep_spell_entries");
        CopyNameArrayAsEntries(profile, "path_hunter_targets", "path_hunter_entries");
        FlattenCampPulling(profile);
        FlattenGeoMaintenance(profile);
        return profile;
    }

    private static string RequiredString(JsonObject profile, string key)
    {
        if (!profile.TryGetPropertyValue(key, out var value) || value is null)
        {
            throw new InvalidDataException($"Runtime active config '{key}' is required.");
        }
        return value.GetValue<string>();
    }

    private static void CopyStringArrayAsPipe(JsonObject profile, string sourceKey, string destinationKey)
    {
        if (!profile.TryGetPropertyValue(sourceKey, out var source) || source is null)
        {
            return;
        }
        if (source is not JsonArray values)
        {
            throw new InvalidDataException($"Runtime active config '{sourceKey}' must be an array.");
        }
        profile[destinationKey] = JoinStringArray(values, sourceKey);
    }

    private static string JoinStringArray(JsonArray values, string path)
    {
        return string.Join("|", values.Select(value =>
            value?.GetValue<string>()
            ?? throw new InvalidDataException($"Runtime active config '{path}' contains a null entry.")));
    }

    private static void CopyNameArrayAsEntries(
        JsonObject profile,
        string namesKey,
        string destinationKey
    )
    {
        if (!profile.TryGetPropertyValue(namesKey, out var source) || source is null)
        {
            return;
        }
        if (source is not JsonArray names)
        {
            throw new InvalidDataException($"Runtime active config '{namesKey}' must be an array.");
        }
        var entries = new List<string>(names.Count);
        for (var i = 0; i < names.Count; i++)
        {
            var name = names[i]?.GetValue<string>()
                ?? throw new InvalidDataException($"Runtime active config '{namesKey}' contains a null entry.");
            entries.Add($"{i + 1}:{name}");
        }
        profile[destinationKey] = string.Join("|", entries);
    }

    private static void FlattenRunTank(JsonObject profile)
    {
        if (!profile.TryGetPropertyValue("tank_run", out var source) || source is null)
        {
            return;
        }
        var run = source as JsonObject
            ?? throw new InvalidDataException("Runtime active config 'tank_run' must be an object.");
        var runes = RequiredObject(run, "runes", "tank_run.runes");
        var foil = RequiredObject(run, "foil", "tank_run.foil");
        var wards = RequiredObject(run, "wards", "tank_run.wards");
        var magic = RequiredObject(run, "magic_support", "tank_run.magic_support");
        profile["run_tank_enabled"] = RequiredValue(run, "enabled", "tank_run.enabled");
        profile["run_tank_runes_maintain"] = RequiredValue(runes, "maintain", "tank_run.runes.maintain");
        profile["run_tank_runes"] = JoinStringArray(RequiredArray(runes, "desired", "tank_run.runes.desired"), "tank_run.runes.desired");
        profile["run_tank_foil"] = RequiredValue(foil, "enabled", "tank_run.foil.enabled");
        foreach (var key in new[] { "vallation", "valiance", "pflug", "swordplay", "battuta", "one_for_all" })
        {
            profile[$"run_tank_{key}"] = RequiredValue(wards, key, $"tank_run.wards.{key}");
        }
        profile["run_tank_gambit"] = RequiredValue(magic, "gambit", "tank_run.magic_support.gambit");
        profile["run_tank_rayke"] = RequiredValue(magic, "rayke", "tank_run.magic_support.rayke");
    }

    private static void FlattenCampPulling(JsonObject profile)
    {
        if (!profile.TryGetPropertyValue("camp_pulling", out var source) || source is null)
        {
            return;
        }
        var pulling = source as JsonObject
            ?? throw new InvalidDataException("Runtime active config 'camp_pulling' must be an object.");
        var action = RequiredObject(pulling, "action", "camp_pulling.action");
        var targets = RequiredArray(pulling, "targets", "camp_pulling.targets");

        profile["camp_pulling_enabled"] = RequiredValue(pulling, "enabled", "camp_pulling.enabled");
        profile["camp_pulling_action_type"] = RequiredValue(action, "type", "camp_pulling.action.type");
        profile["camp_pulling_action_name"] = NullableString(action, "name");
        profile["camp_pulling_targets"] = SerializeCampPullTargets(targets);
        CopyRequiredValue(pulling, "match_mode", profile, "camp_pulling_match_mode", "camp_pulling.match_mode");
        CopyRequiredValue(pulling, "max_active_mobs", profile, "camp_pulling_max_active_mobs", "camp_pulling.max_active_mobs");
        CopyRequiredValue(pulling, "replenish_below_hpp", profile, "camp_pulling_replenish_below_hpp", "camp_pulling.replenish_below_hpp");
        CopyRequiredValue(pulling, "leash_yalms", profile, "camp_pulling_leash_yalms", "camp_pulling.leash_yalms");
        CopyRequiredValue(pulling, "max_z_delta", profile, "camp_pulling_max_z_delta", "camp_pulling.max_z_delta");
        CopyRequiredValue(pulling, "cast_range_ratio", profile, "camp_pulling_cast_range_ratio", "camp_pulling.cast_range_ratio");
        CopyRequiredValue(pulling, "settle_seconds", profile, "camp_pulling_settle_seconds", "camp_pulling.settle_seconds");
        CopyRequiredValue(pulling, "reaction_timeout_seconds", profile, "camp_pulling_reaction_timeout_seconds", "camp_pulling.reaction_timeout_seconds");
        CopyRequiredValue(pulling, "retry_limit", profile, "camp_pulling_retry_limit", "camp_pulling.retry_limit");
        CopyRequiredValue(pulling, "retry_window_seconds", profile, "camp_pulling_retry_window_seconds", "camp_pulling.retry_window_seconds");
        CopyRequiredValue(pulling, "target_cooldown_seconds", profile, "camp_pulling_target_cooldown_seconds", "camp_pulling.target_cooldown_seconds");
        CopyRequiredValue(pulling, "camp_arrival_yalms", profile, "camp_pulling_camp_arrival_yalms", "camp_pulling.camp_arrival_yalms");
    }

    private static void FlattenGeoMaintenance(JsonObject profile)
    {
        if (!profile.TryGetPropertyValue("maintenance_geo", out var source) || source is null)
        {
            return;
        }
        var geo = source as JsonObject
            ?? throw new InvalidDataException("Runtime active config 'maintenance_geo' must be an object.");
        var target = RequiredObject(geo, "geo_target", "maintenance_geo.geo_target");
        var entrust = RequiredObject(geo, "entrust", "maintenance_geo.entrust");
        var luopan = RequiredObject(geo, "luopan", "maintenance_geo.luopan");

        CopyRequiredValue(geo, "enabled", profile, "geo_maintenance_enabled", "maintenance_geo.enabled");
        profile["geo_spell"] = NullableString(geo, "geo_spell");
        profile["indi_spell"] = NullableString(geo, "indi_spell");
        CopyRequiredValue(target, "kind", profile, "geo_target_kind", "maintenance_geo.geo_target.kind");
        profile["geo_target_name"] = NullableString(target, "name");
        CopyRequiredValue(geo, "ordering", profile, "geo_ordering", "maintenance_geo.ordering");
        CopyRequiredValue(geo, "require_camp", profile, "geo_require_camp", "maintenance_geo.require_camp");
        CopyRequiredValue(geo, "camp_tolerance_yalms", profile, "geo_camp_tolerance_yalms", "maintenance_geo.camp_tolerance_yalms");
        CopyRequiredValue(geo, "enemy_geo_requires_camp_radius", profile, "geo_enemy_requires_camp_radius", "maintenance_geo.enemy_geo_requires_camp_radius");
        CopyRequiredValue(entrust, "enabled", profile, "geo_entrust_enabled", "maintenance_geo.entrust.enabled");
        profile["geo_entrust_spell"] = NullableString(entrust, "spell");
        profile["geo_entrust_target_name"] = NullableString(entrust, "target_name");
        CopyRequiredValue(luopan, "use_blaze_of_glory", profile, "geo_use_blaze_of_glory", "maintenance_geo.luopan.use_blaze_of_glory");
        CopyRequiredValue(luopan, "use_ecliptic_attrition", profile, "geo_use_ecliptic_attrition", "maintenance_geo.luopan.use_ecliptic_attrition");
        CopyRequiredValue(luopan, "use_life_cycle", profile, "geo_use_life_cycle", "maintenance_geo.luopan.use_life_cycle");
        CopyRequiredValue(luopan, "life_cycle_hpp", profile, "geo_life_cycle_hpp", "maintenance_geo.luopan.life_cycle_hpp");
        CopyGeoLuopanPlacement(luopan, profile);
        CopyRequiredValue(luopan, "replace_out_of_position", profile, "geo_replace_out_of_position", "maintenance_geo.luopan.replace_out_of_position");
        CopyRequiredValue(luopan, "max_camp_distance_yalms", profile, "geo_max_camp_distance_yalms", "maintenance_geo.luopan.max_camp_distance_yalms");
    }

    private static string SerializeCampPullTargets(JsonArray targets)
    {
        var entries = new List<string>(targets.Count);
        for (var i = 0; i < targets.Count; i++)
        {
            var target = targets[i] as JsonObject
                ?? throw new InvalidDataException($"Runtime active config 'camp_pulling.targets[{i}]' must be an object.");
            var name = target["name"]?.GetValue<string>()
                ?? throw new InvalidDataException($"Runtime active config 'camp_pulling.targets[{i}].name' is required.");
            var priority = target["priority"]?.GetValue<int>()
                ?? throw new InvalidDataException($"Runtime active config 'camp_pulling.targets[{i}].priority' is required.");
            entries.Add($"{name}:{priority}");
        }
        return string.Join("|", entries);
    }

    private static JsonNode RequiredValue(JsonObject source, string key, string path)
    {
        return source[key]?.DeepClone()
            ?? throw new InvalidDataException($"Runtime active config '{path}' is required.");
    }

    private static void CopyGeoLuopanPlacement(JsonObject luopan, JsonObject profile)
    {
        if (!luopan.TryGetPropertyValue("placement", out var value) || value is null)
        {
            // Active runtime projections can outlive an addon update. The durable-profile
            // migration for this newly introduced field has the same canonical default.
            profile["geo_luopan_placement"] = "target";
            return;
        }
        if (value is not JsonValue placementValue
            || !placementValue.TryGetValue<string>(out var placement)
            || (placement != "target" && placement != "camp"))
        {
            throw new InvalidDataException(
                "Runtime active config 'maintenance_geo.luopan.placement' must be 'target' or 'camp'."
            );
        }
        profile["geo_luopan_placement"] = placement;
    }

    private static JsonObject RequiredObject(JsonObject source, string key, string path)
    {
        return source[key] as JsonObject
            ?? throw new InvalidDataException($"Runtime active config '{path}' must be an object.");
    }

    private static JsonArray RequiredArray(JsonObject source, string key, string path)
    {
        return source[key] as JsonArray
            ?? throw new InvalidDataException($"Runtime active config '{path}' must be an array.");
    }

    private static string NullableString(JsonObject source, string key)
    {
        if (!source.TryGetPropertyValue(key, out var value))
        {
            return "";
        }
        return value is null
            ? ""
            : value.GetValue<string>();
    }

    private static void CopyRequiredValue(
        JsonObject source,
        string sourceKey,
        JsonObject destination,
        string destinationKey,
        string path
    )
    {
        destination[destinationKey] = RequiredValue(source, sourceKey, path);
    }
}
