using System.Buffers.Binary;
using System.Text.Json;

namespace SofaTap.Desktop;

internal sealed record PairingImage(string Host, byte[] Png);
internal sealed record ReceiverState(string Name, string Platform, string InputStatus, bool DryRun, bool Connected, PairingImage[] Pairings);

internal static class NativeProtocol
{
    internal const int MaximumLineLength = 4 * 1024 * 1024;

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
            // The URI is deliberately not retained or copied to a clipboard/file.
            pairings.Add(new PairingImage(host, png));
        }
        return new ReceiverState(Text(root, "name", 255), Text(root, "platform", 24), Text(root, "inputStatus", 64),
            root.GetProperty("dryRun").GetBoolean(), root.GetProperty("connected").GetBoolean(), pairings.ToArray());
    }

    private static string Text(JsonElement element, string name, int maximum)
    {
        var value = element.GetProperty(name).GetString();
        if (value is null || value.Length == 0 || value.Length > maximum)
            throw new InvalidDataException("Invalid receiver field.");
        return value;
    }
}
