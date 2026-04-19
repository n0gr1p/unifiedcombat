namespace UnifiedCombatWinForms;

internal static class HubUiConstants
{
    public static readonly string[] ContextBoolKeys = ["ability_active", "weaponskill_active", "aftermath_enabled", "puller"];

    public static readonly string[] GlobalBoolKeys =
    [
        "show_ingame_ui",
        "defensive_enabled",
        "defensive_cure_enabled",
        "defensive_na_enabled",
        "defensive_buff_enabled",
        "defensive_overwrite_enabled",
        "defensive_buff_self_only",
        "Start_Engine",
        "partner",
        "autotarget",
        "spam",
        "closer",
        "manual",
        "prime",
        "static",
        "spacing",
        "face",
        "sub",
        "sub2",
        "move",
        "debug",
        "solo",
        "aeonic",
        "color",
        "tank",
        "sleep",
        "command",
        "hunter",
        "add_control",
        "puller_distance_only",
        "fight_leader",
        "party_follow",
    ];

    public static readonly string[] BoolKeys = ContextBoolKeys.Concat(GlobalBoolKeys).ToArray();

    public static readonly IReadOnlyDictionary<string, string> BoolLabels = new Dictionary<string, string>
    {
        ["defensive_enabled"] = "Healer Enabled",
        ["defensive_cure_enabled"] = "Allow Cures",
        ["defensive_na_enabled"] = "Allow NA/Status Removal",
        ["defensive_buff_enabled"] = "Allow Buff Support",
        ["defensive_overwrite_enabled"] = "Allow Buff Overwrite",
        ["defensive_buff_self_only"] = "Buff Self Only",
        ["show_ingame_ui"] = "Show In-Game UI",
        ["Start_Engine"] = "Run combat engine",
        ["autotarget"] = "Auto Target",
        ["spam"] = "Spam",
        ["closer"] = "Closer",
        ["manual"] = "Manual",
        ["prime"] = "Prime",
        ["static"] = "Static",
        ["spacing"] = "Spacing",
        ["face"] = "Face",
        ["sub"] = "Sub",
        ["sub2"] = "Sub2",
        ["move"] = "Move",
        ["debug"] = "Debug",
        ["solo"] = "Solo",
        ["aeonic"] = "Aeonic",
        ["color"] = "Color",
        ["tank"] = "Tank",
        ["sleep"] = "Sleep",
        ["command"] = "Command",
        ["hunter"] = "Hunter",
        ["partner"] = "Partner follow",
        ["puller_distance_only"] = "Puller spacing: distance only (no HP bypass)",
        ["fight_leader"] = "Fight leader (party target)",
        ["party_follow"] = "Party follow (idle; pauses when engaged)",
        ["add_control"] = "Add control (off-leader adds when FL on)",
        ["ability_active"] = "abilities",
        ["weaponskill_active"] = "weaponskill",
        ["aftermath_enabled"] = "aftermath",
        ["puller"] = "puller",
    };

    public static readonly string[] HealerCardKeys =
    [
        "defensive_enabled",
        "defensive_cure_enabled",
        "defensive_na_enabled",
        "defensive_buff_enabled",
        "defensive_overwrite_enabled",
        "defensive_buff_self_only",
    ];

    public static readonly string[] CombatCardKeys =
        ["Start_Engine", "autotarget", "spam", "closer", "manual", "prime", "solo"];

    public static readonly string[] BehaviorCardKeys =
    [
        "face",
        "spacing",
        "static",
        "move",
        "sub",
        "sub2",
        "puller_distance_only",
        "sleep",
        "tank",
        "hunter",
        "add_control",
        "command",
    ];

    public static readonly string[] VisualsCardKeys = ["show_ingame_ui", "debug", "aeonic", "color"];

    public static string BoolLabel(string key) => BoolLabels.TryGetValue(key, out var v) ? v : key;
}
