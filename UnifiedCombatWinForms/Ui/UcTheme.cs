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

    internal static Color SectionBackground => SystemColors.ControlLight;
    internal static Color MutedText => SystemColors.GrayText;
    internal static Color ControlBorder => SystemColors.ControlDark;
    internal static Color PrimaryBackground => SystemColors.Highlight;
    internal static Color PrimaryText => SystemColors.HighlightText;

    internal static Padding ControlMargin => new(SpaceXs);
    internal static Padding SectionMargin => new(0, 0, 0, SpaceMd);
    internal static Padding SectionPadding => new(SpaceLg);
}
