using System.Text;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class StructuredProfileV2WriterTests
{
    public static int Run()
    {
        try
        {
            RuntimeProfileEditorAdapterTests.Run();
            TestBuildFinalPath();
            TestSerializeShapeAndEscaping();
            TestWeaponskillMinimumTpValidation();
            TestSmartWsAoePreferenceRoundTrip();
            TestSmartWsAoeUiPersistenceContract();
			TestFastSkillchainRoundTrip();
			TestFastSkillchainUiPersistenceContract();
            TestNoSkillchainTargetRoundTrip();
            TestStatusRemovalLimitProfileContract();
            TestSerializeOmitsRetiredOwnershipMarkers();
            TestParseTargetedBuffs();
            TestSerializeOmitsProfileV2AutoloadWhenDisabled();
            TestSerializeIncludesProfileV2AutoloadWhenEnabled();
            TestProfileV2AutoloadIsPartOfPersistedBoolSet();
            TestSerializeOmitsProfileV2AutoReloadWhenDisabled();
            TestSerializeIncludesProfileV2AutoReloadWhenEnabled();
            TestProfileV2AutoReloadIsPartOfPersistedBoolSet();
            TestRecoveryHoldProfileAndUiContract();
            TestActionTimelineLoggingProfileAndUiContract();
            TestSchedulerAlignedWinFormsLayoutContract();
            TestDomainOwnershipUiContract();
            TestDomainOwnershipRequiresExplicitBooleans();
            TestDomainEnabledSectionsMatchOwnership();
            TestProfileSchemaThreeMigratesMissingDomains();
            TestProfileSchemaThreePreservesExplicitDomains();
            TestProfileSchemaThreeRemovesRetiredDarkLaunchKeys();
            TestProfileSchemaFourMigratesKeiFullersDistance();
            TestScholarSublimationActivationMppMigration();
            TestSerializeIncludesPullerNameWhenSelected();
			TestSerializeCampLeashSourceWithoutPullerName();
            TestSerializeGeoMaintenance();
            TestSerializeFoodMaintenance();
            TestSerializeCampPulling();
            TestGeoPullUiOfflineContract();
			TestSerializeIncludesPartnerNames();
            TestSerializeIncludesFightLeaderNameWhenSelected();
            TestSerializeOmitsFightLeaderNameWhenDisabled();
			TestSerializeNyzulParkingRoster();
			TestSerializeOmitsUnconfiguredNyzulRoster();
			TestNyzulUiEditsAreLocalUntilSave();
            TestSerializeIncludesWaitIgnoreNamesAndStripsDisplayIndexes();
            TestSerializeIncludesAddPriorityTargetsAndStripsDisplayIndexes();
            TestBrdOmitsHiddenCorMaintenanceDefaults();
            TestNonCorOmitsHiddenCorMaintenanceDefaultsAcrossJobs();
            TestCorPreservesConfiguredMaintenanceValues();
            TestBrdPreservesConfiguredSongMaintenance();
			TestParseBardTargetedSongs();
			TestBrdRejectsUnknownTargetedSong();
			TestBrdRejectsSoulVoiceWithoutNitro();
			TestBrdRejectsInvalidRecoveryRange();
            TestNonBrdOmitsHiddenBrdMaintenance();
            TestBrdUiEditsAreLocalUntilSave();
			TestBrdRecoveryRangeUiProfilePersistenceContract();
            TestSummonerCapabilityCatalog();
            TestNonSummonerOmitsUnconfiguredSummoner();
            TestSummonerDisabledShape();
            TestSummonerConfiguredRoundTripShape();
            TestSummonerPreservesIncompatibleSelections();
            TestSummonerUiOfflineContract();
            TestPuppetmasterConfiguredRoundTripShape();
            TestNonPuppetmasterRejectsEnabledPuppetmaster();
            TestPuppetmasterUiProfilePersistenceContract();
            TestNonScholarOmitsUnconfiguredScholar();
            TestNonScholarOmitsInactiveScholarPanelState();
            TestNonScholarRejectsConfiguredScholar();
            TestScholarDisabledShape();
            TestScholarConfiguredRoundTripShape();
            TestScholarStormAssignmentValidation();
            TestScholarUiOfflineContract();
            TestSerializeReactionRules();
            TestCombatExtensionProfileContract();
            TestAutoMagicBurstProfileContract();
            TestRejectInvalidRunAwayDistance();
            TestDisabledEmptyReactionsAreOmitted();
            TestReactionUiEditsAreLocalUntilSave();
            TestSerializeGhatjotEncounter();
            TestSerializeKeiEncounter();
            TestEncounterValidation();
            TestEncounterUiProfilePersistenceContract();
            TestKeiSpellOptionRefreshRevalidatesEncounter();
            TestDisabledFormationIsOmitted();
            TestSerializeLilithEasyFormation();
            TestSerializeGenericSortieFormation();
            TestSerializeNamedMobFormations();
            TestFormationMockRejectsLilith();
            TestEnabledFormationRequiresMovementDomain();
            TestFormationUiEditsAreLocalUntilSave();
            TestFormationUiProfilePersistenceContract();
            TestFormationPartyOptionsRefreshContract();
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

    private static void TestDomainOwnershipRequiresExplicitBooleans()
    {
        var flat = BuildSampleFlatProfile();
        flat.Remove("domain_follow_enabled");

        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Terrasjr", "SMN", "SAM")
            ),
            "missing required domain ownership must fail instead of using a fallback"
        );
    }

    private static void TestDomainEnabledSectionsMatchOwnership()
    {
        var flat = BuildSampleFlatProfile();
        flat["domain_combat_enabled"] = false;
        flat["domain_movement_enabled"] = false;
        flat["domain_maintenance_enabled"] = false;
        flat["domain_follow_enabled"] = false;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Niightsiide", "GEO", "RDM")
        );

        AssertContains(
            content,
            "combat = {\n            enabled = false,",
            "combat config must serialize the selected combat-domain state"
        );
        AssertContains(
            content,
            "movement = {\n            enabled = false,",
            "movement config must serialize the selected movement-domain state"
        );
        AssertContains(
            content,
            "follow = {\n            enabled = false,",
            "follow config must serialize the selected follow-domain state"
        );
        AssertContains(
            content,
            "maintenance = {\n            enabled = false,",
            "maintenance config must serialize the selected maintenance-domain state"
        );
        AssertContains(
            content,
            "ownership = {\n            domain_combat_enabled = false,",
            "combat ownership must retain the same selected state"
        );
        AssertContains(content, "domain_movement_enabled = false,", "movement ownership must retain the same selected state");
        AssertContains(content, "domain_maintenance_enabled = false,", "maintenance ownership must retain the same selected state");
        AssertContains(content, "domain_follow_enabled = false,", "follow ownership must retain the same selected state");
    }

    private static void TestProfileSchemaThreeMigratesMissingDomains()
    {
        var profile = new JsonObject
        {
            ["profile_schema_version"] = 2,
            ["domain_combat_enabled"] = false,
        };

        AssertTrue(MainForm.MigrateProfileInPlace(profile), "schema-two profile must migrate");
        AssertEqual(profile["profile_schema_version"]!.GetValue<int>(), 8, "migrated schema version mismatch");
        AssertTrue(!profile["domain_combat_enabled"]!.GetValue<bool>(), "explicit combat domain value must be preserved");
        AssertTrue(profile["domain_defensive_enabled"]!.GetValue<bool>(), "missing defensive domain must migrate enabled");
        AssertTrue(profile["domain_movement_enabled"]!.GetValue<bool>(), "missing movement domain must migrate enabled");
        AssertTrue(profile["domain_maintenance_enabled"]!.GetValue<bool>(), "missing maintenance domain must migrate enabled");
        AssertTrue(profile["domain_follow_enabled"]!.GetValue<bool>(), "missing follow domain must migrate enabled");
    }

    private static void TestProfileSchemaThreePreservesExplicitDomains()
    {
        var profile = new JsonObject
        {
            ["profile_schema_version"] = 2,
            ["domain_combat_enabled"] = false,
            ["domain_defensive_enabled"] = false,
            ["domain_movement_enabled"] = false,
            ["domain_maintenance_enabled"] = false,
            ["domain_follow_enabled"] = false,
        };

        AssertTrue(MainForm.MigrateProfileInPlace(profile), "schema-two profile must migrate");
        foreach (var key in new[]
        {
            "domain_combat_enabled",
            "domain_defensive_enabled",
            "domain_movement_enabled",
            "domain_maintenance_enabled",
            "domain_follow_enabled",
        })
        {
            AssertTrue(!profile[key]!.GetValue<bool>(), $"explicit domain value must be preserved: {key}");
        }
    }

    private static void TestProfileSchemaThreeRemovesRetiredDarkLaunchKeys()
    {
        var profile = new JsonObject
        {
            ["profile_schema_version"] = 2,
            ["scheduler_dark_launch_combat"] = true,
            ["scheduler_dark_launch_defensive"] = true,
            ["scheduler_dark_launch_movement"] = true,
            ["scheduler_dark_launch_maintenance"] = true,
        };

        AssertTrue(MainForm.MigrateProfileInPlace(profile), "retired scheduler flags must migrate");
        AssertTrue(
            !profile.Any(entry => entry.Key.StartsWith("scheduler_dark_launch_", StringComparison.Ordinal)),
            "schema-three profile must not retain retired scheduler dark-launch keys"
        );
    }

    private static void TestProfileSchemaFourMigratesKeiFullersDistance()
    {
        var profile = new JsonObject
        {
            ["profile_schema_version"] = 3,
            ["kei_fullers_run_away_distance"] = 12.0,
        };
        AssertTrue(MainForm.MigrateProfileInPlace(profile), "schema-three Kei profile must migrate");
        AssertEqual(profile["profile_schema_version"]!.GetValue<int>(), 8, "Kei migration schema version mismatch");
        AssertTrue(profile["kei_fullers_target_distance"]!.GetValue<double>() == 12.0, "Kei target distance migration mismatch");
        AssertTrue(!profile.ContainsKey("kei_fullers_run_away_distance"), "Kei legacy distance must be removed after migration");

        var conflict = new JsonObject
        {
            ["profile_schema_version"] = 3,
            ["kei_fullers_target_distance"] = 12.0,
            ["kei_fullers_run_away_distance"] = 15.0,
        };
        AssertThrows<InvalidDataException>(
            () => MainForm.MigrateProfileInPlace(conflict),
            "conflicting Kei target-distance aliases must fail migration"
        );
    }

    private static void TestCombatExtensionProfileContract()
    {
        var migrated = new JsonObject { ["profile_schema_version"] = 4 };
        AssertTrue(MainForm.MigrateProfileInPlace(migrated), "schema-four profile must migrate to combat-extension defaults");
        AssertTrue(migrated["auto_engage"]!.GetValue<bool>(), "legacy profile must default Auto Engage on");
        AssertTrue(!migrated["magic_burst_enabled"]!.GetValue<bool>(), "legacy profile must default Magic Burst off");
        AssertEqual(migrated["spell"]!.GetValue<string>(), "", "legacy profile must default configured spell empty");

        var flat = BuildSampleFlatProfile();
        flat["auto_engage"] = false;
        flat["magic_burst_enabled"] = true;
        flat["spell"] = "Fire V";
        flat["reaction_enabled"] = true;
        flat["reaction_rules"] = new JsonArray
        {
            new JsonObject
            {
                ["trigger"] = "ability_window",
                ["name"] = "Just Desserts",
                ["response"] = "use_action",
                ["action_type"] = "spell",
                ["action_name"] = "Stun",
            },
        };
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Niightsiide", "GEO", "RDM")
        );
        AssertContains(content, "auto_engage = false", "Auto Engage must serialize independently from Auto Target");
        AssertContains(content, "configured = \"Fire V\"", "Magic Burst configured spell missing");
        AssertContains(content, "magic_burst = true", "Magic Burst toggle missing");
        AssertContains(content, "response = \"use_action\"", "use_action reaction response missing");
        AssertContains(content, "action_type = \"spell\"", "reaction action type missing");
        AssertContains(content, "action_name = \"Stun\"", "reaction action name missing");
        AssertTrue(HubUiConstants.BoolKeys.Contains("auto_engage"), "Auto Engage must be persisted by the shared UI boolean registry");
        AssertTrue(HubUiConstants.CombatTargetingUiKeys.Contains("auto_engage"), "Auto Engage must appear in Combat & Targeting UI");
        AssertTrue(HubUiConstants.BoolKeys.Contains("cor_light_shot_dia"), "COR Light Shot Dia must persist through the shared UI boolean registry");
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
        AssertContains(content, "minimum_tp = 2000", "weaponskill minimum TP missing");
        AssertContains(content, "allow_aoe = false", "Smart WS AoE preference missing");
        AssertContains(content, "configured = {", "abilities domain missing");
        AssertContains(content, "list = \"Bar\\\"Spell\\\\Line\\nNext\"", "string escaping mismatch");
        AssertContains(content, "targeted = {", "targeted defensive buff list missing");
        AssertContains(content, "character = \"Terrasjr\"", "targeted defensive buff character missing");
        AssertContains(content, "buff = \"Honor March\"", "targeted defensive buff name missing");
        AssertContains(content, "charm_sleeper = {", "charm sleeper defensive config missing");
        AssertContains(content, "enabled = true", "enabled charm sleeper value missing");
        AssertTrue(HubUiConstants.BoolKeys.Contains("def_charm_sleeper_enabled"), "charm sleeper must be in the shared UI bool key set");
        AssertContains(content, "sleep_waker = {", "sleep waker defensive config missing");
        AssertTrue(HubUiConstants.BoolKeys.Contains("def_sleep_waker_enabled"), "sleep waker must be in the shared UI bool key set");
        AssertContains(content, "limit_enabled = true", "status-removal limit missing");
        AssertContains(content, "priority = \"Poison|Paralyze|Dia\"", "status-removal priority missing");
        AssertContains(content, "curaga = {", "Curaga config missing");
        AssertContains(content, "min_targets = 4", "Curaga minimum targets missing");
        AssertContains(content, "waltz = {", "Waltz config missing");
        AssertContains(content, "tp_reserve = 1000", "Waltz TP reserve missing");
        AssertContains(content, "divine_min_targets = 2", "Divine Waltz minimum missing");
        AssertTrue(HubUiConstants.BoolKeys.Contains("defensive_curaga_enabled"), "Curaga must be a persisted UI boolean");
        AssertTrue(HubUiConstants.BoolKeys.Contains("defensive_waltz_enabled"), "Waltz must be a persisted UI boolean");
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
        AssertNotContains(content, "profile_v2_autoload", "obsolete lifecycle controls must not be serialized");
    }

    private static void TestStatusRemovalLimitProfileContract()
    {
        var flat = BuildSampleFlatProfile();
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertTrue(HubUiConstants.BoolKeys.Contains("defensive_na_limit_enabled"), "status-removal limit must be persisted as a UI boolean");
        AssertContains(content, "limit_enabled = true", "enabled status-removal limit must round trip");
        AssertContains(content, "priority = \"Poison|Paralyze|Dia\"", "status-removal priority must round trip");

        flat.Remove("defensive_na_limit_enabled");
        flat.Remove("defensive_na_priority");
        var legacy = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertContains(legacy, "limit_enabled = false", "older UI profiles must default status-removal limiting off");
        AssertContains(legacy, "priority = \"\"", "older UI profiles must default status-removal priority empty");

        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(ui, "Status Removal Priority", "status-removal priority field must be adjacent to defensive controls");
        AssertContains(logic, "_defNaPriority.Enabled = healerOn && naEnabled && limitEnabled", "priority field must only be editable in limited NA mode");
    }

    private static void TestWeaponskillMinimumTpValidation()
    {
        var flat = BuildSampleFlatProfile();
        flat["weaponskill_min_tp"] = 999;
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
            ),
            "out-of-range weaponskill minimum TP must fail"
        );
    }

	private static void TestSerializeIncludesPartnerNames()
	{
		var flat = BuildSampleFlatProfile();
		flat["partner"] = true;
		flat["partner_entries"] = "1:Ponponponponpon|2:Nyoourke";
		var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
			flat,
			new StructuredProfileV2Identity("Terrasjr", "MNK", "WAR")
		);

		AssertContains(content, "names = {", "partner names must serialize under follow.partner");
		AssertContains(content, "\"Ponponponponpon\"", "primary partner name must be durable");
		AssertContains(content, "\"Nyoourke\"", "secondary partner name must be durable");
		AssertContains(content, "secondary_enabled = true", "two durable partner names must enable the secondary partner");
	}

	private static void TestSerializeNyzulParkingRoster()
	{
		var flat = BuildSampleFlatProfile();
		flat["nyzul_coordinator_name"] = "Redrogue [UC]";
		flat["nyzul_anchor_name"] = "Terrasjr [UC]";
		flat["nyzul_parking_order"] = "Nyoourke [UC]|Ponponponponp [UC]|Niightsiide [UC]";
		var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
			flat,
			new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
		);
		AssertContains(content, "nyzul = {", "configured Nyzul roster must be serialized under follow");
		AssertContains(content, "coordinator_name = \"Redrogue\"", "Nyzul coordinator name mismatch");
		AssertContains(content, "anchor_name = \"Terrasjr\"", "Nyzul anchor name mismatch");
		AssertContains(content, "parking_order = {", "Nyzul parking order missing");
		AssertOrder(content, "\"Nyoourke\"", "\"Ponponponponp\"", "\"Niightsiide\"");
		AssertNotContains(content, "nyzul_coordinator_id", "runtime ids must not be serialized for Nyzul");
	}

	private static void TestSerializeOmitsUnconfiguredNyzulRoster()
	{
		var flat = BuildSampleFlatProfile();
		flat["nyzul_coordinator_name"] = "";
		flat["nyzul_anchor_name"] = "";
		flat["nyzul_parking_order"] = "";
		var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
			flat,
			new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
		);
		AssertNotContains(content, "nyzul = {", "unconfigured Nyzul roster must be omitted");
	}

	private static void TestNyzulUiEditsAreLocalUntilSave()
	{
		var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
		var start = source.IndexOf("private void RebindNyzulParkingList", StringComparison.Ordinal);
		var end = source.IndexOf("private void OnDefProviderSelected", start, StringComparison.Ordinal);
		AssertTrue(start >= 0 && end > start, "Nyzul UI handler source range missing");
		var handlers = source[start..end];
		AssertNotContains(handlers, "Forward(", "Nyzul durable controls must not emit live bridge traffic");
		AssertContains(handlers, "CaptureWorkingProfileFromUi", "Nyzul durable controls must update local working state");
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

    private static void TestSerializeOmitsRetiredOwnershipMarkers()
    {
        var flat = BuildSampleFlatProfile();
        flat["scheduler_dark_launch_combat"] = true;
        flat["scheduler_dark_launch_defensive"] = true;
        flat["scheduler_dark_launch_movement"] = true;
        flat["scheduler_dark_launch_maintenance"] = true;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Ponponponponpon", "COR", "DNC")
        );

        AssertNotContains(content, "scheduler_dark_launch_", "retired ownership markers must not survive a structured profile save");
    }

    private static void TestSerializeIncludesProfileV2AutoloadWhenEnabled()
    {
        var flat = BuildSampleFlatProfile();
        flat["profile_v2_autoload"] = true;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );

        AssertNotContains(content, "profile_v2_autoload", "legacy true autoload input must be ignored");
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

        AssertNotContains(content, "profile_v2_auto_reload_on_change", "legacy true auto-reload input must be ignored");
    }

    private static void TestProfileV2AutoloadIsPartOfPersistedBoolSet()
    {
        AssertTrue(!HubUiConstants.BoolKeys.Contains("profile_v2_autoload"), "autoload must not remain a UI boolean");
    }

    private static void TestProfileV2AutoReloadIsPartOfPersistedBoolSet()
    {
        AssertTrue(!HubUiConstants.BoolKeys.Contains("profile_v2_auto_reload_on_change"), "auto-reload must not remain a UI boolean");
    }

    private static void TestDomainOwnershipUiContract()
    {
        foreach (var key in new[]
        {
            "domain_combat_enabled",
            "domain_defensive_enabled",
            "domain_movement_enabled",
            "domain_maintenance_enabled",
            "domain_follow_enabled",
        })
        {
            AssertTrue(HubUiConstants.BoolKeys.Contains(key), $"{key} must be an editable UI boolean");
        }

        var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        AssertContains(source, "MkGlobal(\"domain_combat_enabled\")", "combat domain control missing");
        AssertContains(source, "MkGlobal(\"domain_defensive_enabled\")", "defensive domain control missing");
        AssertContains(source, "MkGlobal(\"domain_movement_enabled\")", "movement domain control missing");
        AssertContains(source, "MkGlobal(\"domain_maintenance_enabled\")", "maintenance domain control missing");
        AssertContains(source, "MkGlobal(\"domain_follow_enabled\")", "follow domain control missing");
        foreach (var key in new[]
        {
            "scheduler_dark_launch_combat",
            "scheduler_dark_launch_defensive",
            "scheduler_dark_launch_movement",
            "scheduler_dark_launch_maintenance",
        })
        {
            AssertTrue(!HubUiConstants.BoolKeys.Contains(key), $"{key} must be retired from UI booleans");
            AssertNotContains(source, key, $"{key} must be absent from the scheduler UI");
        }
        AssertNotContains(source, "Dark-launch toggles: opt into", "obsolete ownership guidance must be removed");
    }

    private static void TestSchedulerAlignedWinFormsLayoutContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var geoPullUi = ReadRepoFile("UnifiedCombatWinForms", "MainForm.GeoPullUi.cs");
        var profileStore = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");

        foreach (var oldTopCard in new[] { "Healer / Defensive", "Combat Engine", "Behavior / Legacy", "Display / Misc" })
        {
            AssertNotContains(ui, oldTopCard, $"legacy top card '{oldTopCard}' must be removed");
        }
        AssertNotContains(ui, "CreateBoolCard", "legacy top-card builder must be removed");
        AssertNotContains(ui, "MkGlobal(\"Start_Engine\")", "engine run must remain owned by the session controls");

        AssertTrue(
            HubUiConstants.DefensiveUiKeys.SequenceEqual(
                new[]
                {
                    "defensive_enabled",
                    "defensive_cure_enabled",
                    "defensive_resurrection_enabled",
                    "defensive_curaga_enabled",
                    "defensive_waltz_enabled",
                    "defensive_doom_water",
                    "def_charm_sleeper_enabled",
                    "def_sleep_waker_enabled",
                    "def_remove_enemy_buffs",
                    "def_maintain_enemy_debuffs",
                    "defensive_na_enabled",
                    "defensive_na_limit_enabled",
                    "defensive_buff_enabled",
                    "defensive_overwrite_enabled",
                    "defensive_buff_self_only",
                }
            ),
            "defensive controls must be registered in the General defensive section"
        );
        AssertTrue(
            HubUiConstants.CombatTargetingUiKeys.SequenceEqual(new[] { "autotarget", "auto_engage", "ability_allow_unengaged", "tank_enmity_include_pets", "prime", "spam", "solo", "manual", "pause_automation_while_weakened" }),
            "combat and targeting controls must be registered together"
        );
        AssertTrue(
            HubUiConstants.SpacingMovementUiKeys.SequenceEqual(new[] { "face", "spacing", "static", "move" }),
            "movement controls must be registered in Spacing Tuning"
        );
        AssertContains(ui, "MkGlobal(\"sleep\")", "Sleep enable control must be in the Sleep section");
        AssertContains(ui, "MkGlobal(\"tank\")", "Tank enable control must be in the Tank section");
        AssertContains(ui, "MkGlobal(\"hunter\")", "Hunter enable control must be in Pathing");
        AssertContains(ui, "MkGlobal(\"add_control\")", "add control must be in Fight Leader / Add Control");
        AssertContains(
            geoPullUi,
            "CreateGlobalBoolCheckBox(\"puller_distance_only\")",
            "puller distance-only control must be in Camp Pulling"
        );
        AssertNotContains(ui, "new TabPage(\"Profile / Lifecycle\")", "obsolete profile lifecycle tab must be removed");

        var removed = new[] { "show_ingame_ui", "closer", "sub", "sub2", "command", "aeonic", "color" };
        AssertTrue(
            HubUiConstants.CompatibilityOnlyBoolKeys.SequenceEqual(removed),
            "removed controls must remain explicitly owned by compatibility persistence"
        );
        foreach (var key in removed)
        {
            AssertTrue(HubUiConstants.BoolKeys.Contains(key), $"legacy key '{key}' must remain persisted");
            AssertNotContains(ui, $"MkGlobal(\"{key}\")", $"dead control '{key}' must not be rendered");
        }
        AssertContains(profileStore, "ReadPersistedBoolValue", "profile save must preserve non-visual compatibility booleans");
    }

    private static void TestRecoveryHoldProfileAndUiContract()
    {
        var flat = BuildSampleFlatProfile();
        flat["pause_automation_while_weakened"] = true;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertContains(content, "pause_automation_while_weakened = true", "recovery hold must serialize into profile v2 ownership");
        AssertTrue(HubUiConstants.GlobalBoolKeys.Contains("pause_automation_while_weakened"), "recovery hold must persist as a global UI boolean");
        AssertEqual(HubUiConstants.BoolLabel("pause_automation_while_weakened"), "Pause automation while weakened", "recovery hold label mismatch");
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        AssertContains(ui, "While weakened after Raise", "recovery hold tooltip must explain manual recovery positioning");
    }

    private static void TestActionTimelineLoggingProfileAndUiContract()
    {
        var flat = BuildSampleFlatProfile();
        flat["log_action_timeline"] = true;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Ponponponponpon", "GEO", "RDM")
        );

        AssertContains(content, "action_timeline = true", "action timeline logging must serialize into profile v2 debug config");
        AssertTrue(HubUiConstants.GlobalBoolKeys.Contains("log_action_timeline"), "action timeline logging must persist as a global UI boolean");
        AssertTrue(HubUiConstants.DiagnosticsUiKeys.Contains("log_action_timeline"), "action timeline logging must render in Scheduler diagnostics");
        AssertEqual(HubUiConstants.BoolLabel("log_action_timeline"), "Log: action timeline", "action timeline label mismatch");

        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        AssertContains(ui, "file watcher applies valid changes automatically", "Scheduler UI must describe Save as watcher-applied");
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

	private static void TestSerializeCampLeashSourceWithoutPullerName()
	{
		var flat = BuildSampleFlatProfile();
		flat["puller"] = true;
		flat["puller_selected"] = "Niightsiide";
		flat["puller_leash_source"] = "camp";

		var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
			flat,
			new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
		);

		AssertContains(content, "leash_source = \"camp\"", "camp leash source must serialize durably");
		AssertNotContains(content, "puller_name =", "camp leash must not serialize a stale puller name");
		var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
		var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
		var main = ReadRepoFile("UnifiedCombatWinForms", "MainForm.cs");
		var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
		var bridge = ReadRepoFile("remote_bridge.lua");
		AssertContains(ui, "Set camp here", "camp capture button must exist");
		AssertContains(store, "[\"puller_leash_source\"] = leashSource.ToLowerInvariant()", "camp leash source must be captured by UI profiles");
		AssertContains(main, "string.Equals(op, \"camp_set\"", "camp capture must be an explicit runtime bridge operation");
		AssertContains(main, "ApplyCampRuntimeStatus(selectedState)", "recurring live snapshots must refresh camp status");
		AssertContains(logic, "Camp unavailable — reload UnifiedCombat addon", "missing runtime support must produce an actionable camp status");
		AssertContains(logic, "camp_coordinate_mode", "camp status must distinguish XYZ from legacy XY state");
		AssertContains(bridge, "camp_z = camp_status.z", "runtime bridge must expose camp z");
		AssertContains(bridge, "camp_coordinate_mode = camp_status.coordinate_mode", "runtime bridge must expose camp coordinate mode");
	}

    private static void TestSerializeFoodMaintenance()
    {
        var flat = BuildSampleFlatProfile();
        flat["food_enabled"] = true;
        flat["food_item"] = "Grape Daifuku";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Niightsiide", "WHM", "SCH")
        );

        AssertContains(content, "food = {", "food maintenance domain must serialize");
        AssertContains(content, "item = \"Grape Daifuku\"", "configured food item must serialize");

        flat["food_item"] = "";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Niightsiide", "WHM", "SCH")
            ),
            "enabled food maintenance must require an item name"
        );

        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(ui, "Text = \"Use Food\"", "food enable control must exist");
        AssertContains(ui, "PlaceholderText = \"Food item name\"", "food item control must exist");
        AssertContains(store, "[\"food_enabled\"] = _foodEnabled.Checked", "food enabled state must persist");
        AssertContains(store, "[\"food_item\"] = (_foodItem.Text ?? \"\").Trim()", "food item name must persist");
        AssertContains(logic, "SessionStateHelper.GetBool(s, \"food_enabled\", false)", "food enabled state must reload");
        AssertContains(logic, "SessionStateHelper.GetString(s, \"food_item\", \"\")", "food item name must reload");
    }

    private static void TestSerializeGeoMaintenance()
    {
        var flat = BuildSampleFlatProfile();
        flat["geo_maintenance_enabled"] = true;
        flat["geo_spell"] = "Geo-Frailty";
        flat["indi_spell"] = "Indi-Haste";
        flat["geo_target_kind"] = "party_member";
        flat["geo_target_name"] = "Terrasjr";
        flat["geo_ordering"] = "indi_first";
        flat["geo_luopan_placement"] = "camp";
        flat["geo_require_camp"] = true;
        flat["geo_camp_tolerance_yalms"] = 1.5;
        flat["geo_entrust_enabled"] = true;
        flat["geo_entrust_spell"] = "Indi-Fury";
        flat["geo_entrust_target_name"] = "Nyoourke";
        flat["geo_use_blaze_of_glory"] = true;
        flat["geo_use_ecliptic_attrition"] = true;
        flat["geo_use_life_cycle"] = true;
        flat["geo_life_cycle_hpp"] = 45;
        flat["geo_replace_out_of_position"] = true;
        flat["geo_enemy_requires_camp_radius"] = true;
        flat["geo_max_camp_distance_yalms"] = 7.5;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "GEO", "RDM")
        );

        AssertContains(content, "geo_spell = \"Geo-Frailty\"", "GEO spell must serialize");
        AssertContains(content, "kind = \"party_member\"", "GEO target kind must serialize");
        AssertContains(content, "name = \"Terrasjr\"", "GEO target name must serialize");
        AssertContains(content, "indi_spell = \"Indi-Haste\"", "Indi spell must serialize");
        AssertContains(content, "ordering = \"indi_first\"", "GEO ordering must serialize");
        AssertContains(content, "placement = \"camp\"", "Luopan placement must serialize");
        AssertContains(content, "spell = \"Indi-Fury\"", "Entrust spell must serialize");
        AssertContains(content, "target_name = \"Nyoourke\"", "Entrust target must serialize");
        AssertContains(content, "use_blaze_of_glory = true", "Blaze of Glory policy must serialize");
        AssertContains(content, "life_cycle_hpp = 45", "Life Cycle threshold must serialize");
        AssertContains(content, "enemy_geo_requires_camp_radius = true", "enemy Geo camp-radius policy must serialize");
        AssertContains(content, "max_camp_distance_yalms = 7.5", "luopan camp radius must serialize");

        flat.Remove("geo_luopan_placement");
        var missingPlacementContent = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "GEO", "RDM")
        );
        AssertContains(missingPlacementContent, "placement = \"target\"", "missing Luopan placement must default to target");

        flat["geo_luopan_placement"] = "target";
        var targetPlacementContent = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "GEO", "RDM")
        );
        AssertContains(targetPlacementContent, "placement = \"target\"", "target Luopan placement must round-trip");

        flat["geo_luopan_placement"] = "caster";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "GEO", "RDM")
            ),
            "GEO maintenance must reject an unsupported Luopan placement"
        );
        flat["geo_luopan_placement"] = "camp";
        flat["geo_require_camp"] = false;
        var remoteCampPlacementContent = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "GEO", "RDM")
        );
        AssertContains(remoteCampPlacementContent, "placement = \"camp\"", "camp placement must remain enabled independently");
        AssertContains(remoteCampPlacementContent, "require_camp = false", "camp placement must not force require_camp");
        flat["geo_require_camp"] = true;

        flat["geo_spell"] = "Frailty";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "GEO", "RDM")
            ),
            "enabled GEO maintenance must reject a non-Geo spell name"
        );
    }

    private static void TestSerializeCampPulling()
    {
        var flat = BuildSampleFlatProfile();
        flat["camp_pulling_enabled"] = true;
        flat["camp_pulling_action_type"] = "spell";
        flat["camp_pulling_action_name"] = "Dia";
        flat["camp_pulling_targets"] = "Apex Bat:20|Apex Crab:10";
        flat["camp_pulling_match_mode"] = "exact";
        flat["camp_pulling_max_active_mobs"] = 2;
        flat["camp_pulling_replenish_below_hpp"] = 15;
        flat["camp_pulling_leash_yalms"] = 40.0;
        flat["camp_pulling_max_z_delta"] = 3.0;
        flat["camp_pulling_cast_range_ratio"] = 0.85;
        flat["camp_pulling_settle_seconds"] = 0.5;
        flat["camp_pulling_reaction_timeout_seconds"] = 5.0;
        flat["camp_pulling_retry_limit"] = 3;
        flat["camp_pulling_retry_window_seconds"] = 3.0;
        flat["camp_pulling_target_cooldown_seconds"] = 25.0;
        flat["camp_pulling_camp_arrival_yalms"] = 1.0;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "THF", "DNC")
        );

        AssertContains(content, "mode = \"camp\"", "camp pulling mode must serialize");
        AssertContains(content, "type = \"spell\"", "camp pull action type must serialize");
        AssertContains(content, "name = \"Dia\"", "camp pull action name must serialize");
        AssertContains(content, "name = \"Apex Bat\"", "first camp pull target must serialize");
        AssertContains(content, "priority = 20", "camp pull target priority must serialize");
        AssertContains(content, "max_active_mobs = 2", "camp pull quota must serialize");
        AssertContains(content, "cast_range_ratio = 0.85", "camp pull range ratio must serialize");
        AssertContains(content, "camp_arrival_yalms = 1", "camp arrival radius must serialize");

        flat["camp_pulling_targets"] = "Apex Bat";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "THF", "DNC")
            ),
            "camp pulling must reject targets without an explicit priority"
        );
    }

    private static void TestGeoPullUiOfflineContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.GeoPullUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var main = ReadRepoFile("UnifiedCombatWinForms", "MainForm.cs");
        var bridge = ReadRepoFile("remote_bridge.lua");
        AssertContains(ui, "OnGeoPullConfigChanged", "GEO and camp pulling controls need a durable edit handler");
        AssertContains(ui, "Only cast enemy Geo within the camp radius", "GEO UI must expose the enemy camp-radius policy");
        AssertContains(ui, "Luopan placement", "GEO UI must expose Luopan placement");
        AssertContains(ui, "uses the shared camp XYZ", "GEO UI must explain shared XYZ placement");
        AssertContains(ui, "_geoLuopanPlacement.Enabled = geoEnabled", "Luopan placement must disable with GEO maintenance");
        AssertContains(ui, "_geoRequireCamp.Enabled = geoEnabled", "require_camp must remain independently editable");
        AssertNotContains(ui, "campPlacement && !_geoRequireCamp.Checked", "camp placement must not force require_camp");
        AssertContains(ui, "_geoReplaceOutOfPosition.Enabled = geoEnabled && campPlacement", "camp replacement controls must require camp placement");
        AssertContains(ui, "CaptureWorkingProfileFromUi", "GEO and camp pulling edits must update local profile state");
        AssertNotContains(ui, "Forward(", "GEO and camp pulling edits must not emit live mirror commands");
        AssertContains(store, "[\"geo_maintenance_enabled\"]", "GEO enabled state must persist in flat UI profiles");
        AssertContains(store, "[\"geo_luopan_placement\"]", "Luopan placement must persist in flat UI profiles");
        AssertContains(store, "[\"geo_enemy_requires_camp_radius\"]", "enemy Geo camp-radius policy must persist in flat UI profiles");
        AssertContains(store, "[\"camp_pulling_enabled\"]", "camp pulling enabled state must persist in flat UI profiles");
        AssertContains(store, "[\"camp_pulling_targets\"]", "camp pull targets must persist in flat UI profiles");
        AssertContains(main, "ApplyGeoPullRuntimeStatus(selectedState)", "live snapshots must refresh GEO/pull status labels");
        AssertContains(main, "EnsureGeoTabVisibility(false)", "GEO tab must start hidden before a job is selected");
        AssertContains(ui, "_tabGeo = new TabPage(\"GEO\")", "GEO tab must have a stable job-gated tab instance");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(
            logic,
            "EnsureGeoTabVisibility(geoVisible)",
            "GEO tab visibility must follow main/sub job eligibility"
        );
        AssertContains(logic, "string.Equals(subJob, \"GEO\"", "GEO subjob must make the GEO tab visible");
        AssertContains(bridge, "geo_runtime_state = geo_runtime.state", "bridge must publish GEO runtime status");
        AssertContains(bridge, "camp_pull_runtime_state = pull_runtime.state", "bridge must publish camp-puller runtime status");
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
		flat["brd_use_soul_voice"] = true;
        flat["brd_use_clarion_call"] = false;
        flat["brd_use_marcato"] = true;
        flat["brd_marcato_song"] = "Honor March";
		flat["brd_targeted_songs"] = "Tankone,Tanktwo:Mage's Ballad III,Mage's Ballad II";
		flat["brd_song_options"] = "Honor March|Victory March|Valor Minuet V|Valor Minuet IV|Mage's Ballad III|Mage's Ballad II";
		flat["brd_recovery_range_yalms"] = 14.5;
		flat["brd_reposition_for_party_songs"] = true;
		flat["brd_recovery_ignore_names"] = "PullerOne|PullerTwo";
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
		AssertContains(content, "use_soul_voice = true", "BRD Soul Voice policy missing");
        AssertContains(content, "use_marcato = true", "BRD Marcato policy missing");
        AssertContains(content, "marcato_song = \"Honor March\"", "BRD exact Marcato song missing");
		AssertContains(content, "targeted_songs = {", "BRD targeted song sets missing");
		AssertContains(content, "\"Tanktwo\"", "BRD targeted recipient missing");
		AssertContains(content, "priority_songs = {", "BRD targeted priority songs missing");
		AssertContains(content, "\"Mage's Ballad II\"", "BRD targeted priority song identity missing");
		AssertContains(content, "recovery_range_yalms = 14.5", "BRD recovery range missing");
		AssertContains(content, "reposition_for_party_songs = true", "BRD party reposition policy missing");
		AssertContains(content, "recovery_ignore_names = {", "BRD recovery ignore list missing");
		AssertContains(content, "\"PullerTwo\"", "BRD recovery ignore player missing");
        AssertNotContains(content, "duration", "BRD runtime duration must not be durable");
    }

	private static void TestParseBardTargetedSongs()
	{
		var parsed = StructuredProfileV2Writer.ParseBardTargetedSongs(
			"Tankone,Tanktwo:Mage's Ballad III,Mage's Ballad II|Healer:Victory March"
		);
		AssertEqual(parsed.Count, 2, "BRD targeted parser set count mismatch");
		AssertEqual(parsed[0].Recipients[1], "Tanktwo", "BRD targeted parser recipient mismatch");
		AssertEqual(parsed[0].PrioritySongs[0], "Mage's Ballad III", "BRD targeted parser priority mismatch");
		var duplicateSongRejected = false;
		try
		{
			_ = StructuredProfileV2Writer.ParseBardTargetedSongs("Tank:Victory March,Victory March");
		}
		catch (InvalidDataException ex)
		{
			AssertContains(ex.Message, "repeats a song", "duplicate BRD targeted song reason mismatch");
			duplicateSongRejected = true;
		}
		if (!duplicateSongRejected)
		{
			throw new InvalidOperationException("duplicate BRD targeted song must fail parsing");
		}
		try
		{
			_ = StructuredProfileV2Writer.ParseBardTargetedSongs("Tank:Victory March|tank:Honor March");
		}
		catch (InvalidDataException ex)
		{
			AssertContains(ex.Message, "appears more than once", "duplicate BRD targeted recipient reason mismatch");
			return;
		}
		throw new InvalidOperationException("duplicate BRD targeted recipient must fail parsing");
	}

	private static void TestBrdRejectsUnknownTargetedSong()
	{
		var flat = BuildSampleFlatProfile();
		flat["brd_maintenance_enabled"] = true;
		flat["brd_targeted_songs"] = "Redrogue:Mages Ballad III";
		flat["brd_song_options"] = "Honor March|Mage's Ballad III";
		AssertThrows<InvalidDataException>(
			() => StructuredProfileV2Writer.BuildStructuredProfileFile(
				flat,
				new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
			),
			"invalid BRD targeted song must be rejected before profile write"
		);
	}

	private static void TestBrdRejectsSoulVoiceWithoutNitro()
	{
		var flat = BuildSampleFlatProfile();
		flat["brd_use_nitro"] = false;
		flat["brd_use_soul_voice"] = true;
		try
		{
			_ = StructuredProfileV2Writer.BuildStructuredProfileFile(
				flat,
				new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
			);
		}
		catch (InvalidDataException ex)
		{
			AssertContains(ex.Message, "requires NITRO", "Soul Voice without NITRO failure reason mismatch");
			return;
		}
		throw new InvalidOperationException("BRD Soul Voice without NITRO must fail profile serialization");
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

	private static void TestBrdRejectsInvalidRecoveryRange()
	{
		var flat = BuildSampleFlatProfile();
		flat["brd_recovery_range_yalms"] = 20.1;
		try
		{
			_ = StructuredProfileV2Writer.BuildStructuredProfileFile(
				flat,
				new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
			);
		}
		catch (InvalidDataException ex)
		{
			AssertContains(ex.Message, "brd_recovery_range_yalms", "invalid BRD recovery range failure reason mismatch");
			return;
		}
		throw new InvalidOperationException("invalid BRD recovery range must fail profile serialization");
	}

    private static void TestBrdUiEditsAreLocalUntilSave()
    {
        var root = StructuredProfileV2Writer.FindAddonRootFrom(AppContext.BaseDirectory)
            ?? throw new InvalidOperationException("addon root unavailable for BRD UI source test");
        var source = File.ReadAllText(Path.Combine(root, "UnifiedCombatWinForms", "MainForm.ParityLogic.cs"));
        var start = source.IndexOf("private void EnsureBrdTabVisibility", StringComparison.Ordinal);
        var end = source.IndexOf("private void OnMagicBurstConfigChanged", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "BRD UI handler source range missing");
        var brdHandlers = source[start..end];
        AssertNotContains(brdHandlers, "Forward(", "BRD durable controls must not emit live bridge traffic");
        AssertContains(brdHandlers, "CaptureWorkingProfileFromUi", "BRD durable controls must update local working state");
    }

	private static void TestBrdRecoveryRangeUiProfilePersistenceContract()
	{
		var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
		var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
		var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
		var writer = ReadRepoFile("UnifiedCombatWinForms", "StructuredProfileV2Writer.cs");
		AssertContains(ui, "_brdRecoveryRangeYalms = new NumericUpDown", "BRD recovery range control must exist");
		AssertContains(store, "[\"brd_recovery_range_yalms\"] = decimal.ToDouble(_brdRecoveryRangeYalms.Value)", "BRD recovery range must be captured from the UI");
		AssertContains(store, "[\"brd_recovery_range_yalms\"] = 9.9", "BRD recovery range must have a durable UI default");
		AssertContains(logic, "ApplyBrdRecoveryRange(s);", "BRD recovery range must restore from UI profiles");
		AssertContains(writer, ".Add(\"recovery_range_yalms\"", "BRD recovery range must serialize into structured profiles");
		AssertContains(ui, "_brdRepositionForPartySongs = new UcToggle", "BRD party reposition control must exist");
		AssertContains(store, "[\"brd_reposition_for_party_songs\"] = _brdRepositionForPartySongs.Checked", "BRD party reposition policy must be captured from the UI");
		AssertContains(store, "[\"brd_reposition_for_party_songs\"] = false", "BRD party reposition policy must have a durable UI default");
		AssertContains(logic, "_brdRepositionForPartySongs.Checked = SessionStateHelper.GetBool", "BRD party reposition policy must restore from UI profiles");
		AssertContains(writer, ".Add(\"reposition_for_party_songs\"", "BRD party reposition policy must serialize into structured profiles");
		AssertContains(ui, "_brdUseSoulVoice = new UcToggle", "BRD Soul Voice control must exist");
		AssertContains(store, "[\"brd_use_soul_voice\"] = _brdUseSoulVoice.Checked", "BRD Soul Voice policy must be captured from the UI");
		AssertContains(ui, "_brdTargetedSongs = new TextBox", "BRD targeted song control must exist");
		AssertContains(writer, ".Add(\"targeted_songs\"", "BRD targeted songs must serialize into structured profiles");
	}

    private static void TestSummonerCapabilityCatalog()
    {
        AssertEqual(SummonerCapabilities.Avatars.Count, 11, "supported Summoner avatar count mismatch");
        var ifrit = SummonerCapabilities.FindAvatar("Ifrit")
            ?? throw new InvalidOperationException("Ifrit capability missing");
        AssertEqual(ifrit.SummonSpellId, 298, "Ifrit summon spell id mismatch");
        AssertTrue(
            ifrit.Wards.Any(action => action.Name == "Crimson Howl" && action.EffectId == 68),
            "Crimson Howl Ward metadata missing"
        );
		AssertEqual(
			SummonerCapabilities.FindWard("Hastega II")?.Avatar ?? "",
			"Garuda",
			"global Ward ownership mismatch"
		);
		var growl = SummonerCapabilities.FindWard("Ecliptic Growl")
			?? throw new InvalidOperationException("Ecliptic Growl capability missing");
		AssertEqual(growl.Avatar, "Fenrir", "Ecliptic Growl owner mismatch");
		AssertEqual(growl.EffectIds.Count, 7, "Ecliptic Growl effect count mismatch");
		AssertEqual(growl.EffectIds[6], 125, "Ecliptic Growl final effect mismatch");
		var howl = SummonerCapabilities.FindWard("Ecliptic Howl")
			?? throw new InvalidOperationException("Ecliptic Howl capability missing");
		AssertEqual(howl.EffectIds.Count, 2, "Ecliptic Howl effect count mismatch");
		AssertTrue(
			SummonerCapabilities.FindWard("Lunar Cry") is null,
			"enemy-targeted Fenrir Ward must not be offered for maintenance"
		);
        AssertTrue(
            ifrit.Rages.Any(action => action.Name == "Flaming Crush" && action.Id == 550),
            "Flaming Crush Rage metadata missing"
        );
        AssertTrue(
            !SummonerCapabilities.IsCompatible("Garuda", "rage", "Flaming Crush"),
            "cross-avatar Rage must be incompatible"
        );
    }

    private static void TestNonSummonerOmitsUnconfiguredSummoner()
    {
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            BuildSampleFlatProfile(),
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertNotContains(content, "summoner = {", "unconfigured non-SMN profile must remain backward compatible");
    }

    private static void TestSummonerDisabledShape()
    {
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            BuildSampleFlatProfile(),
            new StructuredProfileV2Identity("Redrogue", "SMN", "RDM")
        );
        AssertContains(content, "summoner = {", "SMN profile must include the durable Summoner domain");
        AssertContains(content, "avatar = nil", "disabled SMN profile must persist no desired avatar");
        AssertContains(content, "avatar_favor = false", "disabled SMN profile Favor default mismatch");
        AssertContains(content, "engage_on_combat_start = false", "disabled SMN engage default mismatch");
        AssertContains(content, "usage = \"on_cooldown\"", "disabled SMN Rage usage default mismatch");
        AssertContains(content, "target_hpp_above_enabled = false", "disabled target HPP gate default mismatch");
        AssertContains(content, "target_hpp_above = 50", "target HPP threshold default mismatch");
        AssertContains(content, "pet_tp_above_enabled = false", "disabled pet TP gate default mismatch");
        AssertContains(content, "pet_tp_above = 2000", "pet TP threshold default mismatch");
    }

    private static void TestSummonerConfiguredRoundTripShape()
    {
        var flat = BuildSampleFlatProfile();
        flat["summoner_enabled"] = true;
        flat["summoner_avatar"] = "Ifrit";
        flat["summoner_avatar_favor"] = true;
        flat["summoner_ward_enabled"] = true;
        flat["summoner_ward_action"] = "Crimson Howl";
		flat["summoner_ward_actions"] = "Crimson Howl|Hastega II";
        flat["summoner_engage_on_combat_start"] = true;
        flat["summoner_rage_enabled"] = true;
        flat["summoner_rage_action"] = "Flaming Crush";
        flat["summoner_rage_usage"] = "on_cooldown";
        flat["summoner_rage_target_hpp_above_enabled"] = true;
        flat["summoner_rage_target_hpp_above"] = 50;
        flat["summoner_rage_pet_tp_above_enabled"] = true;
        flat["summoner_rage_pet_tp_above"] = 2999;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "SMN", "RDM")
        );
        AssertContains(content, "avatar = \"Ifrit\"", "desired avatar must serialize");
		AssertContains(content, "actions = {", "Ward action list must serialize");
		AssertContains(content, "\"Crimson Howl\"", "primary-avatar Ward must serialize");
		AssertContains(content, "\"Hastega II\"", "cross-avatar Ward must serialize");
        AssertContains(content, "action = \"Flaming Crush\"", "Rage action must serialize");
        AssertContains(content, "avatar_favor = true", "Favor policy must serialize");
        AssertContains(content, "engage_on_combat_start = true", "engagement policy must serialize");
        AssertContains(content, "target_hpp_above_enabled = true", "target HPP gate must serialize");
        AssertContains(content, "target_hpp_above = 50", "target HPP threshold must serialize");
        AssertContains(content, "pet_tp_above_enabled = true", "pet TP gate must serialize");
        AssertContains(content, "pet_tp_above = 2999", "pet TP threshold must serialize");
    }

    private static void TestSummonerPreservesIncompatibleSelections()
    {
        var flat = BuildSampleFlatProfile();
        flat["summoner_enabled"] = true;
        flat["summoner_avatar"] = "Garuda";
        flat["summoner_ward_enabled"] = true;
		flat["summoner_ward_action"] = "Not a Ward";
		flat["summoner_ward_actions"] = "Not a Ward";
        flat["summoner_rage_enabled"] = true;
        flat["summoner_rage_action"] = "Flaming Crush";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "SMN", "RDM")
        );
        AssertContains(content, "avatar = \"Garuda\"", "changed desired avatar must serialize");
		AssertContains(content, "\"Not a Ward\"", "unsupported Ward must be preserved");
        AssertContains(content, "action = \"Flaming Crush\"", "incompatible Rage must be preserved");
    }

    private static void TestSummonerUiOfflineContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var project = ReadRepoFile("UnifiedCombatWinForms", "UnifiedCombatWinForms.csproj");
        AssertContains(ui, "new TabPage(\"SMN\")", "Summoner tab must be available without runtime state");
        AssertContains(ui, "SummonerCapabilities.Avatars", "avatar options must come from the static catalog");
        AssertContains(store, "[\"summoner_enabled\"] = _summonerEnabled.Checked", "Summoner enabled state must be captured");
		AssertContains(store, "[\"summoner_ward_actions\"]", "Summoner Ward rotation must be captured");
        AssertContains(store, "[\"summoner_rage_action\"] = _summonerRageAction.SelectedItem", "Summoner Rage must be captured");
        AssertContains(store, "[\"summoner_rage_target_hpp_above_enabled\"]", "target HPP gate must be captured");
        AssertContains(store, "[\"summoner_rage_pet_tp_above_enabled\"]", "pet TP gate must be captured");
		AssertContains(logic, "BindSummonerWardList", "Summoner Ward rotation must come from the catalog");
        AssertContains(logic, "incompatible with", "invalidated selections must be visibly diagnosed");
        AssertContains(logic, "EnsureSummonerTabVisibility(summonerVisible)", "SMN tab visibility must follow main/sub job eligibility");
        AssertContains(logic, "string.Equals(subJob, \"SMN\"", "SMN subjob must make the SMN tab visible");
        AssertContains(
            ReadRepoFile("UnifiedCombatWinForms", "MainForm.cs"),
            "EnsureSummonerTabVisibility(false)",
            "SMN tab must start hidden before a job is selected"
        );
        AssertContains(project, "summoner_capabilities.tsv", "Summoner catalog must be embedded for offline UI use");

        var start = logic.IndexOf("private static void BindSummonerActionCombo", StringComparison.Ordinal);
        var end = logic.IndexOf("private void EnsureBrdTabVisibility", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "Summoner UI handler source range missing");
        var handlers = logic[start..end];
        AssertContains(handlers, "CaptureWorkingProfileFromUi", "Summoner edits must update local working state");
        AssertNotContains(handlers, "Forward(", "Summoner durable controls must not require a live addon connection");
    }

    private static void TestPuppetmasterConfiguredRoundTripShape()
    {
        var flat = BuildSampleFlatProfile();
        flat["puppetmaster_enabled"] = true;
        flat["puppetmaster_activate_if_missing"] = true;
        flat["puppetmaster_deploy_on_combat_start"] = true;
        flat["puppetmaster_maneuvers_enabled"] = true;
        flat["puppetmaster_maneuver_pattern"] = "Fire Maneuver|Fire Maneuver|Light Maneuver";
        flat["puppetmaster_post_activate_quiet_seconds"] = 120;
        flat["puppetmaster_safe_burden_ceiling"] = 30;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Terrasjr", "PUP", "WAR")
        );
        AssertContains(content, "puppetmaster = {", "PUP profile must include durable Puppetmaster domain");
        AssertContains(content, "enabled = true", "PUP automation enabled state must serialize");
        AssertContains(content, "activate_if_missing = true", "PUP Activate policy must serialize");
        AssertContains(content, "deploy_on_combat_start = true", "PUP Deploy policy must serialize");
        AssertContains(content, "\"Fire Maneuver\"", "PUP Fire Maneuver must serialize");
        AssertContains(content, "\"Light Maneuver\"", "PUP Light Maneuver must serialize");
        AssertContains(content, "post_activate_quiet_seconds = 120", "PUP safety hold must serialize");
        AssertContains(content, "safe_burden_ceiling = 30", "PUP burden ceiling must serialize");
    }

    private static void TestNonPuppetmasterRejectsEnabledPuppetmaster()
    {
        var flat = BuildSampleFlatProfile();
        flat["puppetmaster_enabled"] = true;
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Terrasjr", "WAR", "NIN")
            ),
            "configured Puppetmaster automation must require PUP main job"
        );
    }

    private static void TestPuppetmasterUiProfilePersistenceContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.PuppetmasterUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var main = ReadRepoFile("UnifiedCombatWinForms", "MainForm.cs");
        var runtime = ReadRepoFile("uc_pup_runtime.lua");

        AssertContains(ui, "selected character / PUP / subjob profile", "PUP UI must describe profile ownership");
        AssertContains(ui, "CaptureWorkingProfileFromUi", "PUP edits must update local working profile state");
        AssertNotContains(ui, "File.WriteAllText", "PUP UI must not own a standalone config file");
        AssertNotContains(ui, "puppetmaster_config.lua", "PUP UI must not reference a standalone config file");
        AssertNotContains(ui, "Save + reload selected PUP", "PUP UI must use the normal profile save path");
        AssertContains(store, "[\"puppetmaster_enabled\"] = _pupEnabled.Checked", "PUP enabled state must be captured by the profile store");
        AssertContains(store, "[\"puppetmaster_maneuver_pattern\"] = PuppetmasterPatternFromUi()", "PUP maneuver pattern must be captured by the profile store");
        AssertContains(logic, "EnsurePuppetmasterTabVisibility(puppetmasterVisible)", "PUP tab visibility must follow PUP main job");
        AssertContains(logic, "ApplyPuppetmasterFromSnapshot(s)", "PUP controls must restore from profile state");
        AssertContains(main, "EnsurePuppetmasterTabVisibility(false)", "PUP tab must start hidden before a PUP profile is selected");
        AssertNotContains(runtime, "dofile", "PUP runtime must not load a standalone file fallback");
        AssertNotContains(runtime, "puppetmaster_config.lua", "PUP runtime must consume active profile config only");
    }

    private static void TestNonScholarOmitsUnconfiguredScholar()
    {
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            BuildSampleFlatProfile(),
            new StructuredProfileV2Identity("Redrogue", "PLD", "SCH")
        );
        AssertNotContains(content, "sch = {", "non-SCH main profile must omit default Scholar config");
    }

    private static void TestNonScholarRejectsConfiguredScholar()
    {
        var flat = BuildSampleFlatProfile();
        flat["sch_enabled"] = true;
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "PLD", "SCH")
            ),
            "configured Scholar automation must require SCH main job"
        );
    }

    private static void TestScholarSublimationActivationMppMigration()
    {
        var profile = new JsonObject
        {
            ["profile_schema_version"] = 4,
            ["sch_sublimation_activate_when_mpp_at_least"] = 95,
            ["sch_sublimation_release_when_mpp_at_most"] = 50,
        };

        AssertTrue(MainForm.MigrateProfileInPlace(profile),
            "current-schema profile with deprecated Sublimation activation MPP must migrate");
        AssertTrue(!profile.ContainsKey("sch_sublimation_activate_when_mpp_at_least"),
            "deprecated Sublimation activation MPP must be removed during profile migration");
        AssertEqual(profile["sch_sublimation_release_when_mpp_at_most"]!.GetValue<int>(), 50,
            "Sublimation release MPP must survive activation-field migration");
    }

    private static void TestNonScholarOmitsInactiveScholarPanelState()
    {
        var flat = BuildSampleFlatProfile();
        flat["sch_enabled"] = false;
        flat["sch_regen_enabled"] = true;
        flat["sch_accession_perpetuance_spells"] = "Regen V|Protect V|Shell V|Adloquium|Phalanx";
        flat["sch_regen_refresh_before_s"] = 10;
        flat["sch_storms_enabled"] = true;
        flat["sch_storm_assignments"] = "Thunderstorm II:Nyoourke";
        flat["sch_sublimation_enabled"] = true;
        flat["sch_accession_cure_enabled"] = true;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Terrasjr", "MNK", "WAR")
        );
        AssertNotContains(content, "sch = {",
            "inactive hidden Scholar panel state must not configure a non-SCH profile");
    }

    private static void TestScholarDisabledShape()
    {
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            BuildSampleFlatProfile(),
            new StructuredProfileV2Identity("Redrogue", "SCH", "RDM")
        );
        AssertContains(content, "sch = {", "SCH profile must include the durable Scholar domain");
        AssertContains(content, "mode = \"support\"", "Scholar support mode default missing");
        AssertContains(content, "default = \"light\"", "Scholar Light Arts default missing");
        AssertContains(content, "spells = {", "Scholar maintenance spell list missing");
        AssertContains(content, "\"Regen V\"", "Scholar default maintenance spell missing");
        AssertContains(content, "\"Accession\"", "Scholar Accession policy missing");
        AssertContains(content, "\"Perpetuance\"", "Scholar Perpetuance policy missing");
        AssertContains(content, "manual_arm_required = true", "Scholar Embrava safety gate missing");
        AssertContains(content, "allow_party_close = false", "deferred skillchain policy must remain disabled");
    }

    private static void TestScholarConfiguredRoundTripShape()
    {
        var flat = BuildSampleFlatProfile();
        flat["sch_enabled"] = true;
        flat["sch_arts_minimum_commit_s"] = 20;
        flat["sch_arts_emergency_off_art_casts"] = false;
        flat["sch_regen_enabled"] = true;
        flat["sch_regen_minimum_coverage"] = 5;
        flat["sch_regen_refresh_before_s"] = 30;
        flat["sch_accession_perpetuance_spells"] = "Regen V|Aurorastorm II|Protect V|Phalanx";
        flat["sch_storms_enabled"] = true;
        flat["sch_storm_assignments"] = "Sandstorm II:Tank,Healer|Hailstorm II:Wizard";
        flat["sch_storms_refresh_before_s"] = 40;
        flat["sch_sublimation_enabled"] = true;
        flat["sch_sublimation_activate_when_mpp_at_least"] = 80;
        flat["sch_sublimation_release_when_mpp_at_most"] = 35;
        flat["sch_sublimation_release_when_complete"] = true;
        flat["sch_sublimation_minimum_hpp_to_activate"] = 85;
        flat["sch_accession_cure_enabled"] = true;
        flat["sch_accession_status_removal_enabled"] = true;
        flat["sch_rapture_enabled"] = true;
        flat["sch_penury_enabled"] = true;

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "SCH", "RDM")
        );
        AssertContains(content, "minimum_commit_s = 20", "Scholar Arts commitment must serialize");
        AssertContains(content, "emergency_off_art_casts = false", "Scholar off-Art policy must serialize");
        AssertContains(content, "minimum_coverage = 5", "Scholar Regen coverage must serialize");
        AssertContains(content, "\"Protect V\"", "Scholar ordered maintenance list must serialize");
        AssertContains(content, "\"Aurorastorm II\"", "Scholar Accession Storm II must serialize");
        AssertContains(content, "\"Phalanx\"", "Scholar self-anchor maintenance spell must serialize");
        AssertContains(content, "spell = \"Sandstorm II\"", "Scholar storm assignment spell missing");
        AssertContains(content, "\"Tank\"", "Scholar storm target missing");
        AssertContains(content, "release_when_complete = true", "Scholar Sublimation release policy missing");
        AssertContains(content, "minimum_hpp_to_activate = 85", "Scholar Sublimation HPP gate missing");
        AssertNotContains(content, "activate_when_mpp_at_least",
            "new Scholar profiles must omit deprecated Sublimation activation MPP");
        AssertContains(content, "accession_cure = {\n                    enabled = true", "Scholar Accession cure policy must serialize");
        AssertContains(content, "accession_status_removal = {\n                    enabled = true", "Scholar Accession status-removal policy must serialize");
        AssertContains(content, "rapture = {\n                    enabled = true", "Scholar Rapture policy must serialize");
        AssertContains(content, "penury = {\n                    enabled = true", "Scholar Penury policy must serialize");
    }

    private static void TestScholarStormAssignmentValidation()
    {
        var assignments = StructuredProfileV2Writer.ParseScholarStormAssignments(
            "Sandstorm II:Tank,Healer|Hailstorm II:Wizard"
        );
        AssertEqual(assignments.Count, 2, "Scholar storm assignment count mismatch");
        AssertEqual(assignments[0].Targets.Count, 2, "Scholar first assignment target count mismatch");
		var maintenanceSpells = StructuredProfileV2Writer.ParseScholarAccessionMaintenanceSpells(
			"Regen V|Protect V\r\nPhalanx"
		);
		AssertEqual(maintenanceSpells.Count, 3, "Scholar maintenance spell count mismatch");
		AssertEqual(maintenanceSpells[2], "Phalanx", "Scholar maintenance order mismatch");
		AssertThrows<InvalidDataException>(
			() => StructuredProfileV2Writer.ParseScholarAccessionMaintenanceSpells("Haste"),
			"unsupported Scholar maintenance spell must fail"
		);
		AssertThrows<InvalidDataException>(
			() => StructuredProfileV2Writer.ParseScholarAccessionMaintenanceSpells("Regen V|Regen V"),
			"duplicate Scholar maintenance spell must fail"
		);
		AssertThrows<InvalidDataException>(
			() => StructuredProfileV2Writer.ParseScholarAccessionMaintenanceSpells("Enfire|Enwater"),
			"exclusive Scholar maintenance spells must fail"
		);
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.ParseScholarStormAssignments("Sandstorm:Tank"),
            "base-tier storm must be rejected"
        );
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.ParseScholarStormAssignments(
                "Sandstorm II:Tank|Hailstorm II:tank"
            ),
            "Scholar storm targets must be globally unique"
        );

        var unrestrictedRelease = BuildSampleFlatProfile();
        unrestrictedRelease["sch_enabled"] = true;
        unrestrictedRelease["sch_sublimation_activate_when_mpp_at_least"] = 45;
        unrestrictedRelease["sch_sublimation_release_when_mpp_at_most"] = 100;
        var unrestrictedContent = StructuredProfileV2Writer.BuildStructuredProfileFile(
            unrestrictedRelease,
            new StructuredProfileV2Identity("Redrogue", "SCH", "RDM")
        );
        AssertContains(unrestrictedContent, "release_when_mpp_at_most = 100",
            "Scholar Sublimation release MPP must not be compared with deprecated activation MPP");
        AssertNotContains(unrestrictedContent, "activate_when_mpp_at_least",
            "deprecated Sublimation activation MPP must not serialize");
    }

    private static void TestScholarUiOfflineContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(ui, "new TabPage(\"SCH\")", "Scholar tab must be available offline");
        AssertContains(ui, "Sandstorm II:Tank,Healer", "Scholar storm assignment format must be visible");
        AssertContains(store, "[\"sch_enabled\"] = _schEnabled.Checked", "Scholar enabled state must be captured");
        AssertContains(store, "[\"sch_storm_assignments\"]", "Scholar storm assignments must be captured");
        AssertContains(store, "[\"sch_accession_perpetuance_spells\"]",
			"Scholar Accession maintenance list must be captured");
        AssertContains(store, "[\"sch_accession_cure_enabled\"]", "Scholar Phase 2 state must be captured");
        AssertContains(ui, "Accession group cures", "Scholar Phase 2 controls must be visible");
        AssertContains(ui, "Minimum HP to start charging (%)", "Scholar Sublimation HP charging label missing");
        AssertContains(ui, "Release stored MP when MP <= (%)", "Scholar Sublimation MP release label missing");
        AssertContains(ui, "Release immediately when fully charged", "Scholar complete-release label missing");
        AssertNotContains(ui, "Activate at MPP at least", "obsolete Sublimation activation MPP label must be removed");
        AssertNotContains(store, "_schSublimationActivateMpp", "obsolete Sublimation activation control must not persist");
        AssertContains(logic, "string.Equals(mainJob, \"SCH\"", "Scholar tab requires SCH main job");
        AssertContains(logic, "ApplyScholarFromSnapshot(s);", "Scholar settings must restore from local state");
        AssertContains(logic, "Scholar support and group-defense configuration is valid.", "Scholar Phase 2 validation must be visible");
        AssertContains(
            ReadRepoFile("UnifiedCombatWinForms", "MainForm.cs"),
            "EnsureScholarTabVisibility(false)",
            "Scholar tab must start hidden"
        );

        var start = logic.IndexOf("private static bool ReadOptionalScholarBool", StringComparison.Ordinal);
        var end = logic.IndexOf("private void EnsureBrdTabVisibility", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "Scholar UI handler source range missing");
        var handlers = logic[start..end];
        AssertContains(handlers, "CaptureWorkingProfileFromUi", "Scholar edits must update local working state");
        AssertNotContains(handlers, "Forward(", "Scholar durable controls must not require a live addon connection");
    }

    private static void TestSerializeReactionRules()
    {
        var flat = BuildSampleFlatProfile();
        flat["reaction_enabled"] = true;
        flat["reaction_rules"] = new JsonArray
        {
            new JsonObject { ["trigger"] = "ability_window", ["name"] = "Cold Stare", ["response"] = "turn_away" },
            new JsonObject { ["trigger"] = "enemy_buff", ["name"] = "Dread Spikes", ["response"] = "stop_attacking" },
            new JsonObject
            {
                ["trigger"] = "ability_window",
                ["name"] = "Dancing Fullers",
                ["response"] = "run_away",
                ["distance"] = 12.0,
            },
            new JsonObject
            {
                ["trigger"] = "ability_window",
                ["name"] = "Range Pulse",
                ["response"] = "move_to_range",
                ["distance"] = 17.5,
            },
            new JsonObject
            {
                ["trigger"] = "event_window",
                ["name"] = "Dread Spikes",
                ["response"] = "stop_attacking",
                ["activate_event"] = "spell_start",
                ["release_event"] = "buff_lost",
                ["release_name"] = "Dread Spikes",
                ["confirmation_timeout_seconds"] = 1.5,
            },
            new JsonObject
            {
                ["trigger"] = "event_window",
                ["name"] = "Dread Spikes",
                ["response"] = "turn_away",
                ["activate_event"] = "spell_start",
                ["release_event"] = "buff_lost",
                ["release_name"] = "Dread Spikes",
                ["confirmation_timeout_seconds"] = 1.5,
            },
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
        AssertContains(content, "name = \"Dancing Fullers\"", "run-away ability missing");
        AssertContains(content, "response = \"run_away\"", "run-away response missing");
        AssertContains(content, "distance = 12", "run-away raw target distance missing");
        AssertContains(content, "response = \"move_to_range\"", "move-to-range response missing");
        AssertContains(content, "distance = 17.5", "move-to-range raw target distance missing");
        AssertContains(content, "trigger = \"event_window\"", "event-window trigger missing");
        AssertContains(content, "activate_event = \"spell_start\"", "event-window activation missing");
        AssertContains(content, "release_event = \"buff_lost\"", "event-window release missing");
        AssertContains(content, "release_name = \"Dread Spikes\"", "event-window release name missing");
        AssertContains(content, "confirmation_timeout_seconds = 1.5", "event-window confirmation timeout missing");
        AssertContains(content, "response = \"turn_away\"", "event-window turn-away response missing");
        var reactionLogic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var addStart = reactionLogic.IndexOf("private void OnReactionRuleAdd()", StringComparison.Ordinal);
        var addEnd = reactionLogic.IndexOf("private void OnReactionRuleRemove()", addStart, StringComparison.Ordinal);
        AssertTrue(addStart >= 0 && addEnd > addStart, "reaction add-handler source range missing");
        var addHandler = reactionLogic[addStart..addEnd];
        AssertContains(
            addHandler,
            "(response is \"stop_attacking\" or \"turn_away\")",
            "event-window Add handler must accept turn-away"
        );
        AssertNotContains(content, "actor_id", "runtime actor ids must not be durable reaction config");
        AssertNotContains(content, "effect_id", "resolved runtime effect ids must not be durable reaction config");
    }

    private static void TestAutoMagicBurstProfileContract()
    {
        var migrated = new JsonObject { ["profile_schema_version"] = 7, ["spell"] = "Fire V" };
        AssertTrue(MainForm.MigrateProfileInPlace(migrated), "schema-seven magic-burst profile must migrate");
        AssertEqual(migrated["profile_schema_version"]!.GetValue<int>(), 8, "auto-burst migration schema mismatch");
        AssertEqual(migrated["magic_burst_mode"]!.GetValue<string>(), "exact", "legacy burst mode must remain exact");
        AssertEqual(migrated["magic_burst_family"]!.GetValue<string>(), "spell", "legacy burst family must default spell");
        AssertEqual(migrated["magic_burst_max_tier"]!.GetValue<int>(), 0, "legacy burst tier must default Auto");
        AssertEqual(migrated["spell"]!.GetValue<string>(), "Fire V", "legacy exact burst spell must be preserved");

        var flat = BuildSampleFlatProfile();
        flat["magic_burst_enabled"] = true;
        flat["magic_burst_mode"] = "auto";
        flat["magic_burst_family"] = "helix";
        flat["magic_burst_max_tier"] = 2;
        flat["spell"] = "Fire V";
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
  flat,
  new StructuredProfileV2Identity("Nyoourke", "SCH", "RDM")
        );
        AssertContains(content, "magic_burst = true", "auto burst enabled flag must serialize");
        AssertContains(content, "magic_burst_mode = \"auto\"", "auto burst mode must serialize");
        AssertContains(content, "magic_burst_family = \"helix\"", "auto burst family must serialize");
        AssertContains(content, "magic_burst_max_tier = 2", "auto burst tier ceiling must serialize");
        AssertContains(content, "configured = \"Fire V\"", "auto mode must preserve the last exact configured spell");

        flat["magic_burst_max_tier"] = 6;
        AssertThrows<InvalidDataException>(
  () => StructuredProfileV2Writer.BuildStructuredProfileFile(
      flat,
      new StructuredProfileV2Identity("Nyoourke", "SCH", "RDM")
  ),
  "magic burst tier ceiling above V must fail"
        );
    }

    private static void TestSmartWsAoePreferenceRoundTrip()
    {
        var flat = BuildSampleFlatProfile();
        flat["weaponskill_allow_aoe"] = false;
        var disabled = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertContains(disabled, "allow_aoe = false", "disabled Smart WS AoE preference must serialize false");

        flat["weaponskill_allow_aoe"] = true;
        var enabled = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertContains(enabled, "allow_aoe = true", "enabled Smart WS AoE preference must serialize true");

        flat.Remove("weaponskill_allow_aoe");
        var missing = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
        );
        AssertContains(missing, "allow_aoe = true", "missing Smart WS AoE preference must default true");
    }

    private static void TestSmartWsAoeUiPersistenceContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");

        AssertContains(ui, "Allow AoE Weapon Skills in Smart Mode", "Smart WS AoE toggle label missing");
        AssertContains(ui, "When disabled, Smart WS will not select area-of-effect weapon skills.", "Smart WS AoE tooltip missing");
        AssertContains(logic, "SessionStateHelper.GetBool(s, \"weaponskill_allow_aoe\", true)", "Smart WS AoE UI load must default true");
        AssertContains(logic, "[\"path\"] = \"weaponskill_allow_aoe\"", "Smart WS AoE live update path missing");
        AssertContains(store, "[\"weaponskill_allow_aoe\"] = _chkWsAllowAoe.Checked", "Smart WS AoE UI save path missing");
        AssertContains(store, "[\"weaponskill_allow_aoe\"] = true", "Smart WS AoE UI profile default must be true");
    }

	private static void TestFastSkillchainRoundTrip()
	{
		var flat = BuildSampleFlatProfile();
		flat["fast_skillchain"] = true;
		var enabled = StructuredProfileV2Writer.BuildStructuredProfileFile(
			flat,
			new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
		);
		AssertContains(enabled, "fast_skillchain = true", "enabled Fast Skillchain must serialize true");

		flat.Remove("fast_skillchain");
		var missing = StructuredProfileV2Writer.BuildStructuredProfileFile(
			flat,
			new StructuredProfileV2Identity("Redrogue", "PLD", "WAR")
		);
		AssertContains(missing, "fast_skillchain = false", "missing Fast Skillchain must default false");
	}

	private static void TestFastSkillchainUiPersistenceContract()
	{
		var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
		var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
		var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");

		AssertContains(ui, "Text = \"Fast Skillchain\"", "Fast Skillchain toggle label missing");
		AssertContains(ui, "tracker confirms a terminal result", "Fast Skillchain tooltip missing");
		AssertContains(logic, "SessionStateHelper.GetBool(s, \"fast_skillchain\", false)",
			"Fast Skillchain UI load must default false");
		AssertContains(logic, "[\"path\"] = \"fast_skillchain\"", "Fast Skillchain live update path missing");
		AssertContains(store, "[\"fast_skillchain\"] = _chkFastSkillchain.Checked",
			"Fast Skillchain UI save path missing");
		AssertContains(store, "[\"fast_skillchain\"] = false", "Fast Skillchain UI profile default must be false");
	}

    private static void TestNoSkillchainTargetRoundTrip()
    {
        var flat = BuildSampleFlatProfile();
        flat["no_skillchain_target_entries"] = "1:Gyre [1]|2:Other Add [2]";
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Terrasjr", "SAM", "WAR")
        );

        AssertContains(content, "no_skillchain_targets = {", "no-skillchain target list must serialize");
        AssertContains(content, "\"Gyre\"", "Gyre target must serialize");
        AssertContains(content, "\"Other Add\"", "second no-skillchain target must serialize");
        AssertNotContains(content, "Gyre [1]", "display index must not serialize");

        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        AssertContains(ui, "No Skillchain Targets", "no-skillchain target UI section missing");
        AssertContains(logic, "no_skillchain_target_replace_names", "no-skillchain target live update missing");
        AssertContains(store, "[\"no_skillchain_target_entries\"]", "no-skillchain target profile persistence missing");
    }

    private static void TestRejectInvalidRunAwayDistance()
    {
        foreach (var response in new[] { "run_away", "move_to_range" })
        {
            var flat = BuildSampleFlatProfile();
            flat["reaction_enabled"] = true;
            flat["reaction_rules"] = new JsonArray
            {
                new JsonObject
                {
                    ["trigger"] = "ability_window",
                    ["name"] = "Range Test",
                    ["response"] = response,
                    ["distance"] = 0.0,
                },
            };
            var rejected = false;
            try
            {
                StructuredProfileV2Writer.BuildStructuredProfileFile(
                    flat,
                    new StructuredProfileV2Identity("Redrogue", "BRD", "WHM")
                );
            }
            catch (InvalidDataException ex)
            {
                rejected = ex.Message.Contains("positive finite distance", StringComparison.Ordinal);
            }
            AssertTrue(rejected, $"{response} distance zero must fail durable profile serialization");
        }
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
        AssertContains(reactionHandlers, "run_away", "reaction UI must expose run-away ability-window rules");
        AssertContains(reactionHandlers, "move_to_range", "reaction UI must expose move-to-range ability-window rules");
        AssertContains(reactionHandlers, "_reactionDistance", "reaction UI must persist distance-bearing response targets");
    }

    private static void TestSerializeGhatjotEncounter()
    {
        var flat = BuildSampleFlatProfile();
        flat["encounter_enabled"] = true;
        flat["encounter_id"] = "sortie_ghatjot";
        flat["encounter_water_damage"] = "enforce";
        flat["encounter_water_skillchain"] = "warn";
        flat["encounter_repeat_action_wall"] = "off";
        flat["encounter_repeat_action_guard_s"] = 10.0;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Nyoourke", "SAM", "WAR")
        );

        AssertContains(content, "encounter = {", "encounter domain missing");
        AssertContains(content, "id = \"sortie_ghatjot\"", "Ghatjot encounter ID missing");
        AssertContains(content, "water_damage = \"enforce\"", "direct Water policy missing");
        AssertContains(content, "water_skillchain = \"warn\"", "Water skillchain policy missing");
        AssertContains(content, "repeat_action_wall = \"off\"", "Ghatjot repeat policy must be off");
        AssertContains(content, "repeat_action_guard_s = 10", "encounter tuning missing");
    }

    private static void TestSerializeKeiEncounter()
    {
        var flat = BuildSampleFlatProfile();
        flat["encounter_enabled"] = true;
        flat["encounter_id"] = "kei";
        flat["kei_elemental_dealer_name"] = "Nyoo [UC]";
        flat["kei_water_probe_spell"] = "Water";
        flat["kei_water_damage_spell"] = "Water III";
        flat["kei_ice_probe_spell"] = "Blizzard";
        flat["kei_ice_damage_spell"] = "Blizzard III";
        flat["kei_sustain_interval_s"] = 2.5;
        flat["kei_probe_timeout_s"] = 3.0;
        flat["kei_fullers_target_distance"] = 12.0;
        flat["kei_fullers_prearm_hpp_margin"] = 1.0;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Nyoo", "BLM", "RDM")
        );

        AssertContains(content, "id = \"kei\"", "Kei encounter ID missing");
        AssertContains(content, "dealer_name = \"Nyoo\"", "Kei dealer name missing");
        AssertContains(content, "probe_spell = \"Water\"", "Kei Water probe missing");
        AssertContains(content, "damage_spell = \"Water III\"", "Kei Water damage spell missing");
        AssertContains(content, "probe_spell = \"Blizzard\"", "Kei Ice probe missing");
        AssertContains(content, "damage_spell = \"Blizzard III\"", "Kei Ice damage spell missing");
        AssertContains(content, "sustain_interval_s = 2.5", "Kei sustain interval missing");
        AssertContains(content, "probe_timeout_s = 3", "Kei probe timeout missing");
        AssertContains(content, "target_distance = 12", "Kei Fullers target distance missing");
        AssertNotContains(content, "run_away_distance", "new Kei profiles must not write the legacy distance name");
        AssertContains(content, "prearm_hpp_margin = 1", "Kei Fullers prearm margin missing");
    }

    private static void TestEncounterValidation()
    {
        var missingId = BuildSampleFlatProfile();
        missingId["encounter_enabled"] = true;
        missingId["encounter_id"] = "";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                missingId,
                new StructuredProfileV2Identity("Nyoourke", "SAM", "WAR")
            ),
            "enabled encounter without identity must fail"
        );

        var invalidMode = BuildSampleFlatProfile();
        invalidMode["encounter_enabled"] = true;
        invalidMode["encounter_id"] = "sortie_ghatjot";
        invalidMode["encounter_water_damage"] = "maybe";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                invalidMode,
                new StructuredProfileV2Identity("Nyoourke", "SAM", "WAR")
            ),
            "invalid encounter policy must fail"
        );
    }

    private static void TestEncounterUiProfilePersistenceContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(ui, "new TabPage(\"Encounter Policy\")", "encounter policy tab must exist");
        AssertContains(store, "[\"encounter_enabled\"] = _encounterEnabled.Checked", "encounter enable state must be captured");
        AssertContains(store, "[\"encounter_id\"] = EncounterIdValue()", "encounter identity must be captured");
        AssertContains(store, "[\"encounter_water_damage\"]", "direct Water mode must be captured");
        AssertContains(store, "[\"kei_elemental_dealer_name\"]", "Kei elemental dealer must be captured");
        AssertContains(store, "[\"kei_fullers_target_distance\"]", "Kei Fullers target distance must be captured");
        AssertContains(ui, "Water Probe Spell", "Kei Water probe selector must exist");
        AssertContains(ui, "Dancing Fullers Target Distance", "Kei Fullers target-distance control must exist");
        AssertContains(logic, "ApplyEncounterConfigFromSnapshot(s);", "encounter settings must restore from UI profiles");
        var start = logic.IndexOf("private string EncounterIdValue", StringComparison.Ordinal);
        var end = logic.IndexOf("private string FormationEncounterValue", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "encounter UI handler source range missing");
        var handlers = logic[start..end];
        AssertNotContains(handlers, "Forward(", "encounter durable controls must not emit live bridge traffic");
        AssertContains(handlers, "CaptureWorkingProfileFromUi", "encounter durable controls must update local working state");
    }

    private static void TestDisabledFormationIsOmitted()
    {
        var flat = BuildSampleFlatProfile();
        flat["formation_enabled"] = false;
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Terrasjr", "PLD", "WAR")
        );

        AssertNotContains(content, "formation = {", "disabled formation must remain optional for older profiles");
    }

    private static void TestSerializeLilithEasyFormation()
    {
        var flat = BuildSampleFlatProfile();
        EnableSampleFormation(flat);
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Niightsiide", "WHM", "RDM")
        );

        AssertContains(content, "formation = {", "formation domain missing from movement config");
        AssertContains(content, "encounter = \"lilith_easy\"", "formation encounter missing");
        AssertContains(content, "role = \"healer\"", "formation role missing");
        AssertContains(content, "tank_name = \"Terrasjr\"", "formation tank name missing");
        AssertContains(content, "required_party_names = {", "formation coverage member list missing");
        AssertContains(content, "\"Etamame\"", "formation coverage member missing");
        AssertNotContains(content, "Etamame [UC]", "formation member display suffix must not be durable");
        AssertContains(content, "capture_stable_s = 0.5", "formation capture interval missing");
        AssertContains(content, "safe_radius = 16", "formation safe radius missing");
        AssertContains(content, "accept_radius = 1.5", "tank accept radius missing");
        AssertContains(content, "return_radius = 3", "tank return radius missing");
        AssertContains(content, "flank_angle_deg = 90", "DPS flank angle missing");
        AssertContains(content, "preferred_radius = 12", "healer preferred radius missing");
        AssertContains(content, "cone_safety_margin_deg = 15", "healer cone safety margin missing");
    }

    private static void TestKeiSpellOptionRefreshRevalidatesEncounter()
    {
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs")
            .Replace("\r\n", "\n", StringComparison.Ordinal);
        const string refreshAndValidate = "RefreshKeiSpellOptions();\n                UpdateEncounterUiState();";
        var occurrences = logic.Split(refreshAndValidate, StringSplitOptions.None).Length - 1;
        AssertTrue(
            occurrences >= 2,
            "Kei encounter validation must rerun when full-session or incremental spell options replace another session's options"
        );
    }

    private static void TestSerializeGenericSortieFormation()
    {
        var flat = BuildSampleFlatProfile();
        flat["domain_movement_enabled"] = true;
        flat["encounter_enabled"] = true;
        flat["encounter_id"] = "sortie_ghatjot";
        flat["encounter_water_damage"] = "enforce";
        flat["encounter_water_skillchain"] = "enforce";
        flat["encounter_repeat_action_wall"] = "off";
        flat["encounter_repeat_action_guard_s"] = 10.0;
        flat["formation_enabled"] = true;
        flat["formation_encounter"] = "sortie_ghatjot";
        flat["formation_mock_enabled"] = true;
        flat["formation_mock_mob_name"] = "Apex Crab";
        flat["formation_placement_mode"] = "polar_band";
        flat["formation_anchor"] = "encounter_origin";
        flat["formation_anchor_member"] = "";
        flat["formation_axis_type"] = "boss_to_member";
        flat["formation_axis_member"] = "Terrasjr [UC]";
        flat["formation_preferred_radius"] = 3.0;
        flat["formation_minimum_radius"] = 2.0;
        flat["formation_maximum_radius"] = 4.0;
        flat["formation_preferred_angle_deg"] = 180.0;
        flat["formation_allowed_angle_half_width_deg"] = 45.0;
        flat["formation_radius_step"] = 0.5;
        flat["formation_angle_step_deg"] = 10.0;
        flat["formation_hysteresis_start_distance"] = 1.0;
        flat["formation_hysteresis_stop_distance"] = 0.5;
        flat["formation_avoid_encounter_hazards"] = true;
        flat["formation_hazard_margin"] = 0.25;
        flat["formation_safe_origin_radius"] = 16.0;
        flat["formation_minimum_boss_distance"] = 1.0;
        flat["formation_maximum_boss_distance"] = 6.0;
        flat["formation_maximum_party_range"] = 12.0;
        flat["formation_required_party_names"] = "Terrasjr [UC]|Etamame";

        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "THF", "WAR")
        );

        AssertContains(content, "encounter = \"sortie_ghatjot\"", "generic formation encounter missing");
        AssertContains(content, "mock = {", "generic formation mock config missing");
        AssertContains(content, "mob_name = \"Apex Crab\"", "generic formation mock target missing");
        AssertContains(content, "mode = \"polar_band\"", "generic placement mode missing");
        AssertContains(content, "anchor = \"encounter_origin\"", "generic anchor missing");
        AssertContains(content, "type = \"boss_to_member\"", "generic axis type missing");
        AssertContains(content, "member = \"Terrasjr\"", "generic axis member missing");
        AssertContains(content, "preferred_angle_deg = 180", "generic preferred angle missing");
        AssertContains(content, "start_distance = 1", "generic hysteresis missing");
        AssertContains(content, "avoid_encounter_hazards = true", "generic hazard preference missing");
        AssertContains(content, "safe_origin_radius = 16", "generic origin constraint missing");
        AssertContains(content, "maximum_party_range = 12", "generic party constraint missing");
        AssertNotContains(content, "role = \"healer\"", "generic formation must not serialize Lilith role semantics");
        AssertNotContains(content, "tank_name =", "generic formation must not serialize Lilith tank semantics");

        flat["formation_axis_type"] = "boss_heading";
        flat["formation_axis_member"] = "";
        var bossHeadingContent = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Redrogue", "WHM", "SCH")
        );
        AssertContains(bossHeadingContent, "type = \"boss_heading\"", "boss heading axis type missing");
        AssertNotContains(bossHeadingContent, "member =", "boss heading axis must not serialize member semantics");

        flat["formation_mock_mob_name"] = "";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "THF", "WAR")
            ),
            "enabled generic formation mock without a mob name must fail"
        );
        flat["formation_mock_mob_name"] = "Apex Crab";

        flat["encounter_id"] = "sortie_dhartok";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Redrogue", "THF", "WAR")
            ),
            "generic formation encounter mismatch must fail"
        );
    }

    private static void TestFormationMockRejectsLilith()
    {
        var flat = BuildSampleFlatProfile();
        EnableSampleFormation(flat);
        flat["formation_mock_enabled"] = true;
        flat["formation_mock_mob_name"] = "Apex Crab";
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Niightsiide", "WHM", "RDM")
            ),
            "Lilith compatibility formation must reject mock mode"
        );
    }

    private static void TestSerializeNamedMobFormations()
    {
        var flat = BuildSampleFlatProfile();
        flat["domain_movement_enabled"] = true;
        flat["formation_enabled"] = false;
        flat["named_formations_enabled"] = true;
        flat["named_formation_entries"] = new JsonArray
        {
            new JsonObject
            {
                ["mob_name"] = "Kei",
                ["formation_placement_mode"] = "polar_band",
                ["formation_anchor"] = "boss",
                ["formation_anchor_member"] = "",
                ["formation_axis_type"] = "boss_heading",
                ["formation_axis_member"] = "",
                ["formation_preferred_radius"] = 12.0,
                ["formation_minimum_radius"] = 10.0,
                ["formation_maximum_radius"] = 14.0,
                ["formation_preferred_angle_deg"] = 180.0,
                ["formation_allowed_angle_half_width_deg"] = 45.0,
                ["formation_radius_step"] = 0.5,
                ["formation_angle_step_deg"] = 10.0,
                ["formation_hysteresis_start_distance"] = 1.0,
                ["formation_hysteresis_stop_distance"] = 0.5,
                ["formation_avoid_encounter_hazards"] = false,
                ["formation_hazard_margin"] = 0.0,
                ["formation_safe_origin_radius"] = 0.0,
                ["formation_minimum_boss_distance"] = 10.0,
                ["formation_maximum_boss_distance"] = 14.0,
                ["formation_maximum_party_range"] = 0.0,
                ["formation_required_party_names"] = "",
            },
        };
        var content = StructuredProfileV2Writer.BuildStructuredProfileFile(
            flat,
            new StructuredProfileV2Identity("Niightsiide", "GEO", "WHM")
        );
        AssertContains(content, "named_formations = {", "named formations domain missing");
        AssertContains(content, "mob_name = \"Kei\"", "named formation exact mob name missing");
        AssertContains(content, "type = \"boss_heading\"", "named formation boss-heading geometry missing");
        AssertContains(content, "minimum_boss_distance = 10", "named formation constraints missing");
        AssertNotContains(content, "encounter = \"kei\"", "named formation must not create an encounter-policy identity");
        AssertNotContains(content, "role =", "named formation must remain role-free");

        flat["named_formation_entries"] = new JsonArray();
        AssertThrows<InvalidDataException>(
            () => StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Niightsiide", "GEO", "WHM")
            ),
            "enabled named formations without entries must fail"
        );
    }

    private static void TestEnabledFormationRequiresMovementDomain()
    {
        var flat = BuildSampleFlatProfile();
        EnableSampleFormation(flat);
        flat["domain_movement_enabled"] = false;
        try
        {
            _ = StructuredProfileV2Writer.BuildStructuredProfileFile(
                flat,
                new StructuredProfileV2Identity("Niightsiide", "WHM", "RDM")
            );
        }
        catch (InvalidDataException ex)
        {
            AssertContains(ex.Message, "requires movement domain", "formation domain failure reason mismatch");
            return;
        }
        throw new InvalidOperationException("enabled formation without movement domain must fail");
    }

    private static void TestFormationUiEditsAreLocalUntilSave()
    {
        var source = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var start = source.IndexOf("private string FormationEncounterValue", StringComparison.Ordinal);
        var end = source.IndexOf("private void OnReactionRuleAdd", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "formation UI handler source range missing");
        var formationHandlers = source[start..end];
        AssertNotContains(formationHandlers, "Forward(", "formation durable controls must not emit live bridge traffic");
        AssertContains(formationHandlers, "CaptureWorkingProfileFromUi", "formation durable controls must update local working state");
        AssertContains(formationHandlers, "domain_movement_enabled", "formation UI must validate movement domain enablement");
        AssertNotContains(formationHandlers, "scheduler_dark_launch_movement", "formation UI must not depend on compatibility-only ownership markers");
    }

    private static void TestFormationUiProfilePersistenceContract()
    {
        var ui = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityUi.cs");
        var store = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ProfileStore.cs");
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        AssertContains(ui, "new TabPage(\"Encounter Formation\")", "formation tab must exist");
        AssertContains(store, "[\"formation_enabled\"] = _formationEnabled.Checked", "formation enable state must be captured");
        AssertContains(store, "[\"named_formations_enabled\"] = _namedFormationsEnabled.Checked", "named formation enable state must be captured");
        AssertContains(store, "BuildNamedFormationEntriesJson()", "named formation entries must be captured");
        AssertContains(store, "[\"formation_mock_enabled\"] = _formationMockEnabled.Checked", "formation mock enable state must be captured");
        AssertContains(store, "[\"formation_mock_mob_name\"]", "formation mock mob name must be captured");
        AssertContains(store, "[\"formation_mock_enabled\"] = false", "new profiles must default formation mock mode off");
        AssertContains(store, "[\"formation_role\"] = FormationRoleValue()", "formation role must be captured");
        AssertContains(store, "[\"formation_required_party_names\"]", "formation coverage members must be captured");
        AssertContains(store, "[\"formation_healer_sample_step_deg\"]", "formation advanced settings must be captured");
        AssertContains(store, "[\"formation_placement_mode\"]", "generic placement mode must be captured");
        AssertContains(store, "[\"formation_avoid_encounter_hazards\"]", "generic hazard preference must be captured");
        AssertContains(ui, "Ghatjot — Generic geometry", "Ghatjot generic formation selection must be exposed");
        AssertContains(ui, "Dhartok — Generic geometry", "Dhartok generic formation selection must be exposed");
        AssertContains(ui, "Use a normal mob as the formation boss", "formation mock UI must be exposed");
        AssertContains(ui, "Enable automatic named mob / boss formations", "named formation UI must be exposed");
        AssertContains(ui, "Configured named formations", "named formation list must be exposed");
        AssertContains(ui, "Target the exact named mob once", "formation mock target-binding instructions must be visible");
        AssertContains(ui, "encounter policies and hazards do not bind to it", "formation mock safety boundary must be visible");
        AssertContains(logic, "Generic formation requires enabled encounter policy", "generic formation UI identity validation missing");
        AssertContains(logic, "formation_mock_enabled", "formation mock settings must restore from UI profiles");
        AssertContains(logic, "ApplyFormationConfigFromSnapshot(s, partnerOpts);", "formation settings must restore from UI profiles");
        AssertContains(logic, "named_formation_entries", "named formation settings must restore from UI profiles");
        AssertContains(logic, "profile save blocked", "invalid formation settings must block profile save");
    }

    private static void TestFormationPartyOptionsRefreshContract()
    {
        var logic = ReadRepoFile("UnifiedCombatWinForms", "MainForm.ParityLogic.cs");
        var start = logic.IndexOf("private void ApplyOptionsFromSnapshotIfPresent", StringComparison.Ordinal);
        var end = logic.IndexOf("private string metaOrJob", start, StringComparison.Ordinal);
        AssertTrue(start >= 0 && end > start, "incremental options handler source range missing");
        var optionsHandler = logic[start..end];
        AssertContains(
            optionsHandler,
            "BindFormationPartyControls(",
            "incremental party options must refresh formation party controls"
        );
        AssertContains(
            optionsHandler,
            "!SequenceEqualOrdinal(_partyOptions, partyOpts)",
            "incremental party refresh must detect a stale shared party-options cache"
        );
        AssertContains(
            optionsHandler,
            "keepFormationAxis",
            "incremental party options must preserve the selected formation axis member"
        );
        AssertContains(
            optionsHandler,
            "keepFormationRequired",
            "incremental party options must preserve checked formation coverage members"
        );
        AssertContains(
            logic,
            "var partyOptsLive = CurrentSelectablePartyNameOptions(",
            "full editor hydration must combine reported party members with connected UC sessions"
        );
        AssertContains(
            optionsHandler,
            "var partyOpts = CurrentSelectablePartyNameOptions(",
            "incremental editor hydration must combine reported party members with connected UC sessions"
        );
        AssertContains(
            logic,
            ".Concat(CurrentPartyNameOptions())",
            "selectable party options must include connected UC session identities"
        );
        AssertContains(
            logic,
            "!string.Equals(name, selectedCharacter, StringComparison.OrdinalIgnoreCase)",
            "selectable party options must exclude the selected character"
        );
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
        AssertNotContains(source, "TrySaveProfileFromUi(sid, profile", "UI save must not write a per-identity JSON profile");
        AssertContains(source, "TrySaveStructuredProfileV2FromUi(sid, profile, out var v2Error)", "UI save must write the structured profile file");
        AssertContains(source, "SetProfileSaveStatus(\"Mirror: Profile V2 saved\")", "UI save must report Profile V2 success");
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
            ["weaponskill_min_tp"] = 2000,
            ["weaponskill_allow_aoe"] = false,
            ["aftermath_enabled"] = true,
            ["aftermath_ws"] = "Atonement",
            ["defensive_enabled"] = true,
            ["defensive_provider"] = "internal",
            ["defensive_resurrection_enabled"] = true,
            ["defensive_resurrection_priority"] = "Arise|Raise III|Raise",
            ["defensive_cure_enabled"] = true,
            ["def_heal_min_tier_cure"] = 3,
            ["def_heal_max_tier_cure"] = 4,
            ["def_heal_min_missing_hp"] = 250,
            ["def_heal_ignore_trusts"] = true,
            ["defensive_curaga_enabled"] = true,
            ["defensive_curaga_min_targets"] = 4,
            ["defensive_waltz_enabled"] = true,
            ["defensive_waltz_tp_reserve"] = 1000,
            ["defensive_divine_waltz_min_targets"] = 2,
            ["defensive_doom_water"] = true,
            ["def_charm_sleeper_enabled"] = true,
            ["def_sleep_waker_enabled"] = true,
            ["defensive_na_enabled"] = true,
            ["defensive_na_limit_enabled"] = true,
            ["defensive_na_priority"] = "Poison|Paralyze|Dia",
            ["def_remove_enemy_buffs"] = false,
            ["def_maintain_enemy_debuffs"] = true,
            ["defensive_enemy_debuffs"] = "Dia III|Distract III",
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
			["puller_leash_source"] = "player",
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
            ["log_action_timeline"] = false,
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
            ["pause_automation_while_weakened"] = false,
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

    private static void EnableSampleFormation(JsonObject flat)
    {
        flat["formation_enabled"] = true;
        flat["formation_encounter"] = "lilith_easy";
        flat["formation_role"] = "healer";
        flat["formation_tank_name"] = "Terrasjr [UC]";
        flat["formation_required_party_names"] = "Terrasjr|Etamame [UC]|Niightsiide";
        flat["formation_capture_stable_s"] = 0.5;
        flat["formation_capture_tolerance"] = 0.1;
        flat["formation_safe_radius"] = 16.0;
        flat["formation_tank_accept_radius"] = 1.5;
        flat["formation_tank_return_radius"] = 3.0;
        flat["formation_dps_flank_angle_deg"] = 90.0;
        flat["formation_dps_melee_radius"] = 3.0;
        flat["formation_dps_position_tolerance"] = 1.5;
        flat["formation_healer_preferred_radius"] = 12.0;
        flat["formation_healer_minimum_boss_distance"] = 8.0;
        flat["formation_healer_maximum_party_range"] = 18.0;
        flat["formation_healer_cone_half_angle_deg"] = 50.0;
        flat["formation_healer_cone_safety_margin_deg"] = 15.0;
        flat["formation_healer_sample_step_deg"] = 10.0;
        flat["domain_movement_enabled"] = true;
    }

    private static void AssertTrue(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void AssertThrows<TException>(Action action, string message)
        where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException(message);
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
