using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using System.IO;
using System.Collections.Concurrent;

namespace UnifiedCombatWinForms;

internal sealed record ProfileV2ReloadResult(
    string Sid,
    string RequestId,
    bool Ok,
    string Character,
    string MainJob,
    string SubJob,
    int DiffCount,
    string Error
);

/// <summary>
/// In-process hub for UnifiedCombat addon sessions.
/// - Hosts a TCP server on 127.0.0.1:27182 for addon clients (NDJSON).
/// - Emits mirror-style snapshot/error lines to keep MainForm parity logic unchanged.
/// - Forwards UI commands directly to selected addon sessions.
/// </summary>
internal sealed class MirrorDuplex : IDisposable
{
    private const int AddonPort = 27182;
    private static readonly IPAddress Loopback = IPAddress.Loopback;

    private readonly CancellationTokenSource _linkedCts;
    private readonly Channel<(string sid, string line)> _outbound = Channel.CreateUnbounded<(string sid, string line)>(
        new UnboundedChannelOptions { SingleReader = true, SingleWriter = false }
    );
    private readonly object _sessionsGate = new();
    private readonly Dictionary<string, SessionConn> _sessions = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, PendingProfileReload> _pendingProfileReloads = new(StringComparer.Ordinal);
    private TcpListener? _listener;
    private Task? _acceptTask;
    private Task? _writeTask;
    private long _sidSuffix = 0;

    public event Action<string>? SnapshotOrErrorLineReceived;

    private sealed class SessionConn
    {
        public required string Sid { get; init; }
        public required TcpClient Client { get; init; }
        public required StreamWriter Writer { get; init; }
        public JsonObject State { get; } = new();
    }

    private sealed record PendingProfileReload(
        string Sid,
        TaskCompletionSource<ProfileV2ReloadResult> Completion
    );

    public MirrorDuplex(CancellationToken appCt)
    {
        _linkedCts = CancellationTokenSource.CreateLinkedTokenSource(appCt);
    }

    public void Start()
    {
        _acceptTask = Task.Run(AcceptLoopAsync);
        _writeTask = Task.Run(WritePumpAsync);
    }

