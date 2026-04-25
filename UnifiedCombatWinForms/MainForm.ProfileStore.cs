using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
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

    private string ProfilePathForSid(string sid)
    {
        if (!_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            return Path.Combine(ProfileRootDir, $"sid_{SafeToken(sid)}.json");
        }

        var ch = SafeToken(meta.CharName);
        var job = SafeToken(meta.Job);
        return Path.Combine(ProfileRootDir, $"{ch}_{job}.json");
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
        var profile = new JsonObject
        {
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
            ["puller_selected"] = _pullerCombo.SelectedItem?.ToString() ?? "",
            ["fight_leader_selected"] = _fightLeaderCombo.SelectedItem?.ToString() ?? "",
            ["party_follow_selected"] = _partyFollowCombo.SelectedItem?.ToString() ?? "",
            ["party_follow_min"] = ParseDouble(_pfFollowMinYalms.Text, 0.5),
            ["party_follow_max"] = ParseDouble(_pfFollowMaxYalms.Text, 50),
            ["fight_follow_min"] = ParseDouble(_pfFightFollowMinYalms.Text, 3),
            ["fight_follow_hold_s"] = ParseDouble(_pfFightFollowHoldS.Text, 8),
            ["spacing_use_prediction"] = _spUsePrediction.Checked,
            ["spacing_band_min"] = ParseDouble(_spBandMin.Text, -0.9),
            ["spacing_band_max"] = ParseDouble(_spBandMax.Text, 0.4),
            ["spacing_model_size_floor"] = ParseDouble(_spModelSizeFloor.Text, 0.9),
            ["spacing_lookahead_s"] = ParseDouble(_spLookahead.Text, 0.25),
            ["spacing_anchor_invalid_ticks"] = ParseInt(_spAnchorInvalidTicks.Text, 5),
            ["spacing_emergency_margin"] = ParseDouble(_spEmergencyMargin.Text, 0.1),
            ["spacing_slot_switch_penalty"] = ParseDouble(_spSwitchPenalty.Text, 0.75),
            ["spacing_slot_switch_margin"] = ParseDouble(_spSwitchMargin.Text, 0.35),
            ["spacing_slot_arrival_tolerance"] = ParseDouble(_spArrivalTolerance.Text, 0.2),
            ["spacing_max_agents"] = ParseInt(_spMaxAgents.Text, 6),
            ["defensive_provider"] = _defProviderCombo.SelectedItem?.ToString() ?? "internal",
            ["defensive_critical_hpp"] = ParseInt(_defCrit.Text, 35),
            ["defensive_medium_hpp"] = ParseInt(_defMed.Text, 55),
            ["defensive_overwrite_interval"] = ParseInt(_defOverwrite.Text, 150),
            ["defensive_buffs"] = _defBuffs.Text ?? "",
            ["cor_roll_1"] = _corRoll1Combo.SelectedItem?.ToString() ?? "",
            ["cor_roll_2"] = _corRoll2Combo.SelectedItem?.ToString() ?? "",
            ["ignore_entries"] = string.Join("|", _ignoreRows.Select(r => $"{r.Id}:{r.Name}")),
            ["partner_entries"] = string.Join("|", _partnerRows.Select(r => $"{r.Id}:{r.Name}")),
            ["target_ignore_entries"] = string.Join("|", _targetIgnoreRows.Select(r => $"{r.Slot}:{r.Name}")),
            ["add_priority_entries"] = string.Join("|", _addPriorityRows.Select(r => $"{r.Slot}:{r.Name}")),
            ["weaponskill"] = (_wsCombo.Text ?? "").Trim(),
            ["ws1"] = (_wsCombo.Text ?? "").Trim(),
        };

        foreach (var key in HubUiConstants.BoolKeys)
        {
            profile[key] = _boolChecks.TryGetValue(key, out var cb) && cb.Checked;
        }

        return profile;
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
            ["aftermath_ws"] = "",
            ["defensive_provider"] = "internal",
            ["defensive_critical_hpp"] = 35,
            ["defensive_medium_hpp"] = 55,
            ["defensive_overwrite_interval"] = 150,
            ["defensive_buffs"] = "",
            ["party_follow_min"] = 0.5,
            ["party_follow_max"] = 50,
            ["fight_follow_min"] = 3,
            ["fight_follow_hold_s"] = 8,
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
            ["path_hunter_entries"] = "",
            ["tank_enmity_actions"] = "",
            ["ignore_entries"] = "",
            ["partner_entries"] = "",
            ["target_ignore_entries"] = "",
            ["add_priority_entries"] = "",
            ["cor_roll_1"] = "",
            ["cor_roll_2"] = "",
            ["spacing_band_min"] = -0.9,
            ["spacing_band_max"] = 0.4,
            ["spacing_model_size_floor"] = 0.9,
            ["spacing_use_prediction"] = true,
            ["spacing_lookahead_s"] = 0.25,
            ["spacing_anchor_invalid_ticks"] = 5,
            ["spacing_emergency_margin"] = 0.1,
            ["spacing_slot_switch_penalty"] = 0.75,
            ["spacing_slot_switch_margin"] = 0.35,
            ["spacing_slot_arrival_tolerance"] = 0.2,
            ["spacing_max_agents"] = 6,
        };
        foreach (var key in HubUiConstants.BoolKeys)
        {
            p[key] = false;
        }

        return p;
    }

    private bool TryLoadProfileForSid(string sid, out JsonDocument doc)
    {
        var path = ProfilePathForSid(sid);
        try
        {
            if (File.Exists(path))
            {
                doc = JsonDocument.Parse(File.ReadAllText(path));
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

    private void TrySaveProfileFromUi(string sid)
    {
        try
        {
            CaptureWorkingProfileFromUi(sid);
            var path = ProfilePathForSid(sid);
            var obj = BuildProfileFromUi(sid);
            File.WriteAllText(path, obj.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // keep UI responsive
        }
    }

    private void LoadGlobalUiSettings()
    {
        bool enabled = false;
        string member = "";
        try
        {
            var path = GlobalUiSettingsPath;
            if (File.Exists(path))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                var root = doc.RootElement;
                enabled = SessionStateHelper.GetBool(root, "spacing_global_anchor_enabled", false);
                member = SessionStateHelper.GetString(root, "spacing_global_anchor_name", "");
            }
        }
        catch
        {
            enabled = false;
            member = "";
        }

        _suppressEvents = true;
        try
        {
            _spGlobalAnchorEnabled.Checked = enabled;
            if (_spGlobalAnchorMember.Items.Count == 0)
            {
                _spGlobalAnchorMember.Items.Add("");
            }

            var match = -1;
            for (var i = 0; i < _spGlobalAnchorMember.Items.Count; i++)
            {
                if (string.Equals(_spGlobalAnchorMember.Items[i]?.ToString() ?? "", member, StringComparison.Ordinal))
                {
                    match = i;
                    break;
                }
            }

            _spGlobalAnchorMember.SelectedIndex = match >= 0 ? match : 0;
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void SaveGlobalUiSettings()
    {
        try
        {
            var obj = new JsonObject
            {
                ["spacing_global_anchor_enabled"] = _spGlobalAnchorEnabled.Checked,
                ["spacing_global_anchor_name"] = (_spGlobalAnchorMember.SelectedItem?.ToString() ?? "").Trim(),
            };
            File.WriteAllText(GlobalUiSettingsPath, obj.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // keep UI responsive
        }
    }
}
