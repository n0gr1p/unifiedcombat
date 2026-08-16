namespace UnifiedCombatWinForms.Ui;

internal static class UcTheme
{
    internal const int SpaceXs = 4;
    internal const int SpaceSm = 8;
    internal const int SpaceMd = 12;
    internal const int SpaceLg = 16;
    internal const int ControlHeight = 32;

    internal static readonly Font BodyFont = new("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
    internal static readonly Font SectionFont = new("Segoe UI Semibold", 10F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font WorkspaceTitleFont = new("Segoe UI Semibold", 13F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font SessionTitleFont = new("Segoe UI Semibold", 10F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font BadgeFont = new("Segoe UI Semibold", 8F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font NavigationFont = new("Segoe UI Semibold", 9F, FontStyle.Bold, GraphicsUnit.Point);

    internal static Color SectionBackground => ControlPaint.Light(SystemColors.Control, 0.035F);
    internal static Color SecondaryBackground => SystemColors.ControlLight;
    internal static Color NavigationHover => SystemColors.ControlLight;
    internal static Color MutedText => SystemColors.GrayText;
    internal static Color ControlBorder => SystemColors.ControlDark;
    internal static Color Separator => SystemColors.ControlDark;
    internal static Color PrimaryBackground => SystemColors.Highlight;
    internal static Color PrimaryText => SystemColors.HighlightText;
    internal static Color Active => SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(46, 166, 111);
    internal static Color Warning => SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(210, 145, 40);
    internal static Color Destructive => SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(194, 62, 62);
    internal static Color BadgeText => SystemInformation.HighContrast ? SystemColors.HighlightText : Color.White;

    internal static Padding ControlMargin => new(SpaceXs);
    internal static Padding SectionMargin => new(0, 0, 0, SpaceSm);
    internal static Padding SectionPadding => new(SpaceLg);
}
