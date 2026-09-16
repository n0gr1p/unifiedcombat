using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private readonly List<ReactionSequenceRule> _reactionSequenceRules = [];
    private readonly List<ReactionSequenceStep> _reactionSequenceDraftSteps = [];
    private ListBox _reactionSequenceRuleList = null!;
    private ComboBox _reactionSequenceTrigger = null!;
    private ComboBox _reactionSequenceSource = null!;
    private ComboBox _reactionSequenceTriggerActionType = null!;
    private ComboBox _reactionSequenceName = null!;
    private Label _reactionSequenceSourceLabel = null!;
    private Label _reactionSequenceTriggerActionTypeLabel = null!;
    private Label _reactionSequenceNameLabel = null!;
    private CheckBox _reactionSequenceOncePerInstance = null!;
    private CheckBox _reactionSequenceHoldSmnRage = null!;
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

    private static string ReactionTriggerFromUi(string? value) => value switch
    {
        "Party Action Complete" => "party_action_complete",
        _ => "ability_window",
    };

    private static string ReactionTriggerToUi(string? value) => value switch
    {
        "party_action_complete" => "Party Action Complete",
        _ => "Enemy Ability",
    };

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
            Text = "Run ordered JA/spell/pet steps when an enemy begins an ability or when a selected party member completes a spell/JA. Party-action triggers are scoped to the current enemy instance; the reaction lane stays reserved between sequence steps.",
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

        var triggerRow = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            Padding = new Padding(0, 6, 0, 0),
        };
        triggerRow.Controls.Add(new Label { Text = "Trigger", AutoSize = true, Padding = new Padding(0, 5, 8, 0) });
        _reactionSequenceTrigger = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 175 };
        _reactionSequenceTrigger.Items.AddRange(["Enemy Ability", "Party Action Complete"]);
        _reactionSequenceTrigger.SelectedItem = "Enemy Ability";
        _reactionSequenceTrigger.SelectedIndexChanged += (_, _) => RefreshReactionSequenceTriggerEditor();
        triggerRow.Controls.Add(_reactionSequenceTrigger);

        _reactionSequenceSourceLabel = new Label { Text = "Source", AutoSize = true, Padding = new Padding(12, 5, 8, 0) };
        triggerRow.Controls.Add(_reactionSequenceSourceLabel);
        _reactionSequenceSource = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, Width = 150 };
        _reactionSequenceSource.DropDown += (_, _) => RefreshReactionSequencePartyOptions();
        _reactionSequenceSource.SelectedIndexChanged += (_, _) => RefreshReactionSequenceTriggerActionOptions();
        triggerRow.Controls.Add(_reactionSequenceSource);

        _reactionSequenceTriggerActionTypeLabel = new Label { Text = "Action type", AutoSize = true, Padding = new Padding(12, 5, 8, 0) };
        triggerRow.Controls.Add(_reactionSequenceTriggerActionTypeLabel);
        _reactionSequenceTriggerActionType = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 75 };
        _reactionSequenceTriggerActionType.Items.AddRange(["spell", "ja"]);
        _reactionSequenceTriggerActionType.SelectedItem = "spell";
        _reactionSequenceTriggerActionType.SelectedIndexChanged += (_, _) => RefreshReactionSequenceTriggerActionOptions();
        triggerRow.Controls.Add(_reactionSequenceTriggerActionType);
        root.Controls.Add(triggerRow);

        var ruleNameRow = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            Padding = new Padding(0, 4, 0, 0),
        };
        _reactionSequenceNameLabel = new Label { Text = "Enemy ability", AutoSize = true, Padding = new Padding(0, 5, 8, 0) };
        ruleNameRow.Controls.Add(_reactionSequenceNameLabel);
        _reactionSequenceName = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, Width = 280 };
        _reactionSequenceName.DropDown += (_, _) => RefreshReactionSequenceTriggerActionOptions();
        ruleNameRow.Controls.Add(_reactionSequenceName);
        _reactionSequenceOncePerInstance = new CheckBox
        {
            Text = "Once per mob instance",
            AutoSize = true,
            Padding = new Padding(12, 2, 0, 0),
        };
        ruleNameRow.Controls.Add(_reactionSequenceOncePerInstance);
        _reactionSequenceHoldSmnRage = new CheckBox
        {
            Text = "Hold SMN Rage until sequence completes",
            AutoSize = true,
            Padding = new Padding(12, 2, 0, 0),
        };
        _reactionSequenceHoldSmnRage.CheckedChanged += (_, _) =>
        {
            if (_reactionSequenceHoldSmnRage.Checked)
            {
                _reactionSequenceOncePerInstance.Checked = true;
            }
        };
        ruleNameRow.Controls.Add(_reactionSequenceHoldSmnRage);
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
        RefreshReactionSequenceTriggerEditor();
        UpdateReactionSequenceValidation();
    }

    private void RefreshReactionSequencePartyOptions()
    {
        if (!_reactionSequenceUiInitialized)
        {
            return;
        }
        var selected = SelectedPartyName(_reactionSequenceSource);
        var names = CurrentSelectablePartyNameOptions(_partyOptions);
        BindPartyCombo(_reactionSequenceSource, names, selected);
    }

    private static IEnumerable<string> SplitReactionOptionText(string? value)
    {
        return (value ?? "")
            .Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(item => item.Length > 0);
    }

    private IEnumerable<string> ReactionTriggerOptionsForSource(string sourceName, string actionType)
    {
        sourceName = NormalizePartyName(sourceName);
        var sourceSid = _sessionMetaBySid
            .FirstOrDefault(pair => string.Equals(pair.Value.CharName, sourceName, StringComparison.OrdinalIgnoreCase))
            .Key;
        if (!string.IsNullOrWhiteSpace(sourceSid) && _workingProfileBySid.TryGetValue(sourceSid, out var profile))
        {
            var key = actionType == "spell" ? "path_pull_spell_options" : "path_pull_ja_options";
            var primary = profile[key]?.ToString();
            var options = SplitReactionOptionText(primary).ToList();
            if (actionType == "ja")
            {
                options.AddRange(SplitReactionOptionText(profile["ability_options"]?.ToString()));
            }
            if (options.Count > 0)
            {
                return options;
            }
        }
        return actionType == "spell"
            ? _pathPullSpellOptions
            : _pathPullJaOptions.Concat(_abilityOptions);
    }

    private void RefreshReactionSequenceTriggerActionOptions()
    {
        if (!_reactionSequenceUiInitialized)
        {
            return;
        }
        var selected = (_reactionSequenceName.Text ?? "").Trim();
        var trigger = ReactionTriggerFromUi(_reactionSequenceTrigger.SelectedItem?.ToString());
        IEnumerable<string> source = Array.Empty<string>();
        if (trigger == "party_action_complete")
        {
            var sourceName = SelectedPartyName(_reactionSequenceSource);
            var actionType = _reactionSequenceTriggerActionType.SelectedItem?.ToString() ?? "spell";
            source = ReactionTriggerOptionsForSource(sourceName, actionType);
        }
        var options = source
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToList();
        if (selected.Length > 0 && !options.Contains(selected, StringComparer.Ordinal))
        {
            options.Insert(0, selected);
        }
        _reactionSequenceName.Items.Clear();
        foreach (var option in options)
        {
            _reactionSequenceName.Items.Add(option);
        }
        _reactionSequenceName.Text = selected;
    }

    private void RefreshReactionSequenceTriggerEditor()
    {
        if (!_reactionSequenceUiInitialized)
        {
            return;
        }
        var partyTrigger = ReactionTriggerFromUi(_reactionSequenceTrigger.SelectedItem?.ToString()) == "party_action_complete";
        _reactionSequenceSourceLabel.Visible = partyTrigger;
        _reactionSequenceSource.Visible = partyTrigger;
        _reactionSequenceTriggerActionTypeLabel.Visible = partyTrigger;
        _reactionSequenceTriggerActionType.Visible = partyTrigger;
        _reactionSequenceHoldSmnRage.Visible = partyTrigger;
        if (!partyTrigger)
        {
            _reactionSequenceHoldSmnRage.Checked = false;
        }
        _reactionSequenceNameLabel.Text = partyTrigger ? "Completed action" : "Enemy ability";
        if (partyTrigger)
        {
            RefreshReactionSequencePartyOptions();
        }
        RefreshReactionSequenceTriggerActionOptions();
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
        var trigger = ReactionTriggerFromUi(_reactionSequenceTrigger.SelectedItem?.ToString());
        var name = (_reactionSequenceName.Text ?? "").Trim();
        var sourceName = trigger == "party_action_complete" ? SelectedPartyName(_reactionSequenceSource) : "";
        var triggerActionType = trigger == "party_action_complete"
            ? _reactionSequenceTriggerActionType.SelectedItem?.ToString() ?? ""
            : "";
        var candidate = new ReactionSequenceRule(
            name,
            _reactionSequenceDraftSteps.ToList(),
            _reactionSequenceOncePerInstance.Checked,
            trigger,
            sourceName,
            triggerActionType,
            _reactionSequenceHoldSmnRage.Checked
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

        if (_reactionRules.Any(rule => string.Equals(rule.Trigger, trigger, StringComparison.Ordinal)
            && string.Equals(rule.Name, name, StringComparison.OrdinalIgnoreCase)))
        {
            _reactionSequenceValidation.Text = $"Remove the existing {trigger} reaction for '{name}' before adding a sequence for the same action.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        var duplicate = _reactionSequenceRules.FindIndex(rule =>
            string.Equals(rule.Trigger, trigger, StringComparison.Ordinal)
            && string.Equals(rule.SourceName, sourceName, StringComparison.OrdinalIgnoreCase)
            && string.Equals(rule.TriggerActionType, triggerActionType, StringComparison.Ordinal)
            && string.Equals(rule.Name, name, StringComparison.OrdinalIgnoreCase));
        if (duplicate >= 0 && duplicate != _reactionSequenceEditIndex)
        {
            _reactionSequenceValidation.Text = $"A matching sequence for '{name}' already exists.";
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
        _reactionSequenceTrigger.SelectedItem = ReactionTriggerToUi(rule.Trigger);
        RefreshReactionSequencePartyOptions();
        if (rule.Trigger == "party_action_complete")
        {
            BindPartyCombo(_reactionSequenceSource, CurrentSelectablePartyNameOptions(_partyOptions), rule.SourceName);
            _reactionSequenceTriggerActionType.SelectedItem = rule.TriggerActionType;
        }
        _reactionSequenceName.Text = rule.Name;
        _reactionSequenceOncePerInstance.Checked = rule.OncePerInstance;
        _reactionSequenceHoldSmnRage.Checked = rule.HoldSmnRageUntilSequenceComplete;
        _reactionSequenceDraftSteps.Clear();
        _reactionSequenceDraftSteps.AddRange(rule.Steps);
        _reactionSequenceSave.Text = "Update sequence";
        RefreshReactionSequenceTriggerEditor();
        RebindReactionSequenceStepList();
        UpdateReactionSequenceValidation();
    }

    private void ClearReactionSequenceEditor(bool clearSelection = true)
    {
        _reactionSequenceEditIndex = -1;
        _reactionSequenceTrigger.SelectedItem = "Enemy Ability";
        _reactionSequenceSource.Text = "";
        _reactionSequenceTriggerActionType.SelectedItem = "spell";
        _reactionSequenceName.Text = "";
        _reactionSequenceOncePerInstance.Checked = false;
        _reactionSequenceHoldSmnRage.Checked = false;
        _reactionSequenceDraftSteps.Clear();
        _reactionSequenceStepList.Items.Clear();
        _reactionSequenceStepName.Text = "";
        _reactionSequenceStepOptional.Checked = false;
        _reactionSequenceSave.Text = "Add sequence";
        if (clearSelection)
        {
            _reactionSequenceRuleList.ClearSelected();
        }
        RefreshReactionSequenceTriggerEditor();
        UpdateReactionSequenceValidation();
    }

    private void RebindReactionSequenceRuleList(int selectedIndex = -1)
    {
        _reactionSequenceRuleList.Items.Clear();
        foreach (var rule in _reactionSequenceRules)
        {
            var actions = string.Join(" -> ", rule.Steps.Select(FormatReactionSequenceStep));
            var once = rule.OncePerInstance ? " | once per mob" : "";
            var rageHold = rule.HoldSmnRageUntilSequenceComplete ? " | hold SMN Rage" : "";
            var trigger = rule.Trigger == "party_action_complete"
                ? $"party_action_complete | {rule.SourceName} | {rule.TriggerActionType}: {rule.Name}"
                : $"ability_window | {rule.Name}";
            _reactionSequenceRuleList.Items.Add($"{trigger}{once}{rageHold} | {actions}");
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
                var sourceName = existingRule["source_name"]?.GetValue<string>() ?? "";
                var actionType = existingRule["action_type"]?.GetValue<string>() ?? "";
                if (trigger == sequence.Trigger
                    && string.Equals(name, sequence.Name, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(sourceName, sequence.SourceName, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(actionType, sequence.TriggerActionType, StringComparison.Ordinal))
                {
                    throw new InvalidDataException($"duplicate {sequence.Trigger} reaction: {sequence.Name}");
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
        if (_reactionSequenceHoldSmnRage.Checked && !_reactionSequenceOncePerInstance.Checked)
        {
            _reactionSequenceValidation.Text = "Holding SMN Rage requires Once per mob instance.";
            _reactionSequenceValidation.ForeColor = Color.Firebrick;
            return;
        }
        _reactionSequenceValidation.Text = _reactionSequenceLoadedSid.Length == 0
            ? "Select a session to edit reaction sequences."
            : "Sequence configuration is ready to save with the profile/activity.";
        _reactionSequenceValidation.ForeColor = SystemColors.ControlText;
    }
}
