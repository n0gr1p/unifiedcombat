namespace UnifiedCombatWinForms.Ui;

internal static class UcControlStyles
{
    internal static void Apply(Control root)
    {
        var controls = new List<Control>();
        CollectControls(root, controls);
        foreach (var control in controls)
        {
            control.SuspendLayout();
        }

        try
        {
            root.Font = UcTheme.BodyFont;
            for (var i = 1; i < controls.Count; i++)
            {
                ApplyControl(controls[i]);
            }
        }
        finally
        {
            for (var i = controls.Count - 1; i >= 0; i--)
            {
                controls[i].ResumeLayout(false);
            }
        }

        root.PerformLayout();
    }

    private static void CollectControls(Control root, List<Control> controls)
    {
        controls.Add(root);
        foreach (Control control in root.Controls)
        {
            CollectControls(control, controls);
        }
    }

    internal static void StylePrimary(Button button)
    {
        ApplyButtonPalette(button, () => UcTheme.PrimaryBackground, () => UcTheme.PrimaryText);
    }

    internal static void StyleSecondary(params Button[] buttons)
    {
        foreach (var button in buttons)
        {
            ApplyButtonPalette(button, () => UcTheme.SecondaryBackground, () => SystemColors.ControlText);
        }
    }

    internal static void StyleDestructive(Button button)
    {
        ApplyButtonPalette(button, () => UcTheme.Destructive, () => UcTheme.BadgeText);
    }

    internal static void StyleCompact(params Button[] buttons)
    {
        foreach (var button in buttons)
        {
            button.Padding = new Padding(UcTheme.SpaceXs, UcTheme.SpaceXs, UcTheme.SpaceXs, UcTheme.SpaceXs);
            button.Margin = new Padding(2);
            button.MinimumSize = new Size(button.MinimumSize.Width, 28);
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
                button.FlatAppearance.BorderSize = 1;
                button.MinimumSize = new Size(button.MinimumSize.Width, UcTheme.ControlHeight);
                button.Padding = new Padding(UcTheme.SpaceMd, UcTheme.SpaceXs, UcTheme.SpaceMd, UcTheme.SpaceXs);
                button.Margin = UcTheme.ControlMargin;
                ApplyButtonPalette(button, () => UcTheme.SecondaryBackground, () => SystemColors.ControlText);
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

    private static void ApplyButtonPalette(Button button, Func<Color> background, Func<Color> foreground)
    {
        void ApplyPalette()
        {
            button.UseVisualStyleBackColor = false;
            var paletteBackground = button.Enabled ? background() : SystemColors.ControlDark;
            var paletteForeground = button.Enabled ? foreground() : SystemColors.GrayText;
            button.BackColor = paletteBackground;
            button.ForeColor = paletteForeground;
            button.FlatAppearance.BorderColor = paletteBackground;
            button.FlatAppearance.MouseOverBackColor = ControlPaint.Light(background(), 0.08F);
            button.FlatAppearance.MouseDownBackColor = ControlPaint.Dark(background(), 0.08F);
        }

        ApplyPalette();
        button.SystemColorsChanged += (_, _) => ApplyPalette();
        button.EnabledChanged += (_, _) => ApplyPalette();
    }
}
