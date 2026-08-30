using System.Drawing.Drawing2D;
using System.Runtime.CompilerServices;

namespace UnifiedCombatWinForms.Ui;

internal static class UcControlStyles
{
    private static readonly ConditionalWeakTable<Button, ButtonVisualState> ButtonStates = new();

    private enum ButtonRole
    {
        Secondary,
        Primary,
        Destructive,
    }

    private sealed class ButtonVisualState
    {
        internal ButtonRole Role { get; set; }
        internal bool Initialized { get; set; }
        internal bool Hovered { get; set; }
        internal bool Pressed { get; set; }
    }

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
        StyleButton(button, ButtonRole.Primary);
    }

    internal static void StyleSecondary(params Button[] buttons)
    {
        foreach (var button in buttons)
        {
            StyleButton(button, ButtonRole.Secondary);
        }
    }

    internal static void StyleDestructive(Button button)
    {
        StyleButton(button, ButtonRole.Destructive);
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
                button.FlatAppearance.BorderSize = 0;
                button.MinimumSize = new Size(button.MinimumSize.Width, UcTheme.ControlHeight);
                button.Padding = new Padding(UcTheme.SpaceMd, UcTheme.SpaceXs, UcTheme.SpaceMd, UcTheme.SpaceXs);
                button.Margin = UcTheme.ControlMargin;
                StyleButton(button, ButtonRole.Secondary);
                break;
            case TextBoxBase textBox:
                textBox.BorderStyle = BorderStyle.FixedSingle;
                textBox.Margin = UcTheme.ControlMargin;
                break;
            case ComboBox comboBox:
                comboBox.FlatStyle = FlatStyle.Flat;
                comboBox.Margin = UcTheme.ControlMargin;
                comboBox.MouseWheel -= ComboBoxMouseWheel;
                comboBox.MouseWheel += ComboBoxMouseWheel;
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

    internal static bool ShouldSuppressComboBoxMouseWheel(bool droppedDown) => !droppedDown;

    private static void ComboBoxMouseWheel(object? sender, MouseEventArgs e)
    {
        var comboBox = (ComboBox)sender!;
        if (ShouldSuppressComboBoxMouseWheel(comboBox.DroppedDown))
        {
            ((HandledMouseEventArgs)e).Handled = true;
        }
    }

    private static void StyleButton(Button button, ButtonRole role)
    {
        var state = ButtonStates.GetOrCreateValue(button);
        state.Role = role;
        if (!state.Initialized)
        {
            state.Initialized = true;
            button.UseVisualStyleBackColor = false;
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.Resize += (_, _) => UpdateButtonRegion(button);
            button.DpiChangedAfterParent += (_, _) => UpdateButtonRegion(button);
            button.HandleCreated += (_, _) => UpdateButtonRegion(button);
            button.SystemColorsChanged += (_, _) => UpdateButtonVisual(button, state);
            button.EnabledChanged += (_, _) => UpdateButtonVisual(button, state);
            button.MouseEnter += (_, _) =>
            {
                state.Hovered = true;
                UpdateButtonVisual(button, state);
            };
            button.MouseLeave += (_, _) =>
            {
                state.Hovered = false;
                state.Pressed = false;
                UpdateButtonVisual(button, state);
            };
            button.MouseDown += (_, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    state.Pressed = true;
                    UpdateButtonVisual(button, state);
                }
            };
            button.MouseUp += (_, _) =>
            {
                state.Pressed = false;
                UpdateButtonVisual(button, state);
            };
            button.MouseCaptureChanged += (_, _) =>
            {
                if (!button.Capture && state.Pressed)
                {
                    state.Pressed = false;
                    UpdateButtonVisual(button, state);
                }
            };
            button.KeyDown += (_, e) =>
            {
                if (e.KeyCode is Keys.Space or Keys.Enter)
                {
                    state.Pressed = true;
                    UpdateButtonVisual(button, state);
                }
            };
            button.KeyUp += (_, e) =>
            {
                if (e.KeyCode is Keys.Space or Keys.Enter)
                {
                    state.Pressed = false;
                    UpdateButtonVisual(button, state);
                }
            };
            button.GotFocus += (_, _) => button.Invalidate();
            button.LostFocus += (_, _) => button.Invalidate();
            button.Paint += (_, e) => PaintButtonFocus(button, e);
        }

        UpdateButtonRegion(button);
        UpdateButtonVisual(button, state);
    }

    private static void UpdateButtonVisual(Button button, ButtonVisualState state)
    {
        var (background, hover, pressed, foreground) = state.Role switch
        {
            ButtonRole.Primary => (UcTheme.PrimaryBackground, UcTheme.PrimaryHover, UcTheme.PrimaryPressed, UcTheme.PrimaryText),
            ButtonRole.Destructive => (UcTheme.Destructive, UcTheme.DestructiveHover, UcTheme.DestructivePressed, UcTheme.BadgeText),
            _ => (UcTheme.SecondaryBackground, UcTheme.SecondaryHover, UcTheme.SecondaryPressed, SystemColors.ControlText),
        };

        if (!button.Enabled)
        {
            background = UcTheme.DisabledSurface;
            hover = background;
            pressed = background;
            foreground = UcTheme.DisabledText;
        }

        button.BackColor = state.Pressed ? pressed : state.Hovered ? hover : background;
        button.ForeColor = foreground;
        button.FlatAppearance.MouseOverBackColor = hover;
        button.FlatAppearance.MouseDownBackColor = pressed;
        button.Invalidate();
    }

    private static void UpdateButtonRegion(Button button)
    {
        UcDrawing.ApplyRoundedRegion(button, UcTheme.CornerRadiusMd);
        button.Invalidate();
    }

    private static void PaintButtonFocus(Button button, PaintEventArgs e)
    {
        if (!button.Focused || button.ClientSize.Width < 8 || button.ClientSize.Height < 8)
        {
            return;
        }

        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var inset = UcDrawing.Scale(button, 3);
        var bounds = Rectangle.Inflate(button.ClientRectangle, -inset, -inset);
        bounds.Width--;
        bounds.Height--;
        using var path = UcDrawing.CreateRoundedPath(
            bounds,
            Math.Max(1, UcDrawing.Scale(button, UcTheme.CornerRadiusMd) - inset)
        );
        using var pen = new Pen(UcTheme.PrimaryBackground, Math.Max(1F, button.DeviceDpi / 96F));
        e.Graphics.DrawPath(pen, path);
    }
}
