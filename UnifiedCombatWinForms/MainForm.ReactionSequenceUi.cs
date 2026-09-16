using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private readonly List<ReactionSequenceRule> _reactionSequenceRules = [];
    private readonly List<ReactionSequenceStep> _reactionSequenceDraftSteps = [];
    private ListBox _reactionSequenceRuleList = null!;
    private TextBox _reactionSequenceName = null!;
    private CheckBox _reactionSequenceOncePerInstance = null!;
    private ListBox _reactionSequenceStepList = null!;
    private ComboBox _reactionSequenceStepType = null!;
    private ComboBox _reactionSequenceStepName = null!;
    private ComboBox _reactionSequenceStepTarget = null!;
    private CheckBox _reactionSequenceStepOptional = null!;
    private Button _reactionSequenceStepAdd = null!;
    private Button _reactionSequenceStepRemove = null!;
    private Button _reactionSequenceStepUp = null!;
    private Button _reactionSequenceStepDown = null!;
    private Button _reactionSequenceSave = null!;
    private Button _reactionSequenceNew = null!;
    private Button _reactionSequenceRemove = null!;
    private Label _reactionSequenceValidation = null!;
    private bool _reactionSequenceUiInitialized;
    private string _reactionSequenceLoadedSid = "";
    private int _reactionSequenceEditIndex = -1;

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        EnsureReactionSequenceUi();
    }

    private void EnsureReactionSequenceUi()
    {
        if (_reactionSequenceUiInitialized)
        {
            return;
        }

        var reactionsTab = _settingsTabs.TabPages.Cast<TabPage>().FirstOrDefault(tab => string.Equals(tab.Text, "Reactions", StringComparison.Ordinal));
        var root = reactionsTab?.Controls.OfType<TableLayoutPanel>().FirstOrDefault();
        if (root is null)
        {
            throw new InvalidOperationException("Reactions tab root is unavailable.");
        }

        var heading = new Label
        {
            Text = "Atomic action sequences",
            AutoSize = true,
            Font = new Font(SystemFonts.DefaultFont, FontStyle.Bold),
            Padding = new Padding(0, 14, 0, 2),
        };
        root.Controls.Add(heading);
        root.Controls.Add(new Label
        {
            Text = "Run ordered JA/spell/pet steps when an enemy begins the named ability. Optional setup steps are skipped when unavailable; the final step must be required. Pet actions currently support Assault and Deploy against the triggering actor. The reaction lane stays reserved between steps.",
            AutoSize = true,
            MaximumSize = new Size(760, 0),
            Padding = new Padding(0, 0, 0, 6),
        });

        _reactionSequenceRuleList = new ListBox
        {
            Height = 105,
            IntegralHeight = false,
            Dock = DockStyle.Top,
        };
        _reactionSequenceRuleList.SelectedIndexChanged += (_, _) => OnReactionSequenceRuleSelected();
        root.Controls.Add(_reactionSequenceRuleList);

        var ruleNameRow = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(0, 6, 0, 0),
        };
        ruleNameRow.Controls.Add(new Label { Text = "Enemy ability", AutoSize = true, Padding = new Padding(0, 5, 8, 0) });
        _reactionSequenceName = new TextBox { Width = 280, PlaceholderText = "Just Desserts" };
        ruleNameRow.Controls.Add(_reactionSequenceName);
        _reactionSequenceOncePerInstance = new CheckBox
        {
            Text = "Once per mob instance",
            AutoSize = true,
            Padding = new Padding(12, 2, 0, 0),
        };
        ruleNameRow.Controls.Add(_reactionSequenceOncePerInstance);
        root.Controls.Add(ruleNameRow);

        _reactionSequenceStepList = new ListBox
        {
            Height = 110,
            IntegralHeight = false,
            Dock = DockStyle.Top,
        };
        root.Controls.Add(_reactionSequenceStepList);

        var stepEditor = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 5,
            Padding = new Padding(0, 6, 0, 0),
        };
        stepEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 80));
        stepEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        stepEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
        stepEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 105));
        stepEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 85));

        _reactionSequenceStepType = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        _reactionSequenceStepType.Items.AddRange(["ja", "spell", "pet"]);
        _reactionSequenceStepType.SelectedItem = "ja";
        _reactionSequenceStepType.SelectedIndexChanged += (_, _) =>
        {
            if (string.Equals(_reactionSequenceStepType.SelectedItem?.ToString(), "pet", StringComparison.Ordinal))
            {
                _reactionSequenceStepTarget.SelectedItem = "actor";
            }
            RefreshReactionSequenceActionOptions();
        };

        _reactionSequenceStepName = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, Dock = DockStyle.Fill };
        _reactionSequenceStepName.DropDown += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_selectedSid))
            {
                EnsureOptionsHydrated(_selectedSid, force: true);
                RefreshReactionSequenceActionOptions();
            }
        };

        _reactionSequenceStepTarget = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        _reactionSequenceStepTarget.Items.AddRange(["self", "actor"]);
        _reactionSequenceStepTarget.SelectedItem = "self";

        _reactionSequenceStepOptional = new CheckBox
        {
            Text = "Optional",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
        };
        _reactionSequenceStepAdd = new Button { Text = "Add step", AutoSize = true };
        _reactionSequenceStepAdd.Click += (_, _) => OnReactionSequenceStepAdd();

        stepEditor.Controls.Add(_reactionSequenceStepType, 0, 0);
        stepEditor.Controls.Add(_reactionSequenceStepName, 1, 0);
        stepEditor.Controls.Add(_reactionSequenceStepTarget, 2, 0);
        stepEditor.Controls.Add(_reactionSequenceStepOptional, 3, 0);
        stepEditor.Controls.Add(_reactionSequenceStepAdd, 4, 0);
        root.Controls.Add(stepEditor);

        var stepButtons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _reactionSequenceStepRemove = new Button { Text = "Remove step", AutoSize = true };
        _reactionSequenceStepRemove.Click += (_, _) => OnReactionSequenceStepRemove();
        _reactionSequenceStepUp = new Button { Text = "Step up", AutoSize = true };
        _reactionSequenceStepUp.Click += (_, _) => OnReactionSequenceStepMove(-1);
        _reactionSequenceStepDown = new Button { Text = "Step down", AutoSize = true };
        _reactionSequenceStepDown.Click += (_, _) => OnReactionSequenceStepMove(1);
        stepButtons.Controls.AddRange([_reactionSequenceStepRemove, _reactionSequenceStepUp, _reactionSequenceStepDown]);
        root.Controls.Add(stepButtons);

        var ruleButtons = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(0, 6, 0, 0),
        };
        _reactionSequenceSave = new Button { Text = "Add sequence", AutoSize = true };
        _reactionSequenceSave.Click += (_, _) => OnReactionSequenceSave();
        _reactionSequenceNew = new Button { Text = "New sequence", AutoSize = true };
        _reactionSequenceNew.Click += (_, _) => ClearReactionSequenceEditor();
        _reactionSequenceRemove = new Button { Text = "Remove sequence", AutoSize = true };
        _reactionSequenceRemove.Click += (_, _) => OnReactionSequenceRemove();
        ruleButtons.Controls.AddRange([_reactionSequenceSave, _reactionSequenceNew, _reactionSequenceRemove]);
        root.Controls.Add(ruleButtons);

        _reactionSequenceValidation = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(760, 0),
            Padding = new Padding(0, 6, 0, 0),
        };
        root.Controls.Add(_reactionSequenceValidation);

        _reactionSequenceUiInitialized = true;
        listSessions.SelectedIndexChanged += (_, _) => BeginInvoke(LoadReactionSequencesForSelectedSession);
        _activityReapply.Click += (_, _) => BeginInvoke(LoadReactionSequencesForSelectedSession);
        LoadReactionSequencesForSelectedSession();
        UpdateReactionSequenceValidation();
    }

    private void RefreshReactionSequenceActionOptions()
    {
        if (!_reactionSequenceUiInitialized && _reactionSequenceStepName is null)
        {
            return;
        }
        var selected = (_reactionSequenceStepName.Text ?? "").Trim();
        var type = _reactionSequenceStepType.SelectedItem?.ToString() ?? "ja";
        IEnumerable<string> source = type switch
        {
            "spell" => _pathPullSpellOptions,
            "pet" => ["Assault", "Deploy"],
            _ => _pathPullJaOptions.Concat(_abilityOptions),
        };
        var options = source
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToList();
        if (selected.Length > 0 && !options.Contains(selected, StringComparer.Ordinal))
        {
            options.Insert(0, selected);
        }
        _reactionSequenceStepName.Items.Clear();
        foreach (var option in options)
        {
            _reactionSequenceStepName.Items.Add(option);
        }
        _reactionSequenceStepName.Text = selected;
    }

    private void OnReactionSequenceStepAdd()
    {
        var actionType = _reactionSequenceStepType.SelectedItem?.ToString() ?? "";
        var actionName = (_reactionSequenceStepName.Text ?? "").Trim();
        var target = _reactionSequenceStepTarget.SelectedItem?.ToString() ?? "";
        if (actionType is not ("ja" or "spell" or "pet") || actionName.Length == 0 || target is not ("self" or "actor"))
        {
            _reactionSequenceValidation.Text = "Each step requires an action type, action name, and self/actor target.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        var candidate = new ReactionSequenceStep(actionType, actionName, target, _reactionSequenceStepOptional.Checked);
        try
        {
            ReactionSequenceProfileCodec.Validate(new ReactionSequenceRule("draft", [candidate with { Optional = false }]));
        }
        catch (InvalidDataException ex)
        {
            _reactionSequenceValidation.Text = ex.Message;
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        _reactionSequenceDraftSteps.Add(candidate);
        _reactionSequenceStepName.Text = "";
        _reactionSequenceStepOptional.Checked = false;
        RebindReactionSequenceStepList(_reactionSequenceDraftSteps.Count - 1);
        UpdateReactionSequenceValidation();
    }

    private void OnReactionSequenceStepRemove()
    {
        var index = _reactionSequenceStepList.SelectedIndex;
        if (index < 0 || index >= _reactionSequenceDraftSteps.Count)
        {
            return;
        }
        _reactionSequenceDraftSteps.RemoveAt(index);
        RebindReactionSequenceStepList(Math.Min(index, _reactionSequenceDraftSteps.Count - 1));
        UpdateReactionSequenceValidation();
    }

    private void OnReactionSequenceStepMove(int direction)
    {
        var index = _reactionSequenceStepList.SelectedIndex;
        var next = index + direction;
        if (index < 0 || next < 0 || next >= _reactionSequenceDraftSteps.Count)
        {
            return;
        }
        (_reactionSequenceDraftSteps[index], _reactionSequenceDraftSteps[next]) =
            (_reactionSequenceDraftSteps[next], _reactionSequenceDraftSteps[index]);
        RebindReactionSequenceStepList(next);
        UpdateReactionSequenceValidation();
    }

    private void OnReactionSequenceSave()
    {
        var name = (_reactionSequenceName.Text ?? "").Trim();
        var candidate = new ReactionSequenceRule(
            name,
            _reactionSequenceDraftSteps.ToList(),
            _reactionSequenceOncePerInstance.Checked
        );
        try
        {
            ReactionSequenceProfileCodec.Validate(candidate);
        }
        catch (InvalidDataException ex)
        {
            _reactionSequenceValidation.Text = ex.Message;
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }

        if (_reactionRules.Any(rule => string.Equals(rule.Trigger, "ability_window", StringComparison.Ordinal)
            && string.Equals(rule.Name, name, StringComparison.OrdinalIgnoreCase)))
        {
            _reactionSequenceValidation.Text = $"Remove the existing ability-window reaction for '{name}' before adding a sequence for the same ability.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        var duplicate = _reactionSequenceRules.FindIndex((rule) => string.Equals(rule.Name, name, StringComparison.OrdinalIgnoreCase));
        if (duplicate >= 0 && duplicate != _reactionSequenceEditIndex)
        {
            _reactionSequenceValidation.Text = $"A sequence for '{name}' already exists.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }

        if (_reactionSequenceEditIndex >= 0 && _reactionSequenceEditIndex < _reactionSequenceRules.Count)
        {
            _reactionSequenceRules[_reactionSequenceEditIndex] = candidate;
        }
        else
        {
            _reactionSequenceRules.Add(candidate);
            _reactionSequenceEditIndex = _reactionSequenceRules.Count - 1;
        }
        RebindReactionSequenceRuleList(_reactionSequenceEditIndex);
        if (!string.IsNullOrWhiteSpace(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
        UpdateReactionSequenceValidation();
    }

    private void OnReactionSequenceRemove()
    {
        var index = _reactionSequenceRuleList.SelectedIndex;
        if (index < 0 || index >= _reactionSequenceRules.Count)
        {
            return;
        }
        _reactionSequenceRules.RemoveAt(index);
        ClearReactionSequenceEditor(clearSelection: false);
        RebindReactionSequenceRuleList(Math.Min(index, _reactionSequenceRules.Count - 1));
        if (!string.IsNullOrWhiteSpace(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
        UpdateReactionSequenceValidation();
    }

    private void OnReactionSequenceRuleSelected()
    {
        var index = _reactionSequenceRuleList.SelectedIndex;
        if (index < 0 || index >= _reactionSequenceRules.Count)
        {
            return;
        }
        var rule = _reactionSequenceRules[index];
        _reactionSequenceEditIndex = index;
        _reactionSequenceName.Text = rule.Name;
        _reactionSequenceOncePerInstance.Checked = rule.OncePerInstance;
        _reactionSequenceDraftSteps.Clear();
        _reactionSequenceDraftSteps.AddRange(rule.Steps);
        _reactionSequenceSave.Text = "Update sequence";
        RebindReactionSequenceStepList();
        UpdateReactionSequenceValidation();
    }

    private void ClearReactionSequenceEditor(bool clearSelection = true)
    {
        _reactionSequenceEditIndex = -1;
        _reactionSequenceName.Text = "";
        _reactionSequenceOncePerInstance.Checked = false;
        _reactionSequenceDraftSteps.Clear();
        _reactionSequenceStepList.Items.Clear();
        _reactionSequenceStepName.Text = "";
        _reactionSequenceStepOptional.Checked = false;
        _reactionSequenceSave.Text = "Add sequence";
        if (clearSelection)
        {
            _reactionSequenceRuleList.ClearSelected();
        }
        UpdateReactionSequenceValidation();
    }

    private void RebindReactionSequenceRuleList(int selectedIndex = -1)
    {
        _reactionSequenceRuleList.Items.Clear();
        foreach (var rule in _reactionSequenceRules)
        {
            var actions = string.Join(" -> ", rule.Steps.Select(FormatReactionSequenceStep));
            var once = rule.OncePerInstance ? " | once per mob" : "";
            _reactionSequenceRuleList.Items.Add($"ability_window | {rule.Name}{once} | {actions}");
        }
        if (selectedIndex >= 0 && _reactionSequenceRuleList.Items.Count > 0)
        {
            _reactionSequenceRuleList.SelectedIndex = Math.Min(selectedIndex, _reactionSequenceRuleList.Items.Count - 1);
        }
    }

    private void RebindReactionSequenceStepList(int selectedIndex = -1)
    {
        _reactionSequenceStepList.Items.Clear();
        for (var i = 0; i < _reactionSequenceDraftSteps.Count; i++)
        {
            _reactionSequenceStepList.Items.Add($"{i + 1}. {FormatReactionSequenceStep(_reactionSequenceDraftSteps[i])}");
        }
        if (selectedIndex >= 0 && _reactionSequenceStepList.Items.Count > 0)
        {
            _reactionSequenceStepList.SelectedIndex = Math.Min(selectedIndex, _reactionSequenceStepList.Items.Count - 1);
        }
    }

    private static string FormatReactionSequenceStep(ReactionSequenceStep step)
    {
        return $"{step.ActionType}: {step.ActionName} <{step.Target}>{(step.Optional ? " (optional)" : "")}";
    }

    private void LoadReactionSequencesForSelectedSession()
    {
        if (!_reactionSequenceUiInitialized)
        {
            return;
        }
        var sid = _selectedSid ?? "";
        if (sid.Length == 0)
        {
            _reactionSequenceRules.Clear();
            _reactionSequenceLoadedSid = "";
            RebindReactionSequenceRuleList();
            ClearReactionSequenceEditor();
            return;
        }

        JsonObject? profile = null;
        if (_workingProfileBySid.TryGetValue(sid, out var working))
        {
            profile = working;
        }
        else if (TryLoadProfileForSid(sid, out var doc))
        {
            using (doc)
            {
                profile = JsonNode.Parse(doc.RootElement.GetRawText()) as JsonObject;
            }
        }

        _reactionSequenceRules.Clear();
        if (profile?["reaction_rules"] is JsonArray rules)
        {
            _reactionSequenceRules.AddRange(ReactionSequenceProfileCodec.ParseRules(rules));
        }
        _reactionSequenceLoadedSid = sid;
        RebindReactionSequenceRuleList();
        ClearReactionSequenceEditor();
        UpdateReactionSequenceValidation();
    }

    private void AppendReactionSequenceRules(JsonArray rules)
    {
        foreach (var sequence in _reactionSequenceRules)
        {
            ReactionSequenceProfileCodec.Validate(sequence);
            foreach (var existing in rules)
            {
                if (existing is not JsonObject existingRule)
                {
                    continue;
                }
                var trigger = existingRule["trigger"]?.GetValue<string>() ?? "";
                var name = existingRule["name"]?.GetValue<string>() ?? "";
                if (trigger == "ability_window" && string.Equals(name, sequence.Name, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException($"duplicate ability-window reaction: {sequence.Name}");
                }
            }
            rules.Add(ReactionSequenceProfileCodec.ToJsonRule(sequence));
        }
    }

    private void UpdateReactionSequenceValidation()
    {
        if (!_reactionSequenceUiInitialized)
        {
            return;
        }
        if (_reactionSequenceRules.Count > 0 && !_reactionEnabled.Checked)
        {
            _reactionSequenceValidation.Text = "Sequence rules are configured, but Enable configured reactions is off.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        if (_reactionSequenceDraftSteps.Count > 0 && _reactionSequenceDraftSteps[^1].Optional)
        {
            _reactionSequenceValidation.Text = "The final sequence step must be required. Add the terminal step or make the current final step required.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        _reactionSequenceValidation.Text = _reactionSequenceLoadedSid.Length == 0
            ? "Select a session to edit reaction sequences."
            : "Sequence configuration is ready to save with the profile/activity.";
        _reactionSequenceValidation.ForeColor = SystemColors.ControlText;
    }
}
