using System.Text;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class StructuredProfileV2WriterTests
{
    public static int Run()
    {
        try
        {
            TestBuildFinalPath();
            TestSerializeShapeAndEscaping();
            TestParseTargetedBuffs();
            TestSerializeOmitsProfileV2AutoloadWhenDisabled();
            TestSerializeIncludesProfileV2AutoloadWhenEnabled();
            TestProfileV2AutoloadIsPartOfPersistedBoolSet();
            TestSerializeOmitsProfileV2AutoReloadWhenDisabled();
            TestSerializeIncludesProfileV2AutoReloadWhenEnabled();
            TestProfileV2AutoReloadIsPartOfPersistedBoolSet();
            TestSerializeIncludesPullerNameWhenSelected();
            TestSerializeIncludesFightLeaderNameWhenSelected();
            TestSerializeOmitsFightLeaderNameWhenDisabled();
            TestSerializeIncludesWaitIgnoreNamesAndStripsDisplayIndexes();
            TestSerializeIncludesAddPriorityTargetsAndStripsDisplayIndexes();
            TestBrdOmitsHiddenCorMaintenanceDefaults();
            TestNonCorOmitsHiddenCorMaintenanceDefaultsAcrossJobs();
            TestCorPreservesConfiguredMaintenanceValues();
            TestBrdPreservesConfiguredSongMaintenance();
            TestNonBrdOmitsHiddenBrdMaintenance();
            TestBrdUiEditsAreLocalUntilSave();
            TestSerializeReactionRules();
            TestDisabledEmptyReactionsAreOmitted();
            TestReactionUiEditsAreLocalUntilSave();
            TestSerializeConfigurableControlRanges();
            TestControlRangeUiEditsAreLocalUntilSave();
            TestUiSaveIsFileOnly();
            TestUiSaveSuppressesOutboundMirrorTraffic();
            TestRemoteBridgeDoesNotConsumeUiSave();
            TestWriteCreatesProfilesDirectory();
            TestWritePreservesExistingFinalOnTempWriteFailure();
            TestWritePreservesExistingFinalOnPromotionFailure();
            Console.WriteLine("StructuredProfileV2WriterTests: OK");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("StructuredProfileV2WriterTests: FAILED");
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    private static void TestBuildFinalPath()
    {
        var path = StructuredProfileV2Writer.BuildFinalPath(
            @"C:\Program Files (x86)\Windower\addons\UnifiedCombat",
            new StructuredProfileV2Identity(" Red Rogue! ", "pld", "war")
        );

        AssertEqual(
            path,
            @"C:\Program Files (x86)\Windower\addons\UnifiedCombat\data\profiles_v2\red_rogue_PLD_WAR.lua",
            "final v2 profile path mismatch"
        );
    }

    private static void TestSerializeShapeAndEscaping()
    {
        var flat = BuildSampleFlatProfile();
        flat["puller"] = true;
        flat["puller_selected"] = "Niightsiide";
        flat["fight_leader"] = true;
        flat["fight_leader_selected"] = "Terrasjr [UC]";
        flat["reaction_enabled"] = true;
        flat["reaction_rules"] = new JsonArray
        {
            new JsonObject { ["trigger"] = "ability_window", ["name"] = "Cold Stare", ["response"] = "turn_away" },
        };
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertContains(content, "return {", "profile must serialize as a Lua return chunk");
        AssertContains(content, "version = 2", "profile version missing");
        AssertContains(content, "schema_version = 2", "profile schema version missing");
        AssertContains(content, "source = \"ui\"", "profile source missing");
        AssertContains(content, "character = \"Redrogue\"", "profile character missing");
        AssertContains(content, "main_job = \"PLD\"", "profile main job missing");
        AssertContains(content, "sub_job = \"WAR\"", "profile sub job missing");
        AssertContains(content, "show_ingame_ui = true", "ui domain missing");
        AssertContains(content, "autotarget = true", "combat domain missing");
        AssertContains(content, "configured = {", "abilities domain missing");
        AssertContains(content, "list = \"Bar\\\"Spell\\\\Line\\nNext\"", "string escaping mismatch");
        AssertContains(content, "targeted = {", "targeted defensive buff list missing");
        AssertContains(content, "character = \"Terrasjr\"", "targeted defensive buff character missing");
        AssertContains(content, "buff = \"Honor March\"", "targeted defensive buff name missing");
        AssertContains(content, "wait_ignore_names = {", "combat wait ignore list missing");
        AssertContains(content, "\"Ally One\"", "combat wait ignore names must be serialized");
        AssertContains(content, "target_ignore_names = {", "target ignore list missing");
        AssertContains(content, "\"Mob One\"", "target ignore names must be serialized");
        AssertContains(content, "range_selected = \"Front\\\"Line\"", "range selection escaping mismatch");
        AssertContains(content, "puller_name = \"Niightsiide\"", "puller name must be serialized as durable profile data");
        AssertContains(content, "leader = true", "fight leader checkbox state must be serialized");
        AssertContains(content, "leader_name = \"Terrasjr\"", "fight leader name must be serialized without display suffixes");
        AssertNotContains(content, "file_name =", "path file name must not be serialized as durable profile data");
        AssertNotContains(content, "puller_id =", "puller id must not be serialized as durable profile data");

        AssertOrder(
            content,
            "ui = {",
            "combat = {",
            "abilities = {",
            "defensive = {",
            "movement = {",
            "follow = {",
            "targeting = {",
            "reactions = {",
            "tank = {",
            "sleep = {",
            "spells = {",
            "maintenance = {",
            "debug = {",
            "ownership = {",
            "legacy = {"
        );

        AssertNotContains(content, "Start_Engine", "runtime engine state must not be serialized");
        AssertNotContains(content, "command = {", "command runtime state must not be serialized");
        AssertNotContains(content, "engine_enabled_default =", "engine runtime state must not be serialized");
        AssertNotContains(content, "fight_leader =", "fight leader runtime state must not be serialized");
        AssertNotContains(content, "fight_leader_id", "fight leader runtime id must not be serialized");
        AssertNotContains(content, "add_priority_entries", "legacy add priority entries must not be serialized");
        AssertNotContains(content, "add_priority_names", "durable add priority names must not be promoted");
        AssertNotContains(content, "sleep_spell_entries", "legacy sleep spell entries must not be serialized");
        AssertNotContains(content, "sleepspells", "legacy sleep list must not be serialized");
        AssertNotContains(content, "sleepspell", "legacy sleep singleton must not be serialized");
        AssertNotContains(content, "profile_v2_autoload", "autoload must be omitted unless explicitly enabled");
    }

    private static void TestParseTargetedBuffs()
    {
        var parsed = StructuredProfileV2Writer.ParseTargetedBuffs("  Terrasjr : Honor March | | malformed | Nyoourke: Valor Minuet V | MissingColon | X: ");
        AssertEqual(parsed.Count, 2, "targeted buff parser should ignore malformed and empty entries");

        AssertEqual(parsed[0].Character, "Terrasjr", "first targeted buff character mismatch");
        AssertEqual(parsed[0].Buff, "Honor March", "first targeted buff name mismatch");
        AssertEqual(parsed[1].Character, "Nyoourke", "second targeted buff character mismatch");
        AssertEqual(parsed[1].Buff, "Valor Minuet V", "second targeted buff name mismatch");
    }

    private static void TestSerializeOmitsProfileV2AutoloadWhenDisabled()
    {
        var flat = BuildSampleFlatProfile();
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertNotContains(content, "profile_v2_autoload", "autoload must stay missing when disabled");
    }

    private static void TestSerializeIncludesProfileV2AutoloadWhenEnabled()
    {
        var flat = BuildSampleFlatProfile();
        flat["profile_v2_autoload"] = true;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertContains(content, "profile_v2_autoload = true", "autoload flag missing when explicitly enabled");
    }

    private static void TestSerializeOmitsProfileV2AutoReloadWhenDisabled()
    {
        var flat = BuildSampleFlatProfile();
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertNotContains(content, "profile_v2_auto_reload_on_change", "auto-reload must stay missing when disabled");
    }

    private static void TestSerializeIncludesProfileV2AutoReloadWhenEnabled()
    {
        var flat = BuildSampleFlatProfile();
        flat["profile_v2_auto_reload_on_change"] = true;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertContains(content, "profile_v2_auto_reload_on_change = true", "auto-reload flag missing when explicitly enabled");
    }

    private static void TestProfileV2AutoloadIsPartOfPersistedBoolSet()
    {
        AssertTrue(
            HubUiConstants.BoolKeys.Contains("profile_v2_autoload"),
            "autoload must be included in the shared UI bool key set so load/save paths persist it"
        );
    }

    private static void TestProfileV2AutoReloadIsPartOfPersistedBoolSet()
    {
        AssertTrue(
            HubUiConstants.BoolKeys.Contains("profile_v2_auto_reload_on_change"),
            "auto-reload must be included in the shared UI bool key set so load/save paths persist it"
        );
    }

    private static void TestSerializeIncludesPullerNameWhenSelected()
    {
        var flat = BuildSampleFlatProfile();
        flat["puller"] = true;
        flat["puller_selected"] = "Niightsiide";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "puller_name = \"Niightsiide\"", "selected puller name must be serialized durably");
        AssertNotContains(content, "puller_id =", "selected puller id must stay runtime-owned");
    }

    private static void TestSerializeIncludesFightLeaderNameWhenSelected()
    {
        var flat = BuildSampleFlatProfile();
        flat["fight_leader"] = true;
        flat["fight_leader_selected"] = "Terrasjr [UC]";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "leader = true", "fight leader enabled flag must be serialized");
        AssertContains(content, "leader_name = \"Terrasjr\"", "fight leader selected name must be serialized without display suffixes");
        AssertNotContains(content, "Terrasjr [UC]", "fight leader display suffix must not be serialized");
        AssertNotContains(content, "leader_id =", "fight leader id must stay runtime-owned");
    }

    private static void TestSerializeOmitsFightLeaderNameWhenDisabled()
    {
        var flat = BuildSampleFlatProfile();
        flat["fight_leader"] = false;
        flat["fight_leader_selected"] = "Terrasjr [UC]";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "leader = false", "disabled fight leader checkbox state must be serialized");
        AssertNotContains(content, "leader_name = \"Terrasjr\"", "disabled fight leader must not serialize the selected durable name");
        AssertNotContains(content, "Terrasjr [UC]", "disabled fight leader display suffix must not be serialized");
    }

    private static void TestSerializeIncludesWaitIgnoreNamesAndStripsDisplayIndexes()
    {
        var flat = BuildSampleFlatProfile();
        flat["ignore_entries"] = "101:Ally One [101]|202:Ally Two [202]";
        flat["target_ignore_entries"] = "1:Mob One [1]|2:Mob Two [2]";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertContains(content, "wait_ignore_names = {", "wait ignore names must be serialized");
        AssertContains(content, "\"Ally One\"", "wait ignore names must strip display indexes");
        AssertContains(content, "\"Ally Two\"", "wait ignore names must include all names");
        AssertNotContains(content, "Ally One [101]", "wait ignore names must not serialize display indexes");
        AssertContains(content, "target_ignore_names = {", "target ignore names must be serialized");
        AssertContains(content, "\"Mob One\"", "target ignore names must strip display indexes");
        AssertContains(content, "\"Mob Two\"", "target ignore names must include all names");
        AssertNotContains(content, "Mob One [1]", "target ignore names must not serialize display indexes");
    }

    private static void TestSerializeIncludesAddPriorityTargetsAndStripsDisplayIndexes()
    {
        var flat = BuildSampleFlatProfile();
        flat["add_priority_entries"] = "1:Bozzetto Mine [1]|2:Apex Bat [2]";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertContains(content, "add_control = true", "add control flag must be serialized");
        AssertContains(content, "targets = {", "add priority targets list must be serialized");
        AssertContains(content, "\"Bozzetto Mine\"", "add priority target names must preserve order");
        AssertContains(content, "\"Apex Bat\"", "add priority target names must include every entry");
        AssertNotContains(content, "Bozzetto Mine [1]", "add priority targets must not serialize display indexes");
        AssertNotContains(content, "Apex Bat [2]", "add priority targets must not serialize display indexes");
        AssertNotContains(content, "add_priority_names", "durable add priority names must not be promoted");
    }

    private static void TestBrdOmitsHiddenCorMaintenanceDefaults()
    {
        var flat = BuildSampleFlatProfile();
        flat["cor_roll_1"] = "";
        flat["cor_roll_2"] = "";
        flat["cor_crooked_roll_slot"] = 0;
        flat["cor_elevens"] = false;
        flat["cor_luzaf_range_override"] = false;
        flat["cor_roll_range_selected"] = "";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "maintenance = {", "BRD profile should still serialize maintenance root");
        AssertNotContains(content, "cor = {", "BRD profile must omit hidden COR maintenance section when defaults are blank");
        AssertNotContains(content, "roll_1 = \"\"", "BRD profile must not serialize blank COR roll 1");
        AssertNotContains(content, "roll_2 = \"\"", "BRD profile must not serialize blank COR roll 2");
        AssertNotContains(content, "luzaf_range_override = false", "BRD profile must not serialize default COR Luzaf override");
    }

    private static void TestNonCorOmitsHiddenCorMaintenanceDefaultsAcrossJobs()
    {
        foreach (var identity in new[]
        {
            new StructuredProfileV2Identity("Redrogue", "PLD", "RDM"),
            new StructuredProfileV2Identity("Redrogue", "SAM", "DRG"),
            new StructuredProfileV2Identity("Redrogue", "GEO", "WHM"),
        })
        {
            var flat = BuildSampleFlatProfile();
            flat["cor_roll_1"] = "";
            flat["cor_roll_2"] = "";
            flat["cor_crooked_roll_slot"] = 0;
            flat["cor_elevens"] = false;
            flat["cor_luzaf_range_override"] = false;
            flat["cor_roll_range_selected"] = "";

            var content = StructuredProfileV2Writer.BuildStructuredProfileFile(flat, identity);

            AssertContains(content, "maintenance = {", $"{identity.MainJob} profile should still serialize maintenance root");
            AssertNotContains(content, "cor = {", $"{identity.MainJob} profile must omit hidden COR maintenance section when defaults are blank");
            AssertNotContains(content, "roll_1 = \"\"", $"{identity.MainJob} profile must not serialize blank COR roll 1");
            AssertNotContains(content, "roll_2 = \"\"", $"{identity.MainJob} profile must not serialize blank COR roll 2");
            AssertNotContains(content, "luzaf_range_override = false", $"{identity.MainJob} profile must not serialize default COR Luzaf override");
        }
    }

    private static void TestCorPreservesConfiguredMaintenanceValues()
    {
        var flat = BuildSampleFlatProfile();
        flat["cor_roll_1"] = "Chaos Roll";
        flat["cor_roll_2"] = "Samurai Roll";
        flat["cor_crooked_roll_slot"] = 2;
        flat["cor_elevens"] = true;
        flat["cor_luzaf_range_override"] = true;
        flat["cor_roll_range_selected"] = "Terrasjr|Nyoourke";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "COR", "WHM")
        );

        AssertContains(content, "cor = {", "COR profile must serialize maintenance COR section");
        AssertContains(content, "roll_1 = \"Chaos Roll\"", "COR profile must preserve configured roll 1");
        AssertContains(content, "roll_2 = \"Samurai Roll\"", "COR profile must preserve configured roll 2");
        AssertContains(content, "crooked_roll_slot = 2", "COR profile must preserve crooked roll slot");
        AssertContains(content, "elevens = true", "COR profile must preserve elevens mode");
        AssertContains(content, "luzaf_range_override = true", "COR profile must preserve Luzaf override");
        AssertContains(content, "range_selected = \"Terrasjr|Nyoourke\"", "COR profile must preserve range selection");
    }

    private static void TestBrdPreservesConfiguredSongMaintenance()
    {
        var flat = BuildSampleFlatProfile();
        flat["brd_maintenance_enabled"] = true;
        flat["brd_songs"] = "Honor March|Victory March|Valor Minuet V|Valor Minuet IV";
        flat["brd_dummy_songs"] = "Army's Paeon|Army's Paeon II";
        flat["brd_use_nitro"] = true;
        flat["brd_use_clarion_call"] = false;
        flat["brd_use_marcato"] = true;
        flat["brd_marcato_song"] = "Honor March";
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "brd = {", "BRD profile must serialize dedicated song maintenance");
        AssertContains(content, "enabled = true", "BRD maintenance enabled flag missing");
        AssertContains(content, "songs = {", "BRD final song list missing");
        AssertContains(content, "\"Honor March\"", "BRD final song identity missing");
        AssertContains(content, "dummy_songs = {", "BRD dummy song list missing");
        AssertContains(content, "\"Army's Paeon II\"", "BRD dummy song identity missing");
        AssertContains(content, "use_nitro = true", "BRD NITRO policy missing");
        AssertContains(content, "use_marcato = true", "BRD Marcato policy missing");
        AssertContains(content, "marcato_song = \"Honor March\"", "BRD exact Marcato song missing");
        AssertNotContains(content, "duration", "BRD runtime duration must not be durable");
    }

    private static void TestNonBrdOmitsHiddenBrdMaintenance()
    {
        var flat = BuildSampleFlatProfile();
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Terrasjr", "PLD", "RDM")
        );

        AssertNotContains(content, "brd = {", "non-BRD profile must omit hidden BRD maintenance");
        AssertNotContains(content, "dummy_songs", "non-BRD profile must not serialize hidden BRD defaults");
        AssertNotContains(content, "marcato_song", "non-BRD profile must not serialize hidden Marcato defaults");
    }

    private static void TestBrdUiEditsAreLocalUntilSave()
    {
        var root = StructuredProfileV2Writer.FindAddonRootFrom(AppContext.BaseDirectory)
            ?? throw new InvalidOperationException("addon root unavailable for BRD UI source test");
        var source = File.ReadAllText(Path.Combine(root, "UnifiedCombatWinForms", "MainForm.ParityLogic.cs"));
        var start = source.IndexOf("private void EnsureBrdTabVisibility", StringComparison.Ordinal);
        var end = source.IndexOf("private void ApplyCorRollFromSnapshot", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "BRD UI handler source range missing");
        var brdHandlers = source[start..end];
        AssertNotContains(brdHandlers, "Forward(", "BRD durable controls must not emit live bridge traffic");
        AssertContains(brdHandlers, "CaptureWorkingProfileFromUi", "BRD durable controls must update local working state");
    }

    private static void TestSerializeReactionRules()
    {
        var flat = BuildSampleFlatProfile();
        flat["reaction_enabled"] = true;
        flat["reaction_rules"] = new JsonArray
        {
            new JsonObject { ["trigger"] = "ability_window", ["name"] = "Cold Stare", ["response"] = "turn_away" },
            new JsonObject { ["trigger"] = "enemy_buff", ["name"] = "Dread Spikes", ["response"] = "stop_attacking" },
        };
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "reactions = {", "reaction domain missing");
        AssertContains(content, "trigger = \"ability_window\"", "ability-window trigger missing");
        AssertContains(content, "name = \"Cold Stare\"", "Cold Stare rule missing");
        AssertContains(content, "response = \"turn_away\"", "turn-away response missing");
        AssertContains(content, "name = \"Dread Spikes\"", "enemy-buff rule missing");
        AssertContains(content, "response = \"stop_attacking\"", "stop-attacking response missing");
        AssertNotContains(content, "actor_id", "runtime actor ids must not be durable reaction config");
        AssertNotContains(content, "effect_id", "resolved runtime effect ids must not be durable reaction config");
    }

    private static void TestDisabledEmptyReactionsAreOmitted()
    {
        var flat = BuildSampleFlatProfile();
        flat["reaction_enabled"] = false;
        flat["reaction_rules"] = new JsonArray();
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Terrasjr", "PLD", "RDM")
        );
        AssertNotContains(content, "reactions = {", "disabled empty reactions must remain optional for older profiles");
    }

    private static void TestReactionUiEditsAreLocalUntilSave()
    {
        var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var start = source.IndexOf("private void ApplyReactionRulesFromSnapshot", StringComparison.Ordinal);
        var end = source.IndexOf("private void OnBrdListAdd", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "reaction UI handler source range missing");
        var reactionHandlers = source[start..end];
        AssertNotContains(reactionHandlers, "Forward(", "reaction durable controls must not emit live bridge traffic");
        AssertContains(reactionHandlers, "CaptureWorkingProfileFromUi", "reaction durable controls must update local working state");
    }

    private static void TestSerializeConfigurableControlRanges()
    {
        var flat = BuildSampleFlatProfile();
        flat["puller_engage_range"] = 9.5;
        flat["sleep_max_target_range"] = 14.0;
        flat["sleep"] = true;
        flat["sleep_spell_entries"] = "1:Horde Lullaby II|2:Sleep II";
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
        );

        AssertContains(content, "engage_range = 9.5", "puller engage range must serialize under follow.partner");
        AssertContains(content, "max_target_range = 14", "sleep target range must serialize under config.sleep");
        AssertContains(content, "enabled = true", "Sleep enabled state must serialize from the UI control");
        AssertContains(content, "\"Horde Lullaby II\"", "ordered Sleep spells must serialize from UI profile entries");
        AssertContains(content, "legacy_primary = \"Horde Lullaby II\"", "primary Sleep compatibility value must mirror the first ordered spell");
        AssertNotContains(content, "puller_engage_range =", "flat puller range key must not leak into v2 config");
        AssertNotContains(content, "sleep_max_target_range =", "flat sleep range key must not leak into v2 config");
    }

    private static void TestControlRangeUiEditsAreLocalUntilSave()
    {
        var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var start = source.IndexOf("private void OnPullerEngageRangeChanged", StringComparison.Ordinal);
        var end = source.IndexOf("private static void ApplyBrdList", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "control range UI handler source range missing");
        var rangeHandlers = source[start..end];
        AssertNotContains(rangeHandlers, "Forward(", "durable range controls must not emit live bridge traffic");
        AssertContains(rangeHandlers, "CaptureWorkingProfileFromUi", "durable range controls must update local working state");
    }

    private static void TestUiSaveIsFileOnly()
    {
        var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(source, "TrySaveProfileFromUi(sid);", "UI save must still write the legacy profile file");
        AssertContains(source, "TrySaveStructuredProfileV2FromUi(sid);", "UI save must still write the structured profile file");
        AssertNotContains(source, "[\"op\"] = \"save\"", "UI save must not send a runtime save command");
    }

    private static void TestUiSaveSuppressesOutboundMirrorTraffic()
    {
        var mainForm = ReadRepoFile("UnifiedCombatWinForms", "MainForm.cs");
        var parity = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(mainForm, "_suppressUiSaveOutbound", "UI save must have an outbound suppression guard");
        AssertContains(mainForm, "if (_suppressUiSaveOutbound)", "outbound mirror traffic must be suppressed during UI save");
        AssertContains(parity, "_suppressUiSaveOutbound = true;", "UI save must enable the outbound suppression guard");
        AssertContains(parity, "_suppressUiSaveOutbound = false;", "UI save must release the outbound suppression guard");
        AssertNotContains(parity, "PushFullFormState(sid);", "UI save must not push runtime state back into the addon");
        AssertNotContains(parity, "await Task.Delay(200)", "UI save should not defer a runtime reapply");
    }

    private static void TestRemoteBridgeDoesNotConsumeUiSave()
    {
        var source = ReadRepoFile("remote_bridge.lua");
        AssertNotContains(source, "op == 'save'", "bridge must not treat UI save as a runtime mutation command");
        AssertNotContains(source, "_G.UC_SaveActiveProfile()", "bridge must not call the runtime save hook from UI save");
    }

    private static void TestWriteCreatesProfilesDirectory()
    {
        var flat = BuildSampleFlatProfile();
        var fs = new FakeStructuredProfileV2FileSystem();
        fs.Directories.Add(@"C:\Addon\data");

        var result = StructuredProfileV2Writer.TryWriteStructuredProfile(
            @"C:\Addon",
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR"),
            fs
        );

        AssertTrue(result.Ok, "structured profile write should succeed");
        AssertTrue(fs.CreatedDirectories.Contains(@"C:\Addon\data\profiles_v2"), "profiles_v2 directory should be created");
        AssertContains(fs.Files[@"C:\Addon\data\profiles_v2\redrogue_PLD_WAR.lua"], "version = 2", "written file content mismatch");
    }

    private static void TestWritePreservesExistingFinalOnTempWriteFailure()
    {
        var flat = BuildSampleFlatProfile();
        var fs = new FakeStructuredProfileV2FileSystem
        {
            ThrowOnWrite = true,
        };
        fs.Directories.Add(@"C:\Addon\data");
        fs.Directories.Add(@"C:\Addon\data\profiles_v2");
        fs.Files[@"C:\Addon\data\profiles_v2\redrogue_PLD_WAR.lua"] = "return { version = 2, preserved = true }\n";

        var result = StructuredProfileV2Writer.TryWriteStructuredProfile(
            @"C:\Addon",
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR"),
            fs
        );

        AssertTrue(result.Ok == false, "temp write failure should fail");
        AssertEqual(fs.Files[@"C:\Addon\data\profiles_v2\redrogue_PLD_WAR.lua"], "return { version = 2, preserved = true }\n", "final file must be preserved when temp write fails");
        AssertTrue(fs.Files.Keys.All(path => !path.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase) && !path.EndsWith(".bak", StringComparison.OrdinalIgnoreCase)), "temp or backup files should be cleaned after temp write failure");
    }

    private static void TestWritePreservesExistingFinalOnPromotionFailure()
    {
        var flat = BuildSampleFlatProfile();
        var fs = new FakeStructuredProfileV2FileSystem
        {
            FailMoveToFinal = true,
        };
        fs.Directories.Add(@"C:\Addon\data");
        fs.Directories.Add(@"C:\Addon\data\profiles_v2");
        fs.Files[@"C:\Addon\data\profiles_v2\redrogue_PLD_WAR.lua"] = "return { version = 2, preserved = true }\n";

        var result = StructuredProfileV2Writer.TryWriteStructuredProfile(
            @"C:\Addon",
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR"),
            fs
        );

        AssertTrue(result.Ok == false, "promotion failure should fail");
        AssertEqual(fs.Files[@"C:\Addon\data\profiles_v2\redrogue_PLD_WAR.lua"], "return { version = 2, preserved = true }\n", "final file must be restored when promotion fails");
        AssertTrue(fs.Files.Keys.All(path => !path.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase) && !path.EndsWith(".bak", StringComparison.OrdinalIgnoreCase)), "temp or backup files should be cleaned after promotion failure");
    }

    private static JsonObject BuildSampleFlatProfile()
    {
        var flat = new JsonObject
        {
            ["show_ingame_ui"] = true,
            ["autotarget"] = true,
            ["spam"] = true,
            ["closer"] = false,
            ["manual"] = false,
            ["prime"] = false,
            ["static"] = false,
            ["face"] = true,
            ["ability_active"] = true,
            ["abilities_selected"] = "Sentinel|Rampart",
            ["weaponskill_active"] = true,
            ["weaponskill"] = "Savage Blade",
            ["ws_mode"] = "smart",
            ["aftermath_enabled"] = true,
            ["aftermath_ws"] = "Atonement",
            ["defensive_enabled"] = true,
            ["defensive_provider"] = "internal",
            ["defensive_cure_enabled"] = true,
            ["def_heal_min_tier_cure"] = 3,
            ["def_heal_max_tier_cure"] = 4,
            ["def_heal_min_missing_hp"] = 250,
            ["def_heal_ignore_trusts"] = true,
            ["defensive_doom_water"] = true,
            ["defensive_na_enabled"] = true,
            ["def_remove_enemy_buffs"] = false,
            ["defensive_buff_enabled"] = true,
            ["defensive_buff_self_only"] = true,
            ["defensive_buffs"] = "Bar\"Spell\\Line\nNext",
            ["defensive_targeted_buffs"] = " Terrasjr : Honor March | Nyoourke: Valor Minuet V | malformed | | MissingColon ",
            ["defensive_overwrite_enabled"] = false,
            ["defensive_overwrite_interval"] = 150,
            ["defensive_critical_hpp"] = 35,
            ["defensive_medium_hpp"] = 55,
            ["move"] = true,
            ["spacing"] = true,
            ["spacing_band_min"] = -0.9,
            ["spacing_band_max"] = 0.4,
            ["spacing_model_size_floor"] = 0.9,
            ["spacing_use_prediction"] = true,
            ["spacing_lookahead_s"] = 0.25,
            ["spacing_repel_hold_ticks"] = 5,
            ["spacing_overlap_deadband"] = 0.1,
            ["spacing_repel_weight"] = 0.35,
            ["spacing_band_deadband"] = 0.2,
            ["path_recording"] = false,
            ["path_follow_enabled"] = true,
            ["path_file_name"] = "route-a",
            ["path_route_type"] = "unknown",
            ["path_party_gate_yalms"] = 3,
            ["path_resume_index_window"] = 12,
            ["path_hunter_max_z_delta"] = 2,
            ["path_hunter_max_target_range"] = 20,
            ["path_hunter_claim_timeout_s"] = 4,
            ["path_hunter_ignore_cooldown_s"] = 20,
            ["path_pull_action_type"] = "ja",
            ["path_pull_action_name"] = "Provoke",
            ["party_follow"] = true,
            ["party_follow_selected"] = "Leader",
            ["party_follow_min"] = 1,
            ["party_follow_max"] = 25,
            ["fight_follow_min"] = 3,
            ["fight_follow_hold_s"] = 8,
            ["partner"] = false,
            ["puller"] = false,
            ["puller_distance_only"] = false,
            ["ignore_entries"] = "101:Ally One|202:Ally Two",
            ["target_ignore_entries"] = "1:Mob One|2:Mob Two",
            ["add_control"] = true,
            ["tank"] = true,
            ["tank_enmity_actions"] = "Provoke|Flash",
            ["spell_active"] = true,
            ["spell"] = "Dia",
            ["cor_roll_1"] = "Chaos Roll",
            ["cor_roll_2"] = "Samurai Roll",
            ["cor_crooked_roll_slot"] = 0,
            ["cor_elevens"] = false,
            ["cor_luzaf_range_override"] = false,
            ["cor_roll_range_selected"] = "Front\"Line",
            ["debug"] = true,
            ["log_combat_sched"] = false,
            ["log_ja_sched"] = false,
            ["log_ja_debug"] = false,
            ["log_def_sched"] = true,
            ["log_tank_sched"] = false,
            ["domain_combat_enabled"] = true,
            ["domain_defensive_enabled"] = true,
            ["domain_movement_enabled"] = true,
            ["domain_maintenance_enabled"] = true,
            ["domain_follow_enabled"] = true,
            ["scheduler_dark_launch_combat"] = true,
            ["scheduler_dark_launch_defensive"] = false,
            ["scheduler_dark_launch_movement"] = false,
            ["scheduler_dark_launch_maintenance"] = false,
            ["sub"] = true,
            ["sub2"] = false,
            ["solo"] = false,
            ["aeonic"] = false,
            ["color"] = false,
            ["command"] = false,
            ["hunter"] = true,
            ["Start_Engine"] = true,
            ["fight_leader"] = true,
            ["fight_leader_id"] = 1234,
            ["add_priority_entries"] = "1:Apex Bat",
            ["sleep_spell_entries"] = "1:Horde Lullaby II",
            ["sleepspells"] = "Horde Lullaby II",
            ["sleepspell"] = "Horde Lullaby II",
        };

        return flat;
    }

    private static void AssertTrue(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void AssertEqual(string actual, string expected, string message)
    {
        if (!string.Equals(actual, expected, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{message}: expected={expected}, actual={actual}");
        }
    }

    private static void AssertEqual(int actual, int expected, string message)
    {
        if (actual != expected)
        {
            throw new InvalidOperationException($"{message}: expected={expected}, actual={actual}");
        }
    }

    private static void AssertContains(string haystack, string needle, string message)
    {
        if (haystack.IndexOf(needle, StringComparison.Ordinal) < 0)
        {
            throw new InvalidOperationException($"{message}: missing {needle}");
        }
    }

    private static void AssertNotContains(string haystack, string needle, string message)
    {
        if (haystack.IndexOf(needle, StringComparison.Ordinal) >= 0)
        {
            throw new InvalidOperationException($"{message}: unexpectedly found {needle}");
        }
    }

    private static void AssertOrder(string haystack, params string[] needles)
    {
        var lastIndex = -1;
        foreach (var needle in needles)
        {
            var index = haystack.IndexOf(needle, lastIndex + 1, StringComparison.Ordinal);
            if (index < 0)
            {
                throw new InvalidOperationException($"missing ordered token: {needle}");
            }
            if (index < lastIndex)
            {
                throw new InvalidOperationException($"token order mismatch: {needle}");
            }
            lastIndex = index;
        }
    }

    private static string ReadRepoFile(params string[] relativeParts)
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            var path = current.FullName;
            foreach (var part in relativeParts)
            {
                path = Path.Combine(path, part);
            }

            if (File.Exists(path))
            {
                return File.ReadAllText(path);
            }

            current = current.Parent;
        }

        throw new FileNotFoundException("unable to locate repo source file: " + string.Join(Path.DirectorySeparatorChar, relativeParts));
    }

    private sealed class FakeStructuredProfileV2FileSystem : IStructuredProfileV2FileSystem
    {
        public Dictionary<string, string> Files { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> Directories { get; } = new(StringComparer.OrdinalIgnoreCase);
        public List<string> CreatedDirectories { get; } = [];

        public bool ThrowOnWrite { get; init; }
        public bool FailMoveToFinal { get; init; }

        public bool DirectoryExists(string path) => Directories.Contains(path);

        public void CreateDirectory(string path)
        {
            CreatedDirectories.Add(path);
            Directories.Add(path);
        }

        public bool FileExists(string path) => Files.ContainsKey(path);

        public void WriteAllText(string path, string content)
        {
            if (ThrowOnWrite)
            {
                throw new StructuredProfileV2FileWriteException("simulated write failure");
            }

            Files[path] = content;
        }

        public void Move(string sourcePath, string destinationPath)
        {
            if (FailMoveToFinal
                && sourcePath.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase)
                && destinationPath.EndsWith(".lua", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("simulated promote failure");
            }

            if (!Files.TryGetValue(sourcePath, out var content))
            {
                throw new InvalidOperationException($"missing source file: {sourcePath}");
            }

            Files[destinationPath] = content;
            Files.Remove(sourcePath);
        }

        public void Delete(string path)
        {
            Files.Remove(path);
        }
    }
}
