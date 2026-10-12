using System.Text.Json;

namespace SofaTap.DeviceHarness;

internal static class PrivateFiles
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public static void PrepareDirectory(string directory)
    {
        if (Directory.Exists(directory))
        {
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0 || Directory.EnumerateFileSystemEntries(directory).Any())
                throw new IOException("A fresh directory is required.");
        }
        Directory.CreateDirectory(directory);
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(directory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }
    public static FileStream Create(string path)
    {
        var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.Read };
        if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        return new FileStream(path, options);
    }
    public static void WriteJson(string path, object value)
    {
        var temporary = path + ".new-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var stream = Create(temporary)) { JsonSerializer.Serialize(stream, value, Json); stream.Flush(); }
            File.Move(temporary, path, true);
        }
        finally { File.Delete(temporary); }
    }
    public static bool IsRegularFile(string path)
    {
        try { return File.Exists(path) && (File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) == 0; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }
}
