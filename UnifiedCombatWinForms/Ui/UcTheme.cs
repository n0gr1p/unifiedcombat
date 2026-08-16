namespace UnifiedCombatWinForms.Ui;

internal static class UcTheme
{
    internal const int SpaceXs = 4;
    internal const int SpaceSm = 8;
    internal const int SpaceMd = 12;
    internal const int SpaceLg = 16;
    internal const int ControlHeight = 32;
    internal const int CornerRadiusSm = 6;
    internal const int CornerRadiusMd = 8;
    internal const int CornerRadiusLg = 10;

    internal static readonly Font BodyFont = new("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
    internal static readonly Font SectionFont = new("Segoe UI Semibold", 10F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font WorkspaceTitleFont = new("Segoe UI Semibold", 13F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font SessionTitleFont = new("Segoe UI Semibold", 10F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font BadgeFont = new("Segoe UI Semibold", 8F, FontStyle.Bold, GraphicsUnit.Point);
    internal static readonly Font NavigationFont = new("Segoe UI Semibold", 9F, FontStyle.Bold, GraphicsUnit.Point);

    internal static Color WorkspaceSurface => ControlPaint.Light(SystemColors.Control, 0.018F);
    internal static Color SectionBackground => ControlPaint.Light(SystemColors.Control, 0.035F);
    internal static Color NavigationBackground => ControlPaint.Dark(SystemColors.Control, 0.025F);
    internal static Color SecondaryBackground => SystemColors.ControlLight;
    internal static Color SecondaryHover => ControlPaint.Light(SecondaryBackground, 0.08F);
    internal static Color SecondaryPressed => ControlPaint.Dark(SecondaryBackground, 0.08F);
    internal static Color NavigationHover => ControlPaint.Light(NavigationBackground, 0.055F);
    internal static Color MutedText => SystemColors.GrayText;
    internal static Color DisabledSurface => ControlPaint.Light(SystemColors.Control, 0.035F);
    internal static Color DisabledText => SystemColors.GrayText;
    internal static Color ControlBorder => SystemColors.ControlDark;
    internal static Color Separator => SystemColors.ControlDark;
    internal static Color PrimaryBackground => SystemColors.Highlight;
    internal static Color PrimaryHover => ControlPaint.Light(PrimaryBackground, 0.08F);
    internal static Color PrimaryPressed => ControlPaint.Dark(PrimaryBackground, 0.08F);
    internal static Color PrimaryText => SystemColors.HighlightText;
    internal static Color Active => SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(46, 166, 111);
    internal static Color Warning => SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(210, 145, 40);
    internal static Color Destructive => SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(194, 62, 62);
    internal static Color DestructiveHover => ControlPaint.Light(Destructive, 0.08F);
    internal static Color DestructivePressed => ControlPaint.Dark(Destructive, 0.08F);
    internal static Color BadgeText => SystemInformation.HighContrast ? SystemColors.HighlightText : Color.White;

    internal static Padding ControlMargin => new(SpaceXs);
    internal static Padding SectionMargin => new(0, 0, 0, SpaceMd);
    internal static Padding SectionPadding => new(SpaceLg);
}
