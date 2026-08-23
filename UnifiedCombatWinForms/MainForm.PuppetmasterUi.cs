using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using UnifiedCombatWinForms.Ui;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private static readonly string[] PuppetmasterManeuverNames =
    [
        "Fire Maneuver",
        "Ice Maneuver",
        "Wind Maneuver",
        "Earth Maneuver",
        "Thunder Maneuver",
        "Water Maneuver",
        "Light Maneuver",
        "Dark Maneuver",
    ];

    private TabPage _tabPuppetmaster = null!;
    private UcToggle _pupEnabled = null!;
    private UcToggle _pupActivateIfMissing = null!;
    private UcToggle _pupDeployOnCombatStart = null!;
    private UcToggle _pupManeuversEnabled = null!;
    private ComboBox _pupManeuver1 = null!;
    private ComboBox _pupManeuver2 = null!;
    private ComboBox _pupManeuver3 = null!;
    private NumericUpDown _pupPostActivateQuiet = null!;
    private NumericUpDown _pupSafeBurdenCeiling = null!;
    private Button _pupSave = null!;
    private Button _pupSaveReload = null!;
    private Label _pupStatus = null!;
    private bool _pupUiLoaded;

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        EnsurePuppetmasterTabBuilt();
        LoadPuppetmasterConfigIntoUi();
        RefreshPuppetmasterTabVisibility();
        listSessions.SelectedIndexChanged += (_, _) => RefreshPuppetmasterTabVisibility();
    }

    private void EnsurePuppetmasterTabBuilt()
    {
        if (_pupUiLoaded)
        {
            return;
        }
        _pupUiLoaded = true;

        _tabPuppetmaster = new TabPage("PUP") { AutoScroll = true };
        var root = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(8),
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 250));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        var row = 0;

        var note = new Label
        {
            Text = "Automaton lifecycle and overload-safe maneuver maintenance. These settings are stored in data/puppetmaster_config.lua and apply to PUP automation after the addon reloads.",
            AutoSize = true,
            MaximumSize = new Size(700, 0),
            Padding = new Padding(0, 0, 0, 8),
        };
        root.Controls.Add(note, 0, row);
        root.SetColumnSpan(note, 2);
        row++;

        _pupEnabled = new UcToggle { Text = "Enable Puppetmaster automation", AutoSize = true, Checked = true };
        root.Controls.Add(_pupEnabled, 0, row);
        root.SetColumnSpan(_pupEnabled, 2);
        row++;

        _pupActivateIfMissing = new UcToggle { Text = "Activate automaton when missing", AutoSize = true, Checked = true };
        root.Controls.Add(_pupActivateIfMissing, 0, row);
        root.SetColumnSpan(_pupActivateIfMissing, 2);
        row++;

        _pupDeployOnCombatStart = new UcToggle { Text = "Deploy automaton on UnifiedCombat target", AutoSize = true, Checked = true };
        root.Controls.Add(_pupDeployOnCombatStart, 0, row);
        root.SetColumnSpan(_pupDeployOnCombatStart, 2);
        row++;

        _pupManeuversEnabled = new UcToggle { Text = "Maintain configured maneuvers", AutoSize = true, Checked = true };
        root.Controls.Add(_pupManeuversEnabled, 0, row);
        root.SetColumnSpan(_pupManeuversEnabled, 2);
        row++;

        _pupManeuver1 = CreatePuppetmasterManeuverCombo("Fire Maneuver");
        AddPuppetmasterRow(root, "Maneuver slot 1", _pupManeuver1, ref row);
        _pupManeuver2 = CreatePuppetmasterManeuverCombo("Fire Maneuver");
        AddPuppetmasterRow(root, "Maneuver slot 2", _pupManeuver2, ref row);
        _pupManeuver3 = CreatePuppetmasterManeuverCombo("Light Maneuver");
        AddPuppetmasterRow(root, "Maneuver slot 3", _pupManeuver3, ref row);

        _pupPostActivateQuiet = new NumericUpDown
        {
            Minimum = 0,
            Maximum = 300,
            Value = 120,
            Increment = 5,
            Width = 90,
            Anchor = AnchorStyles.Left,
        };
        AddPuppetmasterRow(root, "Post-Activate / zone hold (s)", _pupPostActivateQuiet, ref row);

        _pupSafeBurdenCeiling = new NumericUpDown
        {
            Minimum = 0,
            Maximum = 32,
            Value = 30,
            DecimalPlaces = 0,
            Width = 90,
            Anchor = AnchorStyles.Left,
        };
        AddPuppetmasterRow(root, "Safe burden ceiling", _pupSafeBurdenCeiling, ref row);

        var safetyNote = new Label
        {
            Text = "Safety model assumes worst-case normal Maneuver burden (20), Dark burden (15), and 1 burden decay every 3 seconds. If the projected burden would exceed the ceiling, UnifiedCombat waits instead of risking Overload.",
            AutoSize = true,
            MaximumSize = new Size(700, 0),
            Padding = new Padding(0, 8, 0, 8),
        };
        root.Controls.Add(safetyNote, 0, row);
        root.SetColumnSpan(safetyNote, 2);
        row++;

        var buttons = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
        };
        _pupSave = new Button { Text = "Save PUP settings", AutoSize = true };
        _pupSave.Click += (_, _) => SavePuppetmasterConfig(false);
        buttons.Controls.Add(_pupSave);
        _pupSaveReload = new Button { Text = "Save + reload selected PUP", AutoSize = true };
        _pupSaveReload.Click += (_, _) => SavePuppetmasterConfig(true);
        buttons.Controls.Add(_pupSaveReload);
        root.Controls.Add(buttons, 0, row);
        root.SetColumnSpan(buttons, 2);
        row++;

        _pupStatus = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(700, 0),
            Padding = new Padding(0, 6, 0, 0),
        };
        root.Controls.Add(_pupStatus, 0, row);
        root.SetColumnSpan(_pupStatus, 2);

        _tabPuppetmaster.Controls.Add(root);

        var summonerIndex = _settingsTabs.TabPages.IndexOf(_tabSummoner);
        if (summonerIndex >= 0)
        {
            _settingsTabs.TabPages.Insert(summonerIndex + 1, _tabPuppetmaster);
        }
        else
        {
            _settingsTabs.TabPages.Add(_tabPuppetmaster);
        }
    }

    private static void AddPuppetmasterRow(TableLayoutPanel root, string label, Control control, ref int row)
    {
        root.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
        root.Controls.Add(control, 1, row);
        row++;
    }

    private static ComboBox CreatePuppetmasterManeuverCombo(string selected)
    {
        var combo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 220,
            Anchor = AnchorStyles.Left,
        };
        combo.Items.AddRange(PuppetmasterManeuverNames.Cast<object>().ToArray());
        combo.SelectedItem = selected;
        return combo;
    }

    private void RefreshPuppetmasterTabVisibility()
    {
        if (!_pupUiLoaded || _tabPuppetmaster is null)
        {
            return;
        }
        var isPup = false;
        if (!string.IsNullOrWhiteSpace(_selectedSid)
            && _sessionMetaBySid.TryGetValue(_selectedSid, out var meta))
        {
            isPup = string.Equals(meta.Job, "PUP", StringComparison.OrdinalIgnoreCase);
        }

        var present = _settingsTabs.TabPages.Contains(_tabPuppetmaster);
        if (isPup && !present)
        {
            var summonerIndex = _settingsTabs.TabPages.IndexOf(_tabSummoner);
            if (summonerIndex >= 0)
            {
                _settingsTabs.TabPages.Insert(summonerIndex + 1, _tabPuppetmaster);
            }
            else
            {
                _settingsTabs.TabPages.Add(_tabPuppetmaster);
            }
        }
        else if (!isPup && present)
        {
            _settingsTabs.TabPages.Remove(_tabPuppetmaster);
        }
    }

    private string? PuppetmasterConfigPath()
    {
        var addonRoot = StructuredProfileV2Writer.FindAddonRootFrom(AppContext.BaseDirectory);
        return addonRoot is null ? null : Path.Combine(addonRoot, "data", "puppetmaster_config.lua");
    }

    private void LoadPuppetmasterConfigIntoUi()
    {
        var path = PuppetmasterConfigPath();
        if (path is null || !File.Exists(path))
        {
            _pupStatus.Text = path is null
                ? "PUP config path unavailable; using built-in UI defaults."
                : "PUP config file does not exist yet; Save will create it.";
            return;
        }

        try
        {
            var text = File.ReadAllText(path);
            _pupEnabled.Checked = ReadPupBool(text, @"^\s*enabled\s*=\s*(true|false)", true);
            _pupActivateIfMissing.Checked = ReadPupBool(text, @"^\s*activate_if_missing\s*=\s*(true|false)", true);
            _pupDeployOnCombatStart.Checked = ReadPupBool(text, @"^\s*deploy_on_combat_start\s*=\s*(true|false)", true);
            _pupManeuversEnabled.Checked = ReadPupBool(text, @"^\s*maneuvers\s*=\s*\{[\s\S]*?^\s*enabled\s*=\s*(true|false)", true);

            var patternMatch = Regex.Match(
                text,
                @"pattern\s*=\s*\{(?<body>[\s\S]*?)\}",
                RegexOptions.Multiline
            );
            if (patternMatch.Success)
            {
                var names = Regex.Matches(patternMatch.Groups["body"].Value, "'([^']+)'|\"([^\"]+)\"")
                    .Select(m => m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value)
                    .Where(PuppetmasterManeuverNames.Contains)
                    .Take(3)
                    .ToArray();
                if (names.Length > 0) _pupManeuver1.SelectedItem = names[0];
                if (names.Length > 1) _pupManeuver2.SelectedItem = names[1];
                if (names.Length > 2) _pupManeuver3.SelectedItem = names[2];
            }

            _pupPostActivateQuiet.Value = Math.Clamp(
                ReadPupDecimal(text, @"post_activate_quiet_seconds\s*=\s*([0-9.]+)", 120),
                _pupPostActivateQuiet.Minimum,
                _pupPostActivateQuiet.Maximum
            );
            _pupSafeBurdenCeiling.Value = Math.Clamp(
                ReadPupDecimal(text, @"safe_burden_ceiling\s*=\s*([0-9.]+)", 30),
                _pupSafeBurdenCeiling.Minimum,
                _pupSafeBurdenCeiling.Maximum
            );
            _pupStatus.Text = $"Loaded {path}";
        }
        catch (Exception ex)
        {
            _pupStatus.Text = $"Could not read PUP config: {ex.Message}";
        }
    }

    private static bool ReadPupBool(string text, string pattern, bool fallback)
    {
        var match = Regex.Match(text, pattern, RegexOptions.Multiline | RegexOptions.IgnoreCase);
        return match.Success ? string.Equals(match.Groups[1].Value, "true", StringComparison.OrdinalIgnoreCase) : fallback;
    }

    private static decimal ReadPupDecimal(string text, string pattern, decimal fallback)
    {
        var match = Regex.Match(text, pattern, RegexOptions.Multiline | RegexOptions.IgnoreCase);
        return match.Success
            && decimal.TryParse(match.Groups[1].Value, NumberStyles.Number, CultureInfo.InvariantCulture, out var value)
            ? value
            : fallback;
    }

    private void SavePuppetmasterConfig(bool reloadSelected)
    {
        var path = PuppetmasterConfigPath();
        if (path is null)
        {
            _pupStatus.Text = "Cannot save PUP settings: UnifiedCombat addon root was not found.";
            return;
        }

        var maneuvers = new[]
        {
            _pupManeuver1.SelectedItem?.ToString(),
            _pupManeuver2.SelectedItem?.ToString(),
            _pupManeuver3.SelectedItem?.ToString(),
        };
        if (maneuvers.Any(x => string.IsNullOrWhiteSpace(x) || !PuppetmasterManeuverNames.Contains(x!)))
        {
            _pupStatus.Text = "Select a valid maneuver in all three slots before saving.";
            return;
        }

        var sb = new StringBuilder();
        sb.AppendLine("-- Puppetmaster automation defaults.");
        sb.AppendLine("-- Managed by the UnifiedCombat WinForms PUP tab; manual edits are still supported.");
        sb.AppendLine("return {");
        sb.AppendLine($"    enabled = {_pupEnabled.Checked.ToString().ToLowerInvariant()},");
        sb.AppendLine($"    activate_if_missing = {_pupActivateIfMissing.Checked.ToString().ToLowerInvariant()},");
        sb.AppendLine($"    deploy_on_combat_start = {_pupDeployOnCombatStart.Checked.ToString().ToLowerInvariant()},");
        sb.AppendLine("    maneuvers = {");
        sb.AppendLine($"        enabled = {_pupManeuversEnabled.Checked.ToString().ToLowerInvariant()},");
        sb.AppendLine("        pattern = {");
        foreach (var maneuver in maneuvers)
        {
            sb.AppendLine($"            '{maneuver}',");
        }
        sb.AppendLine("        },");
        sb.AppendLine($"        post_activate_quiet_seconds = {_pupPostActivateQuiet.Value.ToString(CultureInfo.InvariantCulture)},");
        sb.AppendLine($"        safe_burden_ceiling = {_pupSafeBurdenCeiling.Value.ToString(CultureInfo.InvariantCulture)},");
        sb.AppendLine("    },");
        sb.AppendLine("}");

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
            _pupStatus.Text = reloadSelected
                ? "PUP settings saved; reloading the selected PUP client..."
                : "PUP settings saved. Reload UnifiedCombat on PUP clients to apply them.";

            if (reloadSelected)
            {
                if (string.IsNullOrWhiteSpace(_selectedSid)
                    || !_sessionMetaBySid.TryGetValue(_selectedSid, out var meta)
                    || !string.Equals(meta.Job, "PUP", StringComparison.OrdinalIgnoreCase))
                {
                    _pupStatus.Text = "PUP settings saved, but the selected session is not a PUP client.";
                    return;
                }
                _btnReloadAddon.PerformClick();
            }
        }
        catch (Exception ex)
        {
            _pupStatus.Text = $"Could not save PUP config: {ex.Message}";
        }
    }
}
