namespace UnifiedCombatWinForms.Ui;

internal static class UcControlStyles
{
    internal static void Apply(Control root)
    {
        root.Font = UcTheme.BodyFont;
        ApplyChildren(root);
    }

    private static void ApplyChildren(Control root)
    {
        foreach (Control control in root.Controls)
        {
            ApplyControl(control);
            ApplyChildren(control);
        }
    }

    internal static void StylePrimary(Button button)
    {
        button.BackColor = UcTheme.PrimaryBackground;
        button.ForeColor = UcTheme.PrimaryText;
        button.FlatAppearance.BorderColor = UcTheme.PrimaryBackground;
        button.SystemColorsChanged += (_, _) =>
        {
            button.BackColor = UcTheme.PrimaryBackground;
            button.ForeColor = UcTheme.PrimaryText;
            button.FlatAppearance.BorderColor = UcTheme.PrimaryBackground;
        };
    }

    internal static void StyleCompact(params Button[] buttons)
    {
        foreach (var button in buttons)
        {
            button.Padding = new Padding(UcTheme.SpaceXs, UcTheme.SpaceXs, UcTheme.SpaceXs, UcTheme.SpaceXs);
            button.Margin = new Padding(2);
        }
    }

    internal static Label CreateWorkspaceTitle(string text)
    {
        return new Label
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            Font = UcTheme.WorkspaceTitleFont,
            Margin = new Padding(0),
            Text = text,
        };
    }

    internal static Label CreateMutedLabel(string text)
    {
        var label = new Label
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            ForeColor = UcTheme.MutedText,
            Margin = new Padding(0, UcTheme.SpaceXs, 0, 0),
            Text = text,
        };
        label.SystemColorsChanged += (_, _) => label.ForeColor = UcTheme.MutedText;
        return label;
    }

    private static void ApplyControl(Control control)
    {
        switch (control)
        {
            case Button button:
                button.FlatStyle = FlatStyle.Flat;
                button.FlatAppearance.BorderColor = UcTheme.ControlBorder;
                button.FlatAppearance.BorderSize = 1;
                button.MinimumSize = new Size(button.MinimumSize.Width, UcTheme.ControlHeight);
                button.Padding = new Padding(UcTheme.SpaceMd, UcTheme.SpaceXs, UcTheme.SpaceMd, UcTheme.SpaceXs);
                button.Margin = UcTheme.ControlMargin;
                button.SystemColorsChanged += (_, _) => button.FlatAppearance.BorderColor = UcTheme.ControlBorder;
                break;
            case TextBoxBase textBox:
                textBox.BorderStyle = BorderStyle.FixedSingle;
                textBox.Margin = UcTheme.ControlMargin;
                break;
            case ComboBox comboBox:
                comboBox.FlatStyle = FlatStyle.Flat;
                comboBox.Margin = UcTheme.ControlMargin;
                break;
            case NumericUpDown numeric:
                numeric.BorderStyle = BorderStyle.FixedSingle;
                numeric.Margin = UcTheme.ControlMargin;
                break;
            case CheckBox checkBox:
                checkBox.Margin = UcTheme.ControlMargin;
                break;
            case Label label when label.Parent is not UcSection
                && label.Text.Length >= 80
                && label.ForeColor == SystemColors.ControlText:
                label.ForeColor = UcTheme.MutedText;
                label.SystemColorsChanged += (_, _) => label.ForeColor = UcTheme.MutedText;
                break;
        }
    }
}