    public void EnqueueForward(string sid, IReadOnlyDictionary<string, object?> msg)
    {
        if (string.IsNullOrWhiteSpace(sid))
        {
            return;
        }

        var line = JsonSerializer.Serialize(msg) + "\n";
        try
        {
            if (msg.TryGetValue("op", out var opObj)
                && string.Equals(Convert.ToString(opObj), "set", StringComparison.Ordinal)
                && msg.TryGetValue("path", out var pathObj))
            {
                var path = Convert.ToString(pathObj) ?? string.Empty;
                if (string.Equals(path, "def_heal_min_missing_hp", StringComparison.Ordinal)
                    || string.Equals(path, "def_remove_enemy_buffs", StringComparison.Ordinal))
                {
                    var valText = msg.TryGetValue("value", out var vObj) && vObj is not null
                        ? Convert.ToString(vObj) ?? "(unprintable)"
                        : "(null-or-missing)";
                    var trace = msg.TryGetValue("trace_id", out var trObj) && trObj is not null
                        ? Convert.ToString(trObj) ?? ""
                        : "";
                    var root = AppContext.BaseDirectory;
                    var logDir = Path.Combine(root, "data", "ui_profiles");
                    Directory.CreateDirectory(logDir);
                    var logPath = Path.Combine(logDir, "ui_def_sync.log");
                    File.AppendAllText(
                        logPath,
                        $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}\tMIRROR_ENQUEUE sid={sid} path={path} value={valText} trace={trace} line={line.Trim()}{Environment.NewLine}"
                    );
                }
            }
        }
        catch
        {
            // debug logging must never impact flow
        }
        _outbound.Writer.TryWrite((sid, line));
    }

    public async Task<ProfileV2ReloadResult> ReloadProfileV2Async(
        string sid,
        TimeSpan timeout,
        CancellationToken cancellationToken
    )
    {
        lock (_sessionsGate)
        {
            if (!_sessions.ContainsKey(sid))
            {
                throw new InvalidOperationException($"Profile-v2 reload session is not connected: {sid}");
            }
        }

        var requestId = Guid.NewGuid().ToString("N");
        var completion = new TaskCompletionSource<ProfileV2ReloadResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_pendingProfileReloads.TryAdd(requestId, new PendingProfileReload(sid, completion)))
        {
            throw new InvalidOperationException("Duplicate profile-v2 reload request id.");
        }

        EnqueueForward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "profile_v2_reload",
                ["request_id"] = requestId,
            }
        );

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _linkedCts.Token);
        timeoutCts.CancelAfter(timeout);
        try
        {
            return await completion.Task.WaitAsync(timeoutCts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested && !_linkedCts.IsCancellationRequested)
        {
            throw new TimeoutException($"Timed out waiting for profile-v2 reload result from session {sid}.");
        }
        finally
        {
            _pendingProfileReloads.TryRemove(requestId, out _);
        }
    }

    private async Task AcceptLoopAsync()
    {
        var ct = _linkedCts.Token;
        try
        {
            _listener = new TcpListener(Loopback, AddonPort);
            _listener.Start();
        }
        catch (Exception ex)
        {
            EmitMirrorError("listen_failed:" + ex.GetType().Name);
            return;
        }

        EmitSnapshot();

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync(ct).ConfigureAwait(false);
                _ = Task.Run(() => HandleClientAsync(client, ct), ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                EmitMirrorError("accept_failed");
            }
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken ct)
    {
        string? sid = null;
        try
        {
            using (client)
            await using (var stream = client.GetStream())
            using (var reader = new StreamReader(
                       stream,
                       Encoding.UTF8,
                       detectEncodingFromByteOrderMarks: false,
                       bufferSize: 65536,
                       leaveOpen: true
                   ))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false), 65536, leaveOpen: true)
                   {
                       AutoFlush = true,
                       NewLine = "\n",
                   })
            {
                while (!ct.IsCancellationRequested)
                {
                    var line = await reader.ReadLineAsync(ct).ConfigureAwait(false);
                    if (line is null)
                    {
                        break;
                    }

                    if (line.Length == 0)
                    {
                        continue;
                    }

                    JsonObject? msg;
                    try
                    {
                        msg = JsonNode.Parse(line) as JsonObject;
                    }
                    catch
                    {
                        continue;
                    }

                    if (msg is null)
                    {
                        continue;
                    }

                    var op = msg["op"]?.GetValue<string>();
                    if (op == "hello")
                    {
                        sid = RegisterHelloSession(client, writer, msg);
                        EmitSnapshot();
                        await SendRequestStateAsync(writer, ct).ConfigureAwait(false);
                        continue;
                    }

                    if ((op == "state" || op == "options") && !string.IsNullOrWhiteSpace(sid))
                    {
                        UpdateSessionState(sid!, msg);
                        EmitSnapshot();
                        continue;
                    }

                    if (op == "profile_v2_reload_result" && !string.IsNullOrWhiteSpace(sid))
                    {
                        CompleteProfileV2Reload(sid!, msg);
                    }
                }
            }
        }
        catch (OperationCanceledException)
        {
            // expected on shutdown
        }
        catch
        {
            EmitMirrorError("client_error");
        }
        finally
        {
            if (!string.IsNullOrWhiteSpace(sid))
            {
                RemoveSession(sid!);
                EmitSnapshot();
            }
        }
    }

    private string RegisterHelloSession(TcpClient client, StreamWriter writer, JsonObject hello)
    {
        var proposed = hello["session"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(proposed))
        {
            proposed = "session_" + Interlocked.Increment(ref _sidSuffix);
        }

        var sid = proposed!;
        lock (_sessionsGate)
        {
            if (_sessions.ContainsKey(sid))
            {
                sid = proposed + "::" + Interlocked.Increment(ref _sidSuffix);
            }

            var rec = new SessionConn
            {
                Sid = sid,
                Client = client,
                Writer = writer,
            };
            rec.State["session"] = sid;
            rec.State["char"] = hello["char"]?.DeepClone();
            rec.State["job"] = hello["job"]?.DeepClone();
            rec.State["engine"] = hello["engine"]?.DeepClone();
            _sessions[sid] = rec;
        }

        return sid;
    }

    private void UpdateSessionState(string sid, JsonObject incoming)
    {
        lock (_sessionsGate)
        {
            if (!_sessions.TryGetValue(sid, out var rec))
            {
                return;
            }

            foreach (var kv in incoming)
            {
                rec.State[kv.Key] = kv.Value?.DeepClone();
            }
            rec.State["session"] = sid;
        }
    }

    private void RemoveSession(string sid)
    {
        lock (_sessionsGate)
        {
            _sessions.Remove(sid);
        }
    }

    private void CompleteProfileV2Reload(string sid, JsonObject incoming)
    {
        var requestId = incoming["request_id"]?.GetValue<string>() ?? "";
        if (requestId.Length == 0 || !_pendingProfileReloads.TryGetValue(requestId, out var pending))
        {
            return;
        }
        if (!string.Equals(pending.Sid, sid, StringComparison.Ordinal))
        {
            pending.Completion.TrySetException(
                new InvalidOperationException("Profile-v2 reload result came from the wrong session.")
            );
            return;
        }

        try
        {
            var result = new ProfileV2ReloadResult(
                sid,
                requestId,
                incoming["ok"]?.GetValue<bool>() == true,
                incoming["character"]?.GetValue<string>() ?? "",
                incoming["main_job"]?.GetValue<string>() ?? "",
                incoming["sub_job"]?.GetValue<string>() ?? "",
                incoming["diff_count"]?.GetValue<int>() ?? -1,
                incoming["error"]?.GetValue<string>() ?? ""
            );
            pending.Completion.TrySetResult(result);
        }
        catch (Exception ex)
        {
            pending.Completion.TrySetException(
                new InvalidOperationException("Profile-v2 reload result is malformed.", ex)
            );
        }
    }

    private async Task SendRequestStateAsync(StreamWriter writer, CancellationToken ct)
    {
        try
        {
            await writer.WriteLineAsync("""{"op":"request_state"}""").ConfigureAwait(false);
            await writer.FlushAsync().ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // ignore
        }
        catch
        {
            // ignore
        }
    }

    private async Task WritePumpAsync()
    {
        var ct = _linkedCts.Token;
        await foreach (var (sid, line) in _outbound.Reader.ReadAllAsync(ct).ConfigureAwait(false))
        {
            StreamWriter? writer = null;
            lock (_sessionsGate)
            {
                if (_sessions.TryGetValue(sid, out var rec))
                {
                    writer = rec.Writer;
                }
            }

            if (writer is null)
            {
                EmitMirrorError("unknown_sid:" + sid);
                continue;
            }

            try
            {
                await writer.WriteAsync(line.AsMemory(), ct).ConfigureAwait(false);
                await writer.FlushAsync().ConfigureAwait(false);
                try
                {
                    if (line.Contains("\"op\":\"set\"", StringComparison.Ordinal)
                        && (line.Contains("\"path\":\"def_remove_enemy_buffs\"", StringComparison.Ordinal)
                            || line.Contains("\"path\":\"def_heal_min_missing_hp\"", StringComparison.Ordinal)))
                    {
                        var root = AppContext.BaseDirectory;
                        var logDir = Path.Combine(root, "data", "ui_profiles");
                        Directory.CreateDirectory(logDir);
                        var logPath = Path.Combine(logDir, "ui_def_sync.log");
                        File.AppendAllText(
                            logPath,
                            $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}\tMIRROR_WRITE_OK sid={sid} line={line.Trim()}{Environment.NewLine}"
                        );
                    }
                }
                catch
                {
                    // never fail flow for logging
                }
            }
            catch
            {
                EmitMirrorError("send_failed:" + sid);
            }
        }
    }

    private void EmitSnapshot()
    {
        var sessions = new JsonObject();
        lock (_sessionsGate)
        {
            foreach (var kv in _sessions)
            {
                sessions[kv.Key] = kv.Value.State.DeepClone();
            }
        }

        var payload = new JsonObject
        {
            ["op"] = "mirror_snapshot",
            ["sessions"] = sessions,
        };
        SnapshotOrErrorLineReceived?.Invoke(payload.ToJsonString());
    }

    private void EmitMirrorError(string reason)
    {
        var payload = new JsonObject
        {
            ["op"] = "mirror_error",
            ["reason"] = reason,
        };
        SnapshotOrErrorLineReceived?.Invoke(payload.ToJsonString());
    }

    private void CloseAllSessions()
    {
        List<SessionConn> toClose;
        lock (_sessionsGate)
        {
            toClose = _sessions.Values.ToList();
            _sessions.Clear();
        }

        foreach (var s in toClose)
        {
            try
            {
                s.Client.Close();
            }
            catch
            {
                // ignore
            }
        }
    }

    public void Dispose()
    {
        _outbound.Writer.TryComplete();
        _linkedCts.Cancel();
        try
        {
            _listener?.Stop();
        }
        catch
        {
            // ignore
        }
        CloseAllSessions();

        foreach (var pending in _pendingProfileReloads.Values)
        {
            pending.Completion.TrySetCanceled(_linkedCts.Token);
        }
        _pendingProfileReloads.Clear();

        _linkedCts.Dispose();
    }
}
