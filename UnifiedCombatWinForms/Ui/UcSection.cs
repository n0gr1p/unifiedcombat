namespace UnifiedCombatWinForms.Ui;

internal sealed class UcSection : TableLayoutPanel
{
    private readonly Label _titleLabel;

    internal UcSection(string title)
    {
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        ColumnCount = 1;
        RowCount = 2;
        Dock = DockStyle.Top;
        Margin = UcTheme.SectionMargin;
        Padding = UcTheme.SectionPadding;

        ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        RowStyles.Add(new RowStyle(SizeType.AutoSize));
        RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

        _titleLabel = new Label
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            Font = UcTheme.SectionFont,
            Margin = new Padding(0, 0, 0, UcTheme.SpaceSm),
            Text = title,
        };
        ContentPanel = new Panel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Fill,
            Margin = new Padding(0),
        };

        Controls.Add(_titleLabel, 0, 0);
        Controls.Add(ContentPanel, 0, 1);
        ApplyTheme();
    }

    internal Panel ContentPanel { get; }

    [System.ComponentModel.Browsable(false)]
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal string Title
    {
        get => _titleLabel.Text;
        set => _titleLabel.Text = value;
    }

    protected override void OnSystemColorsChanged(EventArgs e)
    {
        base.OnSystemColorsChanged(e);
        ApplyTheme();
    }

    private void ApplyTheme()
    {
        BackColor = UcTheme.SectionBackground;
        _titleLabel.BackColor = UcTheme.SectionBackground;
        ContentPanel.BackColor = UcTheme.SectionBackground;
    }
}
