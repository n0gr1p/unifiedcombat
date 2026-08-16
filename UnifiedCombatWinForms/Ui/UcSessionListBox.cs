using System.Drawing.Drawing2D;

namespace UnifiedCombatWinForms.Ui;

internal enum UcSessionActivityState
{
    None,
    Exact,
    Modified,
    NoMatch,
}

internal sealed record UcSessionRow(
    string Sid,
    string AccessibleLabel,
    string Character,
    string Job,
    string Engine,
    bool Running,
    bool Paused,
    string? ActivityName,
    UcSessionActivityState ActivityState
)
{
    internal UcSessionRow WithActivity(string accessibleLabel, string? activityName, UcSessionActivityState activityState)
        => this with { AccessibleLabel = accessibleLabel, ActivityName = activityName, ActivityState = activityState };

    public override string ToString() => AccessibleLabel;
}

internal sealed class UcSessionListBox : ListBox
{
    private const int LogicalItemHeight = 60;

    internal UcSessionListBox()
    {
        BorderStyle = BorderStyle.None;
        DrawMode = DrawMode.OwnerDrawFixed;
        IntegralHeight = false;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        UpdateItemHeight();
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        UpdateItemHeight();
    }

    protected override void OnSystemColorsChanged(EventArgs e)
    {
        base.OnSystemColorsChanged(e);
        Invalidate();
    }

    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        if (e.Index < 0 || e.Index >= Items.Count)
        {
            return;
        }
        if (Items[e.Index] is not UcSessionRow row)
        {
            throw new InvalidOperationException($"Session list item {e.Index} has an unexpected type.");
        }

        var selected = (e.State & DrawItemState.Selected) != 0;
        var background = selected ? SystemColors.Highlight : BackColor;
        var foreground = selected ? SystemColors.HighlightText : ForeColor;
        using (var backgroundBrush = new SolidBrush(background))
        {
            e.Graphics.FillRectangle(backgroundBrush, e.Bounds);
        }
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        var inset = ScaleLogical(UcTheme.SpaceSm);
        var content = Rectangle.Inflate(e.Bounds, -inset, 0);
        var titleHeight = ScaleLogical(30);
        var titleBounds = new Rectangle(content.Left, content.Top + ScaleLogical(5), content.Width, titleHeight);
        TextRenderer.DrawText(
            e.Graphics,
            string.IsNullOrWhiteSpace(row.Character) ? "Unknown character" : row.Character,
            UcTheme.SessionTitleFont,
            titleBounds,
            foreground,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis
        );

        var jobText = string.IsNullOrWhiteSpace(row.Job) ? "?" : row.Job.ToUpperInvariant();
        DrawBadge(e.Graphics, jobText, content.Right, titleBounds.Top + ScaleLogical(5), selected ? SystemColors.HighlightText : UcTheme.MutedText, selected, out _);

        var statusY = content.Top + titleHeight + ScaleLogical(5);
        var statusColor = row.Paused ? UcTheme.Warning : row.Running ? UcTheme.Active : UcTheme.MutedText;
        using (var statusBrush = new SolidBrush(statusColor))
        {
            var dot = ScaleLogical(7);
            e.Graphics.FillEllipse(statusBrush, content.Left, statusY + ScaleLogical(3), dot, dot);
        }
        var stateText = row.Paused ? "Paused" : row.Running ? "Active" : "Stopped";
        var engineText = string.IsNullOrWhiteSpace(row.Engine) ? stateText : $"{stateText}  ·  {row.Engine}";
        var stateLeft = content.Left + ScaleLogical(13);
        var stateBounds = new Rectangle(stateLeft, statusY - ScaleLogical(2), Math.Max(0, content.Width / 2), ScaleLogical(20));
        TextRenderer.DrawText(e.Graphics, engineText, Font, stateBounds, foreground, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);

        var activityText = ActivityBadgeText(row);
        if (activityText.Length > 0)
        {
            var activityColor = row.ActivityState == UcSessionActivityState.Exact ? UcTheme.Active : UcTheme.Warning;
            DrawBadge(e.Graphics, activityText, content.Right, statusY - ScaleLogical(1), activityColor, selected, out _);
        }

        using (var separator = new Pen(selected ? SystemColors.Highlight : UcTheme.Separator))
        {
            e.Graphics.DrawLine(separator, e.Bounds.Left + inset, e.Bounds.Bottom - 1, e.Bounds.Right - inset, e.Bounds.Bottom - 1);
        }
        if ((e.State & DrawItemState.Focus) != 0 && ShowFocusCues)
        {
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(e.Bounds, -2, -2), foreground, background);
        }
    }

    private void DrawBadge(Graphics graphics, string text, int right, int top, Color color, bool selected, out Rectangle bounds)
    {
        var paddingX = ScaleLogical(6);
        var height = ScaleLogical(20);
        var measured = TextRenderer.MeasureText(graphics, text, UcTheme.BadgeFont, Size.Empty, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        var width = Math.Min(ScaleLogical(112), measured.Width + (paddingX * 2));
        bounds = new Rectangle(right - width, top, width, height);
        var badgeColor = selected ? ControlPaint.Light(SystemColors.Highlight, 0.18F) : color;
        using (var path = RoundedRectangle(bounds, ScaleLogical(4)))
        using (var brush = new SolidBrush(badgeColor))
        {
            graphics.FillPath(brush, path);
        }
        TextRenderer.DrawText(graphics, text, UcTheme.BadgeFont, bounds, selected ? SystemColors.HighlightText : UcTheme.BadgeText, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }

    private static string ActivityBadgeText(UcSessionRow row)
    {
        return row.ActivityState switch
        {
            UcSessionActivityState.None => string.Empty,
            UcSessionActivityState.NoMatch => "No Match",
            UcSessionActivityState.Exact => row.ActivityName ?? throw new InvalidOperationException("Exact activity provenance requires an activity name."),
            UcSessionActivityState.Modified => (row.ActivityName ?? throw new InvalidOperationException("Modified activity provenance requires an activity name.")) + "-mod",
            _ => throw new InvalidOperationException($"Unknown activity provenance state: {row.ActivityState}."),
        };
    }

    private void UpdateItemHeight() => ItemHeight = ScaleLogical(LogicalItemHeight);

    private int ScaleLogical(int value) => (int)Math.Round(value * DeviceDpi / 96F);

    private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
