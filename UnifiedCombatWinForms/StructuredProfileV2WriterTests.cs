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
            TestUiSaveIsFileOnly();
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
        AssertContains(content, "range_selected = \"Front\\\"Line\"", "range selection escaping mismatch");
        AssertNotContains(content, "file_name =", "path file name must not be serialized as durable profile data");

        AssertOrder(
            content,
            "ui = {",
            "combat = {",
            "abilities = {",
            "defensive = {",
            "movement = {",
            "follow = {",
            "targeting = {",
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

    private static void TestProfileV2AutoloadIsPartOfPersistedBoolSet()
    {
        AssertTrue(
            HubUiConstants.BoolKeys.Contains("profile_v2_autoload"),
            "autoload must be included in the shared UI bool key set so load/save paths persist it"
        );
    }

    private static void TestUiSaveIsFileOnly()
    {
        var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(source, "TrySaveProfileFromUi(sid);", "UI save must still write the legacy profile file");
        AssertContains(source, "TrySaveStructuredProfileV2FromUi(sid);", "UI save must still write the structured profile file");
        AssertNotContains(source, "PushFullFormState(sid);", "UI save must not push runtime state back into the addon");
        AssertNotContains(source, "[\"op\"] = \"save\"", "UI save must not send a runtime save command");
        AssertNotContains(source, "await Task.Delay(200)", "UI save should not defer a runtime reapply");
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
