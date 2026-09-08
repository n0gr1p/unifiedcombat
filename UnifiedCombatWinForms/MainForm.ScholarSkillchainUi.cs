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

    private CheckBox _schSkillchainEnabled = null!;
    private ComboBox _schSkillchainResult = null!;
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
        _schSkillchainResult.SelectedIndexChanged += (_, _) => OnScholarSkillchainSettingChanged();
        scholarRoot.Controls.Add(_schSkillchainResult, 1, row++);

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

    private static string ScholarSkillchainRecipeText(string result)
    {
        return result switch
        {
            "Fusion" => "Fusion: Fire -> Thunder",
            "Fragmentation" => "Fragmentation: Blizzard -> Water",
            "Distortion" => "Distortion: Luminohelix -> Stone",
            "Gravitation" => "Gravitation: Aero -> Noctohelix",
            _ => throw new InvalidOperationException($"Unsupported Scholar skillchain result: {result}"),
        };
    }

    private void UpdateScholarSkillchainUiState()
    {
        if (_schSkillchainEnabled is null || _schSkillchainResult is null || _schSkillchainRecipe is null)
        {
            return;
        }
        var scholarEnabled = _schEnabled is not null && _schEnabled.Checked;
        _schSkillchainEnabled.Enabled = scholarEnabled;
        _schSkillchainResult.Enabled = scholarEnabled && _schSkillchainEnabled.Checked;
        var result = ScholarSkillchainResultValue();
        _schSkillchainRecipe.Text = ScholarSkillchainRecipeText(result)
            + ". UnifiedCombat owns the canonical spell recipe; the profile stores the requested result.";
    }

    private static void ReadNestedScholarSkillchain(JsonObject profile, ref bool enabled, ref string result)
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
    }

    private void RefreshScholarSkillchainUiFromSelectedProfile()
    {
        if (_schSkillchainEnabled is null || _schSkillchainResult is null || string.IsNullOrWhiteSpace(_selectedSid))
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
        if (profile is not null)
        {
            ReadNestedScholarSkillchain(profile, ref enabled, ref result);
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
            }
            UpdateScholarSkillchainUiState();
        }
        finally
        {
            _suppressEvents = wasSuppressed;
        }
    }
}
