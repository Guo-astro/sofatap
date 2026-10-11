using System.Net;
using System.Net.NetworkInformation;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text.Json;
using Microsoft.Win32;

namespace Sofatap.Login;

internal sealed record Capability(int Version, int Port, string Fingerprint, string Token, string DeviceId, string AccountName, string AccountSid, string Provider, string ReceiverFingerprint);
internal sealed record LoginConfig(Capability Capability, string MachineName, string Pfx, string InternetPrincipal)
{
    internal const string ServiceName = "SofatapLogin";
    internal const string ProviderClsid = "{F8F3819A-9AB1-4C6F-86D5-90B57D9A42C7}";
    internal static readonly string DirectoryPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Sofatap", "Login");
    internal static readonly string ConfigPath = Path.Combine(DirectoryPath, "service.dat");
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal bool IdentityCurrent()
    {
        var identity = NativeWindows.ReadAccountIdentity(Capability.AccountName, Capability.AccountSid);
        return identity?.Provider == Capability.Provider && string.Equals(identity.Principal, InternetPrincipal, StringComparison.OrdinalIgnoreCase);
    }

    internal static LoginConfig Load()
    {
        CheckAcl(Path.GetDirectoryName(DirectoryPath)!, true); CheckAcl(DirectoryPath, true); CheckAcl(ConfigPath, false);
        var clear = ProtectedData.Unprotect(File.ReadAllBytes(ConfigPath), null, DataProtectionScope.LocalMachine);
        try { return JsonSerializer.Deserialize<LoginConfig>(clear, Json) ?? throw new InvalidDataException(); }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }
    internal static void CheckAcl(string path, bool directory)
    {
        FileSystemSecurity acl = directory ? new DirectoryInfo(path).GetAccessControl() : new FileInfo(path).GetAccessControl();
        var trusted = new[] { "S-1-5-18", "S-1-5-32-544" };
        if (!trusted.Contains(acl.GetOwner(typeof(SecurityIdentifier))?.Value)) throw new UnauthorizedAccessException();
        foreach (FileSystemAccessRule rule in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            if (rule.AccessControlType == AccessControlType.Allow && !trusted.Contains(rule.IdentityReference.Value)) throw new UnauthorizedAccessException();
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new UnauthorizedAccessException();
    }
    internal static void Provision(string receiverFingerprint, string receiverProfile)
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        if (!principal.IsInRole(WindowsBuiltInRole.Administrator) || identity.User is null) throw new UnauthorizedAccessException();
        // Reject alternate-account elevation and unknown/nonlocal profile identity providers.
        var local = new NTAccount(Environment.MachineName, Environment.UserName);
        var accountIdentity = NativeWindows.ReadAccountIdentity(Environment.UserName, identity.User.Value);
        if (!NativeWindows.ConsoleIsTarget(identity.User.Value) || !identity.User.Equals(local.Translate(typeof(SecurityIdentifier))) || accountIdentity is null) throw new InvalidOperationException("same_supported_console_account_required");
        var provider = accountIdentity.Provider;
        if (receiverFingerprint.Length != 64 || !receiverFingerprint.All(Uri.IsHexDigit)) throw new ArgumentException("receiver_fingerprint_required");
        var expected = Path.GetFullPath(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SofaTap"));
        if (!string.Equals(Path.GetFullPath(receiverProfile), expected, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("current_user_profile_required");
        // Bind enrollment to the actual ordinary receiver identity, never an arbitrary supplied fingerprint.
        var receiverClear = ProtectedData.Unprotect(File.ReadAllBytes(Path.Combine(receiverProfile, "pairing.dat")), null, DataProtectionScope.CurrentUser);
        try
        {
            using var receiver = JsonDocument.Parse(receiverClear);
            using var receiverCertificate = X509CertificateLoader.LoadPkcs12(Convert.FromBase64String(receiver.RootElement.GetProperty("Pfx").GetString()!), "", X509KeyStorageFlags.EphemeralKeySet);
            if (!string.Equals(Convert.ToHexStringLower(SHA256.HashData(receiverCertificate.RawData)), receiverFingerprint, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("receiver_identity_mismatch");
        }
        finally { CryptographicOperations.ZeroMemory(receiverClear); }
        if (File.Exists(ConfigPath) || File.Exists(Path.Combine(receiverProfile, "unlock-capability.dat"))) throw new InvalidOperationException("existing_enrollment_requires_explicit_uninstall");
        CheckAcl(Path.GetDirectoryName(DirectoryPath)!, true); CheckAcl(DirectoryPath, true);
        using var rsa = RSA.Create(3072);
        var request = new CertificateRequest("CN=Sofatap Optional Windows Login", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.1") }, true));
        var sans = new SubjectAlternativeNameBuilder(); sans.AddDnsName(Environment.MachineName); sans.AddDnsName("localhost"); sans.AddIpAddress(IPAddress.Loopback);
        foreach (var ip in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up).SelectMany(n => n.GetIPProperties().UnicastAddresses).Select(a => a.Address).Distinct()) sans.AddIpAddress(ip);
        request.CertificateExtensions.Add(sans.Build());
        using var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddYears(1));
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var capability = new Capability(1, 53320, Convert.ToHexStringLower(SHA256.HashData(cert.RawData)), token, Guid.NewGuid().ToString("D"), Environment.UserName, identity.User.Value, provider, receiverFingerprint.ToLowerInvariant());
        var config = new LoginConfig(capability, Environment.MachineName, Convert.ToBase64String(cert.Export(X509ContentType.Pfx)), accountIdentity.Principal);
        var clear = JsonSerializer.SerializeToUtf8Bytes(config, Json);
        try { using var file = new FileStream(ConfigPath, FileMode.CreateNew, FileAccess.Write, FileShare.None); file.Write(ProtectedData.Protect(clear, null, DataProtectionScope.LocalMachine)); file.Flush(true); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        Directory.CreateDirectory(receiverProfile);
        clear = JsonSerializer.SerializeToUtf8Bytes(capability, Json);
        try { NativeWindows.WriteEnrollmentNew(Path.Combine(receiverProfile, "unlock-capability.dat"), ProtectedData.Protect(clear, null, DataProtectionScope.CurrentUser)); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        using var key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Chekusu\SofatapLogin");
        key.SetValue("AccountName", capability.AccountName); key.SetValue("AccountSid", capability.AccountSid); key.SetValue("MachineName", config.MachineName); key.SetValue("Provider", provider);
        key.SetValue("QualifiedUserName", provider == "windows-microsoft-password" ? "MicrosoftAccount\\" + accountIdentity.Principal : config.MachineName + "\\" + capability.AccountName);
    }
}
