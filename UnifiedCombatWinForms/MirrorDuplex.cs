using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;

namespace UnifiedCombatWinForms;

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
        _outbound.Writer.TryWrite((sid, line));
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

        _linkedCts.Dispose();
    }
}
