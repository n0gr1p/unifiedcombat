using System.Globalization;
using System.Text.Json;
using UnifiedCombatWinForms.Ui;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private void OnGeoPullConfigChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateGeoPullUiState();
        var sid = RequireSelectedSid();
        if (sid is not null)
        {
            CaptureWorkingProfileFromUi(sid);
        }
    }

    private void ApplyGeoPullRuntimeStatus(JsonElement state)
    {
        if (!state.TryGetProperty("geo_runtime_state", out _))
        {
            _geoRuntimeStatus.Text = "Runtime: unavailable";
        }
        else
        {
            _geoRuntimeStatus.Text = string.Format(
                CultureInfo.InvariantCulture,
                "Runtime: {0} — {1} ({2})",
                SessionStateHelper.GetString(state, "geo_runtime_state", "unknown"),
                SessionStateHelper.GetString(state, "geo_runtime_reason", ""),
                SessionStateHelper.GetString(state, "geo_runtime_detail", "")
            );
        }

        if (!state.TryGetProperty("camp_pull_runtime_state", out _))
        {
            _campPullRuntimeStatus.Text = "Runtime: unavailable";
            return;
        }
        _campPullRuntimeStatus.Text = string.Format(
            CultureInfo.InvariantCulture,
            "Runtime: {0} — {1} ({2}); target {3}:{4}; active {5}/{6}; intent {7}",
            SessionStateHelper.GetString(state, "camp_pull_runtime_state", "unknown"),
            SessionStateHelper.GetString(state, "camp_pull_runtime_reason", ""),
            SessionStateHelper.GetString(state, "camp_pull_runtime_detail", ""),
            SessionStateHelper.GetString(state, "camp_pull_runtime_target_id", "0"),
            SessionStateHelper.GetString(state, "camp_pull_runtime_target_name", ""),
            SessionStateHelper.GetString(state, "camp_pull_runtime_active_count", "0"),
            SessionStateHelper.GetString(state, "camp_pull_runtime_quota", "0"),
            SessionStateHelper.GetString(state, "camp_pull_runtime_intent", "")
        );
    }

    private void UpdateGeoPullUiState()
    {
        var geoEnabled = _geoEnabled.Checked;
        var campPlacement = string.Equals(
            _geoLuopanPlacement.SelectedItem?.ToString(),
            "Camp",
            StringComparison.Ordinal
        );
        if (campPlacement && !_geoRequireCamp.Checked)
        {
            var wasSuppressed = _suppressEvents;
            _suppressEvents = true;
            try
            {
                _geoRequireCamp.Checked = true;
            }
            finally
            {
                _suppressEvents = wasSuppressed;
            }
        }
        _geoSpell.Enabled = geoEnabled;
        _indiSpell.Enabled = geoEnabled;
        _geoTargetKind.Enabled = geoEnabled;
        _geoTargetName.Enabled = geoEnabled
            && string.Equals(_geoTargetKind.SelectedItem?.ToString(), "party_member", StringComparison.Ordinal);
        _geoOrdering.Enabled = geoEnabled;
        _geoLuopanPlacement.Enabled = geoEnabled;
        _geoRequireCamp.Enabled = geoEnabled && !campPlacement;
        _geoCampTolerance.Enabled = geoEnabled && _geoRequireCamp.Checked;
        _geoEntrustEnabled.Enabled = geoEnabled;
        _geoEntrustSpell.Enabled = geoEnabled && _geoEntrustEnabled.Checked;
        _geoEntrustTarget.Enabled = geoEnabled && _geoEntrustEnabled.Checked;
        _geoUseBlaze.Enabled = geoEnabled;
        _geoUseEcliptic.Enabled = geoEnabled;
        _geoUseLifeCycle.Enabled = geoEnabled;
        _geoLifeCycleHpp.Enabled = geoEnabled && _geoUseLifeCycle.Checked;
        _geoReplaceOutOfPosition.Enabled = geoEnabled && campPlacement;
        _geoEnemyRequiresCampRadius.Enabled = geoEnabled
            && string.Equals(_geoTargetKind.SelectedItem?.ToString(), "current_enemy", StringComparison.Ordinal);
        _geoMaxCampDistance.Enabled = geoEnabled
            && ((campPlacement && _geoReplaceOutOfPosition.Checked)
                || _geoEnemyRequiresCampRadius.Checked);

        var pullEnabled = _campPullEnabled.Checked;
        _campPullActionType.Enabled = pullEnabled;
        _campPullActionName.Enabled = pullEnabled;
        _campPullTargets.Enabled = pullEnabled;
        _campPullMatchMode.Enabled = pullEnabled;
        _campPullMaxActive.Enabled = pullEnabled;
        _campPullReplenishHpp.Enabled = pullEnabled;
        _campPullLeash.Enabled = pullEnabled;
        _campPullMaxZ.Enabled = pullEnabled;
        _campPullRangeRatio.Enabled = pullEnabled;
        _campPullSettle.Enabled = pullEnabled;
        _campPullReactionTimeout.Enabled = pullEnabled;
        _campPullRetryLimit.Enabled = pullEnabled;
        _campPullRetryWindow.Enabled = pullEnabled;
        _campPullCooldown.Enabled = pullEnabled;
        _campPullArrival.Enabled = pullEnabled;
    }

    private void ResetGeoPullUi()
    {
        _geoEnabled.Checked = false;
        _geoSpell.Text = "";
        _indiSpell.Text = "";
        _geoTargetKind.SelectedItem = "current_enemy";
        _geoTargetName.Text = "";
        _geoOrdering.SelectedItem = "geo_first";
        _geoLuopanPlacement.SelectedItem = "Target";
        _geoRequireCamp.Checked = true;
        _geoCampTolerance.Value = 1m;
        _geoEntrustEnabled.Checked = false;
        _geoEntrustSpell.Text = "";
        _geoEntrustTarget.Text = "";
        _geoUseBlaze.Checked = false;
        _geoUseEcliptic.Checked = false;
        _geoUseLifeCycle.Checked = false;
        _geoLifeCycleHpp.Value = 50m;
        _geoReplaceOutOfPosition.Checked = false;
        _geoEnemyRequiresCampRadius.Checked = false;
        _geoMaxCampDistance.Value = 6m;

        _campPullEnabled.Checked = false;
        _campPullActionType.SelectedItem = "spell";
        _campPullActionName.Text = "";
        _campPullTargets.Text = "";
        _campPullMatchMode.SelectedItem = "exact";
        _campPullMaxActive.Value = 1m;
        _campPullReplenishHpp.Value = 20m;
        _campPullLeash.Value = 35m;
        _campPullMaxZ.Value = 2m;
        _campPullRangeRatio.Value = 0.9m;
        _campPullSettle.Value = 0.4m;
        _campPullReactionTimeout.Value = 4m;
        _campPullRetryLimit.Value = 2m;
        _campPullRetryWindow.Value = 2.5m;
        _campPullCooldown.Value = 20m;
        _campPullArrival.Value = 0.75m;
        _geoRuntimeStatus.Text = "Runtime: unavailable";
        _campPullRuntimeStatus.Text = "Runtime: unavailable";
        UpdateGeoPullUiState();
    }

    private void ApplyGeoPullFromSnapshot(JsonElement snapshot)
    {
        _geoEnabled.Checked = ReadProfileBool(snapshot, "geo_maintenance_enabled", false);
        _geoSpell.Text = SessionStateHelper.GetString(snapshot, "geo_spell");
        _indiSpell.Text = SessionStateHelper.GetString(snapshot, "indi_spell");
        SelectRequiredValue(
            _geoTargetKind,
            SessionStateHelper.GetString(snapshot, "geo_target_kind", "current_enemy"),
            "geo_target_kind"
        );
        _geoTargetName.Text = SessionStateHelper.GetString(snapshot, "geo_target_name");
        SelectRequiredValue(
            _geoOrdering,
            SessionStateHelper.GetString(snapshot, "geo_ordering", "geo_first"),
            "geo_ordering"
        );
        var placement = SessionStateHelper.GetString(snapshot, "geo_luopan_placement", "target");
        SelectRequiredValue(
            _geoLuopanPlacement,
            placement switch
            {
                "target" => "Target",
                "camp" => "Camp",
                _ => throw new InvalidDataException($"Unsupported geo_luopan_placement value '{placement}'."),
            },
            "geo_luopan_placement"
        );
        _geoRequireCamp.Checked = ReadProfileBool(snapshot, "geo_require_camp", true);
        SetProfileNumber(_geoCampTolerance, ReadProfileDecimal(snapshot, "geo_camp_tolerance_yalms", 1m));
        _geoEntrustEnabled.Checked = ReadProfileBool(snapshot, "geo_entrust_enabled", false);
        _geoEntrustSpell.Text = SessionStateHelper.GetString(snapshot, "geo_entrust_spell");
        _geoEntrustTarget.Text = SessionStateHelper.GetString(snapshot, "geo_entrust_target_name");
        _geoUseBlaze.Checked = ReadProfileBool(snapshot, "geo_use_blaze_of_glory", false);
        _geoUseEcliptic.Checked = ReadProfileBool(snapshot, "geo_use_ecliptic_attrition", false);
        _geoUseLifeCycle.Checked = ReadProfileBool(snapshot, "geo_use_life_cycle", false);
        SetProfileNumber(_geoLifeCycleHpp, ReadProfileDecimal(snapshot, "geo_life_cycle_hpp", 50m));
        _geoReplaceOutOfPosition.Checked = ReadProfileBool(
            snapshot,
            "geo_replace_out_of_position",
            false
        );
        _geoEnemyRequiresCampRadius.Checked = ReadProfileBool(
            snapshot,
            "geo_enemy_requires_camp_radius",
            false
        );
        SetProfileNumber(
            _geoMaxCampDistance,
            ReadProfileDecimal(snapshot, "geo_max_camp_distance_yalms", 6m)
        );

        _campPullEnabled.Checked = ReadProfileBool(snapshot, "camp_pulling_enabled", false);
        SelectRequiredValue(
            _campPullActionType,
            SessionStateHelper.GetString(snapshot, "camp_pulling_action_type", "spell"),
            "camp_pulling_action_type"
        );
        _campPullActionName.Text = SessionStateHelper.GetString(snapshot, "camp_pulling_action_name");
        _campPullTargets.Text = SessionStateHelper.GetString(snapshot, "camp_pulling_targets");
        SelectRequiredValue(
            _campPullMatchMode,
            SessionStateHelper.GetString(snapshot, "camp_pulling_match_mode", "exact"),
            "camp_pulling_match_mode"
        );
        SetProfileNumber(_campPullMaxActive, ReadProfileDecimal(snapshot, "camp_pulling_max_active_mobs", 1m));
        SetProfileNumber(
            _campPullReplenishHpp,
            ReadProfileDecimal(snapshot, "camp_pulling_replenish_below_hpp", 20m)
        );
        SetProfileNumber(_campPullLeash, ReadProfileDecimal(snapshot, "camp_pulling_leash_yalms", 35m));
        SetProfileNumber(_campPullMaxZ, ReadProfileDecimal(snapshot, "camp_pulling_max_z_delta", 2m));
        SetProfileNumber(
            _campPullRangeRatio,
            ReadProfileDecimal(snapshot, "camp_pulling_cast_range_ratio", 0.9m)
        );
        SetProfileNumber(_campPullSettle, ReadProfileDecimal(snapshot, "camp_pulling_settle_seconds", 0.4m));
        SetProfileNumber(
            _campPullReactionTimeout,
            ReadProfileDecimal(snapshot, "camp_pulling_reaction_timeout_seconds", 4m)
        );
        SetProfileNumber(_campPullRetryLimit, ReadProfileDecimal(snapshot, "camp_pulling_retry_limit", 2m));
        SetProfileNumber(
            _campPullRetryWindow,
            ReadProfileDecimal(snapshot, "camp_pulling_retry_window_seconds", 2.5m)
        );
        SetProfileNumber(
            _campPullCooldown,
            ReadProfileDecimal(snapshot, "camp_pulling_target_cooldown_seconds", 20m)
        );
        SetProfileNumber(
            _campPullArrival,
            ReadProfileDecimal(snapshot, "camp_pulling_camp_arrival_yalms", 0.75m)
        );
        UpdateGeoPullUiState();
    }

    private static decimal ReadProfileDecimal(JsonElement snapshot, string key, decimal defaultValue)
    {
        if (!snapshot.TryGetProperty(key, out var value))
        {
            return defaultValue;
        }
        var raw = value.ValueKind switch
        {
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.String => value.GetString(),
            _ => throw new InvalidDataException($"{key} must be numeric."),
        };
        if (!decimal.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
        {
            throw new InvalidDataException($"{key} must be numeric.");
        }
        return parsed;
    }

    private static bool ReadProfileBool(JsonElement snapshot, string key, bool defaultValue)
    {
        if (!snapshot.TryGetProperty(key, out var value))
        {
            return defaultValue;
        }
        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new InvalidDataException($"{key} must be boolean."),
        };
    }

    private static void SetProfileNumber(NumericUpDown control, decimal value)
    {
        if (value < control.Minimum || value > control.Maximum)
        {
            throw new InvalidDataException(
                $"Profile value {value.ToString(CultureInfo.InvariantCulture)} is outside "
                    + $"{control.Minimum.ToString(CultureInfo.InvariantCulture)}.."
                    + $"{control.Maximum.ToString(CultureInfo.InvariantCulture)}."
            );
        }
        control.Value = value;
    }

    private static void SelectRequiredValue(ComboBox control, string value, string fieldName)
    {
        if (!control.Items.Contains(value))
        {
            throw new InvalidDataException($"Unsupported {fieldName} value '{value}'.");
        }
        control.SelectedItem = value;
    }

    private void AddGeoPullTabs()
    {
        _tabGeo = new TabPage("GEO") { AutoScroll = true };
        var geo = CreateGeoPullTable();
        var geoRow = 0;

        _geoEnabled = new UcToggle { Text = "Maintain configured Geo and Indi spells", AutoSize = true };
        AddWide(geo, _geoEnabled, ref geoRow);
        _geoSpell = AddText(geo, "Geo spell", ref geoRow);
        _indiSpell = AddText(geo, "Indi spell", ref geoRow);
        _geoTargetKind = AddChoice(
            geo,
            "Geo target",
            ["current_enemy", "self", "party_member"],
            "current_enemy",
            ref geoRow
        );
        _geoTargetName = AddText(geo, "Geo party member", ref geoRow);
        _geoOrdering = AddChoice(geo, "Casting order", ["geo_first", "indi_first"], "geo_first", ref geoRow);
        _geoLuopanPlacement = AddChoice(geo, "Luopan placement", ["Target", "Camp"], "Target", ref geoRow);
        _geoRequireCamp = new UcToggle { Text = "Require character at camp", AutoSize = true, Checked = true };
        AddWide(geo, _geoRequireCamp, ref geoRow);
        _geoCampTolerance = AddNumber(geo, "Camp tolerance (yalms)", 0m, 50m, 1m, 0.1m, 1, ref geoRow);
        _geoEntrustEnabled = new UcToggle { Text = "Maintain an Entrust Indi spell on a party member", AutoSize = true };
        AddWide(geo, _geoEntrustEnabled, ref geoRow);
        _geoEntrustSpell = AddText(geo, "Entrust Indi spell", ref geoRow);
        _geoEntrustTarget = AddText(geo, "Entrust target", ref geoRow);
        _geoUseBlaze = new UcToggle { Text = "Use Blaze of Glory before Geo placement", AutoSize = true };
        AddWide(geo, _geoUseBlaze, ref geoRow);
        _geoUseEcliptic = new UcToggle { Text = "Use Ecliptic Attrition after Geo placement", AutoSize = true };
        AddWide(geo, _geoUseEcliptic, ref geoRow);
        _geoUseLifeCycle = new UcToggle { Text = "Use Life Cycle for a low-HP luopan", AutoSize = true };
        AddWide(geo, _geoUseLifeCycle, ref geoRow);
        _geoLifeCycleHpp = AddNumber(geo, "Life Cycle below luopan HP %", 1m, 99m, 50m, 1m, 0, ref geoRow);
        _geoReplaceOutOfPosition = new UcToggle { Text = "Replace misplaced camp Luopan", AutoSize = true };
        AddWide(geo, _geoReplaceOutOfPosition, ref geoRow);
        _geoEnemyRequiresCampRadius = new UcToggle
        {
            Text = "Only cast enemy Geo within the camp radius",
            AutoSize = true,
        };
        AddWide(geo, _geoEnemyRequiresCampRadius, ref geoRow);
        _geoMaxCampDistance = AddNumber(geo, "Camp placement radius (yalms)", 0.1m, 50m, 6m, 0.1m, 1, ref geoRow);
        _geoRuntimeStatus = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(720, 0),
            Text = "Runtime: unavailable",
            Padding = new Padding(0, 8, 0, 0),
        };
        AddWide(geo, _geoRuntimeStatus, ref geoRow);
        _geoHelp = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(720, 0),
            Text = "Profile-scoped settings. In game: //uc geo status, //uc geo reseed, "
                + "//uc geo bolster arm, and //uc geo bolster disarm. Camp placement keeps the legal "
                + "Geo target unchanged and currently requires the GEO character at camp because the "
                + "shared camp anchor does not yet provide Z.",
            Padding = new Padding(0, 8, 0, 0),
        };
        AddWide(geo, _geoHelp, ref geoRow);
        WireGeoPullControls(
            _geoEnabled,
            _geoSpell,
            _indiSpell,
            _geoTargetKind,
            _geoTargetName,
            _geoOrdering,
            _geoLuopanPlacement,
            _geoRequireCamp,
            _geoCampTolerance,
            _geoEntrustEnabled,
            _geoEntrustSpell,
            _geoEntrustTarget,
            _geoUseBlaze,
            _geoUseEcliptic,
            _geoUseLifeCycle,
            _geoLifeCycleHpp,
            _geoReplaceOutOfPosition,
            _geoEnemyRequiresCampRadius,
            _geoMaxCampDistance
        );
        _tabGeo.Controls.Add(geo);
        _settingsTabs.TabPages.Add(_tabGeo);

        var pullTab = new TabPage("Camp Pulling") { AutoScroll = true };
        var pull = CreateGeoPullTable();
        var pullRow = 0;
        _campPullEnabled = new UcToggle { Text = "Pull configured mobs back to camp", AutoSize = true };
        AddWide(pull, _campPullEnabled, ref pullRow);
        AddWide(pull, CreateGlobalBoolCheckBox("puller_distance_only"), ref pullRow);
        _campPullActionType = AddChoice(pull, "Pull action type", ["spell", "ja"], "spell", ref pullRow);
        _campPullActionName = AddText(pull, "Pull action", ref pullRow);
        _campPullTargets = AddText(pull, "Targets", ref pullRow);
        AddWide(
            pull,
            new Label
            {
                AutoSize = true,
                MaximumSize = new Size(720, 0),
                Text = "Pipe-separated Name:priority entries, for example Apex Bat:20|Apex Crab:10.",
            },
            ref pullRow
        );
        _campPullMatchMode = AddChoice(pull, "Name matching", ["exact", "substring"], "exact", ref pullRow);
        _campPullMaxActive = AddNumber(pull, "Maximum active mobs", 1m, 20m, 1m, 1m, 0, ref pullRow);
        _campPullReplenishHpp = AddNumber(pull, "Replenish below target HP %", 0m, 100m, 20m, 1m, 0, ref pullRow);
        _campPullLeash = AddNumber(pull, "Candidate leash (yalms)", 1m, 100m, 35m, 0.5m, 1, ref pullRow);
        _campPullMaxZ = AddNumber(pull, "Maximum Z delta", 0m, 20m, 2m, 0.1m, 1, ref pullRow);
        _campPullRangeRatio = AddNumber(pull, "Action range ratio", 0.1m, 1m, 0.9m, 0.05m, 2, ref pullRow);
        _campPullSettle = AddNumber(pull, "Settle time (seconds)", 0m, 3m, 0.4m, 0.1m, 1, ref pullRow);
        _campPullReactionTimeout = AddNumber(pull, "Reaction timeout (seconds)", 0.5m, 30m, 4m, 0.5m, 1, ref pullRow);
        _campPullRetryLimit = AddNumber(pull, "Action retry limit", 0m, 10m, 2m, 1m, 0, ref pullRow);
        _campPullRetryWindow = AddNumber(pull, "Retry window (seconds)", 0.1m, 30m, 2.5m, 0.1m, 1, ref pullRow);
        _campPullCooldown = AddNumber(pull, "Target cooldown (seconds)", 0m, 300m, 20m, 1m, 1, ref pullRow);
        _campPullArrival = AddNumber(pull, "Camp arrival radius (yalms)", 0.1m, 10m, 0.75m, 0.05m, 2, ref pullRow);
        _campPullRuntimeStatus = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(720, 0),
            Text = "Runtime: unavailable",
            Padding = new Padding(0, 8, 0, 0),
        };
        AddWide(pull, _campPullRuntimeStatus, ref pullRow);
        _campPullHelp = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(720, 0),
            Text = "Camp pulling is job-independent and uses the camp anchor from //uc camp set. "
                + "Use //uc camp pullstatus for runtime state. The existing route hunter remains a separate workflow.",
            Padding = new Padding(0, 8, 0, 0),
        };
        AddWide(pull, _campPullHelp, ref pullRow);
        WireGeoPullControls(
            _campPullEnabled,
            _campPullActionType,
            _campPullActionName,
            _campPullTargets,
            _campPullMatchMode,
            _campPullMaxActive,
            _campPullReplenishHpp,
            _campPullLeash,
            _campPullMaxZ,
            _campPullRangeRatio,
            _campPullSettle,
            _campPullReactionTimeout,
            _campPullRetryLimit,
            _campPullRetryWindow,
            _campPullCooldown,
            _campPullArrival
        );
        pullTab.Controls.Add(pull);
        _settingsTabs.TabPages.Add(pullTab);

        UpdateGeoPullUiState();
    }

    private static TableLayoutPanel CreateGeoPullTable()
    {
        var table = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(8),
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 260));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        return table;
    }

    private static void AddWide(TableLayoutPanel table, Control control, ref int row)
    {
        table.Controls.Add(control, 0, row);
        table.SetColumnSpan(control, 2);
        row++;
    }

    private static TextBox AddText(TableLayoutPanel table, string label, ref int row)
    {
        table.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
        var control = new TextBox { Width = 280, Anchor = AnchorStyles.Left };
        table.Controls.Add(control, 1, row++);
        return control;
    }

    private static ComboBox AddChoice(
        TableLayoutPanel table,
        string label,
        string[] choices,
        string selected,
        ref int row
    )
    {
        table.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
        var control = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 180,
            Anchor = AnchorStyles.Left,
        };
        control.Items.AddRange(choices);
        control.SelectedItem = selected;
        table.Controls.Add(control, 1, row++);
        return control;
    }

    private static NumericUpDown AddNumber(
        TableLayoutPanel table,
        string label,
        decimal minimum,
        decimal maximum,
        decimal value,
        decimal increment,
        int decimalPlaces,
        ref int row
    )
    {
        table.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
        var control = new NumericUpDown
        {
            Minimum = minimum,
            Maximum = maximum,
            Value = value,
            Increment = increment,
            DecimalPlaces = decimalPlaces,
            Width = 100,
            Anchor = AnchorStyles.Left,
        };
        table.Controls.Add(control, 1, row++);
        return control;
    }

    private void WireGeoPullControls(params Control[] controls)
    {
        foreach (var control in controls)
        {
            switch (control)
            {
                case CheckBox checkBox:
                    checkBox.CheckedChanged += (_, _) => OnGeoPullConfigChanged();
                    break;
                case ComboBox comboBox:
                    comboBox.SelectedIndexChanged += (_, _) => OnGeoPullConfigChanged();
                    break;
                case NumericUpDown numeric:
                    numeric.ValueChanged += (_, _) => OnGeoPullConfigChanged();
                    break;
                case TextBox textBox:
                    textBox.TextChanged += (_, _) => OnGeoPullConfigChanged();
                    break;
            }
        }
    }
}
