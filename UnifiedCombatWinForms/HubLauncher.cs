using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace UnifiedCombatWinForms;

/// <summary>
/// Ensures the headless Python hub is listening before the UI connects (game TCP 27182 + UI channel 27183).
/// </summary>
internal static class HubLauncher
{
    public const int HubGamePort = 27182;
    public const int HubUiPort = 27183;

    private static readonly TimeSpan ProbeTimeout = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan HubReadyDeadline = TimeSpan.FromSeconds(25);
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(400);

    private static Process? _hubProcess;

    /// <summary>True if this process started the hub and should stop it on exit.</summary>
    public static bool WeStartedHub { get; private set; }

    /// <summary>
    /// If UI port is already accepting connections, returns success immediately.
    /// Otherwise locates <c>unified_combat_ui.py</c>, starts Python, and waits until the port is up or the deadline passes.
    /// </summary>
    public static async Task<(bool ok, string? error)> EnsureHubAsync(CancellationToken ct)
    {
        if (await IsUiPortOpenAsync(ct).ConfigureAwait(false))
        {
            return (true, null);
        }

        var script = FindHubScriptPath();
        if (string.IsNullOrEmpty(script))
        {
            return (
                false,
                "Could not find unified_combat_ui.py. Set environment variable UNIFIEDCOMBAT_HUB_SCRIPT to its full path, "
                    + "or place the script next to this executable / in the UnifiedCombat addon folder."
            );
        }

        var workDir = Path.GetDirectoryName(script);
        if (string.IsNullOrEmpty(workDir))
        {
            return (false, "Could not resolve a working directory for unified_combat_ui.py.");
        }

        Exception? lastEx = null;
        foreach (var psi in EnumeratePythonStartInfos(script, workDir))
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                _hubProcess = Process.Start(psi);
                if (_hubProcess is null)
                {
                    continue;
                }

                WeStartedHub = true;
                await Task.Delay(350, ct).ConfigureAwait(false);
                if (_hubProcess.HasExited)
                {
                    lastEx = new InvalidOperationException(
                        "Process exited immediately (code " + _hubProcess.ExitCode + ") for: " + psi.FileName
                    );
                    TryDisposeHubProcess();
                    WeStartedHub = false;
                    continue;
                }

                break;
            }
            catch (Exception ex)
            {
                lastEx = ex;
                TryDisposeHubProcess();
                WeStartedHub = false;
            }
        }

        if (_hubProcess is null || _hubProcess.HasExited)
        {
            return (
                false,
                "Could not start the hub with a Python interpreter. Install Python 3 and ensure `py -3` or `python` is on PATH, "
                    + "or set UNIFIEDCOMBAT_PYTHON to the full path of python.exe. "
                    + (lastEx is not null ? "Last error: " + lastEx.Message : "")
            );
        }

        var deadline = DateTime.UtcNow + HubReadyDeadline;
        while (DateTime.UtcNow < deadline)
        {
            ct.ThrowIfCancellationRequested();
            if (await IsUiPortOpenAsync(ct).ConfigureAwait(false))
            {
                return (true, null);
            }

            if (_hubProcess.HasExited)
            {
                var err =
                    "The hub process exited before it became ready (exit code "
                    + _hubProcess.ExitCode
                    + "). Check Python output or run unified_combat_ui.py manually in a console.";
                StopIfWeStartedIt();
                return (false, err);
            }

            await Task.Delay(PollInterval, ct).ConfigureAwait(false);
        }

        StopIfWeStartedIt();
        return (
            false,
            "Timed out waiting for the hub on 127.0.0.1:"
                + HubUiPort
                + ". Check that unified_combat_ui.py runs without errors."
        );
    }

    public static void StopIfWeStartedIt()
    {
        if (!WeStartedHub || _hubProcess is null)
        {
            return;
        }

        try
        {
            if (!_hubProcess.HasExited)
            {
                _hubProcess.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // ignore
        }
        finally
        {
            TryDisposeHubProcess();
            WeStartedHub = false;
        }
    }

    private static void TryDisposeHubProcess()
    {
        if (_hubProcess is null)
        {
            return;
        }

        try
        {
            _hubProcess.Dispose();
        }
        catch
        {
            // ignore
        }

        _hubProcess = null;
    }

    private static async Task<bool> IsUiPortOpenAsync(CancellationToken ct)
    {
        try
        {
            using var client = new TcpClient();
            using var probe = CancellationTokenSource.CreateLinkedTokenSource(ct);
            probe.CancelAfter(ProbeTimeout);
            await client.ConnectAsync(IPAddress.Loopback, HubUiPort, probe.Token).ConfigureAwait(false);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string? FindHubScriptPath()
    {
        var env = Environment.GetEnvironmentVariable("UNIFIEDCOMBAT_HUB_SCRIPT");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env))
        {
            return Path.GetFullPath(env);
        }

        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "unified_combat_ui.py"),
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "unified_combat_ui.py")),
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "unified_combat_ui.py")),
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "..", "unified_combat_ui.py")),
        };

        foreach (var c in candidates)
        {
            if (File.Exists(c))
            {
                return c;
            }
        }

        return null;
    }

    private static IEnumerable<ProcessStartInfo> EnumeratePythonStartInfos(string scriptPath, string workDir)
    {
        var quotedScript = "\"" + scriptPath + "\"";

        var envPy = Environment.GetEnvironmentVariable("UNIFIEDCOMBAT_PYTHON");
        if (!string.IsNullOrWhiteSpace(envPy) && File.Exists(envPy))
        {
            yield return new ProcessStartInfo
            {
                FileName = envPy,
                Arguments = quotedScript,
                WorkingDirectory = workDir,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
        }

        yield return new ProcessStartInfo
        {
            FileName = "py",
            Arguments = "-3 " + quotedScript,
            WorkingDirectory = workDir,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        yield return new ProcessStartInfo
        {
            FileName = "python",
            Arguments = quotedScript,
            WorkingDirectory = workDir,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
    }
}
