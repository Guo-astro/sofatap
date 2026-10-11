using System.Buffers.Binary;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SofaTap.Desktop;

internal sealed record PairingImage(string Host, byte[] Png, [property: JsonIgnore] string? Uri = null)
{
    public override string ToString() => $"PairingImage {{ Host = {Host}, HasUri = {Uri is not null} }}";
}
internal sealed record ReceiverState(string Name, string Platform, string InputStatus, bool DryRun, bool Connected, PairingImage[] Pairings);

internal static class NativeProtocol
{
    internal const int MaximumLineLength = 4 * 1024 * 1024;
    internal const int MaximumPairingUriLength = 2048;

    internal static ReceiverState Parse(string line)
    {
        if (line.Length > MaximumLineLength) throw new InvalidDataException("Receiver state is too large.");
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || Text(root, "type", 16) != "state")
            throw new InvalidDataException("Unexpected receiver message.");
        var items = root.GetProperty("pairings");
        if (items.ValueKind != JsonValueKind.Array || items.GetArrayLength() > 32)
            throw new InvalidDataException("Invalid pairing list.");
        var pairings = new List<PairingImage>();
        foreach (var item in items.EnumerateArray())
        {
            var host = Text(item, "host", 255);
            var encoded = Text(item, "qrPng", 1024 * 1024);
            var png = Convert.FromBase64String(encoded);
            // Bound image dimensions before a native image decoder allocates pixels.
            if (png.Length < 24 || !png.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })
                || !png.AsSpan(12, 4).SequenceEqual("IHDR"u8))
                throw new InvalidDataException("Invalid QR image.");
            var width = BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(16, 4));
            var height = BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(20, 4));
            if (width is < 1 or > 2048 || height is < 1 or > 2048)
                throw new InvalidDataException("Invalid QR dimensions.");
            // Older QR-only snapshots remain usable. An invalid optional link disables Copy,
            // rather than turning a valid QR snapshot into a backend failure.
            var uri = item.TryGetProperty("uri", out var link) && link.ValueKind == JsonValueKind.String
                ? ValidPairingUri(link.GetString(), host) : null;
            pairings.Add(new PairingImage(host, png, uri));
        }
        return new ReceiverState(Text(root, "name", 255), Text(root, "platform", 24), Text(root, "inputStatus", 64),
            root.GetProperty("dryRun").GetBoolean(), root.GetProperty("connected").GetBoolean(), pairings.ToArray());
    }

    internal static string? ValidPairingUri(string? value, string expectedHost)
    {
        const string prefix = "sofatap://pair?";
        if (value is null || value.Length > MaximumPairingUriLength
            || !value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            || value.Any(character => character <= ' ' || character >= 127 || character == '#')) return null;
        var query = value[prefix.Length..].Split('&');
        if (query.Length != 4) return null;
        var fields = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in query)
        {
            var separator = item.IndexOf('=');
            if (separator <= 0) return null;
            var name = item[..separator];
            if (name is not ("host" or "port" or "token" or "fingerprint") || fields.ContainsKey(name)) return null;
            var encoded = item[(separator + 1)..];
            for (var index = 0; index < encoded.Length; index++)
            {
                if (encoded[index] != '%') continue;
                if (index + 2 >= encoded.Length || !IsHex(encoded[index + 1]) || !IsHex(encoded[index + 2])) return null;
                index += 2;
            }
            fields[name] = System.Uri.UnescapeDataString(encoded);
        }
        if (!fields.TryGetValue("host", out var host) || !ValidHost(host)
            || !host.Equals(expectedHost, StringComparison.OrdinalIgnoreCase)
            || !fields.TryGetValue("port", out var portText) || portText.Length == 0
            || !portText.All(character => character is >= '0' and <= '9')
            || !int.TryParse(portText, NumberStyles.None, CultureInfo.InvariantCulture, out var port) || port is < 1 or > 65535
            || !fields.TryGetValue("token", out var token) || token.Length is < 32 or > 256
            || !token.All(character => IsAsciiLetterOrDigit(character) || character is '-' or '_')
            || !fields.TryGetValue("fingerprint", out var fingerprint) || fingerprint.Length != 64 || !fingerprint.All(IsHex)) return null;
        return value;
    }

    private static bool ValidHost(string host)
    {
        if (host.Length is < 1 or > 253 || host.Any(character => character >= 128)) return false;
        if (!host.Contains('%') && IPAddress.TryParse(host, out var address) && address.AddressFamily == AddressFamily.InterNetworkV6) return true;
        return host.Split('.').All(label => label.Length is > 0 and <= 63 && label[0] != '-' && label[^1] != '-'
            && label.All(character => IsAsciiLetterOrDigit(character) || character == '-'));
    }

    private static bool IsAsciiLetterOrDigit(char character) => character is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9';
    private static bool IsHex(char character) => character is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F';

    private static string Text(JsonElement element, string name, int maximum)
    {
        var value = element.GetProperty(name).GetString();
        if (value is null || value.Length == 0 || value.Length > maximum)
            throw new InvalidDataException("Invalid receiver field.");
        return value;
    }
}
