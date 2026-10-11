using System.Runtime.InteropServices;
using System.Text;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace Sofatap.Login;

internal static class NativeWindows
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr attributes, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder name, uint length, uint flags);
    internal static void WriteEnrollmentNew(string path, byte[] bytes)
    {
        var locks = new List<SafeFileHandle>();
        try
        {
            var directory = Path.GetDirectoryName(Path.GetFullPath(path))!;
            var ancestors = new Stack<string>();
            for (string? value = directory; value is not null; value = Path.GetDirectoryName(value)) ancestors.Push(value);
            foreach (var ancestor in ancestors)
            {
                // Deny concurrent write/delete handles while creating the file. This prevents replacing
                // a checked user-owned ancestor with a junction during the elevated write.
                var handle = CreateFile(ancestor, 0x80, 1, IntPtr.Zero, 3, 0x02000000 | 0x00200000, IntPtr.Zero);
                if (handle.IsInvalid) { handle.Dispose(); throw new IOException("enrollment_directory_busy"); }
                locks.Add(handle);
                var actual = new StringBuilder(32768);
                if (GetFinalPathNameByHandle(handle, actual, (uint)actual.Capacity, 0) == 0
                    || !string.Equals(actual.ToString().Replace(@"\\?\", "").TrimEnd('\\'), ancestor.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)
                    || (File.GetAttributes(ancestor) & FileAttributes.ReparsePoint) != 0) throw new UnauthorizedAccessException();
            }
            using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            output.Write(bytes); output.Flush(true);
        }
        finally { foreach (var handle in locks) handle.Dispose(); }
    }
    [DllImport("kernel32.dll")] internal static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode)] private static extern bool WTSQuerySessionInformation(IntPtr server, uint session, int info, out IntPtr buffer, out int bytes);
    [DllImport("wtsapi32.dll")] private static extern void WTSFreeMemory(IntPtr memory);
    internal static (int Session, bool Locked)? ConsoleState()
    {
        var session = WTSGetActiveConsoleSessionId(); if (session == uint.MaxValue) return null;
        // WTSINFOEX: DWORD Level, aligned union at +8, Level1 SessionFlags at +16.
        if (!WTSQuerySessionInformation(IntPtr.Zero, session, 25, out var p, out var bytes)) return null;
        try
        {
            if (bytes < 20 || Marshal.ReadInt32(p) != 1) return null;
            var flag = Marshal.ReadInt32(p, 16);
            return flag is 0 or 1 ? ((int)session, flag == 0) : null;
        }
        finally { WTSFreeMemory(p); }
    }
    internal static string ConsoleAccount()
    {
        var session = WTSGetActiveConsoleSessionId();
        string Value(int type)
        {
            if (!WTSQuerySessionInformation(IntPtr.Zero, session, type, out var p, out _)) return "";
            try { return Marshal.PtrToStringUni(p) ?? ""; } finally { WTSFreeMemory(p); }
        }
        return Value(7) + "\\" + Value(5);
    }
    internal static bool ConsoleIsTarget(string sid)
    {
        try { return ((SecurityIdentifier)new NTAccount(ConsoleAccount()).Translate(typeof(SecurityIdentifier))).Value == sid; }
        catch (IdentityNotMappedException) { return false; }
    }
    [StructLayout(LayoutKind.Sequential)] private struct User24 { [MarshalAs(UnmanagedType.Bool)] public bool InternetIdentity; public uint Flags; public IntPtr InternetProviderName, InternetPrincipalName, UserSid; }
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode)] private static extern uint NetUserGetInfo(string? server, string user, uint level, out IntPtr buffer);
    [DllImport("netapi32.dll")] private static extern uint NetApiBufferFree(IntPtr buffer);
    internal sealed record AccountIdentity(string Provider, string Principal);
    internal static AccountIdentity? ReadAccountIdentity(string name, string sid)
    {
        if (NetUserGetInfo(null, name, 24, out var buffer) != 0) return null;
        try {
            var info = Marshal.PtrToStructure<User24>(buffer);
            if (info.UserSid == IntPtr.Zero || new SecurityIdentifier(info.UserSid).Value != sid) return null;
            if (!info.InternetIdentity) return new("windows-local-password", "");
            var principal = Marshal.PtrToStringUni(info.InternetPrincipalName);
            return string.Equals(Marshal.PtrToStringUni(info.InternetProviderName), "MicrosoftAccount", StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(principal) && principal.Length <= 254 ? new("windows-microsoft-password", principal) : null;
        }
        finally { NetApiBufferFree(buffer); }
    }
    [DllImport("kernel32.dll", SetLastError = true)] internal static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint id);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll")] private static extern bool ProcessIdToSessionId(uint pid, out uint session);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr value);
    internal static bool IsConsoleLogonUI(uint pid, int session)
    {
        if (!ProcessIdToSessionId(pid, out var actual) || actual != session || actual != WTSGetActiveConsoleSessionId()) return false;
        var process = OpenProcess(0x1000, false, pid); if (process == IntPtr.Zero) return false;
        try
        {
            var text = new StringBuilder(1024); var size = text.Capacity;
            return QueryFullProcessImageName(process, 0, text, ref size)
                && string.Equals(text.ToString(), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "LogonUI.exe"), StringComparison.OrdinalIgnoreCase);
        }
        finally { CloseHandle(process); }
    }
}
