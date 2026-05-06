using System.Text.Json;
using System.Text.Json.Nodes;
using System.IO;

namespace UnifiedCombatWinForms;

public partial class MainForm : Form
{
    private MirrorDuplex? _mirror;
    private readonly CancellationTokenSource _cts = new();
    private JsonDocument? _snapshotDoc;
    /// <summary>Suppress control events while applying hub snapshot to the form.</summary>
    private bool _suppressEvents;

    private readonly List<string> _listSids = [];
    private readonly Dictionary<string, string> _sessionLabelBySid = new(StringComparer.Ordinal);
    private readonly Dictionary<string, SessionMeta> _sessionMetaBySid = new(StringComparer.Ordinal);
    private readonly Dictionary<string, bool> _sessionRunningBySid = new(StringComparer.Ordinal);
    /// <summary>UI-only reload workflow: char names queued for engine run-state reapply after addon reconnect.</summary>
    private readonly Dictionary<string, DateTime> _pendingEngineReapplyByChar = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTime> _engineReapplyAttemptBySid = new(StringComparer.Ordinal);
    /// <summary>In-memory per-session working profiles. Session switching reads from here first; disk remains explicit-save only.</summary>
    private readonly Dictionary<string, JsonObject> _workingProfileBySid = new(StringComparer.Ordinal);
    private string? _selectedSid;
    private string? _lastFillSid;

    private readonly Dictionary<string, Dictionary<string, (bool val, DateTime ts)>> _pendingBoolBySid = new();
    private readonly Dictionary<string, (string ws, DateTime ts)> _pendingWsBySid = new();
    private readonly Dictionary<string, string> _optionsHydratedJobBySid = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DateTime> _optionsRequestInFlightBySid = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (int expected, DateTime lastSend, DateTime expires)> _pendingDefMinGateBySid = new(StringComparer.Ordinal);
    /// <summary>Last party-follow distance settings pushed to the game; suppress snapshot overwrite until echoed or timeout.</summary>
    private readonly Dictionary<string, (string min, string max, string fightMin, string holdS, DateTime ts)> _pendingPfDistBySid = new(StringComparer.Ordinal);
    /// <summary>Last spacing tuning values pushed to the game; suppress snapshot overwrite until echoed or timeout.</summary>
    private readonly Dictionary<string, (bool usePrediction, string bandMin, string bandMax, string modelSizeFloor, string lookahead, string repelHoldTicks, string overlapDeadband, string repelWeight, string bandDeadband, DateTime ts)> _pendingSpacingBySid = new(StringComparer.Ordinal);
    private DateTime _abilityInteractionUtc = DateTime.MinValue;

    private readonly Dictionary<string, CheckBox> _boolChecks = new(StringComparer.Ordinal);
    private readonly List<string> _abilityOptions = [];
    private readonly List<string> _corRollOptions = [];
    private readonly List<string> _corPartyOptions = [];
    private readonly List<string> _partyOptions = [];
    private readonly List<string> _selectedAbilities = [];
    private readonly List<string> _pathPullJaOptions = [];
    private readonly List<string> _pathPullSpellOptions = [];
    private readonly Dictionary<string, string> _abilitySignatureBySid = new(StringComparer.Ordinal);
    private readonly object _mirrorLineGate = new();
    private string? _pendingMirrorLine;
    private int _mirrorPumpQueued;

    private List<(int Id, string Name)> _ignoreRows = [];
    private List<(int Id, string Name)> _partnerRows = [];
    private List<(int Slot, string Name)> _targetIgnoreRows = [];
    private List<(int Slot, string Name)> _addPriorityRows = [];
    private List<(int Id, string Name)> _pathHunterRows = [];
    private List<string> _tankEnmityRows = [];
    private sealed record SessionMeta(string Sid, string CharName, string Job, string SubJob, string Engine);

