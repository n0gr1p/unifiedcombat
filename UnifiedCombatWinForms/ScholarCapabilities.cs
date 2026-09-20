namespace UnifiedCombatWinForms;

internal static class ScholarCapabilities
{
    internal static readonly IReadOnlyList<string> AccessionMaintenanceSpellNames =
    [
        "Protect", "Protect II", "Protect III", "Protect IV", "Protect V",
        "Shell", "Shell II", "Shell III", "Shell IV", "Shell V",
        "Regen", "Regen II", "Regen III", "Regen IV", "Regen V",
        "Refresh", "Adloquium", "Phalanx", "Stoneskin", "Blink", "Aquaveil",
        "Enfire", "Enblizzard", "Enaero", "Enstone", "Enthunder", "Enwater",
        "Barfire", "Barblizzard", "Baraero", "Barstone", "Barthunder", "Barwater",
        "Barsleep", "Barpoison", "Barparalyze", "Barblind", "Barsilence",
        "Barpetrify", "Barvirus", "Baramnesia",
        "Sandstorm", "Rainstorm", "Windstorm", "Firestorm",
        "Hailstorm", "Thunderstorm", "Voidstorm", "Aurorastorm",
        "Sandstorm II", "Rainstorm II", "Windstorm II", "Firestorm II",
        "Hailstorm II", "Thunderstorm II", "Voidstorm II", "Aurorastorm II",
        "Animus Augeo", "Animus Minuo",
        "Invisible", "Sneak", "Deodorize",
        "Embrava",
    ];

    internal static readonly IReadOnlyDictionary<string, string> AccessionExclusiveGroups =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Protect"] = "Protect",
            ["Protect II"] = "Protect",
            ["Protect III"] = "Protect",
            ["Protect IV"] = "Protect",
            ["Protect V"] = "Protect",
            ["Shell"] = "Shell",
            ["Shell II"] = "Shell",
            ["Shell III"] = "Shell",
            ["Shell IV"] = "Shell",
            ["Shell V"] = "Shell",
            ["Regen"] = "Regen",
            ["Regen II"] = "Regen",
            ["Regen III"] = "Regen",
            ["Regen IV"] = "Regen",
            ["Regen V"] = "Regen",
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
            ["Sandstorm"] = "Storm",
            ["Rainstorm"] = "Storm",
            ["Windstorm"] = "Storm",
            ["Firestorm"] = "Storm",
            ["Hailstorm"] = "Storm",
            ["Thunderstorm"] = "Storm",
            ["Voidstorm"] = "Storm",
            ["Aurorastorm"] = "Storm",
            ["Sandstorm II"] = "Storm",
            ["Rainstorm II"] = "Storm",
            ["Windstorm II"] = "Storm",
            ["Firestorm II"] = "Storm",
            ["Hailstorm II"] = "Storm",
            ["Thunderstorm II"] = "Storm",
            ["Voidstorm II"] = "Storm",
            ["Aurorastorm II"] = "Storm",
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
