using System.Globalization;
using System.Text;

namespace SofaTap;

internal static class PairingUri
{
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    internal static string DeviceName(string? value, string platform)
    {
        var fallback = platform switch { "windows" => "Sofatap Windows", "macos" => "Sofatap Mac", "linux" => "Sofatap Linux", _ => "Sofatap" };
        if (value is null || value.EnumerateRunes().Any(rune => Rune.GetUnicodeCategory(rune) is UnicodeCategory.Control or UnicodeCategory.Format)) return fallback;
        var trimmed = value.Trim();
        try
        {
            return trimmed.Length > 0 && trimmed.EnumerateRunes().Count() <= 80 && StrictUtf8.GetByteCount(trimmed) <= 256 ? trimmed : fallback;
        }
        catch (EncoderFallbackException) { return fallback; }
    }

    internal static string Create(string host, int port, string token, string fingerprint, string platform, string? name)
    {
        if (platform is not ("windows" or "macos" or "linux")) throw new ArgumentException("Unsupported receiver platform.", nameof(platform));
        return $"sofatap://pair?host={Uri.EscapeDataString(host)}&port={port.ToString(CultureInfo.InvariantCulture)}&token={token}&fingerprint={fingerprint}&platform={platform}&name={Uri.EscapeDataString(DeviceName(name, platform))}";
    }
}
