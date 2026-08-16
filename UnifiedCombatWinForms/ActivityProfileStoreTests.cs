using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

internal static class ActivityProfileStoreTests
{
    internal static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "UnifiedCombatActivityTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(root, "data"));
        try
        {
            TestMultiJobCaptureAndGlobalActivation(root);
            TestActivityProvenanceTransitions(root);
            TestLegacyBundleRequiresVariantUpdate(root);
            TestAppliedUiPreservesRuntimeEngineState();
            TestSessionDisplayLabels();
            TestGlobalUiAndBridgeContract();
            Console.WriteLine("ActivityProfileStoreTests: PASS");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ActivityProfileStoreTests: FAIL");
            Console.Error.WriteLine(ex);
            return 1;
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private static void TestGlobalUiAndBridgeContract()
    {
        var addonRoot = StructuredProfileV2Writer.FindAddonRootFrom(AppContext.BaseDirectory)
            ?? throw new InvalidOperationException("activity source contract addon root missing");
        var ui = File.ReadAllText(Path.Combine(addonRoot, "UnifiedCombatWinForms", "MainForm.ActivityProfiles.cs"));
        var main = File.ReadAllText(Path.Combine(addonRoot, "UnifiedCombatWinForms", "MainForm.cs"));
        var parity = File.ReadAllText(Path.Combine(addonRoot, "UnifiedCombatWinForms", "MainForm.ParityLogic.cs"));
        var profileStore = File.ReadAllText(Path.Combine(addonRoot, "UnifiedCombatWinForms", "MainForm.ProfileStore.cs"));
        var mirror = File.ReadAllText(Path.Combine(addonRoot, "UnifiedCombatWinForms", "MirrorDuplex.cs"));
        var bridge = File.ReadAllText(Path.Combine(addonRoot, "remote_bridge.lua"));
        var addon = File.ReadAllText(Path.Combine(addonRoot, "UnifiedCombat.lua"));

        AssertContains(ui, "Activity (all active sessions)", "activity selector must be visibly global");
        AssertContains(ui, "AutoSize = false", "activity selector container must not collapse during preferred-size layout");
        AssertContains(ui, "group.Height = 160", "activity selector container must retain a usable fixed height");
        AssertContains(ui, "Dock = DockStyle.Fill", "activity selector controls must fill the sidebar width");
        AssertContains(ui, "_sessionMetaBySid", "activity operations must enumerate the full active-session cohort");
        AssertContains(ui, "BuildActivationPlan(selected.Id, sessions)", "dropdown activation must build one global plan");
        AssertContains(ui, "private void ActivityComboSelectedIndexChanged", "activity selection must be synchronous and selection-only");
        AssertContains(ui, "selected; click Apply Activity to activate", "activity selection must direct the user to explicit apply");
        AssertContains(ui, "Text = \"Apply Activity\"", "activity apply button label mismatch");
        AssertNotContains(ui, "private async void ActivityComboSelectedIndexChanged", "selecting an activity must not trigger activation");
        AssertContains(ui, "the activity snapshot has conflicting", "known serializer contradictions must have actionable UI errors");
        AssertContains(ui, "select the activity, click Update, then Apply again", "serializer contradiction errors must state the recovery action");
        AssertNotContains(ui, "SelectActivityWithoutApplying(previousActiveId)", "failed or cancelled activation must retain the selected activity");
        AssertNotContains(ui, "TrySaveStructuredProfileV2FromUi(capture.Sid", "activity capture must not rewrite live canonical profiles");
        AssertNotContains(ui, "TrySaveProfileFromUi(capture.Sid", "activity capture must not rewrite individual UI profiles");
        AssertContains(main, "Reload the selected editor after metadata", "session-list rebuild must refresh after metadata commit");
        AssertContains(main, "if (listChanged && !string.IsNullOrWhiteSpace(_selectedSid))", "session-list rebuild refresh guard missing");
        AssertNotContains(ui, "Stop the engine on all active sessions", "running engines must not block a confirmed activity change");
        AssertContains(ui, "already-issued actions will not be cancelled", "live activity changes must warn about in-flight actions");
        AssertContains(ui, "_activityStore.Update(", "activity update must retain and upsert job variants through the store");
        AssertContains(ui, "BuildActivityProfileCapture", "activity capture must retain flat UI JSON");
        AssertContains(ui, "PreserveRuntimeUiState", "activity apply must preserve runtime-owned engine state in the UI");
        AssertContains(ui, "BuildAppliedUiProfileContent", "activity apply must normalize runtime-owned UI state");
        AssertContains(ui, "_workingProfileBySid.Remove(entry.Sid)", "successful activity apply must discard stale UI working state");
        AssertContains(ui, "RefreshEditorFromSnapshot()", "successful activity apply must refresh the selected editor");
        AssertContains(ui, "UnmatchedSessions", "partial activity activation must report unmatched sessions");
        AssertContains(ui, "if (plan.Entries.Count > 0)", "zero-match activity context must skip deployment and reload");
        AssertContains(ui, "matched / {modified} modified / {noMatch} no match", "activity status must report provenance counts");
        AssertContains(ui, "MarkActiveActivityProfileSaved", "individual save must update activity provenance");
        AssertContains(main, "BuildSessionDisplayLabel", "session labels must include activity provenance");
        AssertContains(main, "listSessions.Items[index] = new SessionListItem", "changed labels must replace native ListBox items");
        AssertContains(main, "_suppressSessionSelectionChanged", "label replacement must suppress selection side effects");
        AssertNotContains(main, "listSessions.Refresh()", "label refresh must not rely on repainting a cached item string");
        AssertContains(parity, "TryLoadWorkingProfileForSid(_selectedSid", "session switching must prefer unsaved working state");
        AssertContains(profileStore, "$\"{ch}_{job}_{subJob}.json\"", "UI working profiles must use exact main/subjob identity");
        AssertContains(profileStore, "TryMigrateLegacyUiProfileForSid", "legacy main-job UI profiles need explicit migration");
        AssertContains(mirror, "ReloadProfileV2Async", "UI hub must await profile-v2 reload acknowledgements");
        AssertContains(ui, "DescribeReloadRejection", "activity errors must retain per-session reload diagnostics");
        AssertContains(ui, "runtime restoration failed on", "activity rollback errors must identify restoration failures");
        AssertContains(bridge, "profile_v2_reload_result", "addon bridge must send profile-v2 reload acknowledgements");
        AssertContains(bridge, "json_escape_simple", "bridge acknowledgements must safely encode detailed error text");
        AssertContains(addon, "UC_ReloadProfileV2ForCurrentIdentity", "addon must expose exact-identity profile-v2 reload");
        AssertContains(addon, "format_structured_profile_diff_detail(first_difference)", "activity reload failures must include first-difference detail");
    }

    private static void TestMultiJobCaptureAndGlobalActivation(string root)
    {
        var store = new ActivityProfileStore(root);
        var redPld = new ActivityProfileIdentity("Redrogue", "PLD", "WAR");
        var redRun = new ActivityProfileIdentity("Redrogue", "RUN", "DRK");
        var nightBrd = new ActivityProfileIdentity("Niightsiide", "BRD", "WHM");
        var pldContent = ProfileText(redPld, "pld-wave3");
        var runContent = ProfileText(redRun, "run-wave3");
        var brdContent = ProfileText(nightBrd, "brd-wave3");
        var pldUi = UiProfileText("pld-wave3");
        var runUi = UiProfileText("run-wave3");
        var brdUi = UiProfileText("brd-wave3");

        var created = store.Create(
            "Dynamis Wave 3",
            [
                new ActivityProfileCapture(redPld, pldContent, pldUi),
                new ActivityProfileCapture(nightBrd, brdContent, brdUi),
            ]
        );
        Assert(created.Characters.Count == 2, "create must capture every active character");
        Assert(store.List().Single().VariantCount == 2, "create variant count mismatch");

        var updated = store.Update(created.Id, [new ActivityProfileCapture(redRun, runContent, runUi)]);
        Assert(updated.Characters.Count == 2, "update must retain characters not in the current capture");
        Assert(store.List().Single().VariantCount == 3, "update must retain old job variants and add the current variant");

        var plan = store.BuildActivationPlan(
            created.Id,
            [
                new ActivitySessionIdentity("sid-red", redRun),
                new ActivitySessionIdentity("sid-night", nightBrd),
            ]
        );
        Assert(plan.Entries.Count == 2, "global plan must cover all active sessions");
        Assert(plan.Entries.Single(x => x.Sid == "sid-red").ProfileContent == runContent, "current RUN job selected wrong variant");
        Assert(plan.Entries.Single(x => x.Sid == "sid-red").UiProfileContent == runUi, "current RUN UI profile selected wrong variant");
        Assert(plan.Entries.Single(x => x.Sid == "sid-night").ProfileContent == brdContent, "BRD session selected wrong variant");
        var alternatePlan = store.BuildActivationPlan(
            created.Id,
            [new ActivitySessionIdentity("sid-red", redPld)]
        );
        Assert(alternatePlan.Entries.Single().ProfileContent == pldContent, "retained PLD job variant is not selectable");
        Assert(alternatePlan.Entries.Single().UiProfileContent == pldUi, "retained PLD UI variant is not selectable");

        var unmatchedIdentity = new ActivityProfileIdentity("Redrogue", "WHM", "SCH");
        var partialPlan = store.BuildActivationPlan(
            created.Id,
            [
                new ActivitySessionIdentity("sid-red", unmatchedIdentity),
                new ActivitySessionIdentity("sid-night", nightBrd),
            ]
        );
        Assert(partialPlan.Entries.Count == 1, "partial activation must include only matching sessions");
        Assert(partialPlan.Entries.Single().Sid == "sid-night", "partial activation selected the wrong matching session");
        Assert(partialPlan.UnmatchedSessions.Count == 1, "partial activation must retain the unmatched identity");
        Assert(partialPlan.UnmatchedSessions.Single().Identity.Key == unmatchedIdentity.Key, "unmatched identity mismatch");

        var zeroMatchPlan = store.BuildActivationPlan(
            created.Id,
            [new ActivitySessionIdentity("sid-zero", new ActivityProfileIdentity("Nobody", "WHM", "RDM"))]
        );
        Assert(zeroMatchPlan.Entries.Count == 0, "zero-match activation must not create deployment entries");
        Assert(zeroMatchPlan.UnmatchedSessions.Count == 1, "zero-match activation must retain all sessions as unmatched");
        AssertThrows<ActivityProfileException>(
            () => store.BuildActivationPlan(
                created.Id,
                [
                    new ActivitySessionIdentity("sid-red-1", redRun),
                    new ActivitySessionIdentity("sid-red-2", redRun),
                ]
            ),
            "duplicate live identity must block activation"
        );

        var redDestination = StructuredProfileV2Writer.BuildFinalPath(root, redRun.ToStructuredIdentity());
        var nightDestination = StructuredProfileV2Writer.BuildFinalPath(root, nightBrd.ToStructuredIdentity());
        var redUiDestination = ActivityProfileStore.BuildUiFinalPath(root, redRun);
        var nightUiDestination = ActivityProfileStore.BuildUiFinalPath(root, nightBrd);
        var unmatchedDestination = StructuredProfileV2Writer.BuildFinalPath(root, unmatchedIdentity.ToStructuredIdentity());
        var unmatchedUiDestination = ActivityProfileStore.BuildUiFinalPath(root, unmatchedIdentity);
        Directory.CreateDirectory(Path.GetDirectoryName(redDestination)!);
        Directory.CreateDirectory(Path.GetDirectoryName(redUiDestination)!);
        File.WriteAllText(redDestination, "old-red");
        File.WriteAllText(nightDestination, "old-night");
        File.WriteAllText(redUiDestination, "{\"marker\":\"old-red-ui\"}");
        File.WriteAllText(nightUiDestination, "{\"marker\":\"old-night-ui\"}");
        File.WriteAllText(unmatchedDestination, "old-unmatched");
        File.WriteAllText(unmatchedUiDestination, "{\"marker\":\"old-unmatched-ui\"}");

        using (var partialDeployment = store.Deploy(partialPlan))
        {
            Assert(File.ReadAllText(nightDestination) == brdContent, "partial deployment did not update its matching session");
            Assert(File.ReadAllText(unmatchedDestination) == "old-unmatched", "partial deployment changed an unmatched v2 profile");
            Assert(File.ReadAllText(unmatchedUiDestination) == "{\"marker\":\"old-unmatched-ui\"}", "partial deployment changed an unmatched UI profile");
            partialDeployment.Rollback();
        }
        Assert(File.ReadAllText(nightDestination) == "old-night", "partial rollback did not restore its matching session");
        Assert(File.ReadAllText(unmatchedDestination) == "old-unmatched", "partial rollback changed an unmatched v2 profile");
        Assert(File.ReadAllText(unmatchedUiDestination) == "{\"marker\":\"old-unmatched-ui\"}", "partial rollback changed an unmatched UI profile");

        using (var deployment = store.Deploy(plan))
        {
            Assert(File.ReadAllText(redDestination) == runContent, "deployment did not stage RUN profile");
            Assert(File.ReadAllText(nightDestination) == brdContent, "deployment did not stage BRD profile");
            Assert(File.ReadAllText(redUiDestination) == runUi, "deployment did not stage RUN UI profile");
            Assert(File.ReadAllText(nightUiDestination) == brdUi, "deployment did not stage BRD UI profile");
            deployment.Rollback();
        }
        Assert(File.ReadAllText(redDestination) == "old-red", "rollback did not restore RUN destination");
        Assert(File.ReadAllText(nightDestination) == "old-night", "rollback did not restore BRD destination");
        Assert(File.ReadAllText(redUiDestination) == "{\"marker\":\"old-red-ui\"}", "rollback did not restore RUN UI destination");
        Assert(File.ReadAllText(nightUiDestination) == "{\"marker\":\"old-night-ui\"}", "rollback did not restore BRD UI destination");

        using (var deployment = store.Deploy(plan))
        {
            deployment.Commit();
        }
        Assert(File.ReadAllText(redDestination) == runContent, "committed RUN profile mismatch");
        Assert(File.ReadAllText(nightDestination) == brdContent, "committed BRD profile mismatch");
        Assert(File.ReadAllText(redUiDestination) == runUi, "committed RUN UI profile mismatch");
        Assert(File.ReadAllText(nightUiDestination) == brdUi, "committed BRD UI profile mismatch");

        var uiSourceToCorrupt = plan.Entries.Single(x => x.Sid == "sid-red").UiSourcePath;
        File.AppendAllText(uiSourceToCorrupt, " ");
        AssertThrows<ActivityProfileException>(
            () => store.BuildActivationPlan(created.Id, [new ActivitySessionIdentity("sid-red", redRun)]),
            "UI checksum mismatch must block activation"
        );
        File.WriteAllText(uiSourceToCorrupt, runUi);

        var sourceToCorrupt = plan.Entries.Single(x => x.Sid == "sid-red").SourcePath;
        File.AppendAllText(sourceToCorrupt, "-- corrupt");
        AssertThrows<ActivityProfileException>(
            () => store.BuildActivationPlan(created.Id, [new ActivitySessionIdentity("sid-red", redRun)]),
            "checksum mismatch must block activation"
        );

        store.Delete(created.Id);
        Assert(store.List().Count == 0, "delete must remove only the activity bundle");
        Assert(File.Exists(redDestination), "delete must not remove current canonical character profiles");
        Assert(File.Exists(redUiDestination), "delete must not remove current UI character profiles");
    }

    private static void TestLegacyBundleRequiresVariantUpdate(string root)
    {
        var store = new ActivityProfileStore(root);
        var identity = new ActivityProfileIdentity("Nyoourke", "SAM", "DRG");
        var profile = ProfileText(identity, "legacy");
        var uiProfile = UiProfileText("legacy");
        var created = store.Create("Legacy Activity", [new ActivityProfileCapture(identity, profile, uiProfile)]);
        var activityDirectory = Path.Combine(root, "data", "activity_profiles", created.Id);
        var manifestPath = Path.Combine(activityDirectory, "activity.json");
        var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
        manifest["schema_version"] = 1;
        var variant = manifest["characters"]![0]!["variants"]![0]!.AsObject();
        variant.Remove("ui_profile_file");
        variant.Remove("ui_sha256");
        File.WriteAllText(manifestPath, manifest.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        Directory.Delete(Path.Combine(activityDirectory, "ui_profiles"), recursive: true);

        Assert(store.List().Single().Name == "Legacy Activity", "legacy activity must remain selectable for update or delete");
        AssertThrowsContains<ActivityProfileException>(
            () => store.BuildActivationPlan(created.Id, [new ActivitySessionIdentity("sid-nyo", identity)]),
            "click Update",
            "legacy activity apply must state how to add its UI snapshot"
        );

        var updated = store.Update(created.Id, [new ActivityProfileCapture(identity, profile, uiProfile)]);
        Assert(updated.SchemaVersion == 2, "updating a legacy activity must upgrade its schema");
        Assert(store.BuildActivationPlan(created.Id, [new ActivitySessionIdentity("sid-nyo", identity)]).Entries.Single().UiProfileContent == uiProfile,
            "updated legacy activity must provide UI state");
        store.Delete(created.Id);
    }

    private static void TestActivityProvenanceTransitions(string root)
    {
        var store = new ActivityProfileStore(root);
        var sortieIdentity = new ActivityProfileIdentity("Terrasjr", "MNK", "WAR");
        var noMatchIdentity = new ActivityProfileIdentity("Niightsiide", "WHM", "RDM");
        var sortieProfile = ProfileText(sortieIdentity, "sortie");
        var changedProfile = ProfileText(sortieIdentity, "sortie-changed");
        var sortieUi = UiProfileText("sortie");
        var changedUi = UiProfileText("sortie-changed");
        var created = store.Create(
            "Sortie",
            [new ActivityProfileCapture(sortieIdentity, sortieProfile, sortieUi)]
        );

        var destination = StructuredProfileV2Writer.BuildFinalPath(root, sortieIdentity.ToStructuredIdentity());
        var uiDestination = ActivityProfileStore.BuildUiFinalPath(root, sortieIdentity);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        Directory.CreateDirectory(Path.GetDirectoryName(uiDestination)!);
        File.WriteAllText(destination, sortieProfile);
        File.WriteAllText(uiDestination, MainForm.BuildAppliedUiProfileContent(sortieUi, sortieIdentity, running: true));

        var initial = store.BuildProvenance(
            created.Id,
            [
                new ActivitySessionIdentity("sid-terra", sortieIdentity),
                new ActivitySessionIdentity("sid-night", noMatchIdentity),
            ]
        );
        Assert(initial.Entries.Single(x => x.Sid == "sid-terra").Provenance == ActivityProfileProvenance.Exact,
            "exact saved profile must show [Activity]");
        Assert(initial.Entries.Single(x => x.Sid == "sid-night").Provenance == ActivityProfileProvenance.NoMatch,
            "missing exact variant must show [No Match]");
        Assert(MainForm.ResolveActivityProvenance(ActivityProfileProvenance.NoMatch, individuallySavedInContext: false)
                == ActivityProfileProvenance.NoMatch,
            "unmodified unmatched session must remain [No Match]");
        Assert(MainForm.ResolveActivityProvenance(ActivityProfileProvenance.NoMatch, individuallySavedInContext: true)
                == ActivityProfileProvenance.Modified,
            "individually saved unmatched session must become [Activity-mod]");
        Assert(MainForm.ResolveActivityProvenance(
                    ActivityProfileProvenance.Modified,
                    individuallySavedInContext: false,
                    updatedInContext: true
                ) == ActivityProfileProvenance.Exact,
            "Update Activity must immediately return captured sessions to [Activity]");

        File.WriteAllText(destination, sortieProfile);
        Assert(store.BuildProvenance(created.Id, [new ActivitySessionIdentity("sid-terra", sortieIdentity)])
                .Entries.Single().Provenance == ActivityProfileProvenance.Exact,
            "saving without changing profile content must remain [Activity]");

        File.WriteAllText(destination, changedProfile);
        File.WriteAllText(uiDestination, changedUi);
        Assert(store.BuildProvenance(created.Id, [new ActivitySessionIdentity("sid-terra", sortieIdentity)])
                .Entries.Single().Provenance == ActivityProfileProvenance.Modified,
            "changed saved profile must become [Activity-mod]");

        File.WriteAllText(destination, sortieProfile);
        File.WriteAllText(uiDestination, sortieUi);
        Assert(store.BuildProvenance(created.Id, [new ActivitySessionIdentity("sid-terra", sortieIdentity)])
                .Entries.Single().Provenance == ActivityProfileProvenance.Exact,
            "restoring saved profile content must return to [Activity]");

        File.WriteAllText(destination, changedProfile);
        File.WriteAllText(uiDestination, changedUi);
        store.Update(created.Id, [new ActivityProfileCapture(sortieIdentity, changedProfile, changedUi)]);
        Assert(store.BuildProvenance(created.Id, [new ActivitySessionIdentity("sid-terra", sortieIdentity)])
                .Entries.Single().Provenance == ActivityProfileProvenance.Exact,
            "Update Activity must return captured saved variants to [Activity]");

        var changedJob = new ActivityProfileIdentity("Terrasjr", "WHM", "SCH");
        Assert(store.BuildProvenance(created.Id, [new ActivitySessionIdentity("sid-terra", changedJob)])
                .Entries.Single().Provenance == ActivityProfileProvenance.NoMatch,
            "job/subjob changes must recompute provenance from exact identity");
        Assert(store.BuildProvenance(created.Id, [new ActivitySessionIdentity("sid-terra-reconnected", sortieIdentity)])
                .Entries.Single().Provenance == ActivityProfileProvenance.Exact,
            "reconnect with a new SID must recompute provenance from exact identity");

        store.Delete(created.Id);
    }

    private static void TestAppliedUiPreservesRuntimeEngineState()
    {
        var identity = new ActivityProfileIdentity("Terrasjr", "PLD", "WAR");
        var stopped = MainForm.BuildAppliedUiProfileContent(UiProfileText("wave3"), identity, running: false);
        var running = MainForm.BuildAppliedUiProfileContent(UiProfileText("wave3"), identity, running: true);
        var stoppedJson = JsonNode.Parse(stopped)!.AsObject();
        var runningJson = JsonNode.Parse(running)!.AsObject();
        Assert(stoppedJson["Start_Engine"]!.GetValue<bool>() == false, "stopped engine state must remain stopped in applied UI");
        Assert(runningJson["Start_Engine"]!.GetValue<bool>() == true, "running engine state must remain running in applied UI");
        Assert(runningJson["marker"]!.GetValue<string>() == "wave3", "activity UI settings must survive runtime-state normalization");
    }

    private static void TestSessionDisplayLabels()
    {
        const string baseLabel = "[On] Nyoourke (SAM) [UC]";
        Assert(
            MainForm.BuildSessionDisplayLabel(baseLabel, "Sortie", ActivityProfileProvenance.Exact)
                == "[On] Nyoourke (SAM) [UC] [Sortie]",
            "exact activity provenance label mismatch"
        );
        Assert(
            MainForm.BuildSessionDisplayLabel(baseLabel, "Sortie", ActivityProfileProvenance.Modified)
                == "[On] Nyoourke (SAM) [UC] [Sortie-mod]",
            "modified activity provenance label mismatch"
        );
        Assert(
            MainForm.BuildSessionDisplayLabel(baseLabel, "Sortie", ActivityProfileProvenance.NoMatch)
                == "[On] Nyoourke (SAM) [UC] [No Match]",
            "no-match activity provenance label mismatch"
        );
        Assert(
            MainForm.BuildSessionDisplayLabel(baseLabel, null, null) == baseLabel,
            "clearing the active activity must remove the provenance suffix"
        );
    }

    private static string ProfileText(ActivityProfileIdentity identity, string marker)
    {
        return "return { version = 2, profile = { character = \""
            + identity.Character
            + "\", main_job = \""
            + identity.MainJob
            + "\", sub_job = \""
            + identity.SubJob
            + "\" }, config = { marker = \""
            + marker
            + "\" } }\n";
    }

    private static string UiProfileText(string marker)
    {
        return "{\n  \"profile_schema_version\": 3,\n  \"marker\": \"" + marker + "\"\n}";
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void AssertContains(string content, string expected, string message)
    {
        Assert(content.Contains(expected, StringComparison.Ordinal), message);
    }

    private static void AssertNotContains(string content, string expected, string message)
    {
        Assert(!content.Contains(expected, StringComparison.Ordinal), message);
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

    private static void AssertThrowsContains<TException>(Action action, string expected, string message)
        where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException ex)
        {
            Assert(ex.Message.Contains(expected, StringComparison.Ordinal), message + ": " + ex.Message);
            return;
        }

        throw new InvalidOperationException(message);
    }
}
