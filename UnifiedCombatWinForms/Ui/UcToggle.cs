using System.Drawing.Drawing2D;

namespace UnifiedCombatWinForms.Ui;

internal sealed class UcToggle : CheckBox
{
    private const int TrackWidth = 36;
    private const int TrackHeight = 20;
    private const int ThumbInset = 3;

    internal UcToggle()
    {
        SetStyle(
            ControlStyles.UserPaint
            | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.ResizeRedraw
            | ControlStyles.SupportsTransparentBackColor,
            true
        );
        AutoSize = true;
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        MinimumSize = new Size(0, UcTheme.ControlHeight);
        ThreeState = false;
    }

    public override Size GetPreferredSize(Size proposedSize)
    {
        var trackWidth = ScaleLogical(TrackWidth);
        var trackHeight = ScaleLogical(TrackHeight);
        var gap = ScaleLogical(UcTheme.SpaceSm);
        var textSize = TextRenderer.MeasureText(Text, Font, Size.Empty, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        return new Size(
            trackWidth + gap + textSize.Width + ScaleLogical(UcTheme.SpaceLg),
            Math.Max(ScaleLogical(UcTheme.ControlHeight), Math.Max(trackHeight, textSize.Height))
        );
    }

    protected override void OnCheckedChanged(EventArgs e)
    {
        base.OnCheckedChanged(e);
        Invalidate();
    }

    protected override void OnEnabledChanged(EventArgs e)
    {
        base.OnEnabledChanged(e);
        Invalidate();
    }

    protected override void OnTextChanged(EventArgs e)
    {
        base.OnTextChanged(e);
        PerformLayout();
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaintBackground(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        var trackWidth = ScaleLogical(TrackWidth);
        var trackHeight = ScaleLogical(TrackHeight);
        var inset = ScaleLogical(ThumbInset);
        var track = new Rectangle(0, (Height - trackHeight) / 2, trackWidth, trackHeight);
        var trackColor = !Enabled
            ? SystemColors.ControlDark
            : Checked ? UcTheme.PrimaryBackground : UcTheme.ControlBorder;
        using (var trackPath = UcDrawing.CreateRoundedPath(track, track.Height / 2))
        using (var trackBrush = new SolidBrush(trackColor))
        {
            e.Graphics.FillPath(trackBrush, trackPath);
        }

        var thumbSize = trackHeight - (inset * 2);
        var thumbX = Checked ? track.Right - inset - thumbSize : track.Left + inset;
        var thumb = new Rectangle(thumbX, track.Top + inset, thumbSize, thumbSize);
        using (var thumbBrush = new SolidBrush(Enabled ? Color.White : SystemColors.ControlLight))
        {
            e.Graphics.FillEllipse(thumbBrush, thumb);
        }

        var textLeft = track.Right + ScaleLogical(UcTheme.SpaceSm);
        var textRect = new Rectangle(textLeft, 0, Math.Max(0, Width - textLeft), Height);
        TextRenderer.DrawText(
            e.Graphics,
            Text,
            Font,
            textRect,
            Enabled ? ForeColor : SystemColors.GrayText,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis
        );

        if (Focused && ShowFocusCues)
        {
            ControlPaint.DrawFocusRectangle(e.Graphics, ClientRectangle, ForeColor, Color.Transparent);
        }
    }

    private int ScaleLogical(int value) => UcDrawing.Scale(this, value);
}
