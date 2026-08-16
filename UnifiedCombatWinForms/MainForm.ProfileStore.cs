using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private const int ProfileSchemaVersion = 4;
    private static readonly string[] RequiredDomainBoolKeys =
    [
        "domain_combat_enabled",
        "domain_defensive_enabled",
        "domain_movement_enabled",
        "domain_maintenance_enabled",
        "domain_follow_enabled",
    ];

    private static string? FindAddonRootFrom(string startDir)
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
            // fall through to null
        }

        return null;
    }

    private string ProfileRootDir
    {
        get
        {
            var baseDir = AppContext.BaseDirectory;
            var addonRoot = FindAddonRootFrom(baseDir);
            var dir = addonRoot is not null
                ? Path.Combine(addonRoot, "data", "ui_profiles")
                : Path.Combine(baseDir, "ui_profiles");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    private string GlobalUiSettingsPath => Path.Combine(ProfileRootDir, "ui_global.json");

    private static string SafeToken(string? s)
    {
        var raw = (s ?? "").Trim();
        if (raw.Length == 0)
        {
            return "unknown";
        }

        var bad = Path.GetInvalidFileNameChars();
        var chars = raw.Select(c => bad.Contains(c) ? '_' : c).ToArray();
        return new string(chars);
    }

    private bool TryProfilePathForSid(string sid, out string path)
    {
        path = "";
        if (!_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            return false;
        }

        var chRaw = (meta.CharName ?? "").Trim();
        var jobRaw = (meta.Job ?? "").Trim();
        var subJobRaw = (meta.SubJob ?? "").Trim();
        if (string.IsNullOrWhiteSpace(chRaw) || string.IsNullOrWhiteSpace(jobRaw) || string.IsNullOrWhiteSpace(subJobRaw))
        {
            return false;
        }

        var ch = SafeToken(chRaw);
        var job = SafeToken(jobRaw);
        var subJob = SafeToken(subJobRaw);
        path = Path.Combine(ProfileRootDir, $"{ch}_{job}_{subJob}.json");
        return true;
    }

    private bool TryMigrateLegacyUiProfileForSid(string sid, string exactPath, out string error)
    {
        error = "";
        if (File.Exists(exactPath))
        {
            return true;
        }
        if (!_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            error = "session metadata unavailable";
            return false;
        }

        var chRaw = (meta.CharName ?? "").Trim();
        var jobRaw = (meta.Job ?? "").Trim();
        if (chRaw.Length == 0 || jobRaw.Length == 0)
        {
            error = "legacy UI profile identity unavailable";
            return false;
        }

        var legacyPath = Path.Combine(ProfileRootDir, $"{SafeToken(chRaw)}_{SafeToken(jobRaw)}.json");
        if (!File.Exists(legacyPath))
        {
            return true;
        }

        try
        {
            File.Copy(legacyPath, exactPath, overwrite: false);
            return true;
        }
        catch (Exception ex)
        {
            error = $"legacy UI profile migration failed: {ex.Message}";
            return false;
        }
    }

    private string GetEngineForSid(string sid)
    {
        if (_sessionMetaBySid.TryGetValue(sid, out var meta) && !string.IsNullOrWhiteSpace(meta.Engine))
        {
            return meta.Engine;
        }

        return "UC";
    }

    private List<string> CurrentPartyNameOptions()
    {
        return _sessionMetaBySid.Values
            .Select(x => x.CharName)
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToList();
    }

    private JsonObject BuildProfileFromUi(string sid)
    {
        var partyNames = CurrentPartyNameOptions();
        var running = _sessionRunningBySid.TryGetValue(sid, out var rv) && rv;
		var leashSource = _pullerLeashSource.SelectedItem?.ToString();
		if (leashSource is not ("Player" or "Camp"))
		{
			throw new InvalidOperationException("Puller leash source must be Player or Camp.");
		}
		var summonerWardActions = SelectedSummonerWardActions();
        var profile = new JsonObject
        {
            ["profile_schema_version"] = ProfileSchemaVersion,
            ["engine"] = GetEngineForSid(sid),
            ["Start_Engine"] = running,
            ["ability_options"] = string.Join("|", _abilityOptions),
            ["weaponskill_options"] = string.Join("|", _wsCombo.Items.Cast<object>().Select(x => x.ToString() ?? "")),
            ["path_pull_ja_options"] = string.Join("|", _pathPullJaOptions),
            ["path_pull_spell_options"] = string.Join("|", _pathPullSpellOptions),
            ["partner_options"] = string.Join("|", partyNames),
            ["puller_options"] = string.Join("|", partyNames),
            ["abilities_selected"] = string.Join("|", _selectedAbilities),
            ["aftermath_ws"] = (_aftermathCombo.Text ?? "").Trim(),
            ["path_pull_action_type"] = _pathPullActionType.SelectedItem?.ToString() ?? "ja",
            ["path_pull_action_name"] = (_pathPullActionName.Text ?? "").Trim(),
            ["geo_maintenance_enabled"] = _geoEnabled.Checked,
            ["geo_spell"] = _geoSpell.Text.Trim(),
            ["indi_spell"] = _indiSpell.Text.Trim(),
            ["geo_target_kind"] = _geoTargetKind.SelectedItem?.ToString() ?? "current_enemy",
            ["geo_target_name"] = _geoTargetName.Text.Trim(),
            ["geo_ordering"] = _geoOrdering.SelectedItem?.ToString() ?? "geo_first",
            ["geo_require_camp"] = _geoRequireCamp.Checked,
            ["geo_camp_tolerance_yalms"] = decimal.ToDouble(_geoCampTolerance.Value),
            ["geo_entrust_enabled"] = _geoEntrustEnabled.Checked,
            ["geo_entrust_spell"] = _geoEntrustSpell.Text.Trim(),
            ["geo_entrust_target_name"] = _geoEntrustTarget.Text.Trim(),
            ["geo_use_blaze_of_glory"] = _geoUseBlaze.Checked,
            ["geo_use_ecliptic_attrition"] = _geoUseEcliptic.Checked,
            ["geo_use_life_cycle"] = _geoUseLifeCycle.Checked,
            ["geo_life_cycle_hpp"] = decimal.ToInt32(_geoLifeCycleHpp.Value),
            ["geo_replace_out_of_position"] = _geoReplaceOutOfPosition.Checked,
            ["geo_enemy_requires_camp_radius"] = _geoEnemyRequiresCampRadius.Checked,
            ["geo_max_camp_distance_yalms"] = decimal.ToDouble(_geoMaxCampDistance.Value),
            ["camp_pulling_enabled"] = _campPullEnabled.Checked,
            ["camp_pulling_action_type"] = _campPullActionType.SelectedItem?.ToString() ?? "spell",
            ["camp_pulling_action_name"] = _campPullActionName.Text.Trim(),
            ["camp_pulling_targets"] = _campPullTargets.Text.Trim(),
            ["camp_pulling_match_mode"] = _campPullMatchMode.SelectedItem?.ToString() ?? "exact",
            ["camp_pulling_max_active_mobs"] = decimal.ToInt32(_campPullMaxActive.Value),
            ["camp_pulling_replenish_below_hpp"] = decimal.ToInt32(_campPullReplenishHpp.Value),
            ["camp_pulling_leash_yalms"] = decimal.ToDouble(_campPullLeash.Value),
            ["camp_pulling_max_z_delta"] = decimal.ToDouble(_campPullMaxZ.Value),
            ["camp_pulling_cast_range_ratio"] = decimal.ToDouble(_campPullRangeRatio.Value),
            ["camp_pulling_settle_seconds"] = decimal.ToDouble(_campPullSettle.Value),
            ["camp_pulling_reaction_timeout_seconds"] = decimal.ToDouble(_campPullReactionTimeout.Value),
            ["camp_pulling_retry_limit"] = decimal.ToInt32(_campPullRetryLimit.Value),
            ["camp_pulling_retry_window_seconds"] = decimal.ToDouble(_campPullRetryWindow.Value),
            ["camp_pulling_target_cooldown_seconds"] = decimal.ToDouble(_campPullCooldown.Value),
            ["camp_pulling_camp_arrival_yalms"] = decimal.ToDouble(_campPullArrival.Value),
            ["path_file_name"] = _pathFileValue.Text ?? "",
            ["path_route_type"] = _pathRouteTypeValue.Text ?? "unknown",
            ["path_distance_to_start"] = ParseDouble(_pathDistanceValue.Text, 0),
            ["path_points_count"] = ParseInt(_pathPointCountValue.Text, 0),
            ["path_party_gate_yalms"] = ParseDouble(_pathPartyGateYalms.Text, 3),
            ["path_resume_index_window"] = ParseInt(_pathResumeIndexWindow.Text, 12),
            ["path_hunter_max_z_delta"] = ParseDouble(_pathHunterMaxZDelta.Text, 2),
            ["path_hunter_max_target_range"] = ParseDouble(_pathHunterMaxTargetRange.Text, 20),
            ["path_hunter_claim_timeout_s"] = ParseDouble(_pathHunterClaimTimeout.Text, 4),
            ["path_hunter_ignore_cooldown_s"] = ParseDouble(_pathHunterIgnoreCooldown.Text, 20),
            ["path_hunter_entries"] = string.Join("|", _pathHunterRows.Select(r => $"{r.Id}:{r.Name}")),
            ["tank_enmity_actions"] = string.Join("|", _tankEnmityRows),
            ["puller_selected"] = SelectedPartyName(_pullerCombo),
			["puller_leash_source"] = leashSource.ToLowerInvariant(),
            ["puller_engage_range"] = Math.Clamp(ParseDouble(_pullerEngageRange.Text, 6), 0.1, 50.0),
            ["fight_leader_selected"] = SelectedPartyName(_fightLeaderCombo),
            ["party_follow_selected"] = SelectedPartyName(_partyFollowCombo),
            ["party_follow_min"] = ParseDouble(_pfFollowMinYalms.Text, 0.5),
            ["party_follow_max"] = ParseDouble(_pfFollowMaxYalms.Text, 50),
            ["fight_follow_min"] = ParseDouble(_pfFightFollowMinYalms.Text, 3),
            ["fight_follow_hold_s"] = ParseDouble(_pfFightFollowHoldS.Text, 8),
			["nyzul_coordinator_name"] = SelectedPartyName(_nyzulCoordinatorCombo),
			["nyzul_anchor_name"] = SelectedPartyName(_nyzulAnchorCombo),
			["nyzul_parking_order"] = string.Join("|", _nyzulParkingOrder),
            ["spacing_use_prediction"] = _spUsePrediction.Checked,
            ["spacing_band_min"] = ParseDouble(_spBandMin.Text, -0.9),
            ["spacing_band_max"] = ParseDouble(_spBandMax.Text, 0.4),
            ["spacing_model_size_floor"] = ParseDouble(_spModelSizeFloor.Text, 0.9),
            ["spacing_lookahead_s"] = ParseDouble(_spLookahead.Text, 0.25),
            ["spacing_repel_hold_ticks"] = ParseInt(_spAnchorInvalidTicks.Text, 5),
            ["spacing_overlap_deadband"] = ParseDouble(_spEmergencyMargin.Text, 0.1),
            ["spacing_repel_weight"] = ParseDouble(_spSwitchMargin.Text, 0.35),
            ["spacing_band_deadband"] = ParseDouble(_spArrivalTolerance.Text, 0.2),
            ["encounter_enabled"] = _encounterEnabled.Checked,
            ["encounter_id"] = EncounterIdValue(),
            ["encounter_water_damage"] = EncounterPolicyValue(_encounterWaterDamage),
            ["encounter_water_skillchain"] = EncounterPolicyValue(_encounterWaterSkillchain),
            ["encounter_repeat_action_wall"] = EncounterPolicyValue(_encounterRepeatActionWall),
            ["encounter_repeat_action_guard_s"] = (double)_encounterRepeatActionGuard.Value,
            ["kei_elemental_dealer_name"] = SelectedPartyName(_keiElementalDealer),
            ["kei_water_probe_spell"] = _keiWaterProbeSpell.Text.Trim(),
            ["kei_water_damage_spell"] = _keiWaterDamageSpell.Text.Trim(),
            ["kei_ice_probe_spell"] = _keiIceProbeSpell.Text.Trim(),
            ["kei_ice_damage_spell"] = _keiIceDamageSpell.Text.Trim(),
            ["kei_sustain_interval_s"] = (double)_keiSustainInterval.Value,
            ["kei_probe_timeout_s"] = (double)_keiProbeTimeout.Value,
            ["kei_fullers_target_distance"] = (double)_keiFullersTargetDistance.Value,
            ["kei_fullers_prearm_hpp_margin"] = (double)_keiFullersPrearmMargin.Value,
            ["formation_enabled"] = _formationEnabled.Checked,
            ["named_formations_enabled"] = _namedFormationsEnabled.Checked,
            ["named_formation_entries"] = BuildNamedFormationEntriesJson(),
            ["formation_encounter"] = FormationEncounterValue(),
            ["formation_mock_enabled"] = _formationMockEnabled.Checked,
            ["formation_mock_mob_name"] = _formationMockMobName.Text.Trim(),
            ["formation_role"] = FormationRoleValue(),
            ["formation_tank_name"] = SelectedPartyName(_formationTankName),
            ["formation_required_party_names"] = string.Join("|", SelectedFormationRequiredPartyNames()),
            ["formation_capture_stable_s"] = (double)_formationCaptureStable.Value,
            ["formation_capture_tolerance"] = (double)_formationCaptureTolerance.Value,
            ["formation_safe_radius"] = (double)_formationSafeRadius.Value,
            ["formation_tank_accept_radius"] = (double)_formationTankAcceptRadius.Value,
            ["formation_tank_return_radius"] = (double)_formationTankReturnRadius.Value,
            ["formation_dps_flank_angle_deg"] = (double)_formationDpsFlankAngle.Value,
            ["formation_dps_melee_radius"] = (double)_formationDpsMeleeRadius.Value,
            ["formation_dps_position_tolerance"] = (double)_formationDpsPositionTolerance.Value,
            ["formation_healer_preferred_radius"] = (double)_formationHealerPreferredRadius.Value,
            ["formation_healer_minimum_boss_distance"] = (double)_formationHealerMinimumBossDistance.Value,
            ["formation_healer_maximum_party_range"] = (double)_formationHealerMaximumPartyRange.Value,
            ["formation_healer_cone_half_angle_deg"] = (double)_formationHealerConeHalfAngle.Value,
            ["formation_healer_cone_safety_margin_deg"] = (double)_formationHealerConeSafetyMargin.Value,
            ["formation_healer_sample_step_deg"] = (double)_formationHealerSampleStep.Value,
            ["formation_placement_mode"] = FormationPlacementModeValue(),
            ["formation_anchor"] = FormationAnchorValue(),
            ["formation_anchor_member"] = SelectedPartyName(_formationAnchorMember),
            ["formation_axis_type"] = FormationAxisTypeValue(),
            ["formation_axis_member"] = SelectedPartyName(_formationAxisMember),
            ["formation_preferred_radius"] = (double)_formationPreferredRadius.Value,
            ["formation_minimum_radius"] = (double)_formationMinimumRadius.Value,
            ["formation_maximum_radius"] = (double)_formationMaximumRadius.Value,
            ["formation_preferred_angle_deg"] = (double)_formationPreferredAngle.Value,
            ["formation_allowed_angle_half_width_deg"] = (double)_formationAllowedAngleHalfWidth.Value,
            ["formation_radius_step"] = (double)_formationRadiusStep.Value,
            ["formation_angle_step_deg"] = (double)_formationAngleStep.Value,
            ["formation_hysteresis_start_distance"] = (double)_formationHysteresisStart.Value,
            ["formation_hysteresis_stop_distance"] = (double)_formationHysteresisStop.Value,
            ["formation_avoid_encounter_hazards"] = _formationAvoidEncounterHazards.Checked,
            ["formation_hazard_margin"] = (double)_formationHazardMargin.Value,
            ["formation_safe_origin_radius"] = (double)_formationSafeOriginRadius.Value,
            ["formation_minimum_boss_distance"] = (double)_formationMinimumBossDistance.Value,
            ["formation_maximum_boss_distance"] = (double)_formationMaximumBossDistance.Value,
            ["formation_maximum_party_range"] = (double)_formationMaximumPartyRange.Value,
            ["defensive_provider"] = _defProviderCombo.SelectedItem?.ToString() ?? "internal",
            ["defensive_critical_hpp"] = ParseInt(_defCrit.Text, 35),
            ["defensive_medium_hpp"] = ParseInt(_defMed.Text, 55),
            ["def_heal_min_tier_cure"] = ParseInt(_defHealMinTier.Text, 3),
            ["def_heal_max_tier_cure"] = ParseInt(_defHealMaxTier.Text, 4),
            ["def_heal_min_missing_hp"] = ParseInt(_defHealMinMissingHp.Text, 250),
            ["def_heal_ignore_trusts"] = _defHealIgnoreTrusts.Checked,
            ["defensive_overwrite_interval"] = ParseInt(_defOverwrite.Text, 150),
            ["defensive_buffs"] = _defBuffs.Text ?? "",
            ["defensive_targeted_buffs"] = _defTargetedBuffs.Text ?? "",
            ["cor_roll_1"] = _corRoll1Combo.SelectedItem?.ToString() ?? "",
            ["cor_roll_2"] = _corRoll2Combo.SelectedItem?.ToString() ?? "",
            ["cor_roll_options"] = string.Join("|", _corRollOptions),
            ["cor_crooked_roll_slot"] = _corCrookedRoll1.Checked ? 1 : (_corCrookedRoll2.Checked ? 2 : 0),
            ["cor_elevens"] = _corElevens.Checked,
            ["cor_luzaf_range_override"] = _corLuzafRangeOverride.Checked,
            ["cor_roll_range_selected"] = string.Join(
                "|",
                _corRangePartyPanel.Controls.OfType<CheckBox>()
                    .Where(c => c.Checked)
                    .Select(c => c.Tag?.ToString() ?? c.Text)
                    .Where(n => !string.IsNullOrWhiteSpace(n))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
            ),
            ["brd_maintenance_enabled"] = _brdEnabled.Checked,
            ["brd_songs"] = string.Join("|", _brdSongList.Items.Cast<object>().Select(x => x.ToString() ?? "")),
            ["brd_dummy_songs"] = string.Join("|", _brdDummyList.Items.Cast<object>().Select(x => x.ToString() ?? "")),
            ["brd_song_options"] = string.Join("|", _brdSongOptions),
            ["brd_use_nitro"] = _brdUseNitro.Checked,
			["brd_use_soul_voice"] = _brdUseSoulVoice.Checked,
            ["brd_use_clarion_call"] = _brdUseClarion.Checked,
            ["brd_use_marcato"] = _brdUseMarcato.Checked,
            ["brd_marcato_song"] = _brdUseMarcato.Checked ? (_brdMarcatoSong.SelectedItem?.ToString() ?? "") : "",
			["brd_targeted_songs"] = _brdTargetedSongs.Text,
			["brd_recovery_range_yalms"] = decimal.ToDouble(_brdRecoveryRangeYalms.Value),
			["brd_reposition_for_party_songs"] = _brdRepositionForPartySongs.Checked,
            ["brd_recovery_ignore_names"] = _brdRecoveryIgnoreNames.Text,
            ["summoner_enabled"] = _summonerEnabled.Checked,
            ["summoner_avatar"] = _summonerAvatar.SelectedItem?.ToString() ?? "",
            ["summoner_avatar_favor"] = _summonerAvatarFavor.Checked,
            ["summoner_ward_enabled"] = _summonerWardEnabled.Checked,
			["summoner_ward_action"] = summonerWardActions.FirstOrDefault() ?? "",
			["summoner_ward_actions"] = string.Join("|", summonerWardActions),
            ["summoner_engage_on_combat_start"] = _summonerEngage.Checked,
            ["summoner_rage_enabled"] = _summonerRageEnabled.Checked,
            ["summoner_rage_action"] = _summonerRageAction.SelectedItem?.ToString() ?? "",
            ["summoner_rage_usage"] = "on_cooldown",
            ["summoner_rage_target_hpp_above_enabled"] = _summonerRageTargetHppAboveEnabled.Checked,
            ["summoner_rage_target_hpp_above"] = decimal.ToInt32(_summonerRageTargetHppAbove.Value),
            ["summoner_rage_pet_tp_above_enabled"] = _summonerRagePetTpAboveEnabled.Checked,
            ["summoner_rage_pet_tp_above"] = decimal.ToInt32(_summonerRagePetTpAbove.Value),
            ["reaction_enabled"] = _reactionEnabled.Checked,
            ["reaction_rules"] = BuildReactionRulesJson(),
            ["ignore_entries"] = string.Join("|", _ignoreRows.Select(r => $"{r.Id}:{r.Name}")),
            ["partner_entries"] = string.Join("|", _partnerRows.Select(r => $"{r.Id}:{r.Name}")),
            ["target_ignore_entries"] = string.Join("|", _targetIgnoreRows.Select(r => $"{r.Slot}:{r.Name}")),
            ["add_priority_entries"] = string.Join("|", _addPriorityRows.Select(r => $"{r.Slot}:{r.Name}")),
            ["sleep_spell_entries"] = string.Join("|", _sleepSpellRows.Select(r => $"{r.Slot}:{r.Name}")),
            ["sleep_max_target_range"] = Math.Clamp(ParseDouble(_sleepMaxTargetRange.Text, 6), 0.1, 50.0),
            ["weaponskill"] = (_wsCombo.Text ?? "").Trim(),
            ["ws1"] = (_wsCombo.Text ?? "").Trim(),
            ["ws_mode"] = string.Equals(_wsModeCombo.SelectedItem?.ToString(), "Primary Only (No SC)", StringComparison.Ordinal) ? "primary_no_sc" : "smart",
            ["weaponskill_min_tp"] = decimal.ToInt32(_wsMinimumTp.Value),
            ["weaponskill_allow_aoe"] = _chkWsAllowAoe.Checked,
        };

        foreach (var key in HubUiConstants.BoolKeys)
        {
            profile[key] = ReadPersistedBoolValue(sid, key, running);
        }

        if (profile.TryGetPropertyValue("profile_v2_autoload", out var autoloadValue)
            && autoloadValue is JsonValue autoloadJson
            && autoloadJson.TryGetValue<bool>(out var autoloadEnabled)
            && autoloadEnabled == false)
        {
            profile.Remove("profile_v2_autoload");
        }
        if (profile.TryGetPropertyValue("profile_v2_auto_reload_on_change", out var autoReloadValue)
            && autoReloadValue is JsonValue autoReloadJson
            && autoReloadJson.TryGetValue<bool>(out var autoReloadEnabled)
            && autoReloadEnabled == false)
        {
            profile.Remove("profile_v2_auto_reload_on_change");
        }

        return profile;
    }

    private bool ReadPersistedBoolValue(string sid, string key, bool running)
    {
        if (string.Equals(key, "Start_Engine", StringComparison.Ordinal))
        {
            return running;
        }
        if (_boolChecks.TryGetValue(key, out var checkBox))
        {
            return checkBox.Checked;
        }
        if (!HubUiConstants.CompatibilityOnlyBoolKeys.Contains(key, StringComparer.Ordinal))
        {
            throw new InvalidOperationException($"Persisted boolean '{key}' has no UI or compatibility owner.");
        }
        if (!_compatibilityBoolBySid.TryGetValue(sid, out var compatibilityBools)
            || !compatibilityBools.TryGetValue(key, out var value))
        {
            throw new InvalidOperationException($"Compatibility boolean '{key}' is unavailable for session '{sid}'.");
        }
        return value;
    }

    private JsonArray BuildReactionRulesJson()
    {
        var rules = new JsonArray();
        foreach (var rule in _reactionRules)
        {
            var serialized = new JsonObject
            {
                ["trigger"] = rule.Trigger,
                ["name"] = rule.Name,
                ["response"] = rule.Response,
            };
            if (rule.Response is "run_away" or "move_to_range")
            {
                if (!rule.Distance.HasValue || !double.IsFinite(rule.Distance.Value) || rule.Distance.Value <= 0)
                {
                    throw new InvalidDataException($"{rule.Response} reaction requires a positive finite distance");
                }
                serialized["distance"] = rule.Distance.Value;
            }
            rules.Add(serialized);
        }
        return rules;
    }

    private JsonArray BuildNamedFormationEntriesJson()
    {
        var entries = new JsonArray();
        foreach (var formation in _namedFormations)
        {
            var serialized = (JsonObject)formation.Geometry.DeepClone();
            serialized["mob_name"] = formation.MobName;
            entries.Add(serialized);
        }
        return entries;
    }

    private static int ParseInt(string? text, int fallback)
    {
        return int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : fallback;
    }

    private static double ParseDouble(string? text, double fallback)
    {
        return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var n) ? n : fallback;
    }

    private JsonObject BuildDefaultProfile(string sid)
    {
        var partyNames = CurrentPartyNameOptions();
        var p = new JsonObject
        {
            ["profile_schema_version"] = ProfileSchemaVersion,
            ["engine"] = GetEngineForSid(sid),
            ["Start_Engine"] = false,
            ["ability_options"] = "",
            ["weaponskill_options"] = "",
            ["path_pull_ja_options"] = "",
            ["path_pull_spell_options"] = "",
            ["partner_options"] = string.Join("|", partyNames),
            ["puller_options"] = string.Join("|", partyNames),
            ["abilities_selected"] = "",
            ["weaponskill"] = "",
            ["ws1"] = "",
            ["ws_mode"] = "smart",
            ["weaponskill_min_tp"] = 1000,
            ["weaponskill_allow_aoe"] = true,
            ["aftermath_ws"] = "",
            ["defensive_provider"] = "internal",
            ["defensive_critical_hpp"] = 35,
            ["defensive_medium_hpp"] = 55,
            ["def_heal_min_tier_cure"] = 3,
            ["def_heal_max_tier_cure"] = 4,
            ["def_heal_min_missing_hp"] = 250,
            ["def_heal_ignore_trusts"] = true,
            ["defensive_overwrite_interval"] = 150,
            ["defensive_buffs"] = "",
            ["defensive_targeted_buffs"] = "",
            ["party_follow_min"] = 0.5,
            ["party_follow_max"] = 50,
            ["fight_follow_min"] = 3,
            ["fight_follow_hold_s"] = 8,
			["nyzul_coordinator_name"] = "",
			["nyzul_anchor_name"] = "",
			["nyzul_parking_order"] = "",
            ["puller_engage_range"] = 6,
			["puller_leash_source"] = "player",
            ["path_route_type"] = "unknown",
            ["path_distance_to_start"] = 0,
            ["path_points_count"] = 0,
            ["path_party_gate_yalms"] = 3,
            ["path_resume_index_window"] = 12,
            ["path_hunter_max_z_delta"] = 2,
            ["path_hunter_max_target_range"] = 20,
            ["path_hunter_claim_timeout_s"] = 4,
            ["path_hunter_ignore_cooldown_s"] = 20,
            ["path_pull_action_type"] = "ja",
            ["path_pull_action_name"] = "",
            ["geo_maintenance_enabled"] = false,
            ["geo_spell"] = "",
            ["indi_spell"] = "",
            ["geo_target_kind"] = "current_enemy",
            ["geo_target_name"] = "",
            ["geo_ordering"] = "geo_first",
            ["geo_require_camp"] = true,
            ["geo_camp_tolerance_yalms"] = 1.0,
            ["geo_entrust_enabled"] = false,
            ["geo_entrust_spell"] = "",
            ["geo_entrust_target_name"] = "",
            ["geo_use_blaze_of_glory"] = false,
            ["geo_use_ecliptic_attrition"] = false,
            ["geo_use_life_cycle"] = false,
            ["geo_life_cycle_hpp"] = 50,
            ["geo_replace_out_of_position"] = false,
            ["geo_enemy_requires_camp_radius"] = false,
            ["geo_max_camp_distance_yalms"] = 6.0,
            ["camp_pulling_enabled"] = false,
            ["camp_pulling_action_type"] = "spell",
            ["camp_pulling_action_name"] = "",
            ["camp_pulling_targets"] = "",
            ["camp_pulling_match_mode"] = "exact",
            ["camp_pulling_max_active_mobs"] = 1,
            ["camp_pulling_replenish_below_hpp"] = 20,
            ["camp_pulling_leash_yalms"] = 35.0,
            ["camp_pulling_max_z_delta"] = 2.0,
            ["camp_pulling_cast_range_ratio"] = 0.9,
            ["camp_pulling_settle_seconds"] = 0.4,
            ["camp_pulling_reaction_timeout_seconds"] = 4.0,
            ["camp_pulling_retry_limit"] = 2,
            ["camp_pulling_retry_window_seconds"] = 2.5,
            ["camp_pulling_target_cooldown_seconds"] = 20.0,
            ["camp_pulling_camp_arrival_yalms"] = 0.75,
            ["path_hunter_entries"] = "",
            ["tank_enmity_actions"] = "",
            ["ignore_entries"] = "",
            ["partner_entries"] = "",
            ["target_ignore_entries"] = "",
            ["add_priority_entries"] = "",
            ["sleep_spell_entries"] = "1:Horde Lullaby II",
            ["sleep_max_target_range"] = 6,
            ["cor_roll_1"] = "",
            ["cor_roll_2"] = "",
            ["cor_roll_options"] = "",
            ["cor_crooked_roll_slot"] = 0,
            ["cor_elevens"] = false,
            ["cor_luzaf_range_override"] = false,
            ["cor_roll_range_selected"] = "",
            ["brd_maintenance_enabled"] = false,
            ["brd_songs"] = "",
            ["brd_dummy_songs"] = "",
            ["brd_song_options"] = "",
            ["brd_use_nitro"] = false,
			["brd_use_soul_voice"] = false,
            ["brd_use_clarion_call"] = false,
            ["brd_use_marcato"] = false,
            ["brd_marcato_song"] = "",
			["brd_targeted_songs"] = "",
			["brd_recovery_range_yalms"] = 9.9,
			["brd_reposition_for_party_songs"] = false,
			["brd_recovery_ignore_names"] = "",
            ["summoner_enabled"] = false,
            ["summoner_avatar"] = "",
            ["summoner_avatar_favor"] = false,
            ["summoner_ward_enabled"] = false,
            ["summoner_ward_action"] = "",
			["summoner_ward_actions"] = "",
            ["summoner_engage_on_combat_start"] = false,
            ["summoner_rage_enabled"] = false,
            ["summoner_rage_action"] = "",
            ["summoner_rage_usage"] = "on_cooldown",
            ["summoner_rage_target_hpp_above_enabled"] = false,
            ["summoner_rage_target_hpp_above"] = 50,
            ["summoner_rage_pet_tp_above_enabled"] = false,
            ["summoner_rage_pet_tp_above"] = 2000,
            ["reaction_enabled"] = false,
            ["reaction_rules"] = new JsonArray(),
            ["spacing_band_min"] = -0.9,
            ["spacing_band_max"] = 0.4,
            ["spacing_model_size_floor"] = 0.9,
            ["spacing_use_prediction"] = true,
            ["spacing_lookahead_s"] = 0.25,
            ["spacing_repel_hold_ticks"] = 5,
            ["spacing_overlap_deadband"] = 0.1,
            ["spacing_repel_weight"] = 0.35,
            ["spacing_band_deadband"] = 0.2,
            ["encounter_enabled"] = false,
            ["encounter_id"] = "sortie_ghatjot",
            ["encounter_water_damage"] = "enforce",
            ["encounter_water_skillchain"] = "enforce",
            ["encounter_repeat_action_wall"] = "off",
            ["encounter_repeat_action_guard_s"] = 10.0,
            ["kei_elemental_dealer_name"] = "",
            ["kei_water_probe_spell"] = "Water",
            ["kei_water_damage_spell"] = "Water III",
            ["kei_ice_probe_spell"] = "Blizzard",
            ["kei_ice_damage_spell"] = "Blizzard III",
            ["kei_sustain_interval_s"] = 2.5,
            ["kei_probe_timeout_s"] = 3.0,
            ["kei_fullers_target_distance"] = 12.0,
            ["kei_fullers_prearm_hpp_margin"] = 1.0,
            ["formation_enabled"] = false,
            ["named_formations_enabled"] = false,
            ["named_formation_entries"] = new JsonArray(),
            ["formation_encounter"] = "lilith_easy",
            ["formation_mock_enabled"] = false,
            ["formation_mock_mob_name"] = "",
            ["formation_role"] = "disabled",
            ["formation_tank_name"] = "",
            ["formation_required_party_names"] = "",
            ["formation_capture_stable_s"] = 0.5,
            ["formation_capture_tolerance"] = 0.1,
            ["formation_safe_radius"] = 16.0,
            ["formation_tank_accept_radius"] = 1.5,
            ["formation_tank_return_radius"] = 3.0,
            ["formation_dps_flank_angle_deg"] = 90.0,
            ["formation_dps_melee_radius"] = 3.0,
            ["formation_dps_position_tolerance"] = 1.5,
            ["formation_healer_preferred_radius"] = 12.0,
            ["formation_healer_minimum_boss_distance"] = 8.0,
            ["formation_healer_maximum_party_range"] = 18.0,
            ["formation_healer_cone_half_angle_deg"] = 50.0,
            ["formation_healer_cone_safety_margin_deg"] = 15.0,
            ["formation_healer_sample_step_deg"] = 10.0,
            ["formation_placement_mode"] = "radial_band",
            ["formation_anchor"] = "boss",
            ["formation_anchor_member"] = "",
            ["formation_axis_type"] = "boss_to_member",
            ["formation_axis_member"] = "",
            ["formation_preferred_radius"] = 3.0,
            ["formation_minimum_radius"] = 2.0,
            ["formation_maximum_radius"] = 4.0,
            ["formation_preferred_angle_deg"] = 180.0,
            ["formation_allowed_angle_half_width_deg"] = 60.0,
            ["formation_radius_step"] = 0.5,
            ["formation_angle_step_deg"] = 10.0,
            ["formation_hysteresis_start_distance"] = 1.0,
            ["formation_hysteresis_stop_distance"] = 0.5,
            ["formation_avoid_encounter_hazards"] = false,
            ["formation_hazard_margin"] = 0.0,
            ["formation_safe_origin_radius"] = 0.0,
            ["formation_minimum_boss_distance"] = 0.0,
            ["formation_maximum_boss_distance"] = 0.0,
            ["formation_maximum_party_range"] = 0.0,
        };
        foreach (var key in HubUiConstants.BoolKeys)
        {
            p[key] = false;
        }
        foreach (var key in RequiredDomainBoolKeys)
        {
            p[key] = true;
        }

        return p;
    }

    private bool TryLoadProfileForSid(string sid, out JsonDocument doc)
    {
        if (!TryProfilePathForSid(sid, out var path))
        {
            doc = null!;
            return false;
        }
        try
        {
            if (!TryMigrateLegacyUiProfileForSid(sid, path, out _))
            {
                doc = null!;
                return false;
            }
            if (File.Exists(path))
            {
                var text = File.ReadAllText(path);
                var node = JsonNode.Parse(text) as JsonObject ?? new JsonObject();
                if (MigrateProfileInPlace(node))
                {
                    File.WriteAllText(path, node.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
                }
                doc = JsonDocument.Parse(node.ToJsonString());
                return true;
            }

            var def = BuildDefaultProfile(sid);
            File.WriteAllText(path, def.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            doc = JsonDocument.Parse(def.ToJsonString());
            return true;
        }
        catch
        {
            doc = null!;
            return false;
        }
    }

    private bool TryLoadWorkingProfileForSid(string sid, out JsonDocument doc)
    {
        try
        {
            if (_workingProfileBySid.TryGetValue(sid, out var obj))
            {
                doc = JsonDocument.Parse(obj.ToJsonString());
                return true;
            }
        }
        catch
        {
            // fall through
        }

        doc = null!;
        return false;
    }

    private void CaptureWorkingProfileFromUi(string sid)
    {
        try
        {
            var obj = BuildProfileFromUi(sid);
            if (obj.DeepClone() is JsonObject clone)
            {
                _workingProfileBySid[sid] = clone;
            }
            else
            {
                _workingProfileBySid[sid] = obj;
            }
        }
        catch
        {
            // keep UI responsive
        }
    }

    private bool TrySaveProfileFromUi(string sid, JsonObject profile, out string error)
    {
        try
        {
            if (!TryProfilePathForSid(sid, out var path))
            {
                error = "UI profile path unavailable";
                return false;
            }
            File.WriteAllText(path, profile.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            _workingProfileBySid[sid] = profile.DeepClone().AsObject();
            error = "";
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private bool TryResolveStructuredProfileV2Root(out string addonRoot, out string error)
    {
        var baseDir = AppContext.BaseDirectory;
        var resolved = StructuredProfileV2Writer.FindAddonRootFrom(baseDir);
        if (resolved is null)
        {
            addonRoot = "";
            error = "addon root unavailable";
            return false;
        }

        addonRoot = resolved;
        error = "";
        return true;
    }

    private bool TrySaveStructuredProfileV2FromUi(string sid, JsonObject flatProfile, out string error)
    {
        try
        {
            if (!_sessionMetaBySid.TryGetValue(sid, out var meta))
            {
                error = "session metadata unavailable";
                return false;
            }

            var charName = (meta.CharName ?? "").Trim();
            var mainJob = (meta.Job ?? "").Trim();
            var subJob = (meta.SubJob ?? "").Trim();
            if (string.IsNullOrWhiteSpace(charName) || string.IsNullOrWhiteSpace(mainJob) || string.IsNullOrWhiteSpace(subJob))
            {
                error = "character, main job, or subjob unavailable";
                return false;
            }

            if (!TryResolveStructuredProfileV2Root(out var addonRoot, out var rootErr))
            {
                error = rootErr;
                return false;
            }

            var identity = new StructuredProfileV2Identity(charName, mainJob, subJob);
            var result = StructuredProfileV2Writer.TryWriteStructuredProfile(addonRoot, flatProfile, identity);
            if (!result.Ok)
            {
                error = $"{result.Error}: {result.Detail}";
                return false;
            }

            error = "";
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    internal static bool MigrateProfileInPlace(JsonObject root)
    {
        var changed = false;
        var schema = 0;
        if (root.TryGetPropertyValue("profile_schema_version", out var v) && v is not null)
        {
            if (v is JsonValue jv && jv.TryGetValue<int>(out var parsed))
            {
                schema = parsed;
            }
        }

        if (schema >= ProfileSchemaVersion)
        {
            return false;
        }

        static void MoveIfMissing(JsonObject obj, string oldKey, string newKey, ref bool dirty)
        {
            if (obj.ContainsKey(newKey))
            {
                if (obj.Remove(oldKey))
                {
                    dirty = true;
                }
                return;
            }
            if (obj.TryGetPropertyValue(oldKey, out var val) && val is not null)
            {
                obj[newKey] = val.DeepClone();
                obj.Remove(oldKey);
                dirty = true;
            }
        }

        MoveIfMissing(root, "spacing_slot_arrival_tolerance", "spacing_band_deadband", ref changed);
        MoveIfMissing(root, "spacing_slot_switch_margin", "spacing_repel_weight", ref changed);
        MoveIfMissing(root, "spacing_emergency_margin", "spacing_overlap_deadband", ref changed);
        MoveIfMissing(root, "spacing_anchor_invalid_ticks", "spacing_repel_hold_ticks", ref changed);

        if (root.TryGetPropertyValue("kei_fullers_run_away_distance", out var legacyFullersDistance)
            && legacyFullersDistance is not null)
        {
            if (root.TryGetPropertyValue("kei_fullers_target_distance", out var targetFullersDistance)
                && targetFullersDistance is not null
                && !JsonNode.DeepEquals(targetFullersDistance, legacyFullersDistance))
            {
                throw new InvalidDataException(
                    "kei_fullers_target_distance conflicts with legacy alias kei_fullers_run_away_distance"
                );
            }
            if (!root.ContainsKey("kei_fullers_target_distance"))
            {
                root["kei_fullers_target_distance"] = legacyFullersDistance.DeepClone();
            }
            root.Remove("kei_fullers_run_away_distance");
            changed = true;
        }

        if (root.Remove("spacing_slot_switch_penalty"))
        {
            changed = true;
        }
        if (root.Remove("spacing_max_agents"))
        {
            changed = true;
        }
        if (root.Remove("spacing_global_anchor_enabled"))
        {
            changed = true;
        }
        if (root.Remove("spacing_global_anchor_name"))
        {
            changed = true;
        }

        if (!root.ContainsKey("spacing_use_prediction"))
        {
            root["spacing_use_prediction"] = true;
            changed = true;
        }
        if (!root.ContainsKey("spacing_band_min"))
        {
            root["spacing_band_min"] = -0.9;
            changed = true;
        }
        if (!root.ContainsKey("spacing_band_max"))
        {
            root["spacing_band_max"] = 0.4;
            changed = true;
        }
        if (!root.ContainsKey("spacing_model_size_floor"))
        {
            root["spacing_model_size_floor"] = 0.9;
            changed = true;
        }
        if (!root.ContainsKey("spacing_lookahead_s"))
        {
            root["spacing_lookahead_s"] = 0.25;
            changed = true;
        }
        if (!root.ContainsKey("spacing_repel_hold_ticks"))
        {
            root["spacing_repel_hold_ticks"] = 5;
            changed = true;
        }
        if (!root.ContainsKey("spacing_overlap_deadband"))
        {
            root["spacing_overlap_deadband"] = 0.1;
            changed = true;
        }
        if (!root.ContainsKey("spacing_repel_weight"))
        {
            root["spacing_repel_weight"] = 0.35;
            changed = true;
        }
        if (!root.ContainsKey("spacing_band_deadband"))
        {
            root["spacing_band_deadband"] = 0.2;
            changed = true;
        }

        if (!root.ContainsKey("sleep_spell_entries"))
        {
            var migratedSleep = new List<string>();
            if (root.TryGetPropertyValue("sleepspells", out var sleepListNode) && sleepListNode is JsonArray sleepArray)
            {
                for (var i = 0; i < sleepArray.Count; i++)
                {
                    var raw = sleepArray[i]?.GetValue<string>() ?? "";
                    var trimmed = raw.Trim();
                    if (trimmed.Length > 0)
                    {
                        migratedSleep.Add(trimmed);
                    }
                }
            }
            if (migratedSleep.Count == 0 && root.TryGetPropertyValue("sleepspell", out var sleepNode) && sleepNode is not null)
            {
                var raw = sleepNode.GetValue<string>() ?? "";
                var trimmed = raw.Trim();
                if (trimmed.Length > 0)
                {
                    migratedSleep.Add(trimmed);
                }
            }
            if (migratedSleep.Count == 0)
            {
                migratedSleep.Add("Horde Lullaby II");
            }
            root["sleep_spell_entries"] = string.Join("|", migratedSleep.Select((name, idx) => $"{idx + 1}:{name}"));
            changed = true;
        }

        if (schema < 3)
        {
            foreach (var key in RequiredDomainBoolKeys)
            {
                if (!root.ContainsKey(key))
                {
                    root[key] = true;
                    changed = true;
                }
            }

            foreach (var retiredKey in new[]
            {
                "scheduler_dark_launch_combat",
                "scheduler_dark_launch_defensive",
                "scheduler_dark_launch_movement",
                "scheduler_dark_launch_maintenance",
            })
            {
                if (root.Remove(retiredKey))
                {
                    changed = true;
                }
            }
        }

        if (!root.TryGetPropertyValue("profile_schema_version", out var sv) || sv is null || !(sv is JsonValue svv && svv.TryGetValue<int>(out var sver) && sver == ProfileSchemaVersion))
        {
            root["profile_schema_version"] = ProfileSchemaVersion;
            changed = true;
        }

        return changed;
    }
}
