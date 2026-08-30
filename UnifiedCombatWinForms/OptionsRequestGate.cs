namespace UnifiedCombatWinForms;

internal static class OptionsRequestGate
{
    private static readonly TimeSpan InFlightWindow = TimeSpan.FromSeconds(2);

    internal static bool TryBegin(
        Dictionary<string, string> hydratedJobBySid,
        Dictionary<string, DateTime> requestInFlightBySid,
        string sid,
        string? currentJobIdentity,
        bool force,
        DateTime nowUtc
    )
    {
        if (requestInFlightBySid.TryGetValue(sid, out var lastRequest)
            && nowUtc - lastRequest < InFlightWindow)
        {
            return false;
        }

        if (!force
            && currentJobIdentity is not null
            && hydratedJobBySid.TryGetValue(sid, out var hydratedJob)
            && string.Equals(hydratedJob, currentJobIdentity, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        requestInFlightBySid[sid] = nowUtc;
        return true;
    }

    internal static void Invalidate(
        Dictionary<string, string> hydratedJobBySid,
        Dictionary<string, DateTime> requestInFlightBySid,
        string sid
    )
    {
        hydratedJobBySid.Remove(sid);
        requestInFlightBySid.Remove(sid);
    }

    internal static void Complete(
        Dictionary<string, string> hydratedJobBySid,
        Dictionary<string, DateTime> requestInFlightBySid,
        string sid,
        string currentJobIdentity
    )
    {
        hydratedJobBySid[sid] = currentJobIdentity;
        requestInFlightBySid.Remove(sid);
    }
}
