namespace UnifiedCombatWinForms.Ui;

internal sealed class UcNavigationTabs : TabControl
{
    internal UcNavigationTabs()
    {
        Appearance = TabAppearance.Normal;
        DrawMode = TabDrawMode.OwnerDrawFixed;
        Font = UcTheme.NavigationFont;
        ItemSize = new Size(0, 32);
        Padding = new Point(UcTheme.SpaceSm, UcTheme.SpaceXs);
        SizeMode = TabSizeMode.Normal;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }

    public override Rectangle DisplayRectangle
        => new(0, ItemSize.Height, ClientSize.Width, Math.Max(0, ClientSize.Height - ItemSize.Height));

    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        var selected = e.Index == SelectedIndex;
        var bounds = GetTabRect(e.Index);
        var background = SystemColors.Control;
        using (var brush = new SolidBrush(background))
        {
            e.Graphics.FillRectangle(brush, Rectangle.Inflate(bounds, 1, 1));
        }

        var textBounds = Rectangle.Inflate(bounds, -UcTheme.SpaceXs, -UcTheme.SpaceXs);
        TextRenderer.DrawText(
            e.Graphics,
            TabPages[e.Index].Text,
            Font,
            textBounds,
            selected ? SystemColors.ControlText : UcTheme.MutedText,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis
        );

        if (selected)
        {
            using var accent = new SolidBrush(UcTheme.PrimaryBackground);
            e.Graphics.FillRectangle(accent, bounds.Left + UcTheme.SpaceSm, bounds.Bottom - 3, Math.Max(1, bounds.Width - (UcTheme.SpaceSm * 2)), 3);
        }

        if ((e.State & DrawItemState.Focus) != 0 && Focused && ShowFocusCues)
        {
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(bounds, -2, -2));
        }
    }

    protected override void OnSystemColorsChanged(EventArgs e)
    {
        base.OnSystemColorsChanged(e);
        Invalidate();
    }
}
