using System.Linq;
using System.Windows.Forms;
using Microsoft.Win32;

namespace UnifiedCombatWinForms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Any(arg => string.Equals(arg, "--selftest-profile-v2", StringComparison.Ordinal)))
        {
            Environment.ExitCode = StructuredProfileV2WriterTests.Run();
            return;
        }

        if (args.Any(arg => string.Equals(arg, "--selftest-activity-profiles", StringComparison.Ordinal)))
        {
            Environment.ExitCode = ActivityProfileStoreTests.Run();
            return;
        }

        ApplicationConfiguration.Initialize();
        // Follow Windows Settings → Personalization → mode (light / dark). Requires WinForms + OS support (e.g. Windows 11).
        Application.SetColorMode(SystemColorMode.System);
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        Application.ApplicationExit += (_, _) =>
        {
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        };

        Application.Run(new MainForm());
    }

    private static void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        // Theme / accent / high-contrast toggles: re-query system color mode (WinForms may not update every surface live).
        if (e.Category != UserPreferenceCategory.General && e.Category != UserPreferenceCategory.Color)
        {
            return;
        }

        try
        {
            Application.SetColorMode(SystemColorMode.System);
        }
        catch
        {
            return;
        }

        foreach (Form f in Application.OpenForms.Cast<Form>().ToArray())
        {
            if (f.IsDisposed || !f.IsHandleCreated)
            {
                continue;
            }

            try
            {
                f.BeginInvoke(
                    () =>
                    {
                        if (f.IsDisposed)
                        {
                            return;
                        }

                        f.Invalidate(true);
                        f.PerformLayout();
                    }
                );
            }
            catch (InvalidOperationException)
            {
                // Handle teardown during shutdown.
            }
        }
    }
}
