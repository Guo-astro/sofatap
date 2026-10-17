using System.IO.Compression;
using System.Numerics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SofaTap.Desktop;

// Deliberately independent of WinForms/network/processes, so package validation is
// exercised with inert archives on every CI platform.
internal sealed record ReceiverVersion(string Text, BigInteger Major, BigInteger Minor, BigInteger Patch, string[] Prerelease) : IComparable<ReceiverVersion>
{
    internal static ReceiverVersion? Parse(string? text)
    {
        if (text is null || text.Length > 100) return null;
        var match = Regex.Match(text, @"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z", RegexOptions.CultureInvariant);
        if (!match.Success || text.Length > 100) return null;
        var prerelease = match.Groups[4].Success ? match.Groups[4].Value.Split('.') : [];
        if (prerelease.Any(part => part.All(char.IsAsciiDigit) && part.Length > 1 && part[0] == '0')) return null;
        return new(text, BigInteger.Parse(match.Groups[1].Value), BigInteger.Parse(match.Groups[2].Value), BigInteger.Parse(match.Groups[3].Value), prerelease);
    }
    public int CompareTo(ReceiverVersion? other)
    {
        if (other is null) return 1;
        foreach (var comparison in new[] { Major.CompareTo(other.Major), Minor.CompareTo(other.Minor), Patch.CompareTo(other.Patch) })
            if (comparison != 0) return comparison;
        if (Prerelease.Length == 0 || other.Prerelease.Length == 0) return (Prerelease.Length == 0 ? 1 : 0).CompareTo(other.Prerelease.Length == 0 ? 1 : 0);
        for (var index = 0; index < Math.Min(Prerelease.Length, other.Prerelease.Length); index++)
        {
            var left = Prerelease[index]; var right = other.Prerelease[index];
            var leftNumeric = left.All(char.IsAsciiDigit); var rightNumeric = right.All(char.IsAsciiDigit);
            var leftNumber = leftNumeric ? BigInteger.Parse(left) : BigInteger.Zero; var rightNumber = rightNumeric ? BigInteger.Parse(right) : BigInteger.Zero;
            var comparison = leftNumeric && rightNumeric ? leftNumber.CompareTo(rightNumber)
                : leftNumeric != rightNumeric ? (leftNumeric ? -1 : 1) : string.CompareOrdinal(left, right);
            if (comparison != 0) return comparison;
        }
        return Prerelease.Length.CompareTo(other.Prerelease.Length);
    }
}

internal sealed record UpdateRelease(string Tag, string Version, string Url, string Sha256, long Size);
internal sealed record PackageManifest(string Product, string Version, string Architecture, Dictionary<string, string> Files);

internal static class UpdatePackage
{
    internal const string AssetName = "SofaTap-Windows-x64.zip";
    internal const string ArchiveRoot = "SofaTap-Windows-x64/";
    internal const string ManifestName = "sofatap-package.json";
    internal const string Product = "com.chekusu.sofatap.receiver.windows";
    internal const long MaximumDownload = 512L * 1024 * 1024;
    internal const long MaximumExtracted = 1024L * 1024 * 1024;
    internal const int MaximumFiles = 3000;
    internal static bool IsHash(string? value) => value is not null && Regex.IsMatch(value, "^[a-fA-F0-9]{64}$", RegexOptions.CultureInvariant);