    private void LogDefSync(string message)
    {
        try
        {
            var path = Path.Combine(ProfileRootDir, "ui_def_sync.log");
            File.AppendAllText(path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}\t{message}{Environment.NewLine}");
        }
        catch
        {
            // ignore logging failures
        }
    }

    public MainForm()
    {
        InitializeComponent();
        BuildParityEditor(panelEditorHost, flowSessionActions);
        _mirror = new MirrorDuplex(_cts.Token);
        _mirror.SnapshotOrErrorLineReceived += OnMirrorLine;
        _mirror.Start();
        FormClosed += (_, _) =>
        {
            _cts.Cancel();
            _mirror?.Dispose();
            _snapshotDoc?.Dispose();
        };
    }

    private void OnMirrorLine(string line)
    {
        if (IsDisposed || !IsHandleCreated)
        {
            return;
        }

        lock (_mirrorLineGate)
        {
            _pendingMirrorLine = line;
        }

        if (Interlocked.Exchange(ref _mirrorPumpQueued, 1) == 0)
        {
            BeginInvoke(PumpLatestMirrorLine);
        }
    }

    private void PumpLatestMirrorLine()
    {
        try
        {
            while (true)
            {
                string? line;
                lock (_mirrorLineGate)
                {
                    line = _pendingMirrorLine;
                    _pendingMirrorLine = null;
                }

                if (string.IsNullOrEmpty(line))
                {
                    break;
                }

                ApplyMirrorLine(line);
            }
        }
        finally
        {
            Interlocked.Exchange(ref _mirrorPumpQueued, 0);
            bool hasPending;
            lock (_mirrorLineGate)
            {
                hasPending = !string.IsNullOrEmpty(_pendingMirrorLine);
            }

            if (hasPending && Interlocked.Exchange(ref _mirrorPumpQueued, 1) == 0 && !IsDisposed && IsHandleCreated)
            {
                BeginInvoke(PumpLatestMirrorLine);
            }
        }
    }

    private void ListSessions_SelectedIndexChanged(object? sender, EventArgs e)
    {
        var prevSid = _selectedSid;
        if (!string.IsNullOrWhiteSpace(prevSid) && _listSids.Contains(prevSid))
        {
            CaptureWorkingProfileFromUi(prevSid);
        }

        if (listSessions.SelectedItem is SessionListItem li)
        {
            _selectedSid = li.Sid;
            RefreshEditorFromSnapshot();
        }
        else
        {
            _selectedSid = null;
            ClearForm();
        }
    }

    private sealed record SessionListItem(string Sid, string Label)
    {
        public override string ToString() => Label;
    }

    private string? RequireSelectedSid()
    {
        if (!string.IsNullOrEmpty(_selectedSid) && _listSids.Contains(_selectedSid))
        {
            return _selectedSid;
        }

        MessageBox.Show(this, "Select a session first.", "UnifiedCombat", MessageBoxButtons.OK, MessageBoxIcon.Information);
        return null;
    }

