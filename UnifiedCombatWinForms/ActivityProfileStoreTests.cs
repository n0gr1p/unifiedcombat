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

        var created = store.Create(
            "Dynamis Wave 3",
            [
                new ActivityProfileCapture(redPld, pldContent),
                new ActivityProfileCapture(nightBrd, brdContent),
            ]
        );
        Assert(created.Characters.Count == 2, "create must capture every active character");
        Assert(store.List().Single().VariantCount == 2, "create variant count mismatch");

        var updated = store.Update(created.Id, [new ActivityProfileCapture(redRun, runContent)]);
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
        Assert(plan.Entries.Single(x => x.Sid == "sid-night").ProfileContent == brdContent, "BRD session selected wrong variant");
        var alternatePlan = store.BuildActivationPlan(
            created.Id,
            [new ActivitySessionIdentity("sid-red", redPld)]
        );
        Assert(alternatePlan.Entries.Single().ProfileContent == pldContent, "retained PLD job variant is not selectable");

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
        Directory.CreateDirectory(Path.GetDirectoryName(redDestination)!);
        File.WriteAllText(redDestination, "old-red");
        File.WriteAllText(nightDestination, "old-night");

        using (var deployment = store.Deploy(plan))
        {
            Assert(File.ReadAllText(redDestination) == runContent, "deployment did not stage RUN profile");
            Assert(File.ReadAllText(nightDestination) == brdContent, "deployment did not stage BRD profile");
            deployment.Rollback();
        }
        Assert(File.ReadAllText(redDestination) == "old-red", "rollback did not restore RUN destination");
        Assert(File.ReadAllText(nightDestination) == "old-night", "rollback did not restore BRD destination");

        using (var deployment = store.Deploy(plan))
        {
            deployment.Commit();
        }
        Assert(File.ReadAllText(redDestination) == runContent, "committed RUN profile mismatch");
        Assert(File.ReadAllText(nightDestination) == brdContent, "committed BRD profile mismatch");

        var sourceToCorrupt = plan.Entries.Single(x => x.Sid == "sid-red").SourcePath;
        File.AppendAllText(sourceToCorrupt, "-- corrupt");
        AssertThrows<ActivityProfileException>(
            () => store.BuildActivationPlan(created.Id, [new ActivitySessionIdentity("sid-red", redRun)]),
            "checksum mismatch must block activation"
        );

        store.Delete(created.Id);
        Assert(store.List().Count == 0, "delete must remove only the activity bundle");
        Assert(File.Exists(redDestination), "delete must not remove current canonical character profiles");
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
}
