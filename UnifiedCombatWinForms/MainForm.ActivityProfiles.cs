using System.Text;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
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
    private readonly Dictionary<string, string> _activeActivityCohortBySid = new(StringComparer.Ordinal);

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
        var group = new GroupBox
        {
            Text = "Activity (all active sessions)",
            AutoSize = false,
            Height = 160,
            MinimumSize = new Size(210, 160),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Padding = new Padding(6),
            Margin = new Padding(0, 0, 0, 10),
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
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34F));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34F));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

        _activityCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 0, 6),
        };
        _activityCombo.SelectedIndexChanged += ActivityComboSelectedIndexChanged;
        layout.Controls.Add(_activityCombo, 0, 0);

        var editButtons = new FlowLayoutPanel
        {
            AutoSize = false,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 4),
        };
        _activityCreate = new Button { Text = "Create", AutoSize = true };
        _activityCreate.Click += (_, _) => CreateActivity();
        _activityUpdate = new Button { Text = "Update", AutoSize = true };
        _activityUpdate.Click += (_, _) => UpdateActivity();
        _activityDelete = new Button { Text = "Delete", AutoSize = true };
        _activityDelete.Click += (_, _) => DeleteActivity();
        editButtons.Controls.AddRange([_activityCreate, _activityUpdate, _activityDelete]);
        layout.Controls.Add(editButtons, 0, 1);

        _activityReapply = new Button
        {
            Text = "Apply to all sessions",
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
        group.Controls.Add(layout);
        footer.Controls.Add(group);
        void sizeActivityGroup()
        {
            group.Width = Math.Max(210, footer.ClientSize.Width - footer.Padding.Horizontal - 2);
            group.Height = 160;
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

        _activityStatus.Text = string.Equals(selected.Id, _activeActivityId, StringComparison.Ordinal)
            ? $"{selected.Name} active on {_activeActivityCohortBySid.Count} sessions"
            : $"{selected.Name} selected; click Apply to all sessions to activate";
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
                captures.Select(x => new ActivityProfileCapture(x.Identity, x.StructuredContent)).ToList()
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
                captures.Select(x => new ActivityProfileCapture(x.Identity, x.StructuredContent)).ToList()
            );
            RefreshActivityList(manifest.Id);
            _activeActivityCohortBySid.Clear();
            _activityStatus.Text = $"{manifest.Name} updated; click Apply to activate";
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
                _activeActivityCohortBySid.Clear();
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
                profile = ReadExistingUiProfileForActivityCapture(sid);
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

    private JsonObject ReadExistingUiProfileForActivityCapture(string sid)
    {
        if (!TryProfilePathForSid(sid, out var path))
        {
            throw new ActivityProfileException($"UI profile path is unavailable for session {sid}.");
        }
        if (!TryMigrateLegacyUiProfileForSid(sid, path, out var migrationError))
        {
            throw new ActivityProfileException(migrationError);
        }
        if (!File.Exists(path))
        {
            throw new ActivityProfileException($"Save the individual session profile before capturing an activity: {path}");
        }

        JsonObject profile;
        try
        {
            profile = JsonNode.Parse(File.ReadAllText(path, Encoding.UTF8)) as JsonObject
                ?? throw new ActivityProfileException($"UI profile is not a JSON object: {path}");
        }
        catch (ActivityProfileException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new ActivityProfileException($"UI profile is invalid: {path}", ex);
        }

        MigrateProfileInPlace(profile);
        return profile;
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

            var runningCount = _sessionRunningBySid.Count(x => x.Value);

            var sessions = _sessionMetaBySid
                .OrderBy(x => x.Value.CharName, StringComparer.OrdinalIgnoreCase)
                .Select(x => new ActivitySessionIdentity(x.Key, RequireActivityIdentity(x.Value)))
                .ToList();
            var plan = _activityStore.BuildActivationPlan(selected.Id, sessions);
            if (confirm)
            {
                var confirmationMessage = $"Apply '{plan.ActivityName}' to all {plan.Entries.Count} active sessions?";
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
            _activityStatus.Text = $"Applying {plan.ActivityName} to {plan.Entries.Count} sessions…";

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

            _activeActivityId = plan.ActivityId;
            _activeActivityName = plan.ActivityName;
            _activeActivityCohortBySid.Clear();
            foreach (var entry in plan.Entries)
            {
                _activeActivityCohortBySid[entry.Sid] = entry.Identity.Key;
            }
            _activityStatus.Text = $"{plan.ActivityName} active on {plan.Entries.Count} sessions";
            statusConnection.Text = $"Mirror: activity applied ({plan.ActivityName}, {plan.Entries.Count} sessions)";
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

    private void RefreshActivityCohortStatus()
    {
        if (_activityOperationInProgress || string.IsNullOrWhiteSpace(_activeActivityId))
        {
            return;
        }

        var exact = _sessionMetaBySid.Count == _activeActivityCohortBySid.Count;
        if (exact)
        {
            foreach (var pair in _sessionMetaBySid)
            {
                var meta = pair.Value;
                if (string.IsNullOrWhiteSpace(meta.CharName)
                    || string.IsNullOrWhiteSpace(meta.Job)
                    || string.IsNullOrWhiteSpace(meta.SubJob))
                {
                    exact = false;
                    break;
                }
                var identity = RequireActivityIdentity(meta);
                if (!_activeActivityCohortBySid.TryGetValue(pair.Key, out var appliedKey)
                    || !string.Equals(appliedKey, identity.Key, StringComparison.Ordinal))
                {
                    exact = false;
                    break;
                }
            }
        }

        _activityStatus.Text = exact
            ? $"{_activeActivityName} active on {_activeActivityCohortBySid.Count} sessions"
            : $"{_activeActivityName}: active sessions or jobs changed; apply again required";
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
