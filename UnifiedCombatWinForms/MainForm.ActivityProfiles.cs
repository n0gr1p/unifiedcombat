using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using UnifiedCombatWinForms.Ui;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private static readonly JsonSerializerOptions ActivityUiJsonOptions = new() { WriteIndented = true };
    private ActivityProfileStore _activityStore = null!;
    private ComboBox _activityCombo = null!;
    private Button _activityCreate = null!;
    private Button _activityUpdate = null!;
    private Button _activityDelete = null!;
    private Button _activityReapply = null!;
    private Label _activityStatus = null!;
    private bool _suppressActivitySelection;
    private bool _activityOperationInProgress;
    private string? _activeActivityId;
    private string? _activeActivityName;
    private readonly HashSet<string> _activeActivitySavedIdentityKeys = new(StringComparer.Ordinal);
    private readonly HashSet<string> _activeActivityUpdatedIdentityKeys = new(StringComparer.Ordinal);

    private sealed record ActivityComboItem(string Id, string Name, int CharacterCount, int VariantCount)
    {
        public override string ToString() => $"{Name} ({VariantCount} variants)";
    }

    private sealed record ActivityCaptureSource(
        string Sid,
        ActivityProfileIdentity Identity,
        JsonObject FlatProfile,
        string StructuredContent
    );

    private void InitializeActivityProfiles()
    {
        var addonRoot = StructuredProfileV2Writer.FindAddonRootFrom(AppContext.BaseDirectory);
        if (addonRoot is null)
        {
            throw new InvalidOperationException("UnifiedCombat addon root is required for activity profiles.");
        }

        _activityStore = new ActivityProfileStore(addonRoot);
    }

    private void BuildGlobalActivityControls(FlowLayoutPanel footer)
    {
        var group = new UcSection("Activity")
        {
            AutoSize = false,
            FillAvailableHeight = true,
            Height = 196,
            MinimumSize = new Size(210, 196),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Margin = new Padding(0, UcTheme.SpaceSm, 0, UcTheme.SpaceMd),
        };
        var layout = new TableLayoutPanel
        {
            AutoSize = false,
            ColumnCount = 1,
            RowCount = 4,
            Dock = DockStyle.Fill,
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42F));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42F));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

        _activityCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 0, 6),
        };
        _activityCombo.SelectedIndexChanged += ActivityComboSelectedIndexChanged;
        layout.Controls.Add(_activityCombo, 0, 0);

        var editButtons = new TableLayoutPanel
        {
            ColumnCount = 3,
            RowCount = 1,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 0, 4),
        };
        editButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.333F));
        editButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.333F));
        editButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.334F));
        _activityCreate = new Button { Text = "Create", AutoSize = false, Dock = DockStyle.Fill };
        _activityCreate.Click += (_, _) => CreateActivity();
        _activityUpdate = new Button { Text = "Update", AutoSize = false, Dock = DockStyle.Fill };
        _activityUpdate.Click += (_, _) => UpdateActivity();
        _activityDelete = new Button { Text = "Delete", AutoSize = false, Dock = DockStyle.Fill };
        _activityDelete.Click += (_, _) => DeleteActivity();
        editButtons.Controls.Add(_activityCreate, 0, 0);
        editButtons.Controls.Add(_activityUpdate, 1, 0);
        editButtons.Controls.Add(_activityDelete, 2, 0);
        layout.Controls.Add(editButtons, 0, 1);

        _activityReapply = new Button
        {
            Text = "Apply Activity",
            AutoSize = false,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 0, 4),
        };
        _activityReapply.Click += async (_, _) => await ApplySelectedActivityAsync(confirm: true);
        layout.Controls.Add(_activityReapply, 0, 2);

        _activityStatus = new Label
        {
            Text = "No activity active",
            AutoSize = false,
            Dock = DockStyle.Fill,
            AutoEllipsis = true,
            ForeColor = SystemColors.GrayText,
        };
        layout.Controls.Add(_activityStatus, 0, 3);
        group.SetContent(layout);
        footer.Controls.Add(group);
        void sizeActivityGroup()
        {
            group.Width = Math.Max(210, footer.ClientSize.Width - footer.Padding.Horizontal - 2);
            group.Height = 196;
        }
        footer.SizeChanged += (_, _) => sizeActivityGroup();
        sizeActivityGroup();
    }

    private void RefreshActivityList(string? selectId = null)
    {
        IReadOnlyList<ActivityProfileSummary> activities;
        try
        {
            activities = _activityStore.List();
        }
        catch (Exception ex)
        {
            _activityStatus.Text = "Activity load failed: " + ex.Message;
            SetActivityControlsEnabled(false);
            return;
        }

        _suppressActivitySelection = true;
        try
        {
            _activityCombo.Items.Clear();
            foreach (var activity in activities)
            {
                _activityCombo.Items.Add(
                    new ActivityComboItem(activity.Id, activity.Name, activity.CharacterCount, activity.VariantCount)
                );
            }

            if (!string.IsNullOrWhiteSpace(selectId))
            {
                SelectActivityWithoutApplying(selectId);
            }
        }
        finally
        {
            _suppressActivitySelection = false;
        }

        SetActivityControlsEnabled(true);
    }

    private void SelectActivityWithoutApplying(string? activityId)
    {
        var wasSuppressed = _suppressActivitySelection;
        _suppressActivitySelection = true;
        try
        {
            _activityCombo.SelectedIndex = -1;
            if (string.IsNullOrWhiteSpace(activityId))
            {
                return;
            }

            for (var i = 0; i < _activityCombo.Items.Count; i++)
            {
                if (_activityCombo.Items[i] is ActivityComboItem item
                    && string.Equals(item.Id, activityId, StringComparison.Ordinal))
                {
                    _activityCombo.SelectedIndex = i;
                    return;
                }
            }
        }
        finally
        {
            _suppressActivitySelection = wasSuppressed;
        }
    }

    private void ActivityComboSelectedIndexChanged(object? sender, EventArgs e)
    {
        if (_suppressActivitySelection || _activityOperationInProgress || _activityCombo.SelectedItem is not ActivityComboItem selected)
        {
            return;
        }

        if (string.Equals(selected.Id, _activeActivityId, StringComparison.Ordinal))
        {
            RefreshActivityCohortStatus();
        }
        else
        {
            _activityStatus.Text = $"{selected.Name} selected; click Apply Activity to activate";
        }
    }

    private void CreateActivity()
    {
        var name = PromptForActivityName();
        if (name is null)
        {
            return;
        }

        try
        {
            var captures = BuildAndPersistActivityCaptures();
            var manifest = _activityStore.Create(
                name,
                captures.Select(BuildActivityProfileCapture).ToList()
            );
            RefreshActivityList(manifest.Id);
            _activityStatus.Text = $"{manifest.Name} created from {captures.Count} active sessions; click Apply to activate";
        }
        catch (Exception ex)
        {
            ShowActivityError("Activity creation failed", ex);
        }
    }

    private void UpdateActivity()
    {
        if (_activityCombo.SelectedItem is not ActivityComboItem selected)
        {
            MessageBox.Show(this, "Select an activity first.", "UnifiedCombat", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            var captures = BuildAndPersistActivityCaptures();
            var manifest = _activityStore.Update(
                selected.Id,
                captures.Select(BuildActivityProfileCapture).ToList()
            );
            RefreshActivityList(manifest.Id);
            _activeActivityId = manifest.Id;
            _activeActivityName = manifest.Name;
            _activeActivitySavedIdentityKeys.Clear();
            _activeActivityUpdatedIdentityKeys.Clear();
            foreach (var capture in captures)
            {
                _activeActivityUpdatedIdentityKeys.Add(capture.Identity.Key);
            }
            RefreshSessionLabelsForActivityContext();
            RefreshActivityCohortStatus();
        }
        catch (Exception ex)
        {
            ShowActivityError("Activity update failed", ex);
        }
    }

    private void DeleteActivity()
    {
        if (_activityCombo.SelectedItem is not ActivityComboItem selected)
        {
            MessageBox.Show(this, "Select an activity first.", "UnifiedCombat", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var answer = MessageBox.Show(
            this,
            $"Delete activity '{selected.Name}'? Current character profiles will not be deleted.",
            "UnifiedCombat",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2
        );
        if (answer != DialogResult.Yes)
        {
            return;
        }

        try
        {
            _activityStore.Delete(selected.Id);
            if (string.Equals(_activeActivityId, selected.Id, StringComparison.Ordinal))
            {
                _activeActivityId = null;
                _activeActivityName = null;
                _activeActivitySavedIdentityKeys.Clear();
                _activeActivityUpdatedIdentityKeys.Clear();
                RefreshSessionLabelsForActivityContext();
            }
            RefreshActivityList();
            _activityStatus.Text = "Activity deleted; current character profiles unchanged";
        }
        catch (Exception ex)
        {
            ShowActivityError("Activity deletion failed", ex);
        }
    }

    private List<ActivityCaptureSource> BuildAndPersistActivityCaptures()
    {
        if (_sessionMetaBySid.Count == 0)
        {
            throw new ActivityProfileException("There are no active sessions to capture.");
        }
        if (!ValidateEncounterConfiguration(out var encounterError))
        {
            throw new ActivityProfileException(encounterError);
        }
        if (!ValidateFormationConfiguration(out var formationError))
        {
            throw new ActivityProfileException(formationError);
        }

        JsonObject? selectedProfile = null;
        if (!string.IsNullOrWhiteSpace(_selectedSid) && _sessionMetaBySid.ContainsKey(_selectedSid))
        {
            selectedProfile = BuildProfileFromUi(_selectedSid);
            _workingProfileBySid[_selectedSid] = selectedProfile.DeepClone().AsObject();
        }

        var captures = new List<ActivityCaptureSource>();
        foreach (var pair in _sessionMetaBySid.OrderBy(x => x.Value.CharName, StringComparer.OrdinalIgnoreCase))
        {
            var sid = pair.Key;
            var meta = pair.Value;
            var identity = RequireActivityIdentity(meta);
            JsonObject profile;
            if (string.Equals(sid, _selectedSid, StringComparison.Ordinal) && selectedProfile is not null)
            {
                profile = selectedProfile.DeepClone().AsObject();
            }
            else if (_workingProfileBySid.TryGetValue(sid, out var working))
            {
                profile = working.DeepClone().AsObject();
            }
            else
            {
                profile = ReadRuntimeActiveProfileForActivityCapture(sid);
            }

            var content = StructuredProfileV2Writer.BuildStructuredProfileFile(profile, identity.ToStructuredIdentity());
            captures.Add(new ActivityCaptureSource(sid, identity, profile, content));
        }

        var duplicate = captures.GroupBy(x => x.Identity.Key, StringComparer.Ordinal).FirstOrDefault(x => x.Count() > 1);
        if (duplicate is not null)
        {
            throw new ActivityProfileException($"Active sessions contain duplicate character/job identity: {duplicate.Key}");
        }

        return captures;
    }

    private static ActivityProfileCapture BuildActivityProfileCapture(ActivityCaptureSource source)
    {
        return new ActivityProfileCapture(
            source.Identity,
            source.StructuredContent,
            source.FlatProfile.ToJsonString(ActivityUiJsonOptions)
        );
    }

    private JsonObject ReadRuntimeActiveProfileForActivityCapture(string sid)
    {
        if (_snapshotDoc is null
            || !_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions)
            || !sessions.TryGetProperty(sid, out var session)
            || !session.TryGetProperty("active_config", out var activeConfig)
            || activeConfig.ValueKind != JsonValueKind.Object)
        {
            throw new ActivityProfileException($"Runtime active configuration is unavailable for session {sid}.");
        }
        return RuntimeProfileEditorAdapter.Build(session, activeConfig);
    }

    private async Task ApplySelectedActivityAsync(bool confirm)
    {
        if (_activityOperationInProgress || _activityCombo.SelectedItem is not ActivityComboItem selected)
        {
            return;
        }

        try
        {
            if (_sessionMetaBySid.Count == 0)
            {
                throw new ActivityProfileException("There are no active sessions to apply this activity to.");
            }

            var sessions = _sessionMetaBySid
                .OrderBy(x => x.Value.CharName, StringComparer.OrdinalIgnoreCase)
                .Select(x => new ActivitySessionIdentity(x.Key, RequireActivityIdentity(x.Value)))
                .ToList();
            var plan = PreserveRuntimeUiState(_activityStore.BuildActivationPlan(selected.Id, sessions));
            var runningCount = plan.Entries.Count(
                entry => _sessionRunningBySid.TryGetValue(entry.Sid, out var running) && running
            );
            if (confirm)
            {
                var confirmationMessage = $"Apply '{plan.ActivityName}' to {plan.Entries.Count} matching active sessions?";
                if (plan.UnmatchedSessions.Count > 0)
                {
                    confirmationMessage +=
                        $"\n\n{plan.UnmatchedSessions.Count} active sessions have no exact variant and will remain unchanged.";
                }
                if (runningCount > 0)
                {
                    var engineWord = runningCount == 1 ? "engine is" : "engines are";
                    confirmationMessage +=
                        $"\n\n{runningCount} combat {engineWord} currently running. "
                        + "Configuration changes take effect immediately; already-issued actions will not be cancelled.";
                }

                var answer = MessageBox.Show(
                    this,
                    confirmationMessage,
                    "UnifiedCombat",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question,
                    MessageBoxDefaultButton.Button2
                );
                if (answer != DialogResult.Yes)
                {
                    return;
                }
            }

            _activityOperationInProgress = true;
            SetActivityControlsEnabled(false);
            _activityStatus.Text = $"Applying {plan.ActivityName} to {plan.Entries.Count} matching sessions…";

            if (plan.Entries.Count > 0)
            {
                using var deployment = _activityStore.Deploy(plan);
                try
                {
                    var mirror = _mirror ?? throw new ActivityProfileException("Session hub is unavailable.");
                    var reloadTasks = plan.Entries.Select(
                        entry => mirror.ReloadProfileV2Async(entry.Sid, TimeSpan.FromSeconds(15), _cts.Token)
                    );
                    var results = await Task.WhenAll(reloadTasks);
                    ValidateReloadResults(plan, results);
                    deployment.Commit();
                }
                catch (Exception activationError)
                {
                    deployment.Rollback();
                    var recovery = await ReloadRestoredProfilesAsync(plan);
                    throw new ActivityProfileException(
                        $"Activity apply failed: {activationError.Message}. Previous profile files were restored; {recovery}",
                        activationError
                    );
                }
            }

            foreach (var entry in plan.Entries)
            {
                _workingProfileBySid[entry.Sid] = JsonNode.Parse(entry.UiProfileContent)?.AsObject()
                    ?? throw new ActivityProfileException($"Activity editor snapshot is invalid for {entry.Identity.Key}.");
            }
            if (!string.IsNullOrWhiteSpace(_selectedSid)
                && plan.Entries.Any(entry => string.Equals(entry.Sid, _selectedSid, StringComparison.Ordinal)))
            {
                RefreshEditorFromSnapshot();
            }

            _activeActivityId = plan.ActivityId;
            _activeActivityName = plan.ActivityName;
            _activeActivitySavedIdentityKeys.Clear();
            _activeActivityUpdatedIdentityKeys.Clear();
            RefreshSessionLabelsForActivityContext();
            RefreshActivityCohortStatus(force: true);
            statusConnection.Text = plan.Entries.Count == 0
                ? $"Mirror: activity context established ({plan.ActivityName}, zero matches)"
                : $"Mirror: activity applied ({plan.ActivityName}, {plan.Entries.Count} matching sessions)";
            if (plan.UnmatchedSessions.Count > 0)
            {
                ShowUnmatchedActivityWarning(plan);
            }
        }
        catch (Exception ex)
        {
            ShowActivityError("Activity activation failed", ex);
        }
        finally
        {
            _activityOperationInProgress = false;
            SetActivityControlsEnabled(true);
        }
    }

    private async Task<string> ReloadRestoredProfilesAsync(ActivityActivationPlan plan)
    {
        if (_mirror is null)
        {
            return "runtime restoration could not be requested because the session hub is unavailable";
        }

        try
        {
            var tasks = plan.Entries.Select(
                entry => _mirror.ReloadProfileV2Async(entry.Sid, TimeSpan.FromSeconds(15), _cts.Token)
            );
            var results = await Task.WhenAll(tasks);
            var entriesBySid = plan.Entries.ToDictionary(x => x.Sid, StringComparer.Ordinal);
            var failures = new List<string>();
            foreach (var result in results)
            {
                if (!entriesBySid.TryGetValue(result.Sid, out var expected))
                {
                    failures.Add($"unknown session {result.Sid} returned a restoration result");
                    continue;
                }
                if (!ReloadIdentityMatches(expected, result))
                {
                    failures.Add(
                        $"{expected.Identity.Character} expected {expected.Identity.MainJob}/{expected.Identity.SubJob}, "
                        + $"but session reported {result.MainJob}/{result.SubJob}"
                    );
                    continue;
                }
                if (!result.Ok || result.DiffCount != 0)
                {
                    failures.Add(DescribeReloadRejection(expected, result));
                }
            }

            return failures.Count == 0
                ? $"previous runtime profile restored on all {plan.Entries.Count} sessions"
                : $"runtime restoration failed on {failures.Count}/{plan.Entries.Count} sessions: {string.Join("; ", failures)}";
        }
        catch (Exception ex)
        {
            return "runtime restoration acknowledgement failed: " + ex.Message;
        }
    }

    private ActivityActivationPlan PreserveRuntimeUiState(ActivityActivationPlan plan)
    {
        var entries = new List<ActivityActivationEntry>(plan.Entries.Count);
        foreach (var entry in plan.Entries)
        {
            if (!_sessionRunningBySid.TryGetValue(entry.Sid, out var running))
            {
                throw new ActivityProfileException($"Runtime engine state is unavailable for session {entry.Sid}.");
            }
            entries.Add(entry with
            {
                UiProfileContent = BuildAppliedUiProfileContent(entry.UiProfileContent, entry.Identity, running),
            });
        }
        return plan with { Entries = entries };
    }

    internal static string BuildAppliedUiProfileContent(
        string content,
        ActivityProfileIdentity identity,
        bool running
    )
    {
        var uiProfile = JsonNode.Parse(content) as JsonObject
            ?? throw new ActivityProfileException($"Activity UI snapshot is not an object for {identity.Key}.");
        uiProfile["Start_Engine"] = running;
        return uiProfile.ToJsonString(ActivityUiJsonOptions);
    }

    private static void ValidateReloadResults(
        ActivityActivationPlan plan,
        IReadOnlyList<ProfileV2ReloadResult> results
    )
    {
        if (results.Count != plan.Entries.Count)
        {
            throw new ActivityProfileException("Not every active session returned a profile-v2 reload result.");
        }

        var entriesBySid = plan.Entries.ToDictionary(x => x.Sid, StringComparer.Ordinal);
        foreach (var result in results)
        {
            if (!entriesBySid.TryGetValue(result.Sid, out var expected))
            {
                throw new ActivityProfileException($"Unexpected profile-v2 reload result from {result.Sid}.");
            }
            if (!result.Ok || result.DiffCount != 0)
            {
                throw new ActivityProfileException(DescribeReloadRejection(expected, result));
            }
            if (!ReloadIdentityMatches(expected, result))
            {
                throw new ActivityProfileException($"Session {result.Sid} changed jobs during activity activation.");
            }
        }
    }

    private static bool ReloadIdentityMatches(ActivityActivationEntry expected, ProfileV2ReloadResult result)
    {
        return string.Equals(result.Character, expected.Identity.Character, StringComparison.OrdinalIgnoreCase)
            && string.Equals(result.MainJob, expected.Identity.MainJob, StringComparison.OrdinalIgnoreCase)
            && string.Equals(result.SubJob, expected.Identity.SubJob, StringComparison.OrdinalIgnoreCase);
    }

    private static string DescribeReloadRejection(ActivityActivationEntry expected, ProfileV2ReloadResult result)
    {
        var detail = result.Error.Trim();
        if (detail.Length == 0)
        {
            detail = $"reload acknowledgement omitted error detail (diff_count={result.DiffCount})";
        }

        foreach (var domain in new[]
                 {
                     (Path: "config.combat.enabled", Label: "Combat"),
                     (Path: "config.movement.enabled", Label: "Movement"),
                     (Path: "config.maintenance.enabled", Label: "Maintenance"),
                     (Path: "config.follow.enabled", Label: "Follow"),
                 })
        {
            if (detail.Contains($"structured profile conversion mismatch: {domain.Path}", StringComparison.Ordinal))
            {
                return $"{expected.Identity.Character} {expected.Identity.MainJob}/{expected.Identity.SubJob}: "
                    + $"the activity snapshot has conflicting {domain.Label} domain enabled values. "
                    + "This snapshot was created by an older UI build; select the activity, click Update, then Apply again.";
            }
        }

        return $"{expected.Identity.Character} {expected.Identity.MainJob}/{expected.Identity.SubJob}: {detail}";
    }

    private static ActivityProfileIdentity RequireActivityIdentity(SessionMeta meta)
    {
        var character = meta.CharName.Trim();
        var mainJob = meta.Job.Trim().ToUpperInvariant();
        var subJob = meta.SubJob.Trim().ToUpperInvariant();
        if (character.Length == 0 || mainJob.Length == 0 || subJob.Length == 0)
        {
            throw new ActivityProfileException($"Session {meta.Sid} has incomplete character/job metadata.");
        }
        return new ActivityProfileIdentity(character, mainJob, subJob);
    }

    internal static ActivityProfileProvenance ResolveActivityProvenance(
        ActivityProfileProvenance storedProvenance,
        bool individuallySavedInContext,
        bool updatedInContext = false
    )
    {
        if (updatedInContext && storedProvenance != ActivityProfileProvenance.NoMatch)
        {
            return ActivityProfileProvenance.Exact;
        }
        return storedProvenance == ActivityProfileProvenance.NoMatch && individuallySavedInContext
            ? ActivityProfileProvenance.Modified
            : storedProvenance;
    }

    private Dictionary<string, ActivityProfileProvenance> BuildActiveActivityProvenanceBySid(
        IReadOnlyDictionary<string, SessionMeta> sessionMetaBySid
    )
    {
        var output = new Dictionary<string, ActivityProfileProvenance>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(_activeActivityId))
        {
            return output;
        }

        var sessions = new List<ActivitySessionIdentity>();
        foreach (var pair in sessionMetaBySid)
        {
            var meta = pair.Value;
            if (string.IsNullOrWhiteSpace(meta.CharName)
                || string.IsNullOrWhiteSpace(meta.Job)
                || string.IsNullOrWhiteSpace(meta.SubJob))
            {
                output[pair.Key] = ActivityProfileProvenance.NoMatch;
                continue;
            }
            sessions.Add(new ActivitySessionIdentity(pair.Key, RequireActivityIdentity(meta)));
        }

        var snapshot = _activityStore.BuildProvenance(_activeActivityId, sessions);
        foreach (var entry in snapshot.Entries)
        {
            output[entry.Sid] = ResolveActivityProvenance(
                entry.Provenance,
                _activeActivitySavedIdentityKeys.Contains(entry.Identity.Key),
                _activeActivityUpdatedIdentityKeys.Contains(entry.Identity.Key)
            );
        }
        return output;
    }

    internal static string BuildSessionDisplayLabel(
        string baseLabel,
        string? activityName,
        ActivityProfileProvenance? provenance
    )
    {
        return provenance.HasValue
            ? baseLabel + " " + ActivityProvenanceSuffix(activityName, provenance.Value)
            : baseLabel;
    }

    private static string ActivityProvenanceSuffix(
        string? activityName,
        ActivityProfileProvenance provenance
    )
    {
        if (provenance == ActivityProfileProvenance.NoMatch)
        {
            return "[No Match]";
        }

        if (string.IsNullOrWhiteSpace(activityName))
        {
            throw new ActivityProfileException("Active activity name is unavailable.");
        }
        return provenance == ActivityProfileProvenance.Exact
            ? $"[{activityName}]"
            : $"[{activityName}-mod]";
    }

    private void MarkActiveActivityProfileSaved(string sid)
    {
        if (string.IsNullOrWhiteSpace(_activeActivityId))
        {
            return;
        }
        if (!_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            throw new ActivityProfileException($"Session metadata is unavailable after saving {sid}.");
        }

        var identityKey = RequireActivityIdentity(meta).Key;
        _activeActivityUpdatedIdentityKeys.Remove(identityKey);
        _activeActivitySavedIdentityKeys.Add(identityKey);
        RefreshSessionLabelsForActivityContext();
        RefreshActivityCohortStatus();
    }

    private void RefreshActivityCohortStatus(bool force = false)
    {
        if ((!force && _activityOperationInProgress) || string.IsNullOrWhiteSpace(_activeActivityId))
        {
            return;
        }

        var provenance = BuildActiveActivityProvenanceBySid(_sessionMetaBySid);
        var matched = provenance.Count(x => x.Value == ActivityProfileProvenance.Exact);
        var modified = provenance.Count(x => x.Value == ActivityProfileProvenance.Modified);
        var noMatch = provenance.Count(x => x.Value == ActivityProfileProvenance.NoMatch);
        _activityStatus.Text = $"{_activeActivityName}: {matched} matched / {modified} modified / {noMatch} no match";
    }

    private void ShowUnmatchedActivityWarning(ActivityActivationPlan plan)
    {
        var identities = plan.UnmatchedSessions
            .Select(x => $"{x.Identity.Character} {x.Identity.MainJob}/{x.Identity.SubJob}")
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase);
        MessageBox.Show(
            this,
            $"'{plan.ActivityName}' is active, but these sessions had no exact variant and were left unchanged:\n\n"
                + string.Join("\n", identities),
            "Activity applied with unmatched sessions",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning
        );
    }

    private void SetActivityControlsEnabled(bool enabled)
    {
        if (_activityCombo is null)
        {
            return;
        }
        _activityCombo.Enabled = enabled;
        _activityCreate.Enabled = enabled;
        _activityUpdate.Enabled = enabled;
        _activityDelete.Enabled = enabled;
        _activityReapply.Enabled = enabled;
    }

    private void ShowActivityError(string title, Exception ex)
    {
        _activityStatus.Text = ex.Message;
        statusConnection.Text = "Mirror: " + ex.Message;
        MessageBox.Show(this, ex.Message, title, MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private string? PromptForActivityName()
    {
        using var dialog = new Form
        {
            Text = "Create activity",
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MinimizeBox = false,
            MaximizeBox = false,
            ShowInTaskbar = false,
            ClientSize = new Size(360, 118),
        };
        var label = new Label { Text = "Activity name", AutoSize = true, Location = new Point(12, 12) };
        var text = new TextBox { Location = new Point(12, 34), Width = 336, MaxLength = 80 };
        var ok = new Button { Text = "Create", DialogResult = DialogResult.OK, Location = new Point(192, 76), Width = 75 };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, Location = new Point(273, 76), Width = 75 };
        dialog.Controls.AddRange([label, text, ok, cancel]);
        dialog.AcceptButton = ok;
        dialog.CancelButton = cancel;
        dialog.Shown += (_, _) => text.Focus();
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return null;
        }

        var name = text.Text.Trim();
        if (name.Length == 0)
        {
            MessageBox.Show(this, "Enter an activity name.", "UnifiedCombat", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return null;
        }
        return name;
    }
}
