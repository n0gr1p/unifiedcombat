using UnifiedCombatWinForms.Ui;

namespace UnifiedCombatWinForms;

internal static class DropdownInteractionTests
{
    internal static int Run()
    {
        try
        {
            TestForcedRefreshAfterHydration();
            TestInFlightRequestDeduplication();
            TestJobChangeInvalidationAndSessionIsolation();
            TestJobChangeDropsMergedStaleWeaponSkills();
            TestChangedOptionsReplaceStaleAvailability();
            TestUnchangedOptionsDoNotRebuildOrResetSelection();
            TestConfiguredUnavailableValueIsPreserved();
            TestMouseWheelSuppressionDecision();
            TestClosedComboBoxWheelEventIsHandled();
            Console.WriteLine("DropdownInteractionTests: PASS");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("DropdownInteractionTests: FAIL");
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    private static void TestForcedRefreshAfterHydration()
    {
        var hydrated = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["sam-session"] = "SAM/WAR",
        };
        var inFlight = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        var now = new DateTime(2026, 8, 30, 12, 0, 0, DateTimeKind.Utc);

        Assert(
            OptionsRequestGate.TryBegin(hydrated, inFlight, "sam-session", "SAM/WAR", force: true, now),
            "an explicitly forced refresh must bypass prior hydration for the same job identity"
        );
    }

    private static void TestInFlightRequestDeduplication()
    {
        var hydrated = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["sam-session"] = "SAM/WAR",
        };
        var inFlight = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        var now = new DateTime(2026, 8, 30, 12, 0, 0, DateTimeKind.Utc);

        Assert(
            OptionsRequestGate.TryBegin(hydrated, inFlight, "sam-session", "SAM/WAR", force: true, now),
            "first forced refresh must begin"
        );
        Assert(
            !OptionsRequestGate.TryBegin(hydrated, inFlight, "sam-session", "SAM/WAR", force: true, now.AddSeconds(1)),
            "forced refresh must retain in-flight request deduplication"
        );
    }

    private static void TestJobChangeInvalidationAndSessionIsolation()
    {
        var hydrated = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["sam-session"] = "SAM/WAR",
            ["war-session"] = "WAR/NIN",
        };
        var inFlight = new Dictionary<string, DateTime>(StringComparer.Ordinal)
        {
            ["sam-session"] = DateTime.UtcNow,
            ["war-session"] = DateTime.UtcNow,
        };

        OptionsRequestGate.Invalidate(hydrated, inFlight, "sam-session");

