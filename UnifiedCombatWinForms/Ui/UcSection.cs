namespace UnifiedCombatWinForms.Ui;

internal sealed class UcSection : Panel
{
    private readonly Label _titleLabel;
    private Control? _content;
    private bool _fillAvailableHeight;
    private bool _layingOut;

    internal UcSection(string title)
    {
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        _titleLabel = new Label
        {
            AutoSize = true,
            Font = UcTheme.SectionFont,
            Margin = new Padding(0),
            Text = title,
        };

        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Dock = DockStyle.Top;
        Margin = UcTheme.SectionMargin;
        Padding = UcTheme.SectionPadding;
        Controls.Add(_titleLabel);
        ApplyTheme();
    }

    [System.ComponentModel.Browsable(false)]
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool FillAvailableHeight
    {
        get => _fillAvailableHeight;
        set
        {
            _fillAvailableHeight = value;
            PerformLayout();
        }
    }

    internal void SetContent(Control content)
    {
        if (_content is not null)
        {
            throw new InvalidOperationException("UcSection content was assigned more than once.");
        }

        _content = content;
        content.AutoSizeChanged += ContentLayoutChanged;
        content.SizeChanged += ContentLayoutChanged;
        content.Margin = new Padding(0);
        content.BackColor = UcTheme.SectionBackground;
        Controls.Add(content);
        PerformLayout();
    }

    [System.ComponentModel.Browsable(false)]
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal string Title
    {
        get => _titleLabel.Text;
        set => _titleLabel.Text = value;
    }

    public override Size GetPreferredSize(Size proposedSize)
    {
        var availableWidth = proposedSize.Width > Padding.Horizontal
            ? proposedSize.Width - Padding.Horizontal
            : 0;
        var titleSize = _titleLabel.GetPreferredSize(new Size(availableWidth, 0));
        var contentSize = _content?.GetPreferredSize(new Size(availableWidth, 0)) ?? Size.Empty;
        var width = Math.Max(titleSize.Width, contentSize.Width) + Padding.Horizontal;
        var height = titleSize.Height + Padding.Vertical;
        if (_content is not null)
        {
            height += UcTheme.SpaceSm + contentSize.Height;
        }

        return new Size(width, height);
    }

    protected override void OnLayout(LayoutEventArgs levent)
    {
        base.OnLayout(levent);
        if (_layingOut)
        {
            return;
        }

        _layingOut = true;
        try
        {
            var contentWidth = Math.Max(0, ClientSize.Width - Padding.Horizontal);
            var titleSize = _titleLabel.GetPreferredSize(new Size(contentWidth, 0));
            _titleLabel.Bounds = new Rectangle(Padding.Left, Padding.Top, contentWidth, titleSize.Height);

            if (_content is null)
            {
                return;
            }

            var contentTop = _titleLabel.Bottom + UcTheme.SpaceSm;
            var preferredContentHeight = _content.GetPreferredSize(new Size(contentWidth, 0)).Height;
            var availableContentHeight = Math.Max(0, ClientSize.Height - contentTop - Padding.Bottom);
            var contentHeight = _fillAvailableHeight
                ? Math.Max(preferredContentHeight, availableContentHeight)
                : preferredContentHeight;
            _content.Bounds = new Rectangle(Padding.Left, contentTop, contentWidth, contentHeight);
        }
        finally
        {
            _layingOut = false;
        }
    }

    protected override void OnSystemColorsChanged(EventArgs e)
    {
        base.OnSystemColorsChanged(e);
        ApplyTheme();
        Invalidate();
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        UcDrawing.ApplyRoundedRegion(this, UcTheme.CornerRadiusLg);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        UcDrawing.ApplyRoundedRegion(this, UcTheme.CornerRadiusLg);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var separator = new Pen(UcTheme.Separator);
        var dividerY = _titleLabel.Bottom + UcTheme.SpaceXs;
        e.Graphics.DrawLine(separator, Padding.Left, dividerY, ClientSize.Width - Padding.Right, dividerY);
    }

    private void ContentLayoutChanged(object? sender, EventArgs e)
    {
        if (!_layingOut)
        {
            PerformLayout();
        }
    }

    private void ApplyTheme()
    {
        BackColor = UcTheme.SectionBackground;
        _titleLabel.BackColor = UcTheme.SectionBackground;
        if (_content is not null)
        {
            _content.BackColor = UcTheme.SectionBackground;
        }
    }
}
