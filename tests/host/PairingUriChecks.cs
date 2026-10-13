using SofaTap;

static class PairingUriChecks
{
    public static void Run(Action<bool, string> check)
    {
        const string name = "客厅 + TV 🛋️";
        foreach (var platform in new[] { "windows", "macos", "linux" })
        {
            var link = PairingUri.Create("192.0.2.1", 53319, new string('D', 43), new string('a', 64), platform, "\u00a0 " + name + "\u3000");
            check(link.Contains("&platform=" + platform + "&name=" + Uri.EscapeDataString(name)), "QR carries normalized platform/name " + platform);
            check(!link.Contains(' ') && !link.Contains('+'), "QR display metadata is percent encoded " + platform);
        }
        check(PairingUri.DeviceName(new string('a', 80), "macos") == new string('a', 80), "80 scalar name boundary accepted");
        check(PairingUri.DeviceName(string.Concat(Enumerable.Repeat("😀", 64)), "macos") == string.Concat(Enumerable.Repeat("😀", 64)), "256 UTF-8 bytes and supplementary scalars accepted");
        check(PairingUri.DeviceName(new string('客', 80), "linux") == new string('客', 80), "80 CJK scalar values accepted");
        foreach (var invalid in new string?[] { null, "", " \u00a0", new string('a', 81), string.Concat(Enumerable.Repeat("😀", 65)),
            string.Concat(Enumerable.Repeat("e\u0301", 41)), "TV\n", "\tTV", "TV\u0000", "TV\u0085", "TV\u200b", "TV\u202e", "bad\ud800" })
            check(PairingUri.DeviceName(invalid, "windows") == "Sofatap Windows", "invalid OS device names get safe fallback");
    }
}
