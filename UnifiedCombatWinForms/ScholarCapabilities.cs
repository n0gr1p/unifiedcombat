namespace UnifiedCombatWinForms;

internal static class ScholarCapabilities
{
    internal static readonly IReadOnlyList<string> AccessionMaintenanceSpellNames =
    [
        "Protect V", "Shell V", "Regen V", "Refresh", "Adloquium", "Phalanx",
        "Stoneskin", "Blink", "Aquaveil",
        "Enfire", "Enblizzard", "Enaero", "Enstone", "Enthunder", "Enwater",
        "Barfire", "Barblizzard", "Baraero", "Barstone", "Barthunder", "Barwater",
        "Barsleep", "Barpoison", "Barparalyze", "Barblind", "Barsilence",
        "Barpetrify", "Barvirus", "Baramnesia",
    ];

    internal static readonly IReadOnlyDictionary<string, string> AccessionExclusiveGroups =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Enfire"] = "Enspell",
            ["Enblizzard"] = "Enspell",
            ["Enaero"] = "Enspell",
            ["Enstone"] = "Enspell",
            ["Enthunder"] = "Enspell",
            ["Enwater"] = "Enspell",
            ["Barfire"] = "Bar-element",
            ["Barblizzard"] = "Bar-element",
            ["Baraero"] = "Bar-element",
            ["Barstone"] = "Bar-element",
            ["Barthunder"] = "Bar-element",
            ["Barwater"] = "Bar-element",
            ["Barsleep"] = "Bar-status",
            ["Barpoison"] = "Bar-status",
            ["Barparalyze"] = "Bar-status",
            ["Barblind"] = "Bar-status",
            ["Barsilence"] = "Bar-status",
            ["Barpetrify"] = "Bar-status",
            ["Barvirus"] = "Bar-status",
            ["Baramnesia"] = "Bar-status",
        };

    internal static readonly IReadOnlyList<string> StormNames =
    [
        "Sandstorm II",
        "Rainstorm II",
        "Windstorm II",
        "Firestorm II",
        "Hailstorm II",
        "Thunderstorm II",
        "Voidstorm II",
        "Aurorastorm II",
    ];
}