    private void Forward(string sid, Dictionary<string, object?> msg)
    {
        if (msg.TryGetValue("op", out var opGuardObj)
            && string.Equals(Convert.ToString(opGuardObj), "set", StringComparison.Ordinal)
            && msg.TryGetValue("path", out var pathGuardObj)
            && string.Equals(Convert.ToString(pathGuardObj), "def_heal_min_missing_hp", StringComparison.Ordinal))
        {
            if (!msg.TryGetValue("value", out var gateObj) || gateObj is null)
            {
                LogDefSync($"UI_DROP sid={sid} reason=nil_value path=def_heal_min_missing_hp");
                return;
            }

            var gateText = Convert.ToString(gateObj) ?? string.Empty;
            if (!int.TryParse(gateText, out var gateVal))
            {
                LogDefSync($"UI_DROP sid={sid} reason=bad_value path=def_heal_min_missing_hp raw={gateText}");
                return;
            }

            gateVal = Math.Clamp(gateVal, 0, 5000);
            msg["value"] = gateVal;
        }

        try
        {
            var opDbg = msg.TryGetValue("op", out var opObj) ? Convert.ToString(opObj) ?? "" : "";
            if (string.Equals(opDbg, "set", StringComparison.Ordinal)
                && msg.TryGetValue("path", out var pathObj)
                && string.Equals(Convert.ToString(pathObj) ?? "", "def_heal_min_missing_hp", StringComparison.Ordinal))
            {
                var valueDbg = msg.TryGetValue("value", out var vObj) ? Convert.ToString(vObj) ?? "(null)" : "(missing)";
                LogDefSync($"UI_SEND sid={sid} selected={_selectedSid ?? ""} value={valueDbg}");
            }
        }
        catch
        {
            // ignore debug-only path
        }
        _mirror?.EnqueueForward(sid, msg);
        if (!string.Equals(_selectedSid, sid, StringComparison.Ordinal))
        {
            return;
        }

        var op = msg.TryGetValue("op", out var ov) ? Convert.ToString(ov) ?? "" : "";
        if (
            string.Equals(op, "request_state", StringComparison.Ordinal)
            || string.Equals(op, "request_options", StringComparison.Ordinal)
        )
        {
            return;
        }

        // Profile persistence is explicit-only via Save action.
    }

    private void ApplyMirrorLine(string line)
    {
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(line);
        }
        catch (JsonException)
        {
            return;
        }

        var root = doc.RootElement;
        var op = root.TryGetProperty("op", out var opEl) ? opEl.GetString() : null;
        if (op == "mirror_error")
        {
            var reason = root.TryGetProperty("reason", out var r) ? r.GetString() : "error";
            statusConnection.Text = "Mirror: " + (reason ?? "error");
            doc.Dispose();
            return;
        }

        if (op != "mirror_snapshot" || !root.TryGetProperty("sessions", out var sessionsEl) || sessionsEl.ValueKind != JsonValueKind.Object)
        {
            doc.Dispose();
            return;
        }

        var prevMeta = new Dictionary<string, SessionMeta>(_sessionMetaBySid, StringComparer.Ordinal);
        _snapshotDoc?.Dispose();
        _snapshotDoc = doc;

        var keepSid = _selectedSid;
        var nextSids = new List<string>();
        var nextLabels = new Dictionary<string, string>(StringComparer.Ordinal);
        var nextMeta = new Dictionary<string, SessionMeta>(StringComparer.Ordinal);
        var nextRun = new Dictionary<string, bool>(StringComparer.Ordinal);
        var newlyAddedSids = new List<string>();
        foreach (var p in sessionsEl.EnumerateObject())
        {
            nextSids.Add(p.Name);
            nextLabels[p.Name] = SessionLineLabel(p.Name, p.Value);
            var ch = SessionStateHelper.GetString(p.Value, "char", "");
            var job = SessionStateHelper.GetString(p.Value, "job", "");
            var subJob = SessionStateHelper.GetString(p.Value, "sub_job", "");
            var eng = SessionStateHelper.GetString(p.Value, "engine", "UC");
            nextMeta[p.Name] = new SessionMeta(p.Name, ch, job, subJob, eng);
            nextRun[p.Name] = SessionStateHelper.GetBool(p.Value, "Start_Engine", false);
        }

        var listChanged = nextLabels.Count != _sessionLabelBySid.Count;
        if (!listChanged)
        {
            foreach (var kv in nextLabels)
            {
                if (!_sessionLabelBySid.TryGetValue(kv.Key, out var cur) || !string.Equals(cur, kv.Value, StringComparison.Ordinal))
                {
                    listChanged = true;
                    break;
                }
            }
        }

        _listSids.Clear();
        _listSids.AddRange(nextSids);