    internal static UpdateRelease? Select(IEnumerable<JsonElement> releases, ReceiverVersion current)
    {
        var candidates = new List<(ReceiverVersion Version, JsonElement Release)>();
        foreach (var release in releases)
        {
            if (release.GetProperty("draft").GetBoolean()) continue;
            var tag = release.GetProperty("tag_name").GetString() ?? "";
            if (!tag.StartsWith('v') || ReceiverVersion.Parse(tag[1..]) is not { } version || version.CompareTo(current) <= 0) continue;
            // Beta users can move to newer beta or stable. Once on stable,
            // prereleases are excluded even if release metadata mislabels them.
            if (current.Prerelease.Length == 0 && (version.Prerelease.Length > 0 ||
                release.TryGetProperty("prerelease", out var beta) && beta.GetBoolean())) continue;
            // Android tags can never enter this desktop channel.
            if (!release.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array) continue;
            if (assets.EnumerateArray().Any(asset => asset.GetProperty("name").GetString() == AssetName)) candidates.Add((version, release));
        }
        var newest = candidates.OrderByDescending(item => item.Version).FirstOrDefault();
        if (newest.Version is null) return null;
        var chosen = newest.Release.GetProperty("assets").EnumerateArray().Where(asset => asset.GetProperty("name").GetString() == AssetName).ToArray();
        if (chosen.Length != 1) throw new InvalidDataException("更新包信息重复，请稍后重试。");
        var item = chosen[0];
        var releaseTag = newest.Release.GetProperty("tag_name").GetString()!;
        var url = item.GetProperty("browser_download_url").GetString() ?? "";
        var size = item.GetProperty("size").GetInt64();
        var digest = item.TryGetProperty("digest", out var digestValue) && digestValue.ValueKind == JsonValueKind.String ? digestValue.GetString() : null;
        if (item.GetProperty("state").GetString() != "uploaded" || size is <= 0 or > MaximumDownload ||
            digest is null || !digest.StartsWith("sha256:", StringComparison.Ordinal) || !IsHash(digest[7..]) ||
            url != "https://github.com/chekusu/sofatap/releases/download/" + releaseTag + "/" + AssetName)
            throw new InvalidDataException("最新更新包尚未提供完整的安全校验信息，请稍后重试。");
        return new(releaseTag, newest.Version.Text, url, digest[7..].ToLowerInvariant(), size);
    }

    internal static string HashFile(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }

