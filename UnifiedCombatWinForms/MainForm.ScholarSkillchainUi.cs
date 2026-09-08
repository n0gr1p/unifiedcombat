using System.Text.Json;
using System.Text.Json.Nodes;
using UnifiedCombatWinForms.Ui;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private static readonly string[] ScholarSkillchainResults =
    [
        "Fusion",
        "Fragmentation",
        "Distortion",
        "Gravitation",
    ];

    private static readonly IReadOnlyDictionary<string, string[]> ScholarSkillchainCloserOptions =
        new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            ["Fusion"] = ["Thunder V", "Thunder IV", "Thunder III", "Thunder II", "Thunder"],
            ["Fragmentation"] = ["Water V", "Water IV", "Water III", "Water II", "Water"],
            ["Distortion"] = ["Stone V", "Stone IV", "Stone III", "Stone II", "Stone"],
            ["Gravitation"] = ["Noctohelix II", "Noctohelix"],
        };

    private CheckBox _schSkillchainEnabled = null!;
    private ComboBox _schSkillchainResult = null!;
    private ComboBox _schSkillchainCloser = null!;
    private Label _schSkillchainRecipe = null!;
    private bool _schSkillchainUiInitialized;

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        if (_schSkillchainUiInitialized)
        {
            return;
        }
        _schSkillchainUiInitialized = true;
        InitializeScholarSkillchainUi();
        _schEnabled.CheckedChanged += (_, _) => UpdateScholarSkillchainUiState();
        listSessions.SelectedIndexChanged += (_, _) => QueueScholarSkillchainUiRefresh();
        _activityStatus.TextChanged += (_, _) =>
        {
            if (_activityOperationInProgress)
            {
                QueueScholarSkillchainUiRefresh();
            }
        };
        RefreshScholarSkillchainUiFromSelectedProfile();
    }

    private void QueueScholarSkillchainUiRefresh()
    {
        if (IsHandleCreated && !IsDisposed)
        {
            BeginInvoke(new Action(RefreshScholarSkillchainUiFromSelectedProfile));
        }
    }

    private void InitializeScholarSkillchainUi()
    {
        if (_tabScholar.Controls.OfType<TableLayoutPanel>().FirstOrDefault() is not { } scholarRoot)
        {
            throw new InvalidOperationException("Scholar settings layout is unavailable.");
        }

        var legacyDeferredNote = scholarRoot.Controls.Cast<Control>()
            .OfType<Label>()
            .FirstOrDefault(label => label.Text.Contains("autonomous Immanence chains", StringComparison.Ordinal));
        if (legacyDeferredNote is not null)
        {
            legacyDeferredNote.Text = "Tabula Rasa remains manual.";
        }

        scholarRoot.Controls.Remove(_schValidation);
        var row = scholarRoot.Controls.Cast<Control>()
            .Select(control => scholarRoot.GetRow(control))
            .DefaultIfEmpty(-1)
            .Max() + 1;

        var offenseLabel = new Label
        {
            Text = "Immanence skillchains",
            AutoSize = true,
            Font = new Font(SystemFonts.DefaultFont, FontStyle.Bold),
            Padding = new Padding(0, 10, 0, 2),
        };
        scholarRoot.Controls.Add(offenseLabel, 0, row);
        scholarRoot.SetColumnSpan(offenseLabel, 2);
        row++;

        _schSkillchainEnabled = new UcToggle
        {
            Text = "Enable autonomous Immanence skillchains",
            AutoSize = true,
        };
        _schSkillchainEnabled.CheckedChanged += (_, _) => OnScholarSkillchainSettingChanged();
        scholarRoot.Controls.Add(_schSkillchainEnabled, 0, row);
        scholarRoot.SetColumnSpan(_schSkillchainEnabled, 2);
        row++;

        scholarRoot.Controls.Add(
            new Label { Text = "Skillchain result", AutoSize = true, Anchor = AnchorStyles.Left },
            0,
            row
        );
        _schSkillchainResult = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 220,
            Anchor = AnchorStyles.Left,
        };
        _schSkillchainResult.Items.AddRange(ScholarSkillchainResults.Cast<object>().ToArray());
        _schSkillchainResult.SelectedItem = "Fusion";
        _schSkillchainResult.SelectedIndexChanged += (_, _) => OnScholarSkillchainResultChanged();
        scholarRoot.Controls.Add(_schSkillchainResult, 1, row++);

        scholarRoot.Controls.Add(
            new Label { Text = "Closing spell", AutoSize = true, Anchor = AnchorStyles.Left },
            0,
            row
        );
        _schSkillchainCloser = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 220,
            Anchor = AnchorStyles.Left,
        };
        RefreshScholarSkillchainCloserOptions("Fusion", "Thunder V");
        _schSkillchainCloser.SelectedIndexChanged += (_, _) => OnScholarSkillchainSettingChanged();
        scholarRoot.Controls.Add(_schSkillchainCloser, 1, row++);

        _schSkillchainRecipe = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(680, 0),
            ForeColor = SystemColors.GrayText,
            Padding = new Padding(0, 2, 0, 6),
        };
        scholarRoot.Controls.Add(_schSkillchainRecipe, 0, row);
        scholarRoot.SetColumnSpan(_schSkillchainRecipe, 2);
        row++;

        scholarRoot.Controls.Add(_schValidation, 0, row);
        scholarRoot.SetColumnSpan(_schValidation, 2);

        UpdateScholarSkillchainUiState();
    }

    private void OnScholarSkillchainResultChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        var result = ScholarSkillchainResultValue();
        RefreshScholarSkillchainCloserOptions(result, DefaultScholarSkillchainCloser(result));
        OnScholarSkillchainSettingChanged();
    }

    private void OnScholarSkillchainSettingChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateScholarSkillchainUiState();
        OnScholarSettingChanged();
    }

    private string ScholarSkillchainResultValue()
    {
        var result = (_schSkillchainResult.SelectedItem?.ToString() ?? "Fusion").Trim();
        return ScholarSkillchainResults.Contains(result, StringComparer.Ordinal)
            ? result
            : throw new InvalidOperationException($"Unsupported Scholar skillchain result: {result}");
    }

    private string ScholarSkillchainCloserValue()
    {
        var result = ScholarSkillchainResultValue();
        var closer = (_schSkillchainCloser.SelectedItem?.ToString() ?? "").Trim();
        return ScholarSkillchainCloserOptions[result].Contains(closer, StringComparer.Ordinal)
            ? closer
            : throw new InvalidOperationException($"Unsupported Scholar {result} closer: {closer}");
    }

    private static string DefaultScholarSkillchainCloser(string result)
    {
        if (!ScholarSkillchainCloserOptions.TryGetValue(result, out var options) || options.Length == 0)
        {
            throw new InvalidOperationException($"Unsupported Scholar skillchain result: {result}");
        }
        return options[0];
    }

    private void RefreshScholarSkillchainCloserOptions(string result, string? selected)
    {
        if (_schSkillchainCloser is null)
        {
            return;
        }
        if (!ScholarSkillchainCloserOptions.TryGetValue(result, out var options))
        {
            throw new InvalidOperationException($"Unsupported Scholar skillchain result: {result}");
        }
        var wanted = (selected ?? "").Trim();
        if (!options.Contains(wanted, StringComparer.Ordinal))
        {
            wanted = options[0];
        }
        var wasSuppressed = _suppressEvents;
        _suppressEvents = true;
        try
        {
            _schSkillchainCloser.Items.Clear();
            _schSkillchainCloser.Items.AddRange(options.Cast<object>().ToArray());
            _schSkillchainCloser.SelectedItem = wanted;
        }
        finally
        {
            _suppressEvents = wasSuppressed;
        }
    }

    private static string ScholarSkillchainOpener(string result)
    {
        return result switch
        {
            "Fusion" => "Fire",
            "Fragmentation" => "Blizzard",
            "Distortion" => "Luminohelix",
            "Gravitation" => "Aero",
            _ => throw new InvalidOperationException($"Unsupported Scholar skillchain result: {result}"),
        };
    }

    private static bool ScholarCloserRequiresAddendumBlack(string closer)
    {
        return closer is "Stone IV" or "Stone V"
            or "Water IV" or "Water V"
            or "Aero IV" or "Aero V"
            or "Fire IV" or "Fire V"
            or "Blizzard IV" or "Blizzard V"
            or "Thunder IV" or "Thunder V";
    }

    private void UpdateScholarSkillchainUiState()
    {
        if (_schSkillchainEnabled is null || _schSkillchainResult is null
            || _schSkillchainCloser is null || _schSkillchainRecipe is null)
        {
            return;
        }
        var scholarEnabled = _schEnabled is not null && _schEnabled.Checked;
        _schSkillchainEnabled.Enabled = scholarEnabled;
        _schSkillchainResult.Enabled = scholarEnabled && _schSkillchainEnabled.Checked;
        _schSkillchainCloser.Enabled = scholarEnabled && _schSkillchainEnabled.Checked;
        var result = ScholarSkillchainResultValue();
        var closer = ScholarSkillchainCloserValue();
        _schSkillchainRecipe.Text = $"{result}: {ScholarSkillchainOpener(result)} -> {closer}."
            + (ScholarCloserRequiresAddendumBlack(closer)
                ? " Tier IV/V closer requires Addendum: Black; UC budgets that extra stratagem when needed."
                : "")
            + " The opener stays low tier for timing; the exact closer is profile-controlled.";
    }

    private static void ReadNestedScholarSkillchain(
        JsonObject profile,
        ref bool enabled,
        ref string result,
        ref string closer
    )
    {
        if (profile["sch"] is not JsonObject sch
            || sch["offense"] is not JsonObject offense
            || offense["skillchain"] is not JsonObject skillchain)
        {
            return;
        }
        if (skillchain["enabled"] is JsonValue enabledValue
            && enabledValue.TryGetValue<bool>(out var nestedEnabled))
        {
            enabled = nestedEnabled;
        }
        if (skillchain["plans"] is not JsonArray plans || plans.Count == 0 || plans[0] is not JsonObject plan)
        {
            return;
        }
        if (plan["result"] is JsonValue resultValue
            && resultValue.TryGetValue<string>(out var nestedResult)
            && ScholarSkillchainResults.Contains(nestedResult, StringComparer.Ordinal))
        {
            result = nestedResult;
        }
        if (plan["closer"] is JsonValue closerValue
            && closerValue.TryGetValue<string>(out var nestedCloser)
            && ScholarSkillchainCloserOptions[result].Contains(nestedCloser, StringComparer.Ordinal))
        {
            closer = nestedCloser;
        }
    }

    private void RefreshScholarSkillchainUiFromSelectedProfile()
    {
        if (_schSkillchainEnabled is null || _schSkillchainResult is null
            || _schSkillchainCloser is null || string.IsNullOrWhiteSpace(_selectedSid))
        {
            return;
        }

        JsonObject? profile = null;
        if (_workingProfileBySid.TryGetValue(_selectedSid, out var working))
        {
            profile = working;
        }
        else if (_snapshotDoc is not null
            && _snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions)
            && sessions.TryGetProperty(_selectedSid, out var session)
            && session.TryGetProperty("active_config", out var activeConfig)
            && activeConfig.ValueKind == JsonValueKind.Object)
        {
            profile = RuntimeProfileEditorAdapter.Build(session, activeConfig);
        }

        var enabled = false;
        var result = "Fusion";
        var closer = DefaultScholarSkillchainCloser(result);
        if (profile is not null)
        {
            ReadNestedScholarSkillchain(profile, ref enabled, ref result, ref closer);
            if (profile.TryGetPropertyValue("sch_skillchain_enabled", out var enabledNode)
                && enabledNode is JsonValue enabledValue
                && enabledValue.TryGetValue<bool>(out var parsedEnabled))
            {
                enabled = parsedEnabled;
            }
            if (profile.TryGetPropertyValue("sch_skillchain_result", out var resultNode)
                && resultNode is JsonValue resultValue
                && resultValue.TryGetValue<string>(out var parsedResult)
                && ScholarSkillchainResults.Contains(parsedResult, StringComparer.Ordinal))
            {
                result = parsedResult;
            }
            if (profile.TryGetPropertyValue("sch_skillchain_closer", out var closerNode)
                && closerNode is JsonValue closerValue
                && closerValue.TryGetValue<string>(out var parsedCloser)
                && ScholarSkillchainCloserOptions[result].Contains(parsedCloser, StringComparer.Ordinal))
            {
                closer = parsedCloser;
            }
        }

        if (!ScholarSkillchainCloserOptions[result].Contains(closer, StringComparer.Ordinal))
        {
            closer = DefaultScholarSkillchainCloser(result);
        }

        var wasSuppressed = _suppressEvents;
        _suppressEvents = true;
        try
        {
            _schSkillchainEnabled.Checked = enabled;
            _schSkillchainResult.SelectedItem = result;
            if (_schSkillchainResult.SelectedIndex < 0)
            {
                _schSkillchainResult.SelectedItem = "Fusion";
                result = "Fusion";
            }
            RefreshScholarSkillchainCloserOptions(result, closer);
            UpdateScholarSkillchainUiState();
        }
        finally
        {
            _suppressEvents = wasSuppressed;
        }
    }
}
