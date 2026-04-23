using System.Text.Json;

namespace UnifiedCombatWinForms;

public partial class MainForm : Form
{
    private MirrorDuplex? _mirror;
    private readonly CancellationTokenSource _cts = new();
    private JsonDocument? _snapshotDoc;
    /// <summary>Suppress control events while applying hub snapshot to the form.</summary>
    private bool _suppressEvents;

    private readonly List<string> _listSids = [];
    private string? _selectedSid;
    private string? _lastFillSid;

    private readonly Dictionary<string, Dictionary<string, (bool val, DateTime ts)>> _pendingBoolBySid = new();
    private readonly Dictionary<string, (string ws, DateTime ts)> _pendingWsBySid = new();
    /// <summary>Last party-follow distance settings pushed to the game; suppress snapshot overwrite until echoed or timeout.</summary>
    private readonly Dictionary<string, (string min, string max, string fightMin, string holdS, DateTime ts)> _pendingPfDistBySid = new(StringComparer.Ordinal);
    /// <summary>Last spacing tuning values pushed to the game; suppress snapshot overwrite until echoed or timeout.</summary>
    private readonly Dictionary<string, (bool usePrediction, string bandMin, string bandMax, string lookahead, string anchorInvalidTicks, string emergencyMargin, string switchPenalty, string switchMargin, string arrivalTolerance, string maxAgents, DateTime ts)> _pendingSpacingBySid = new(StringComparer.Ordinal);
    private DateTime _abilityInteractionUtc = DateTime.MinValue;

    private readonly Dictionary<string, CheckBox> _boolChecks = new(StringComparer.Ordinal);
    private readonly List<string> _abilityOptions = [];
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

    private void Forward(string sid, Dictionary<string, object?> msg) => _mirror?.EnqueueForward(sid, msg);

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

        _snapshotDoc?.Dispose();
        _snapshotDoc = doc;

        var keepSid = _selectedSid;
        _listSids.Clear();
        var items = new List<SessionListItem>();
        foreach (var p in sessionsEl.EnumerateObject())
        {
            _listSids.Add(p.Name);
            items.Add(new SessionListItem(p.Name, SessionLineLabel(p.Name, p.Value)));
        }

        listSessions.BeginUpdate();
        try
        {
            listSessions.Items.Clear();
            foreach (var it in items)
            {
                listSessions.Items.Add(it);
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

        statusConnection.Text = $"Mirror: snapshot ({_listSids.Count} sessions)";
        statusLastUpdate.Text = "Last snapshot: " + DateTime.Now.ToString("T");
        RefreshEditorFromSnapshot();
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
