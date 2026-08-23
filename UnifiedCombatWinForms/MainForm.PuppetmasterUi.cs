using System.Globalization;
using System.Text.Json;
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
    private bool _pupUiLoaded;

    private void EnsurePuppetmasterTabBuilt()
    {
        if (_pupUiLoaded) return;
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
            Text = "Automaton lifecycle and overload-safe maneuver maintenance. These settings belong to the selected character / PUP / subjob profile and are saved through the normal UnifiedCombat profile-v2 flow.",
            AutoSize = true,
            MaximumSize = new Size(700, 0),
            Padding = new Padding(0, 0, 0, 8),
        };
        root.Controls.Add(note, 0, row);
        root.SetColumnSpan(note, 2);
        row++;

        _pupEnabled = new UcToggle { Text = "Enable Puppetmaster automation", AutoSize = true };
        AddPuppetmasterToggle(root, _pupEnabled, ref row);
        _pupActivateIfMissing = new UcToggle { Text = "Activate automaton when missing", AutoSize = true, Checked = true };
        AddPuppetmasterToggle(root, _pupActivateIfMissing, ref row);
        _pupDeployOnCombatStart = new UcToggle { Text = "Deploy automaton on UnifiedCombat target", AutoSize = true, Checked = true };
        AddPuppetmasterToggle(root, _pupDeployOnCombatStart, ref row);
        _pupManeuversEnabled = new UcToggle { Text = "Maintain configured maneuvers", AutoSize = true, Checked = true };
        AddPuppetmasterToggle(root, _pupManeuversEnabled, ref row);

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
            Text = "Safety model assumes worst-case normal Maneuver burden (20), Dark burden (15), and 1 burden decay every 3 seconds. If projected burden would exceed the ceiling, UnifiedCombat waits instead of risking Overload.",
            AutoSize = true,
            MaximumSize = new Size(700, 0),
            Padding = new Padding(0, 8, 0, 8),
        };
        root.Controls.Add(safetyNote, 0, row);
        root.SetColumnSpan(safetyNote, 2);

        _tabPuppetmaster.Controls.Add(root);
        ResetPuppetmasterUi();
    }

    private void AddPuppetmasterToggle(TableLayoutPanel root, UcToggle toggle, ref int row)
    {
        toggle.CheckedChanged += (_, _) => OnPuppetmasterSettingChanged();
        root.Controls.Add(toggle, 0, row);
        root.SetColumnSpan(toggle, 2);
        row++;
    }

    private void AddPuppetmasterRow(TableLayoutPanel root, string label, Control control, ref int row)
    {
        switch (control)
        {
            case ComboBox combo:
                combo.SelectedIndexChanged += (_, _) => OnPuppetmasterSettingChanged();
                break;
            case NumericUpDown number:
                number.ValueChanged += (_, _) => OnPuppetmasterSettingChanged();
                break;
        }
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

    private void EnsurePuppetmasterTabVisibility(bool shouldShow)
    {
        EnsurePuppetmasterTabBuilt();
        EnsureJobTabVisibility(_tabPuppetmaster, shouldShow);
    }

    private void ResetPuppetmasterUi()
    {
        if (!_pupUiLoaded) return;
        _pupEnabled.Checked = false;
        _pupActivateIfMissing.Checked = true;
        _pupDeployOnCombatStart.Checked = true;
        _pupManeuversEnabled.Checked = true;
        _pupManeuver1.SelectedItem = "Fire Maneuver";
        _pupManeuver2.SelectedItem = "Fire Maneuver";
        _pupManeuver3.SelectedItem = "Light Maneuver";
        _pupPostActivateQuiet.Value = 120;
        _pupSafeBurdenCeiling.Value = 30;
        UpdatePuppetmasterUiState();
    }

    private void ApplyPuppetmasterFromSnapshot(JsonElement snapshot)
    {
        EnsurePuppetmasterTabBuilt();
        _pupEnabled.Checked = SessionStateHelper.GetBool(snapshot, "puppetmaster_enabled", false);
        _pupActivateIfMissing.Checked = SessionStateHelper.GetBool(snapshot, "puppetmaster_activate_if_missing", true);
        _pupDeployOnCombatStart.Checked = SessionStateHelper.GetBool(snapshot, "puppetmaster_deploy_on_combat_start", true);
        _pupManeuversEnabled.Checked = SessionStateHelper.GetBool(snapshot, "puppetmaster_maneuvers_enabled", true);

        var pattern = SessionStateHelper.SplitOptions(
            snapshot.TryGetProperty("puppetmaster_maneuver_pattern", out var patternNode) ? patternNode : default
        );
        if (pattern.Count == 0) pattern = ["Fire Maneuver", "Fire Maneuver", "Light Maneuver"];
        ApplyPuppetmasterManeuver(_pupManeuver1, pattern.ElementAtOrDefault(0) ?? "Fire Maneuver");
        ApplyPuppetmasterManeuver(_pupManeuver2, pattern.ElementAtOrDefault(1) ?? "Fire Maneuver");
        ApplyPuppetmasterManeuver(_pupManeuver3, pattern.ElementAtOrDefault(2) ?? "Light Maneuver");
        _pupPostActivateQuiet.Value = ReadPuppetmasterInteger(snapshot, "puppetmaster_post_activate_quiet_seconds", 120, 0, 300);
        _pupSafeBurdenCeiling.Value = ReadPuppetmasterInteger(snapshot, "puppetmaster_safe_burden_ceiling", 30, 0, 32);
        UpdatePuppetmasterUiState();
    }

    private static void ApplyPuppetmasterManeuver(ComboBox combo, string name)
    {
        combo.SelectedItem = PuppetmasterManeuverNames.Contains(name, StringComparer.Ordinal)
            ? name
            : "Fire Maneuver";
    }

    private static decimal ReadPuppetmasterInteger(JsonElement snapshot, string key, int fallback, int minimum, int maximum)
    {
        if (!snapshot.TryGetProperty(key, out var node)) return fallback;
        if (node.ValueKind == JsonValueKind.Number && node.TryGetInt32(out var number))
            return Math.Clamp(number, minimum, maximum);
        var raw = SessionStateHelper.GetString(snapshot, key, fallback.ToString(CultureInfo.InvariantCulture));
        return int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
            ? Math.Clamp(parsed, minimum, maximum)
            : fallback;
    }

    private string PuppetmasterPatternFromUi()
    {
        return string.Join("|", new[]
        {
            _pupManeuver1.SelectedItem?.ToString() ?? "Fire Maneuver",
            _pupManeuver2.SelectedItem?.ToString() ?? "Fire Maneuver",
            _pupManeuver3.SelectedItem?.ToString() ?? "Light Maneuver",
        });
    }

    private void OnPuppetmasterSettingChanged()
    {
        if (_suppressEvents) return;
        UpdatePuppetmasterUiState();
        if (!string.IsNullOrWhiteSpace(_selectedSid) && _listSids.Contains(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
    }

    private void UpdatePuppetmasterUiState()
    {
        if (!_pupUiLoaded) return;
        var enabled = _pupEnabled.Checked;
        _pupActivateIfMissing.Enabled = enabled;
        _pupDeployOnCombatStart.Enabled = enabled;
        _pupManeuversEnabled.Enabled = enabled;
        var maneuversEnabled = enabled && _pupManeuversEnabled.Checked;
        _pupManeuver1.Enabled = maneuversEnabled;
        _pupManeuver2.Enabled = maneuversEnabled;
        _pupManeuver3.Enabled = maneuversEnabled;
        _pupPostActivateQuiet.Enabled = maneuversEnabled;
        _pupSafeBurdenCeiling.Enabled = maneuversEnabled;
    }
}