        if (listChanged)
        {
            listSessions.BeginUpdate();
            try
            {
                listSessions.Items.Clear();
                foreach (var sid in nextSids)
                {
                    if (nextLabels.TryGetValue(sid, out var label))
                    {
                        listSessions.Items.Add(new SessionListItem(sid, label));
                    }
                }

                var newIndex = -1;
                if (keepSid != null)
                {
                    for (var i = 0; i < listSessions.Items.Count; i++)
                    {
                        if (listSessions.Items[i] is SessionListItem li && li.Sid == keepSid)
                        {
                            newIndex = i;
                            break;
                        }
                    }
                }

                if (newIndex >= 0)
                {
                    listSessions.SelectedIndex = newIndex;
                }
                else if (listSessions.Items.Count > 0)
                {
                    listSessions.SelectedIndex = 0;
                }
                else
                {
                    _selectedSid = null;
                    ClearForm();
                }
            }
            finally
            {
                listSessions.EndUpdate();
            }
        }
        else if (_selectedSid != null && !_listSids.Contains(_selectedSid))
        {
            _selectedSid = null;
            ClearForm();
        }

        _sessionLabelBySid.Clear();
        foreach (var kv in nextLabels)
        {
            _sessionLabelBySid[kv.Key] = kv.Value;
        }
        _sessionMetaBySid.Clear();
        foreach (var kv in nextMeta)
        {
            _sessionMetaBySid[kv.Key] = kv.Value;
        }
        foreach (var kv in nextMeta)
        {
            if (!prevMeta.TryGetValue(kv.Key, out var oldMeta))
            {
                _optionsHydratedJobBySid.Remove(kv.Key);
                _optionsRequestInFlightBySid.Remove(kv.Key);
                _workingProfileBySid.Remove(kv.Key);
                newlyAddedSids.Add(kv.Key);
                continue;
            }

            if (!string.Equals(oldMeta.Job, kv.Value.Job, StringComparison.OrdinalIgnoreCase))
            {
                _optionsHydratedJobBySid.Remove(kv.Key);
                _optionsRequestInFlightBySid.Remove(kv.Key);
                _workingProfileBySid.Remove(kv.Key);
            }
        }
        foreach (var oldSid in prevMeta.Keys)
        {
            if (!nextMeta.ContainsKey(oldSid))
            {
                _optionsHydratedJobBySid.Remove(oldSid);
                _optionsRequestInFlightBySid.Remove(oldSid);
                _workingProfileBySid.Remove(oldSid);
            }
        }
        _sessionRunningBySid.Clear();
        foreach (var kv in nextRun)
        {
            _sessionRunningBySid[kv.Key] = kv.Value;
        }
        // Reapply after metadata is committed so profile path resolves as Character_Job.json, not sid fallback.
        foreach (var sid in newlyAddedSids)
        {
            ReapplyDefensiveMinMissingHpForSid(sid);
        }
        TryApplyQueuedEngineReapply();

