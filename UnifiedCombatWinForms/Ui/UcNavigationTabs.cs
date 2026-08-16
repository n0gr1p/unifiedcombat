using System.Drawing.Drawing2D;

namespace UnifiedCombatWinForms.Ui;

internal sealed class UcNavigationTabs : TabControl
{
    private int _hotIndex = -1;

    internal UcNavigationTabs()
    {
        Appearance = TabAppearance.Normal;
        DrawMode = TabDrawMode.OwnerDrawFixed;
        Font = UcTheme.NavigationFont;
        ItemSize = new Size(0, 34);
        Padding = new Point(UcTheme.SpaceSm, UcTheme.SpaceXs);
        SizeMode = TabSizeMode.Normal;
        SetStyle(
            ControlStyles.UserPaint
            | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.ResizeRedraw,
            true
        );
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

        var previousHotIndex = _hotIndex;
        _hotIndex = nextHotIndex;
        InvalidateTab(previousHotIndex);
        InvalidateTab(_hotIndex);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (_hotIndex < 0)
        {
            return;
        }

        var previousHotIndex = _hotIndex;
        _hotIndex = -1;
        InvalidateTab(previousHotIndex);
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

    protected override void OnGotFocus(EventArgs e)
    {
        base.OnGotFocus(e);
        InvalidateTab(SelectedIndex);
    }

    protected override void OnLostFocus(EventArgs e)
    {
        base.OnLostFocus(e);
        InvalidateTab(SelectedIndex);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        var headerBounds = new Rectangle(0, 0, ClientSize.Width, ItemSize.Height + 1);
        var clippedHeader = Rectangle.Intersect(headerBounds, e.ClipRectangle);
        if (!clippedHeader.IsEmpty)
        {
            using var headerBrush = new SolidBrush(UcTheme.NavigationBackground);
            e.Graphics.FillRectangle(headerBrush, clippedHeader);
        }

        var workspaceBounds = new Rectangle(0, DisplayRectangle.Top, ClientSize.Width, Math.Max(0, ClientSize.Height - DisplayRectangle.Top));
        var clippedWorkspace = Rectangle.Intersect(workspaceBounds, e.ClipRectangle);
        if (!clippedWorkspace.IsEmpty)
        {
            using var workspaceBrush = new SolidBrush(UcTheme.WorkspaceSurface);
            e.Graphics.FillRectangle(workspaceBrush, clippedWorkspace);
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        DrawHeader(e.Graphics, e.ClipRectangle);
    }

    private void DrawHeader(Graphics graphics, Rectangle clipRectangle)
    {
        graphics.SmoothingMode = SmoothingMode.AntiAlias;

        for (var index = 0; index < TabCount; index++)
        {
            if (index != SelectedIndex && GetTabPaintBounds(index).IntersectsWith(clipRectangle))
            {
                DrawTab(graphics, index);
            }
        }
        if (SelectedIndex >= 0
            && SelectedIndex < TabCount
            && GetTabPaintBounds(SelectedIndex).IntersectsWith(clipRectangle))
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
        Invalidate(new Rectangle(0, 0, ClientSize.Width, ItemSize.Height + 2), false);
    }

    private void InvalidateTab(int index)
    {
        if (index < 0 || index >= TabCount)
        {
            return;
        }
        Invalidate(GetTabPaintBounds(index), false);
    }

    private Rectangle GetTabPaintBounds(int index)
    {
        var bounds = GetTabRect(index);
        bounds.Inflate(UcTheme.SpaceXs, UcTheme.SpaceXs);
        return bounds;
    }
}
