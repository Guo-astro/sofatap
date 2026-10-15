using SofaTap;

internal static class CredentialPersistenceChecks
{
    internal static void Run(Action<bool, string> check)
    {
        // Synthetic documentation addresses keep this regression independent of
        // the runner's NICs and never start a listener or send desktop input.
        const string homeAddress = "192.0.2.10";
        const string virtualAddress = "198.51.100.20";
        const string replacementHomeAddress = "203.0.113.30";
        var directory = Path.Combine(Path.GetTempPath(), "sofatap-credentials-" + Guid.NewGuid().ToString("N"));
        try
        {
            string token; string fingerprint;
            using (var credentials = Credentials.LoadOrCreate(directory, [homeAddress]))
            {
                token = credentials.Token; fingerprint = credentials.Fingerprint;
                check(credentials.CertificateIPv4.Contains(homeAddress), "initial pairing certificate covers home address");
            }
            var persisted = File.ReadAllBytes(Path.Combine(directory, "pairing.dat"));
            using (var credentials = Credentials.LoadOrCreate(directory, [virtualAddress, homeAddress]))
            {
                check(credentials.Token == token && credentials.Fingerprint == fingerprint,
                    "new virtual adapter preserves saved pairing on the existing home network");
                check(!credentials.CertificateIPv4.Contains(virtualAddress),
                    "retained certificate does not claim an uncertified adapter address");
            }
            check(File.ReadAllBytes(Path.Combine(directory, "pairing.dat")).AsSpan().SequenceEqual(persisted),
                "unrelated adapter does not rewrite the stored pairing profile");
            using (var credentials = Credentials.LoadOrCreate(directory, []))
                check(credentials.Token == token && credentials.Fingerprint == fingerprint,
                    "offline restart preserves pairing credentials");
            using (var credentials = Credentials.LoadOrCreate(directory, [homeAddress]))
                check(credentials.Token == token && credentials.Fingerprint == fingerprint,
                    "returning to the original network keeps the pairing after an offline restart");
            using (var credentials = Credentials.LoadOrCreate(directory, [virtualAddress]))
            {
                check(credentials.Token != token && credentials.Fingerprint != fingerprint,
                    "complete address change still rotates both certificate and bearer token");
                check(credentials.CertificateIPv4.Contains(virtualAddress) && !credentials.CertificateIPv4.Contains(homeAddress),
                    "replacement certificate covers the new endpoint without retaining stale network addresses");
                token = credentials.Token; fingerprint = credentials.Fingerprint;
            }
            using (var credentials = Credentials.LoadOrCreate(directory, [virtualAddress]))
                check(credentials.Token == token && credentials.Fingerprint == fingerprint,
                    "replacement pairing persists across the following receiver restart");

            var overlappingDirectory = Path.Combine(directory, "overlapping-network");
            using (var credentials = Credentials.LoadOrCreate(overlappingDirectory, [homeAddress, virtualAddress]))
            {
                token = credentials.Token; fingerprint = credentials.Fingerprint;
            }
            using (var credentials = Credentials.LoadOrCreate(overlappingDirectory, [virtualAddress]))
                check(credentials.Token == token && credentials.Fingerprint == fingerprint,
                    "pure removal of a certified address preserves pairing");
            using (var credentials = Credentials.LoadOrCreate(overlappingDirectory, [virtualAddress, replacementHomeAddress]))
            {
                check(credentials.Token != token && credentials.Fingerprint != fingerprint,
                    "home address replacement rotates credentials despite an unchanged VPN address");
                check(credentials.CertificateIPv4.Contains(replacementHomeAddress)
                    && credentials.CertificateIPv4.Contains(virtualAddress) && !credentials.CertificateIPv4.Contains(homeAddress),
                    "replacement home address is certified while the stable VPN address remains available");
            }

            var offlineDirectory = Path.Combine(directory, "initially-offline");
            using (var credentials = Credentials.LoadOrCreate(offlineDirectory, []))
            {
                token = credentials.Token; fingerprint = credentials.Fingerprint;
            }
            using (var credentials = Credentials.LoadOrCreate(offlineDirectory, [homeAddress]))
            {
                check(credentials.Token != token && credentials.Fingerprint != fingerprint,
                    "initially offline profile renews when its first network address appears");
                check(credentials.CertificateIPv4.Contains(homeAddress),
                    "first online certificate covers the endpoint for strict TLS validation");
            }
        }
        finally { Directory.Delete(directory, true); }
    }
}
