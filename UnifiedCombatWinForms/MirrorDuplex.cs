using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;

namespace UnifiedCombatWinForms;

/// <summary>
/// Localhost duplex line protocol: reads NDJSON from hub (mirror_snapshot, mirror_error);
/// writes mirror_forward lines built by the UI.
/// </summary>
internal sealed class MirrorDuplex : IDisposable
{
    private const string DefaultHost = "127.0.0.1";
    public static int MirrorPort => HubLauncher.HubUiPort;

    private readonly CancellationTokenSource _linkedCts;
    private readonly Channel<string> _outbound = Channel.CreateUnbounded<string>(
        new UnboundedChannelOptions { SingleReader = true, SingleWriter = false }
    );
    private Task? _ioTask;
    private TcpClient? _client;

    public event Action<string>? SnapshotOrErrorLineReceived;

    public MirrorDuplex(CancellationToken appCt)
    {
        _linkedCts = CancellationTokenSource.CreateLinkedTokenSource(appCt);
    }

    public void Start() => _ioTask = Task.Run(IoLoopAsync);

    public void EnqueueForward(string sid, IReadOnlyDictionary<string, object?> msg)
    {
        var env = new Dictionary<string, object?> { ["op"] = "mirror_forward", ["sid"] = sid, ["msg"] = msg };
        var line = JsonSerializer.Serialize(env) + "\n";
        _outbound.Writer.TryWrite(line);
    }

    private async Task IoLoopAsync()
    {
        var ct = _linkedCts.Token;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                _client?.Close();
                _client = new TcpClient();
                await _client.ConnectAsync(DefaultHost, MirrorPort, ct).ConfigureAwait(false);
                await using var stream = _client.GetStream();
                using var reader = new StreamReader(
                    stream,
                    Encoding.UTF8,
                    detectEncodingFromByteOrderMarks: false,
                    bufferSize: 65536,
                    leaveOpen: true
                );
                using var connCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                var writerTask = WritePumpAsync(stream, connCts.Token);
                try
                {
                    await ReadPumpAsync(reader, connCts.Token).ConfigureAwait(false);
                }
                finally
                {
                    connCts.Cancel();
                    try
                    {
                        await writerTask.ConfigureAwait(false);
                    }
                    catch
                    {
                        // ignore cancel / disconnect
                    }
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                SnapshotOrErrorLineReceived?.Invoke(
                    """{"op":"mirror_error","reason":"disconnected_or_unreachable"}"""
                );
            }

            if (ct.IsCancellationRequested)
            {
                break;
            }

            try
            {
                await Task.Delay(2000, ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task ReadPumpAsync(StreamReader reader, CancellationToken ct)
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

            SnapshotOrErrorLineReceived?.Invoke(line);
        }
    }

    private async Task WritePumpAsync(NetworkStream stream, CancellationToken ct)
    {
        var enc = Encoding.UTF8;
        await foreach (var line in _outbound.Reader.ReadAllAsync(ct).ConfigureAwait(false))
        {
            var bytes = enc.GetBytes(line);
            await stream.WriteAsync(bytes, ct).ConfigureAwait(false);
            await stream.FlushAsync(ct).ConfigureAwait(false);
        }
    }

    public void Dispose()
    {
        _outbound.Writer.TryComplete();
        _linkedCts.Cancel();
        try
        {
            _client?.Close();
        }
        catch
        {
            // ignore
        }

        _linkedCts.Dispose();
    }
}
