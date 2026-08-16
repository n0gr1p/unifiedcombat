using System.Drawing.Drawing2D;

namespace UnifiedCombatWinForms.Ui;

internal sealed class UcNavigationTabs : TabControl
{
    private const int WmPaint = 0x000F;
    private const int WmPrintClient = 0x0318;
    private int _hotIndex = -1;

    internal UcNavigationTabs()
    {
        Appearance = TabAppearance.Normal;
        DrawMode = TabDrawMode.OwnerDrawFixed;
        Font = UcTheme.NavigationFont;
        ItemSize = new Size(0, 34);
        Padding = new Point(UcTheme.SpaceSm, UcTheme.SpaceXs);
        SizeMode = TabSizeMode.Normal;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        ApplyTheme();
    }

    public override Rectangle DisplayRectangle
        => new(0, ItemSize.Height - 1, ClientSize.Width, Math.Max(0, ClientSize.Height - ItemSize.Height + 1));

    protected override void OnControlAdded(ControlEventArgs e)
    {
        base.OnControlAdded(e);
        if (e.Control is not TabPage page)
        {
            return;
        }

        StylePage(page);
    }

    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        DrawTab(e.Graphics, e.Index);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var nextHotIndex = HitTestTab(e.Location);
        if (nextHotIndex == _hotIndex)
        {
            return;
        }

        _hotIndex = nextHotIndex;
        InvalidateHeader();
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (_hotIndex < 0)
        {
            return;
        }

        _hotIndex = -1;
        InvalidateHeader();
    }

    protected override void OnSelectedIndexChanged(EventArgs e)
    {
        base.OnSelectedIndexChanged(e);
        if (SelectedTab is not null)
        {
            StylePage(SelectedTab);
        }
        InvalidateHeader();
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        InvalidateHeader();
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        InvalidateHeader();
    }

    protected override void OnSystemColorsChanged(EventArgs e)
    {
        base.OnSystemColorsChanged(e);
        ApplyTheme();
        foreach (TabPage page in TabPages)
        {
            StylePage(page);
        }
        Invalidate(true);
    }

    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);
        if ((m.Msg == WmPaint || m.Msg == WmPrintClient) && IsHandleCreated && ClientSize.Width > 0)
        {
            using var graphics = CreateGraphics();
            DrawHeader(graphics);
        }
    }

    private void DrawHeader(Graphics graphics)
    {
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var headerBounds = new Rectangle(0, 0, ClientSize.Width, ItemSize.Height + 1);
        using (var headerBrush = new SolidBrush(UcTheme.NavigationBackground))
        {
            graphics.FillRectangle(headerBrush, headerBounds);
        }

        for (var index = 0; index < TabCount; index++)
        {
            if (index != SelectedIndex)
            {
                DrawTab(graphics, index);
            }
        }
        if (SelectedIndex >= 0 && SelectedIndex < TabCount)
        {
            DrawTab(graphics, SelectedIndex);
        }
    }

    private void DrawTab(Graphics graphics, int index)
    {
        if (index < 0 || index >= TabCount)
        {
            return;
        }

        var bounds = GetTabRect(index);
        if (bounds.Right <= 0 || bounds.Left >= ClientSize.Width)
        {
            return;
        }

        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var selected = index == SelectedIndex;
        var hovered = index == _hotIndex && !selected;
        if (selected)
        {
            var selectedBounds = new Rectangle(
                bounds.Left + 1,
                bounds.Top + 1,
                Math.Max(1, bounds.Width - 2),
                Math.Max(1, DisplayRectangle.Top - bounds.Top + 3)
            );
            using var selectedPath = UcDrawing.CreateTopRoundedPath(
                selectedBounds,
                UcDrawing.Scale(this, UcTheme.CornerRadiusMd)
            );
            using var selectedBrush = new SolidBrush(UcTheme.WorkspaceSurface);
            graphics.FillPath(selectedBrush, selectedPath);

            using var accent = new SolidBrush(UcTheme.PrimaryBackground);
            var accentInset = UcDrawing.Scale(this, UcTheme.SpaceSm);
            graphics.FillRectangle(
                accent,
                selectedBounds.Left + accentInset,
                selectedBounds.Top,
                Math.Max(1, selectedBounds.Width - (accentInset * 2)),
                Math.Max(2, UcDrawing.Scale(this, 2))
            );
        }
        else if (hovered)
        {
            var hoverBounds = Rectangle.Inflate(bounds, -2, -3);
            using var hoverPath = UcDrawing.CreateRoundedPath(
                hoverBounds,
                UcDrawing.Scale(this, UcTheme.CornerRadiusSm)
            );
            using var hoverBrush = new SolidBrush(UcTheme.NavigationHover);
            graphics.FillPath(hoverBrush, hoverPath);
        }

        var textBounds = Rectangle.Inflate(bounds, -UcTheme.SpaceXs, -UcTheme.SpaceXs);
        TextRenderer.DrawText(
            graphics,
            TabPages[index].Text,
            Font,
            textBounds,
            selected ? SystemColors.ControlText : UcTheme.MutedText,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis
        );

        if (selected && Focused && ShowFocusCues)
        {
            var focusBounds = Rectangle.Inflate(bounds, -UcTheme.SpaceXs, -UcTheme.SpaceXs);
            using var focusPath = UcDrawing.CreateRoundedPath(
                focusBounds,
                UcDrawing.Scale(this, UcTheme.CornerRadiusSm)
            );
            using var focusPen = new Pen(UcTheme.PrimaryBackground) { DashStyle = DashStyle.Dot };
            graphics.DrawPath(focusPen, focusPath);
        }
    }

    private int HitTestTab(Point location)
    {
        for (var index = 0; index < TabCount; index++)
        {
            if (GetTabRect(index).Contains(location))
            {
                return index;
            }
        }
        return -1;
    }

    private void StylePage(TabPage page)
    {
        page.UseVisualStyleBackColor = false;
        page.BackColor = UcTheme.WorkspaceSurface;
        StyleWorkspaceContainers(page);
    }

    private static void StyleWorkspaceContainers(Control root)
    {
        foreach (Control child in root.Controls)
        {
            if (child is UcSection)
            {
                continue;
            }
            if (child is Panel)
            {
                child.BackColor = UcTheme.WorkspaceSurface;
            }
            StyleWorkspaceContainers(child);
        }
    }

    private void ApplyTheme()
    {
        BackColor = UcTheme.NavigationBackground;
    }

    private void InvalidateHeader()
    {
        Invalidate(new Rectangle(0, 0, ClientSize.Width, ItemSize.Height + 2));
    }
}