        Assert(!hydrated.ContainsKey("sam-session"), "job change must invalidate the affected session hydration");
        Assert(!inFlight.ContainsKey("sam-session"), "job change must invalidate the affected session request state");
        Assert(hydrated["war-session"] == "WAR/NIN", "one session invalidation must not alter another session hydration");
        Assert(inFlight.ContainsKey("war-session"), "one session invalidation must not alter another session request state");
    }

    private static void TestJobChangeDropsMergedStaleWeaponSkills()
    {
        var currentState = new System.Text.Json.Nodes.JsonObject
        {
            ["job"] = "SAM",
            ["sub_job"] = "WAR",
            ["weaponskill_options"] = "Tachi: Fudo|Tachi: Shoha",
        };
        var incomingState = new System.Text.Json.Nodes.JsonObject
        {
            ["job"] = "DRG",
            ["sub_job"] = "WAR",
        };

        var invalidated = SessionOptionState.InvalidateWeaponSkillsForJobChange(currentState, incomingState);

        Assert(invalidated, "a main-job change must invalidate merged weapon-skill option state");
        Assert(
            !currentState.ContainsKey("weaponskill_options"),
            "stale weapon-skill options must not be published under the new job identity"
        );
    }

    private static void TestChangedOptionsReplaceStaleAvailability()
    {
        using var comboBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown };
        comboBox.Items.AddRange(["Tachi: Fudo", "Tachi: Shoha"]);
        comboBox.Text = "Tachi: Fudo";
        var committedSelections = 0;
        comboBox.SelectionChangeCommitted += (_, _) => committedSelections++;

        var display = ComboBoxOptionUpdater.BuildDisplayOptions(
            ["Impulse Drive", "Stardiver"],
            "Tachi: Fudo"
        );
        var changed = ComboBoxOptionUpdater.ReplaceItemsPreservingTextIfChanged(comboBox, display, "Tachi: Fudo");

        Assert(changed, "a changed runtime WS list must replace the displayed options");
        Assert(!comboBox.Items.Contains("Tachi: Shoha"), "stale runtime WS options must not remain merged");
        Assert(comboBox.Items.Contains("Impulse Drive"), "new runtime WS options must be displayed");
        Assert(comboBox.Items.Contains("Stardiver"), "all new runtime WS options must be displayed");
        Assert(committedSelections == 0, "programmatic option replacement must not become a user selection");
    }

    private static void TestUnchangedOptionsDoNotRebuildOrResetSelection()
    {
        using var comboBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown };
        comboBox.Items.AddRange(["Tachi: Fudo", "Tachi: Shoha"]);
        comboBox.SelectedIndex = 1;
        var selectionChanges = 0;
        comboBox.SelectedIndexChanged += (_, _) => selectionChanges++;

        var changed = ComboBoxOptionUpdater.ReplaceItemsPreservingTextIfChanged(
            comboBox,
            ["Tachi: Fudo", "Tachi: Shoha"],
            "Tachi: Shoha"
        );

        Assert(!changed, "an identical runtime WS list must not rebuild the ComboBox items");
        Assert(comboBox.SelectedIndex == 1, "an identical runtime WS list must not reset selection");
        Assert(selectionChanges == 0, "an identical runtime WS list must not raise a selection reset event");
    }

    private static void TestConfiguredUnavailableValueIsPreserved()
    {
        using var comboBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown };
        comboBox.Items.AddRange(["Tachi: Fudo", "Tachi: Shoha"]);
        comboBox.Text = "Tachi: Fudo";

        var display = ComboBoxOptionUpdater.BuildDisplayOptions(
            ["Impulse Drive", "Stardiver"],
            "Tachi: Fudo"
        );
        ComboBoxOptionUpdater.ReplaceItemsPreservingTextIfChanged(comboBox, display, "Tachi: Fudo");

        Assert(comboBox.Text == "Tachi: Fudo", "availability refresh must preserve an unavailable configured WS");
        Assert(comboBox.Items[0]?.ToString() == "Tachi: Fudo", "the configured WS must remain editable when unavailable");
    }

    private static void TestMouseWheelSuppressionDecision()
    {
        Assert(
            UcControlStyles.ShouldSuppressComboBoxMouseWheel(droppedDown: false),
            "closed ComboBoxes must suppress mouse-wheel selection changes"
        );
        Assert(
            !UcControlStyles.ShouldSuppressComboBoxMouseWheel(droppedDown: true),
            "open ComboBoxes must retain native mouse-wheel behavior"
        );
    }

    private static void TestClosedComboBoxWheelEventIsHandled()
    {
        using var panel = new Panel();
        using var comboBox = new TestComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
        comboBox.Items.AddRange(["One", "Two"]);
        comboBox.SelectedIndex = 0;
        panel.Controls.Add(comboBox);
        UcControlStyles.Apply(panel);

        var wheelEvent = new HandledMouseEventArgs(MouseButtons.None, 0, 0, 0, -120);
        comboBox.RaiseMouseWheel(wheelEvent);

        Assert(wheelEvent.Handled, "the shared ComboBox wiring must handle wheel input while closed");
        Assert(comboBox.SelectedIndex == 0, "closed ComboBox wheel input must leave selection unchanged");
    }

    private sealed class TestComboBox : ComboBox
    {
        internal void RaiseMouseWheel(MouseEventArgs e) => OnMouseWheel(e);
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }
}
