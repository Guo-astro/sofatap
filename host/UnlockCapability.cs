using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SofaTap;

/// Explicitly installed login capability. This is never a password, never part
/// of the QR code, and only travels over the authenticated paired connection.
public sealed record UnlockCapability(int Version, int Port, string Fingerprint, string Token,
    string DeviceId, string AccountName, string AccountSid, string Provider)
{
    public override string ToString() => "Sofatap optional Windows login capability (redacted)";
}

public static partial class UnlockCapabilityStore
{
    public const string FileName = "unlock-capability.dat";
    private const int MaximumBytes = 8192;

    public static UnlockCapability? Read(string directory, string receiverFingerprint,
        bool isWindows, bool dryRun, string inputStatus)
    {
        // Enrollment requires an available local Windows desktop. The phone
        // retains its separately enrolled service capability for later logon.
        if (!isWindows || !OperatingSystem.IsWindows() || dryRun || inputStatus != "ready") return null;
        byte[]? clear = null;
        try
        {
            var path = Path.Combine(directory, FileName);
            var info = new FileInfo(path);
            if (!info.Exists || info.Length is < 1 or > MaximumBytes ||
                (info.Attributes & FileAttributes.ReparsePoint) != 0) return null;
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is < 1 or > MaximumBytes) return null;
            var stored = new byte[(int)file.Length];
            file.ReadExactly(stored);
            clear = Credentials.Dpapi.Unprotect(stored);
            return Parse(clear, receiverFingerprint);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            CryptographicException or InvalidOperationException or JsonException or ArgumentException)
        {
            // A damaged, absent or wrong-user enrollment is unsupported. Never
            // log secret-bearing payloads or native exception messages.
            return null;
        }
        finally { if (clear is not null) CryptographicOperations.ZeroMemory(clear); }
    }

    public static UnlockCapability? Parse(ReadOnlyMemory<byte> data, string receiverFingerprint)
    {
        if (data.Length is < 1 or > MaximumBytes || !Fingerprint().IsMatch(receiverFingerprint)) return null;
        try
        {
            using var document = JsonDocument.Parse(data, new JsonDocumentOptions { MaxDepth = 3 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var expected = new HashSet<string>(["receiverFingerprint", "version", "port", "fingerprint",
                "token", "deviceId", "accountName", "accountSid", "provider"], StringComparer.Ordinal);
            foreach (var property in root.EnumerateObject()) if (!expected.Remove(property.Name)) return null;
            if (expected.Count != 0) return null;
            string? Text(string name) => root.GetProperty(name).ValueKind == JsonValueKind.String
                ? root.GetProperty(name).GetString() : null;
            if (Text("receiverFingerprint") != receiverFingerprint ||
                !root.GetProperty("version").TryGetInt32(out var version) || version != 1 ||
                !root.GetProperty("port").TryGetInt32(out var port) || port != 53320) return null;
            var pin = Text("fingerprint"); var token = Text("token");
            var device = Text("deviceId"); var account = Text("accountName"); var sid = Text("accountSid");
            var provider = Text("provider");
            if (pin is null || !Fingerprint().IsMatch(pin) || token is null || !Token().IsMatch(token) ||
                device is null || !Guid.TryParseExact(device, "D", out var id) || id == Guid.Empty ||
                account is null || account.Length is < 1 or > 104 ||
                account != account.Trim() || account.Any(char.IsControl) || account.IndexOfAny(['\\', '/', '@']) >= 0 ||
                sid is null || !LocalSid().IsMatch(sid) ||
                sid.Split('-').Skip(4).Any(part => !uint.TryParse(part, out _)) ||
                provider is not ("windows-local-password" or "windows-microsoft-password")) return null;
            var decoded = Convert.FromBase64String(token.Replace('-', '+').Replace('_', '/') + "=");
            var canonical = Convert.ToBase64String(decoded).TrimEnd('=').Replace('+', '-').Replace('/', '_');
            if (decoded.Length != 32 || canonical != token) return null;
            return new(version, port, pin, token, id.ToString("D"), account, sid, provider);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or FormatException)
        { return null; }
    }

    [GeneratedRegex("\\A[0-9a-f]{64}\\z", RegexOptions.CultureInvariant)]
    private static partial Regex Fingerprint();
    [GeneratedRegex("\\A[A-Za-z0-9_-]{43}\\z", RegexOptions.CultureInvariant)]
    private static partial Regex Token();
    [GeneratedRegex("\\AS-1-5-21-[0-9]{1,10}-[0-9]{1,10}-[0-9]{1,10}-[0-9]{1,10}\\z", RegexOptions.CultureInvariant)]
    private static partial Regex LocalSid();
}