    internal static void VerifyDownload(string file, UpdateRelease release)
    {
        if (!IsHash(release.Sha256) || release.Size <= 0 || release.Size > MaximumDownload ||
            new FileInfo(file).Length != release.Size || !string.Equals(HashFile(file), release.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("更新下载校验失败，原版本保持不变。");
    }

    internal static string SafeRelative(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length > 240 || value.Contains('\\') || value.StartsWith('/') || value.EndsWith('/'))
            throw new InvalidDataException("更新包包含无效路径。");
        foreach (var component in value.Split('/'))
        {
            if (component is "" or "." or ".." || component.EndsWith('.') || component.EndsWith(' ') ||
                component.Any(character => character < 32 || "<>:\"|?*".Contains(character)) ||
                Regex.IsMatch(component, @"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
                throw new InvalidDataException("更新包包含不安全的 Windows 路径。");
        }
        return value;
    }

    internal static void NoLinks(string path)
    {
        var current = new DirectoryInfo(Path.GetFullPath(path));
        for (FileSystemInfo? item = current; item is not null; item = (item as DirectoryInfo)?.Parent)
            if (item.Exists && (item.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("更新不支持符号链接或重解析目录。");
    }

    internal static PackageManifest ReadManifest(string path, string? expectedVersion = null)
    {
        if (new FileInfo(path).Length > 2 * 1024 * 1024) throw new InvalidDataException("更新清单过大。");
        var manifest = JsonSerializer.Deserialize<PackageManifest>(File.ReadAllText(path)) ?? throw new InvalidDataException("更新清单缺失。");
        ValidateManifest(manifest, expectedVersion);
        return manifest;
    }
    private static void ValidateManifest(PackageManifest manifest, string? expectedVersion)
    {
        if (manifest.Product != Product || manifest.Architecture != "x64" || ReceiverVersion.Parse(manifest.Version) is null ||
            (expectedVersion is not null && manifest.Version != expectedVersion) || manifest.Files is null ||
            manifest.Files.Count is < 2 or > MaximumFiles || !manifest.Files.ContainsKey("SofaTap.exe") || !manifest.Files.ContainsKey("SofaTapHost.exe"))
            throw new InvalidDataException("更新包与此接收器不匹配。");
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var pair in manifest.Files)
            if (!paths.Add(SafeRelative(pair.Key)) || pair.Key.Equals(ManifestName, StringComparison.OrdinalIgnoreCase) || !IsHash(pair.Value))
                throw new InvalidDataException("更新文件清单无效。");
    }

    internal static PackageManifest ExtractVerified(string archivePath, UpdateRelease release, string destination)
    {
        VerifyDownload(archivePath, release);
        NoLinks(Path.GetDirectoryName(destination)!);
        if (Directory.Exists(destination) || File.Exists(destination)) throw new IOException("更新暂存位置已存在。");
        using var input = new FileStream(archivePath, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var archive = new ZipArchive(input, ZipArchiveMode.Read);
        if (archive.Entries.Count > MaximumFiles + 100) throw new InvalidDataException("更新包文件过多。");
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var files = new List<(ZipArchiveEntry Entry, string Relative)>();
        long extracted = 0;
        foreach (var entry in archive.Entries)
        {
            if (!entry.FullName.StartsWith(ArchiveRoot, StringComparison.Ordinal) || (entry.ExternalAttributes >> 16 & 0xF000) == 0xA000 ||
                (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("更新包包含异常根目录或链接。");
            var relative = entry.FullName[ArchiveRoot.Length..];
            if (relative.Length == 0 && entry.FullName.EndsWith('/')) continue;
            if (relative.EndsWith('/')) { SafeRelative(relative.TrimEnd('/')); continue; }
            SafeRelative(relative);
            if (!paths.Add(relative)) throw new InvalidDataException("更新包包含重复路径。");
            extracted = checked(extracted + entry.Length);
            if (entry.Length < 0 || extracted > MaximumExtracted) throw new InvalidDataException("更新包解压后过大。");
            files.Add((entry, relative));
        }
        var manifestEntry = files.SingleOrDefault(item => item.Relative == ManifestName).Entry ?? throw new InvalidDataException("更新包缺少安全清单。");
        if (manifestEntry.Length > 2 * 1024 * 1024) throw new InvalidDataException("更新清单过大。");
        PackageManifest manifest;
        using (var reader = new StreamReader(manifestEntry.Open()))
            manifest = JsonSerializer.Deserialize<PackageManifest>(reader.ReadToEnd()) ?? throw new InvalidDataException("更新清单缺失。");
        ValidateManifest(manifest, release.Version);
        if (files.Count != manifest.Files.Count + 1 || files.Any(file => file.Relative != ManifestName && !manifest.Files.ContainsKey(file.Relative)))
            throw new InvalidDataException("更新包有未声明的文件。");
        Directory.CreateDirectory(destination);
        try
        {
            foreach (var file in files)
            {
                var target = Path.Combine(destination, file.Relative.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using (var source = file.Entry.Open())
                using (var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    var buffer = new byte[81920]; long copied = 0; int count;
                    while ((count = source.Read(buffer)) > 0)
                    {
                        copied += count;
                        if (copied > file.Entry.Length) throw new InvalidDataException("更新包文件大小不匹配。");
                        output.Write(buffer, 0, count);
                    }
                    if (copied != file.Entry.Length) throw new InvalidDataException("更新包文件不完整。");
                }
                if (file.Relative != ManifestName && !string.Equals(HashFile(target), manifest.Files[file.Relative], StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("更新包文件校验失败。");
            }
            return manifest;
        }
        catch { Directory.Delete(destination, recursive: true); throw; }
    }

    internal static void PreserveUnmanagedFiles(string installation, PackageManifest oldManifest, string stage)
    {
        NoLinks(installation);
        var managed = new HashSet<string>(oldManifest.Files.Keys, StringComparer.OrdinalIgnoreCase) { ManifestName };
        void Visit(string directory)
        {
            foreach (var path in Directory.EnumerateFileSystemEntries(directory))
            {
                var attributes = File.GetAttributes(path);
                if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("安装目录有链接，不能自动更新。");
                var relative = Path.GetRelativePath(installation, path).Replace(Path.DirectorySeparatorChar, '/');
                SafeRelative(relative);
                var destination = Path.Combine(stage, relative.Replace('/', Path.DirectorySeparatorChar));
                if ((attributes & FileAttributes.Directory) != 0) { Directory.CreateDirectory(destination); Visit(path); }
                else if (!managed.Contains(relative))
                {
                    if (File.Exists(destination)) throw new IOException("新版本与安装目录中的自定义文件冲突，请手动更新。");
                    Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                    File.Copy(path, destination, overwrite: false);
                }
            }
        }
        Visit(installation);
    }
}
