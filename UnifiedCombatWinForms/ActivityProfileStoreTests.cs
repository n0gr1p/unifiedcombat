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
            TestLegacyBundleRequiresVariantUpdate(root);
            TestAppliedUiPreservesRuntimeEngineState();
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
        AssertContains(ui, "selected; click Apply to all sessions to activate", "activity selection must direct the user to explicit apply");
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
        AssertContains(ui, "UI synchronized", "successful activity apply must report UI synchronization");
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

        AssertThrows<ActivityProfileException>(
            () => store.BuildActivationPlan(
                created.Id,
                [
                    new ActivitySessionIdentity("sid-red", new ActivityProfileIdentity("Redrogue", "WHM", "SCH")),
                    new ActivitySessionIdentity("sid-night", nightBrd),
                ]
            ),
            "unsupported active job must block the whole activity"
        );
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
        Directory.CreateDirectory(Path.GetDirectoryName(redDestination)!);
        Directory.CreateDirectory(Path.GetDirectoryName(redUiDestination)!);
        File.WriteAllText(redDestination, "old-red");
        File.WriteAllText(nightDestination, "old-night");
        File.WriteAllText(redUiDestination, "{\"marker\":\"old-red-ui\"}");
        File.WriteAllText(nightUiDestination, "{\"marker\":\"old-night-ui\"}");

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
