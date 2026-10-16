namespace SofaTap;

/// <summary>Build-time capabilities, never negotiated by a remote controller.</summary>
internal static class ReceiverDistribution
{
    internal static bool IsMacAppStore
    {
        get
        {
#if SOFATAP_MAC_APP_STORE
            return true;
#else
            return false;
#endif
        }
    }

    internal static bool SupportsTextInspection => !IsMacAppStore;

    internal static string DataDirectory(string? requested)
    {
#if SOFATAP_MAC_APP_STORE
        // The native parent resolves Application Support in its own sandbox and
        // passes it explicitly. Never fall back to the direct-download profile.
        // The OS sandbox is the authority for actual filesystem access.
        if (string.IsNullOrWhiteSpace(requested) || !Path.IsPathFullyQualified(requested))
            throw new ArgumentException("The Mac App Store receiver requires an absolute container data directory from its native app.");
        return Path.GetFullPath(requested);
#else
        return requested ?? Credentials.DefaultDirectory;
#endif
    }

    internal static ITextFocusProbe? CreateTextFocus(bool dryRun)
    {
#if SOFATAP_MAC_APP_STORE
        return null;
#else
        return dryRun ? null : TextFocusProbe.Create();
#endif
    }

    internal static Func<ILiveTextEditor>? CreateTextEditorFactory(bool dryRun)
    {
#if SOFATAP_MAC_APP_STORE
        return null;
#else
        return !dryRun && OperatingSystem.IsWindows()
            ? () => OperatingSystem.IsWindows() ? new WindowsTextEditor() : throw new PlatformNotSupportedException()
            : !dryRun && OperatingSystem.IsMacOS() ? () => new MacTextEditor() : null;
#endif
    }
}