        statusConnection.Text = $"Mirror: snapshot ({_listSids.Count} sessions)";
        statusLastUpdate.Text = "Last snapshot: " + DateTime.Now.ToString("T");
        if (!string.IsNullOrWhiteSpace(_selectedSid) && sessionsEl.TryGetProperty(_selectedSid, out var selectedState))
        {
            ApplyOptionsFromSnapshotIfPresent(_selectedSid!, selectedState);
        }
        EnforceAuthoritativeDefMinAgainstSnapshot(sessionsEl);
        ReconcileDefensiveMinGateAgainstSnapshot(sessionsEl);
        // UI is authoritative after initial/manual session selection.
        // Do not force-refresh controls on every inbound snapshot.
    }

    private bool TryReadProfileDefMinForSid(string sid, out int gate)
    {
        gate = 0;
        try
        {
            if (!TryLoadProfileForSid(sid, out var prof))
            {
                return false;
            }
            using (prof)
            {
                var root = prof.RootElement;
                if (!root.TryGetProperty("def_heal_min_missing_hp", out var gateEl))
                {
                    LogDefSync($"PROFILE_READ sid={sid} result=no_key");
                    return false;
                }
                var raw = gateEl.ValueKind == JsonValueKind.String ? (gateEl.GetString() ?? "") : gateEl.GetRawText();
                if (!int.TryParse(raw, out gate))
                {
                    LogDefSync($"PROFILE_READ sid={sid} result=bad_parse raw={raw}");
                    return false;
                }
                gate = Math.Clamp(gate, 0, 5000);
                if (TryProfilePathForSid(sid, out var profPath))
                {
                    LogDefSync($"PROFILE_READ sid={sid} value={gate} path={profPath}");
                }
                return true;
            }
        }
        catch
        {
            return false;
        }
    }

    private void EnforceAuthoritativeDefMinAgainstSnapshot(JsonElement sessionsEl)
    {
        var now = DateTime.UtcNow;
        foreach (var p in sessionsEl.EnumerateObject())
        {
            var sid = p.Name;
            if (!TryReadProfileDefMinForSid(sid, out var desired))
            {
                continue;
            }

            if (_pendingDefMinGateBySid.TryGetValue(sid, out var pend) && (now - pend.lastSend).TotalMilliseconds < 900)
            {
                continue;
            }

            if (!p.Value.TryGetProperty("def_heal_min_missing_hp", out var curEl))
            {
                LogDefSync($"ENFORCE sid={sid} current=(missing) desired={desired}");
                SendDefensiveMinGate(sid, desired);
                continue;
            }
            var raw = curEl.ValueKind == JsonValueKind.String ? (curEl.GetString() ?? "") : curEl.GetRawText();
            if (!int.TryParse(raw, out var current))
            {
                LogDefSync($"ENFORCE sid={sid} current=(bad:{raw}) desired={desired}");
                SendDefensiveMinGate(sid, desired);
                continue;
            }
            if (current != desired)
            {
                LogDefSync($"ENFORCE sid={sid} current={current} desired={desired}");
                SendDefensiveMinGate(sid, desired);
            }
        }
    }

    private void ReapplyDefensiveMinMissingHpForSid(string sid)
    {
        try
        {
            JsonDocument prof;
            if (!TryLoadProfileForSid(sid, out prof) && !TryLoadWorkingProfileForSid(sid, out prof))
            {
                return;
            }
            using (prof)
            {
                var root = prof.RootElement;
                if (root.TryGetProperty("def_heal_min_missing_hp", out var gateEl))
                {
                    var val = gateEl.ValueKind == JsonValueKind.String
                        ? (gateEl.GetString() ?? "")
                        : gateEl.GetRawText();
                    if (!int.TryParse(val, out var n))
                    {
                        return;
                    }
                    n = Math.Clamp(n, 0, 5000);
                    SendDefensiveMinGate(sid, n);
                }
            }
        }
        catch
        {
            // best-effort reconnect reapply only
        }
    }

    private void SendDefensiveMinGate(string sid, int n)
    {
        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "set",
                ["path"] = "def_heal_min_missing_hp",
                ["value"] = n,
            }
        );
        _pendingDefMinGateBySid[sid] = (n, DateTime.UtcNow, DateTime.UtcNow.AddSeconds(30));
    }

    private void ReconcileDefensiveMinGateAgainstSnapshot(JsonElement sessionsEl)
    {
        var now = DateTime.UtcNow;
        foreach (var sid in _pendingDefMinGateBySid.Keys.ToList())
        {
            if (_pendingDefMinGateBySid[sid].expires <= now)
            {
                _pendingDefMinGateBySid.Remove(sid);
            }
        }

        foreach (var p in sessionsEl.EnumerateObject())
        {
            var sid = p.Name;
            if (!_pendingDefMinGateBySid.TryGetValue(sid, out var pend))
            {
                continue;
            }

            if (!p.Value.TryGetProperty("def_heal_min_missing_hp", out var curEl))
            {
                continue;
            }
            var currentRaw = curEl.ValueKind == JsonValueKind.String ? (curEl.GetString() ?? "") : curEl.GetRawText();
            if (!int.TryParse(currentRaw, out var current))
            {
                continue;
            }
            if (current == pend.expected)
            {
                _pendingDefMinGateBySid.Remove(sid);
                continue;
            }

            if ((now - pend.lastSend).TotalSeconds >= 1.0 && pend.expires > now)
            {
                SendDefensiveMinGate(sid, pend.expected);
            }
        }
    }

    private void TryApplyQueuedEngineReapply()
    {
        if (_pendingEngineReapplyByChar.Count == 0)
        {
            return;
        }

        var now = DateTime.UtcNow;
        foreach (var key in _pendingEngineReapplyByChar.Keys.ToList())
        {
            if (_pendingEngineReapplyByChar[key] <= now)
            {
                _pendingEngineReapplyByChar.Remove(key);
            }
        }

        if (_pendingEngineReapplyByChar.Count == 0)
        {
            return;
        }

        foreach (var kv in _sessionMetaBySid)
        {
            var sid = kv.Key;
            var meta = kv.Value;
            if (string.IsNullOrWhiteSpace(meta.CharName))
            {
                continue;
            }
            if (!_pendingEngineReapplyByChar.ContainsKey(meta.CharName))
            {
                continue;
            }

            var running = _sessionRunningBySid.TryGetValue(sid, out var rv) && rv;
            if (running)
            {
                _pendingEngineReapplyByChar.Remove(meta.CharName);
                continue;
            }

            if (_engineReapplyAttemptBySid.TryGetValue(sid, out var lastTry) && (now - lastTry).TotalSeconds < 2.0)
            {
                continue;
            }

            _engineReapplyAttemptBySid[sid] = now;
            Forward(sid, new Dictionary<string, object?> { ["op"] = "start_engine" });
            _sessionRunningBySid[sid] = true;
            _pendingEngineReapplyByChar.Remove(meta.CharName);
            statusConnection.Text = $"Mirror: re-applied engine run after reload ({meta.CharName})";
        }
    }

    private bool IsOptionsHydratedForCurrentJob(string sid)
    {
        if (!_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            return false;
        }
        if (!_optionsHydratedJobBySid.TryGetValue(sid, out var hydratedJob))
        {
            return false;
        }
        return string.Equals(hydratedJob, meta.Job, StringComparison.OrdinalIgnoreCase);
    }

    private void EnsureOptionsHydrated(string sid, bool force = false)
    {
        if (string.IsNullOrWhiteSpace(sid))
        {
            return;
        }
        if (!force && IsOptionsHydratedForCurrentJob(sid))
        {
            return;
        }
        if (!force && _optionsRequestInFlightBySid.TryGetValue(sid, out var lastReq) && (DateTime.UtcNow - lastReq).TotalSeconds < 2)
        {
            return;
        }

        _optionsRequestInFlightBySid[sid] = DateTime.UtcNow;
        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "request_options",
            }
        );
    }

    private static string SessionLineLabel(string sid, JsonElement s)
    {
        _ = sid;
        var running = SessionStateHelper.GetBool(s, "Start_Engine", false);
        var zpaused = SessionStateHelper.GetBool(s, "zone_suspend_active", false);
        var runFlag = running && zpaused ? "Paused" : running ? "On" : "Off";
        var ch = SessionStateHelper.GetString(s, "char", "?");
        if (string.IsNullOrEmpty(ch))
        {
            ch = "?";
        }

        var job = SessionStateHelper.GetString(s, "job", "?");
        if (string.IsNullOrEmpty(job))
        {
            job = "?";
        }

        var eng = SessionStateHelper.GetString(s, "engine", "?");
        if (string.IsNullOrEmpty(eng))
        {
            eng = "?";
        }

        return $"[{runFlag}] {ch} ({job}) [{eng}]";
    }
}
