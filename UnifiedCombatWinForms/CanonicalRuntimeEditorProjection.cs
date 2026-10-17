using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class CanonicalRuntimeEditorProjection
{
    private static readonly (string Path, string Key)[] DirectMappings =
    [
        ("ui.show_ingame_ui", "show_ingame_ui"),

        ("combat.autotarget", "autotarget"),
        ("combat.auto_engage", "auto_engage"),
        ("combat.spam", "spam"),
        ("combat.closer", "closer"),
        ("combat.manual", "manual"),
        ("combat.prime", "prime"),
        ("combat.static", "static"),
        ("combat.face", "face"),
        ("combat.weaponskill.enabled", "weaponskill_active"),
        ("combat.weaponskill.primary", "weaponskill"),
        ("combat.weaponskill.mode", "ws_mode"),
        ("combat.weaponskill.minimum_tp", "weaponskill_min_tp"),
        ("combat.weaponskill.allow_aoe", "weaponskill_allow_aoe"),
        ("combat.weaponskill.fast_skillchain", "fast_skillchain"),
        ("combat.weaponskill.no_skillchain_targets", "weaponskill_no_skillchain_targets"),
        ("combat.weaponskill.skillchain_target", "skillchain_target"),
        ("combat.weaponskill.wait_ignore_names", "wait_ignore_names"),
        ("combat.weaponskill.aftermath_enabled", "aftermath_enabled"),
        ("combat.weaponskill.aftermath_ws", "aftermath_ws"),
        ("combat.recurring_spells.enabled", "recurring_spells_enabled"),

        ("abilities.enabled", "ability_active"),
        ("abilities.allow_unengaged", "ability_allow_unengaged"),
        ("abilities.configured", "abilities"),
        ("abilities.wsabilities", "wsabilities"),

        ("defensive.enabled", "defensive_enabled"),
        ("defensive.provider", "defensive_provider"),
        ("defensive.resurrection.enabled", "defensive_resurrection_enabled"),
        ("defensive.resurrection.priority", "defensive_resurrection_priority"),
        ("defensive.cure.enabled", "defensive_cure_enabled"),
        ("defensive.cure.min_tier", "def_heal_min_tier_cure"),
        ("defensive.cure.max_tier", "def_heal_max_tier_cure"),
        ("defensive.cure.min_missing_hp", "def_heal_min_missing_hp"),
        ("defensive.cure.ignore_trusts", "def_heal_ignore_trusts"),
        ("defensive.cure.curaga.enabled", "defensive_curaga_enabled"),
        ("defensive.cure.curaga.min_targets", "defensive_curaga_min_targets"),
        ("defensive.waltz.enabled", "defensive_waltz_enabled"),
        ("defensive.waltz.tp_reserve", "defensive_waltz_tp_reserve"),
        ("defensive.waltz.divine_min_targets", "defensive_divine_waltz_min_targets"),
        ("defensive.doom.holy_water_enabled", "defensive_doom_water"),
        ("defensive.charm_sleeper.enabled", "def_charm_sleeper_enabled"),
        ("defensive.sleep_waker.enabled", "def_sleep_waker_enabled"),
        ("defensive.na.enabled", "defensive_na_enabled"),
        ("defensive.na.limit_enabled", "defensive_na_limit_enabled"),
        ("defensive.na.priority", "defensive_na_priority"),
        ("defensive.enemy_buffs.remove", "def_remove_enemy_buffs"),
        ("defensive.enemy_debuffs.enabled", "def_maintain_enemy_debuffs"),
        ("defensive.enemy_debuffs.list", "defensive_enemy_debuffs"),
        ("defensive.buffs.enabled", "defensive_buff_enabled"),
        ("defensive.buffs.self_only", "defensive_buff_self_only"),
        ("defensive.buffs.list", "defensive_buffs"),
        ("defensive.buffs.overwrite_enabled", "defensive_overwrite_enabled"),
        ("defensive.buffs.overwrite_interval", "defensive_overwrite_interval"),
        ("defensive.thresholds.critical_hpp", "defensive_critical_hpp"),
        ("defensive.thresholds.medium_hpp", "defensive_medium_hpp"),

        ("movement.move", "move"),
        ("movement.spacing.enabled", "spacing"),
        ("movement.spacing.band_min", "spacing_band_min"),
        ("movement.spacing.band_max", "spacing_band_max"),
        ("movement.spacing.model_size_floor", "spacing_model_size_floor"),
        ("movement.spacing.use_prediction", "spacing_use_prediction"),
        ("movement.spacing.lookahead_s", "spacing_lookahead_s"),
        ("movement.spacing.repel_hold_ticks", "spacing_repel_hold_ticks"),
        ("movement.spacing.overlap_deadband", "spacing_overlap_deadband"),
        ("movement.spacing.repel_weight", "spacing_repel_weight"),
        ("movement.spacing.band_deadband", "spacing_band_deadband"),
        ("movement.path.recording", "path_recording"),
        ("movement.path.follow_enabled", "path_follow_enabled"),
        ("movement.path.party_gate_yalms", "path_party_gate_yalms"),
        ("movement.path.resume_index_window", "path_resume_index_window"),
        ("movement.path.hunter_targets", "path_hunter_targets"),
        ("movement.path.hunter_max_z_delta", "path_hunter_max_z_delta"),
        ("movement.path.hunter_max_target_range", "path_hunter_max_target_range"),
        ("movement.path.hunter_claim_timeout_s", "path_hunter_claim_timeout_s"),
        ("movement.path.hunter_ignore_cooldown_s", "path_hunter_ignore_cooldown_s"),
        ("movement.path.pull_action_type", "path_pull_action_type"),
        ("movement.path.pull_action_name", "path_pull_action_name"),
        ("movement.path.pull_attack_fallback_enabled", "path_pull_attack_fallback_enabled"),

        ("follow.party.enabled", "party_follow"),
        ("follow.party.leader_name", "party_follow_leader_name"),
        ("follow.party.min", "party_follow_min"),
        ("follow.party.max", "party_follow_max"),
        ("follow.fight.leader", "fight_leader"),
        ("follow.fight.leader_name", "fight_leader_selected"),
        ("follow.fight.leader_name", "fight_leader_name"),
        ("follow.fight.min", "fight_follow_min"),
        ("follow.fight.hold_s", "fight_follow_hold_s"),
        ("follow.partner.enabled", "partner"),
        ("follow.partner.secondary_enabled", "partner2"),
        ("follow.partner.names", "partner_names"),
        ("follow.partner.puller", "puller"),
        ("follow.partner.puller_name", "puller_selected"),
        ("follow.partner.puller_name", "puller_name"),
        ("follow.partner.leash_source", "puller_leash_source"),
        ("follow.partner.engage_range", "puller_engage_range"),
        ("follow.partner.puller_distance_only", "puller_distance_only"),
        ("follow.nyzul.coordinator_name", "nyzul_coordinator_name"),
        ("follow.nyzul.anchor_name", "nyzul_anchor_name"),
        ("follow.nyzul.parking_order", "nyzul_parking_order"),

        ("targeting.add_control", "add_control"),
        ("targeting.targets", "add_priority_names"),
        ("targeting.target_ignore_names", "target_ignore_names"),

        ("tank.enabled", "tank"),
        ("tank.enmity.actions", "tank_enmity_actions"),
        ("tank.enmity.include_pets", "tank_enmity_include_pets"),

        ("sleep.enabled", "sleep"),
        ("sleep.order", "sleepspells"),
        ("sleep.legacy_primary", "sleepspell"),
        ("sleep.max_target_range", "sleep_max_target_range"),

        ("spells.enabled", "spell_active"),
        ("spells.configured", "spell"),
        ("spells.magic_burst", "magic_burst_enabled"),
        ("spells.magic_burst_mode", "magic_burst_mode"),
        ("spells.magic_burst_family", "magic_burst_family"),
        ("spells.magic_burst_max_tier", "magic_burst_max_tier"),
        ("spells.dd2_slots", "dd2_spell_slots"),

        ("maintenance.cor.roll_1", "cor_roll_1"),
        ("maintenance.cor.roll_2", "cor_roll_2"),
        ("maintenance.cor.crooked_roll_slot", "cor_crooked_roll_slot"),
        ("maintenance.cor.elevens", "cor_elevens"),
        ("maintenance.cor.luzaf_range_override", "cor_luzaf_range_override"),
        ("maintenance.cor.light_shot_dia", "cor_light_shot_dia"),
        ("maintenance.cor.range_selected", "cor_roll_range_selected"),
        ("maintenance.brd.enabled", "brd_maintenance_enabled"),
        ("maintenance.brd.songs", "brd_songs"),
        ("maintenance.brd.dummy_songs", "brd_dummy_songs"),
        ("maintenance.brd.recovery_range_yalms", "brd_recovery_range_yalms"),
        ("maintenance.brd.recovery_ignore_names", "brd_recovery_ignore_names"),
        ("maintenance.brd.reposition_for_party_songs", "brd_reposition_for_party_songs"),
        ("maintenance.brd.use_nitro", "brd_use_nitro"),
        ("maintenance.brd.use_soul_voice", "brd_use_soul_voice"),
        ("maintenance.brd.use_clarion_call", "brd_use_clarion_call"),
        ("maintenance.brd.use_marcato", "brd_use_marcato"),
        ("maintenance.brd.marcato_song", "brd_marcato_song"),
        ("maintenance.food.enabled", "food_enabled"),
        ("maintenance.food.item", "food_item"),

        ("summoner.enabled", "summoner_enabled"),
        ("summoner.avatar", "summoner_avatar"),
        ("summoner.maintenance.avatar_favor", "summoner_avatar_favor"),
        ("summoner.maintenance.ward.enabled", "summoner_ward_enabled"),
        ("summoner.pet_combat.engage_on_combat_start", "summoner_engage_on_combat_start"),
        ("summoner.pet_combat.offensive_action.enabled", "summoner_rage_enabled"),
        ("summoner.pet_combat.offensive_action.action", "summoner_rage_action"),
        ("summoner.pet_combat.offensive_action.usage", "summoner_rage_usage"),
        ("summoner.pet_combat.offensive_action.target_hpp_above_enabled", "summoner_rage_target_hpp_above_enabled"),
        ("summoner.pet_combat.offensive_action.target_hpp_above", "summoner_rage_target_hpp_above"),
        ("summoner.pet_combat.offensive_action.pet_tp_above_enabled", "summoner_rage_pet_tp_above_enabled"),
        ("summoner.pet_combat.offensive_action.pet_tp_above", "summoner_rage_pet_tp_above"),

        ("puppetmaster.enabled", "puppetmaster_enabled"),
        ("puppetmaster.activate_if_missing", "puppetmaster_activate_if_missing"),
        ("puppetmaster.deploy_on_combat_start", "puppetmaster_deploy_on_combat_start"),
        ("puppetmaster.maneuvers.enabled", "puppetmaster_maneuvers_enabled"),
        ("puppetmaster.maneuvers.post_activate_quiet_seconds", "puppetmaster_post_activate_quiet_seconds"),
        ("puppetmaster.maneuvers.safe_burden_ceiling", "puppetmaster_safe_burden_ceiling"),

        ("sch.enabled", "sch_enabled"),
        ("sch.arts.minimum_commit_s", "sch_arts_minimum_commit_s"),
        ("sch.arts.emergency_off_art_casts", "sch_arts_emergency_off_art_casts"),
        ("sch.support.regen.enabled", "sch_regen_enabled"),
        ("sch.support.regen.minimum_coverage", "sch_regen_minimum_coverage"),
        ("sch.support.regen.refresh_before_s", "sch_regen_refresh_before_s"),
        ("sch.support.storms.enabled", "sch_storms_enabled"),
        ("sch.support.storms.refresh_before_s", "sch_storms_refresh_before_s"),
        ("sch.sublimation.enabled", "sch_sublimation_enabled"),
        ("sch.sublimation.release_when_mpp_at_most", "sch_sublimation_release_when_mpp_at_most"),
        ("sch.sublimation.release_when_complete", "sch_sublimation_release_when_complete"),
        ("sch.sublimation.minimum_hpp_to_activate", "sch_sublimation_minimum_hpp_to_activate"),
        ("sch.defensive.accession_cure.enabled", "sch_accession_cure_enabled"),
        ("sch.defensive.accession_status_removal.enabled", "sch_accession_status_removal_enabled"),
        ("sch.defensive.rapture.enabled", "sch_rapture_enabled"),
        ("sch.defensive.penury.enabled", "sch_penury_enabled"),

        ("debug.enabled", "debug"),
        ("debug.action_timeline", "log_action_timeline"),
        ("debug.combat_sched", "log_combat_sched"),
        ("debug.ja_sched", "log_ja_sched"),
        ("debug.ja_debug", "log_ja_debug"),
        ("debug.def_sched", "log_def_sched"),
        ("debug.tank_sched", "log_tank_sched"),

        ("legacy.sub", "sub"),
        ("legacy.sub2", "sub2"),
        ("legacy.solo", "solo"),
        ("legacy.aeonic", "aeonic"),
        ("legacy.color", "color"),
        ("legacy.command", "command"),
        ("legacy.hunter", "hunter"),
    ];

    internal static JsonObject Project(JsonElement activeConfig)
    {
        if (activeConfig.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("Runtime active configuration must be a JSON object.");
        }

        var root = JsonNode.Parse(activeConfig.GetRawText())?.AsObject()
            ?? throw new InvalidDataException("Runtime active configuration must be a JSON object.");

        // Transitional compatibility for an older addon snapshot that still
        // publishes the already-projected editor shape.
        if (root["config"] is not JsonObject config)
        {
            return (JsonObject)root.DeepClone();
        }

        var editor = new JsonObject
        {
            ["profile_schema_version"] = 2,
        };
        if (root["profile"] is JsonObject metadata)
        {
            CopyNode(metadata, "engine", editor, "engine");
        }

        foreach (var (path, key) in DirectMappings)
        {
            CopyPath(config, path, editor, key);
        }

        ProjectOwnership(config, editor);
        ProjectRecurringSpells(config, editor);
        ProjectAbilities(config, editor);
        ProjectDefensiveComplex(config, editor);
        ProjectEncounter(config, editor);
        ProjectMovementComplex(config, editor);
        ProjectFollowComplex(config, editor);
        ProjectReactions(config, editor);
        ProjectTankComplex(config, editor);
        ProjectMaintenanceComplex(config, editor);
        ProjectSummonerComplex(config, editor);
        ProjectPuppetmasterComplex(config, editor);
        ProjectScholarComplex(config, editor);

        return editor;
    }

    private static void ProjectOwnership(JsonObject config, JsonObject editor)
    {
        foreach (var (source, destination) in new[]
        {
            ("domain_combat_enabled", "domain_combat_enabled"),
            ("domain_defensive_enabled", "domain_defensive_enabled"),
            ("domain_movement_enabled", "domain_movement_enabled"),
            ("domain_maintenance_enabled", "domain_maintenance_enabled"),
            ("domain_follow_enabled", "domain_follow_enabled"),
            ("auto_accept_raise", "auto_accept_raise"),
            ("pause_automation_while_weakened", "pause_automation_while_weakened"),
        })
        {
            CopyPath(config, $"ownership.{source}", editor, destination);
        }

        CopyFallback(config, editor, "domain_combat_enabled", "combat.enabled");
        CopyFallback(config, editor, "domain_defensive_enabled", "defensive.enabled");
        CopyFallback(config, editor, "domain_movement_enabled", "movement.enabled");
        CopyFallback(config, editor, "domain_maintenance_enabled", "maintenance.enabled");
        CopyFallback(config, editor, "domain_follow_enabled", "follow.enabled");
    }

    private static void ProjectRecurringSpells(JsonObject config, JsonObject editor)
    {
        if (PathNode(config, "combat.recurring_spells.list") is JsonArray spells)
        {
            editor["recurring_spells"] = JoinStringArray(spells, "config.combat.recurring_spells.list");
        }
    }

    private static void ProjectAbilities(JsonObject config, JsonObject editor)
    {
        var configured = PathNode(config, "abilities.configured") as JsonArray;
        var legacy = PathNode(config, "abilities.legacy_slots") as JsonArray;
        var compatibility = configured is { Count: > 0 } ? configured : legacy;
        for (var i = 0; i < 6; i++)
        {
            editor[$"ability{i + 1}"] = compatibility is not null && i < compatibility.Count
                ? compatibility[i]?.DeepClone() ?? JsonValue.Create("")
                : JsonValue.Create("");
        }
    }

    private static void ProjectDefensiveComplex(JsonObject config, JsonObject editor)
    {
        if (PathNode(config, "defensive.buffs.targeted") is JsonArray targeted)
        {
            editor["defensive_targeted_buffs"] = SerializeTargetedBuffs(targeted);
        }
    }

    private static void ProjectEncounter(JsonObject config, JsonObject editor)
    {
        var encounter = PathObject(config, "encounter");
        if (encounter is null)
        {
            editor["encounter_enabled"] = false;
            editor["encounter_id"] = "sortie_ghatjot";
            editor["encounter_water_damage"] = "enforce";
            editor["encounter_water_skillchain"] = "enforce";
            editor["encounter_repeat_action_wall"] = "off";
            editor["encounter_repeat_action_guard_s"] = 10.0;
            ProjectKeiDefaults(editor);
            return;
        }

        CopyNode(encounter, "enabled", editor, "encounter_enabled");
        CopyNode(encounter, "id", editor, "encounter_id");
        var id = StringValue(encounter["id"]);
        if (string.Equals(id, "kei", StringComparison.Ordinal)
            && encounter["kei"] is JsonObject kei)
        {
            var elemental = kei["elemental_damage"] as JsonObject;
            if (elemental is not null)
            {
                CopyNode(elemental, "dealer_name", editor, "kei_elemental_dealer_name");
                if (elemental["water"] is JsonObject water)
                {
                    CopyNode(water, "probe_spell", editor, "kei_water_probe_spell");
                    CopyNode(water, "damage_spell", editor, "kei_water_damage_spell");
                }
                if (elemental["ice"] is JsonObject ice)
                {
                    CopyNode(ice, "probe_spell", editor, "kei_ice_probe_spell");
                    CopyNode(ice, "damage_spell", editor, "kei_ice_damage_spell");
                }
                CopyNode(elemental, "sustain_interval_s", editor, "kei_sustain_interval_s");
                CopyNode(elemental, "probe_timeout_s", editor, "kei_probe_timeout_s");
            }
            if (kei["fullers"] is JsonObject fullers)
            {
                CopyNode(fullers, "target_distance", editor, "kei_fullers_target_distance");
                CopyNode(fullers, "prearm_hpp_margin", editor, "kei_fullers_prearm_hpp_margin");
            }
            return;
        }

        var repeatDefault = string.Equals(id, "sortie_dhartok", StringComparison.Ordinal) ? "warn" : "off";
        editor["encounter_water_damage"] = PathNode(config, "encounter.policy.water_damage")?.DeepClone()
            ?? JsonValue.Create("enforce");
        editor["encounter_water_skillchain"] = PathNode(config, "encounter.policy.water_skillchain")?.DeepClone()
            ?? JsonValue.Create("enforce");
        editor["encounter_repeat_action_wall"] = PathNode(config, "encounter.policy.repeat_action_wall")?.DeepClone()
            ?? JsonValue.Create(repeatDefault);
        editor["encounter_repeat_action_guard_s"] = PathNode(config, "encounter.tuning.repeat_action_guard_s")?.DeepClone()
            ?? JsonValue.Create(10.0);
        ProjectKeiDefaults(editor);
    }

    private static void ProjectKeiDefaults(JsonObject editor)
    {
        editor["kei_elemental_dealer_name"] ??= "";
        editor["kei_water_probe_spell"] ??= "Water";
        editor["kei_water_damage_spell"] ??= "Water III";
        editor["kei_ice_probe_spell"] ??= "Blizzard";
        editor["kei_ice_damage_spell"] ??= "Blizzard III";
        editor["kei_sustain_interval_s"] ??= 2.5;
        editor["kei_probe_timeout_s"] ??= 3.0;
        editor["kei_fullers_target_distance"] ??= 12.0;
        editor["kei_fullers_prearm_hpp_margin"] ??= 1.0;
    }

    private static void ProjectMovementComplex(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "combat.pulling") is JsonObject pulling)
        {
            editor["camp_pulling"] = pulling.DeepClone();
        }

        if (PathObject(config, "movement.formation") is JsonObject formation)
        {
            editor["formation_enabled"] = formation["enabled"]?.DeepClone() ?? JsonValue.Create(false);
            CopyNode(formation, "encounter", editor, "formation_encounter");
            CopyNode(formation, "role", editor, "formation_role");
            CopyNode(formation, "tank_name", editor, "formation_tank_name");
            CopyNode(formation, "required_party_names", editor, "formation_required_party_names");
            CopyNode(formation, "capture_stable_s", editor, "formation_capture_stable_s");
            CopyNode(formation, "capture_tolerance", editor, "formation_capture_tolerance");
            CopyNode(formation, "safe_radius", editor, "formation_safe_radius");

            if (formation["mock"] is JsonObject mock)
            {
                CopyNode(mock, "enabled", editor, "formation_mock_enabled");
                CopyNode(mock, "mob_name", editor, "formation_mock_mob_name");
            }
            else
            {
                editor["formation_mock_enabled"] = false;
                editor["formation_mock_mob_name"] = "";
            }

            CopySubObject(formation, "tank", editor, [
                ("accept_radius", "formation_tank_accept_radius"),
                ("return_radius", "formation_tank_return_radius"),
            ]);
            CopySubObject(formation, "dps", editor, [
                ("flank_angle_deg", "formation_dps_flank_angle_deg"),
                ("melee_radius", "formation_dps_melee_radius"),
                ("position_tolerance", "formation_dps_position_tolerance"),
            ]);
            CopySubObject(formation, "healer", editor, [
                ("preferred_radius", "formation_healer_preferred_radius"),
                ("minimum_boss_distance", "formation_healer_minimum_boss_distance"),
                ("maximum_party_range", "formation_healer_maximum_party_range"),
                ("cone_half_angle_deg", "formation_healer_cone_half_angle_deg"),
                ("cone_safety_margin_deg", "formation_healer_cone_safety_margin_deg"),
                ("sample_step_deg", "formation_healer_sample_step_deg"),
            ]);

            if (formation["placement"] is JsonObject placement)
            {
                CopyPlacement(placement, editor);
            }
            if (formation["hysteresis"] is JsonObject hysteresis)
            {
                CopyNode(hysteresis, "start_distance", editor, "formation_hysteresis_start_distance");
                CopyNode(hysteresis, "stop_distance", editor, "formation_hysteresis_stop_distance");
            }
            if (formation["constraints"] is JsonObject constraints)
            {
                CopyConstraints(constraints, editor);
            }
        }
        else
        {
            editor["formation_enabled"] = false;
            editor["formation_mock_enabled"] = false;
            editor["formation_mock_mob_name"] = "";
        }

        if (PathObject(config, "movement.named_formations") is JsonObject named
            && named["entries"] is JsonArray entries)
        {
            editor["named_formations_enabled"] = named["enabled"]?.DeepClone() ?? JsonValue.Create(false);
            var projected = new JsonArray();
            foreach (var node in entries)
            {
                var entry = node as JsonObject
                    ?? throw new InvalidDataException("config.movement.named_formations.entries must contain objects.");
                var flat = new JsonObject();
                CopyNode(entry, "mob_name", flat, "mob_name");
                if (entry["placement"] is JsonObject placement)
                {
                    CopyPlacement(placement, flat);
                }
                if (entry["hysteresis"] is JsonObject hysteresis)
                {
                    CopyNode(hysteresis, "start_distance", flat, "formation_hysteresis_start_distance");
                    CopyNode(hysteresis, "stop_distance", flat, "formation_hysteresis_stop_distance");
                }
                if (entry["constraints"] is JsonObject constraints)
                {
                    CopyConstraints(constraints, flat);
                    if (flat["formation_required_party_names"] is JsonArray required)
                    {
                        flat["formation_required_party_names"] = JoinStringArray(
                            required,
                            "config.movement.named_formations.entries.constraints.required_party_names"
                        );
                    }
                }
                projected.Add(flat);
            }
            editor["named_formation_entries"] = projected;
        }
        else
        {
            editor["named_formations_enabled"] = false;
            editor["named_formation_entries"] = new JsonArray();
        }
    }

    private static void CopyPlacement(JsonObject placement, JsonObject editor)
    {
        foreach (var (source, destination) in new[]
        {
            ("mode", "formation_placement_mode"),
            ("anchor", "formation_anchor"),
            ("anchor_member", "formation_anchor_member"),
            ("preferred_radius", "formation_preferred_radius"),
            ("minimum_radius", "formation_minimum_radius"),
            ("maximum_radius", "formation_maximum_radius"),
            ("preferred_angle_deg", "formation_preferred_angle_deg"),
            ("allowed_angle_half_width_deg", "formation_allowed_angle_half_width_deg"),
            ("radius_step", "formation_radius_step"),
            ("angle_step_deg", "formation_angle_step_deg"),
        })
        {
            CopyNode(placement, source, editor, destination);
        }
        if (placement["axis"] is JsonObject axis)
        {
            CopyNode(axis, "type", editor, "formation_axis_type");
            CopyNode(axis, "member", editor, "formation_axis_member");
        }
    }

    private static void CopyConstraints(JsonObject constraints, JsonObject editor)
    {
        foreach (var (source, destination) in new[]
        {
            ("avoid_encounter_hazards", "formation_avoid_encounter_hazards"),
            ("hazard_margin", "formation_hazard_margin"),
            ("safe_origin_radius", "formation_safe_origin_radius"),
            ("minimum_boss_distance", "formation_minimum_boss_distance"),
            ("maximum_boss_distance", "formation_maximum_boss_distance"),
            ("maximum_party_range", "formation_maximum_party_range"),
            ("required_party_names", "formation_required_party_names"),
        })
        {
            CopyNode(constraints, source, editor, destination);
        }
    }

    private static void ProjectFollowComplex(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "follow") is JsonObject follow)
        {
            editor["follow"] = follow.DeepClone();
        }
    }

    private static void ProjectReactions(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "reactions") is JsonObject reactions)
        {
            editor["reaction_enabled"] = reactions["enabled"]?.DeepClone() ?? JsonValue.Create(false);
            editor["reaction_rules"] = reactions["rules"]?.DeepClone() ?? new JsonArray();
        }
        else
        {
            editor["reaction_enabled"] = false;
            editor["reaction_rules"] = new JsonArray();
        }
    }

    private static void ProjectTankComplex(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "tank.run") is JsonObject run)
        {
            editor["tank_run"] = run.DeepClone();
        }
    }

    private static void ProjectMaintenanceComplex(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "maintenance.brd") is JsonObject brd)
        {
            editor["maintenance_brd"] = brd.DeepClone();
            if (brd["targeted_songs"] is JsonArray targeted)
            {
                editor["brd_targeted_songs"] = SerializeBardTargetedSongs(targeted);
            }
        }
        if (PathObject(config, "maintenance.geo") is JsonObject geo)
        {
            editor["maintenance_geo"] = geo.DeepClone();
        }
    }

    private static void ProjectSummonerComplex(JsonObject config, JsonObject editor)
    {
        if (PathNode(config, "summoner.maintenance.ward.actions") is JsonArray actions)
        {
            var pipe = JoinStringArray(actions, "config.summoner.maintenance.ward.actions");
            editor["summoner_ward_actions"] = pipe;
            editor["summoner_ward_action"] = actions.Count > 0
                ? actions[0]?.DeepClone() ?? JsonValue.Create("")
                : JsonValue.Create("");
        }
        editor["summoner_avatar"] ??= "";
        editor["summoner_rage_action"] ??= "";
    }

    private static void ProjectPuppetmasterComplex(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "puppetmaster") is not JsonObject pup)
        {
            editor["puppetmaster_enabled"] = false;
            return;
        }
        editor["puppetmaster"] = pup.DeepClone();
        if (PathNode(config, "puppetmaster.maneuvers.pattern") is JsonArray pattern)
        {
            editor["puppetmaster_maneuver_pattern"] = JoinStringArray(
                pattern,
                "config.puppetmaster.maneuvers.pattern"
            );
        }
    }

    private static void ProjectScholarComplex(JsonObject config, JsonObject editor)
    {
        if (PathObject(config, "sch") is not JsonObject sch)
        {
            return;
        }
        editor["sch"] = sch.DeepClone();
        if (PathNode(config, "sch.support.regen.spells") is JsonArray spells)
        {
            editor["sch_accession_perpetuance_spells"] = JoinStringArray(
                spells,
                "config.sch.support.regen.spells"
            );
        }
        if (PathNode(config, "sch.support.storms.assignments") is JsonArray assignments)
        {
            editor["sch_storm_assignments"] = SerializeScholarStormAssignments(assignments);
        }
        if (PathObject(config, "sch.offense.skillchain") is JsonObject skillchain)
        {
            editor["sch_skillchain_enabled"] = skillchain["enabled"]?.DeepClone() ?? JsonValue.Create(false);
            if (skillchain["plans"] is JsonArray plans && plans.Count > 0 && plans[0] is JsonObject plan)
            {
                CopyNode(plan, "result", editor, "sch_skillchain_result");
                CopyNode(plan, "closer", editor, "sch_skillchain_closer");
            }
        }
    }

    private static string SerializeTargetedBuffs(JsonArray entries)
    {
        var result = new List<string>();
        foreach (var node in entries)
        {
            if (node is not JsonObject entry)
            {
                continue;
            }
            var character = StringValue(entry["character"]);
            var buff = StringValue(entry["buff"]);
            if (!string.IsNullOrWhiteSpace(character) && !string.IsNullOrWhiteSpace(buff))
            {
                result.Add($"{character}:{buff}");
            }
        }
        return string.Join("|", result);
    }

    private static string SerializeBardTargetedSongs(JsonArray entries)
    {
        var result = new List<string>();
        foreach (var node in entries)
        {
            if (node is not JsonObject entry
                || entry["recipients"] is not JsonArray recipients
                || entry["priority_songs"] is not JsonArray songs)
            {
                continue;
            }
            var recipientText = string.Join(",", StringArray(recipients));
            var songText = string.Join(",", StringArray(songs));
            if (recipientText.Length > 0 && songText.Length > 0)
            {
                result.Add($"{recipientText}:{songText}");
            }
        }
        return string.Join("|", result);
    }

    private static string SerializeScholarStormAssignments(JsonArray assignments)
    {
        var result = new List<string>();
        foreach (var node in assignments)
        {
            if (node is not JsonObject assignment || assignment["targets"] is not JsonArray targets)
            {
                continue;
            }
            var spell = StringValue(assignment["spell"]);
            var targetText = string.Join(",", StringArray(targets));
            if (spell.Length > 0 && targetText.Length > 0)
            {
                result.Add($"{spell}:{targetText}");
            }
        }
        return string.Join("|", result);
    }

    private static IEnumerable<string> StringArray(JsonArray values)
    {
        foreach (var node in values)
        {
            var value = StringValue(node);
            if (value.Length > 0)
            {
                yield return value;
            }
        }
    }

    private static string JoinStringArray(JsonArray values, string path)
    {
        return string.Join("|", values.Select(value =>
            value is JsonValue item && item.TryGetValue<string>(out var text)
                ? text
                : throw new InvalidDataException($"{path} must contain only strings.")));
    }

    private static string StringValue(JsonNode? node)
    {
        return node is JsonValue value && value.TryGetValue<string>(out var text)
            ? text
            : "";
    }

    private static void CopyFallback(JsonObject config, JsonObject editor, string destination, string sourcePath)
    {
        if (editor[destination] is null)
        {
            CopyPath(config, sourcePath, editor, destination);
        }
    }

    private static void CopySubObject(
        JsonObject source,
        string sourceKey,
        JsonObject destination,
        IReadOnlyList<(string Source, string Destination)> mappings
    )
    {
        if (source[sourceKey] is not JsonObject child)
        {
            return;
        }
        foreach (var (from, to) in mappings)
        {
            CopyNode(child, from, destination, to);
        }
    }

    private static void CopyPath(JsonObject root, string path, JsonObject destination, string destinationKey)
    {
        var node = PathNode(root, path);
        if (node is not null)
        {
            destination[destinationKey] = node.DeepClone();
        }
    }

    private static JsonObject? PathObject(JsonObject root, string path)
    {
        return PathNode(root, path) as JsonObject;
    }

    private static JsonNode? PathNode(JsonObject root, string path)
    {
        JsonNode? current = root;
        foreach (var segment in path.Split('.'))
        {
            if (current is not JsonObject obj || !obj.TryGetPropertyValue(segment, out current))
            {
                return null;
            }
        }
        return current;
    }

    private static void CopyNode(JsonObject source, string sourceKey, JsonObject destination, string destinationKey)
    {
        if (source.TryGetPropertyValue(sourceKey, out var node) && node is not null)
        {
            destination[destinationKey] = node.DeepClone();
        }
    }
}
