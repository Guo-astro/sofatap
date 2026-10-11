// One-shot, local, pointer-only diagnostic. This binary has no network or keyboard path.
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <wtsapi32.h>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <iterator>
#include <sstream>
#include <string>
#include <thread>
#include <vector>
#include "Policy.h"

namespace {
constexpr wchar_t ServiceName[] = L"SofatapSecureInputProbe";
constexpr wchar_t ExeName[] = L"Sofatap.SecureInputProbe.exe";
constexpr wchar_t TrustedInstallerSid[] = L"S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464";
constexpr DWORD ServiceDeadlineMs = 12000;
constexpr DWORD WorkerDeadlineMs = 6000;
constexpr DWORD ContextDeadlineMs = 4000;
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    Handle() = default;
    explicit Handle(HANDLE h) : value(h) {}
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    Handle(Handle&& other) noexcept : value(other.value) { other.value = INVALID_HANDLE_VALUE; }
    Handle& operator=(Handle&& other) noexcept { if (this != &other) { Reset(); value = other.value; other.value = INVALID_HANDLE_VALUE; } return *this; }
    ~Handle() { Reset(); }
    bool Valid() const { return value && value != INVALID_HANDLE_VALUE; }
    void Reset() { if (Valid()) CloseHandle(value); value = INVALID_HANDLE_VALUE; }
};
struct LocalMemory { HLOCAL value = nullptr; ~LocalMemory() { if (value) LocalFree(value); } };
struct Desktop { HDESK value = nullptr; ~Desktop() { if (value) CloseDesktop(value); } };
struct Paths { std::wstring programFiles, parent, install, exe, results; };
Paths FixedPaths() {
    PWSTR known = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_ProgramFiles, KF_FLAG_DEFAULT, nullptr, &known))) return {};
    std::wstring root(known); CoTaskMemFree(known);
    if (root.size() < 4 || root[1] != L':' || root[2] != L'\\' || root.find(L"..") != std::wstring::npos) return {};
    Paths p; p.programFiles = root; p.parent = root + L"\\Chekusu";
    p.install = p.parent + L"\\SofatapSecureInputProbe";
    p.exe = p.install + L"\\" + ExeName; p.results = p.install + L"\\Results"; return p;
}
bool SamePath(const std::wstring& a, const std::wstring& b) { return _wcsicmp(a.c_str(), b.c_str()) == 0; }
bool IsTrustedSid(PSID sid) {
    if (!sid || !IsValidSid(sid)) return false;
    if (IsWellKnownSid(sid, WinLocalSystemSid) || IsWellKnownSid(sid, WinBuiltinAdministratorsSid)) return true;
    PSID ti = nullptr;
    if (!ConvertStringSidToSidW(TrustedInstallerSid, &ti)) return false;
    const bool trusted = EqualSid(sid, ti) != FALSE; LocalFree(ti); return trusted;
}
bool TrustedObject(HANDLE object, bool volumeRoot) {
    PSID owner = nullptr; PACL acl = nullptr; PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (GetSecurityInfo(object, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
        &owner, nullptr, &acl, nullptr, &descriptor) != ERROR_SUCCESS) return false;
    LocalMemory guard; guard.value = descriptor;
    if (!IsTrustedSid(owner) || !acl) return false;
    // A volume root can allow creation of unrelated directories. It must not let
    // untrusted principals replace our existing trusted Program Files ancestor.
    const ACCESS_MASK forbidden = volumeRoot ? DELETE | FILE_DELETE_CHILD | WRITE_DAC | WRITE_OWNER | GENERIC_ALL
        : FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA | FILE_WRITE_ATTRIBUTES | DELETE | FILE_DELETE_CHILD | WRITE_DAC | WRITE_OWNER | GENERIC_WRITE | GENERIC_ALL;
    for (DWORD i = 0; i < acl->AceCount; ++i) {
        void* raw = nullptr;
        if (!GetAce(acl, i, &raw)) return false;
        const auto header = static_cast<ACE_HEADER*>(raw);
        if (header->AceFlags & INHERIT_ONLY_ACE) continue;
        if (header->AceType == ACCESS_DENIED_ACE_TYPE || header->AceType == SYSTEM_AUDIT_ACE_TYPE) continue;
        // Fail closed on callback/object allow ACEs instead of guessing their SID layout.
        if (header->AceType != ACCESS_ALLOWED_ACE_TYPE) return false;
        const auto allow = static_cast<ACCESS_ALLOWED_ACE*>(raw);
        if ((allow->Mask & forbidden) && !IsTrustedSid(&allow->SidStart)) return false;
    }
    return true;
}
struct PathLocks {
    std::vector<Handle> handles;
    bool Add(const std::wstring& path, bool directory, bool volumeRoot = false) {
        Handle handle(CreateFileW(path.c_str(), READ_CONTROL | FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | (directory ? FILE_SHARE_WRITE : 0), nullptr, OPEN_EXISTING,
            FILE_FLAG_OPEN_REPARSE_POINT | (directory ? FILE_FLAG_BACKUP_SEMANTICS : 0), nullptr));
        if (!handle.Valid()) return false;
        BY_HANDLE_FILE_INFORMATION info{};
        if (!GetFileInformationByHandle(handle.value, &info) || (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
            || !!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != directory
            || (!directory && info.nNumberOfLinks != 1) || !TrustedObject(handle.value, volumeRoot)) return false;
        wchar_t finalPath[32768];
        const DWORD length = GetFinalPathNameByHandleW(handle.value, finalPath, static_cast<DWORD>(std::size(finalPath)), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
        if (!length || length >= std::size(finalPath) || !SamePath(std::wstring(finalPath), L"\\\\?\\" + path)) return false;
        handles.push_back(std::move(handle)); return true;
    }
    bool Verify(const Paths& paths) {
        if (paths.exe.empty()) return false;
        wchar_t self[32768];
        const DWORD count = GetModuleFileNameW(nullptr, self, static_cast<DWORD>(std::size(self)));
        if (!count || count >= std::size(self) || !SamePath(self, paths.exe)) return false;
        const std::wstring root = paths.programFiles.substr(0, 3);
        if (!Add(root, true, true)) return false;
        // Pin every existing path component, including redirected Program Files ancestors.
        std::size_t slash = 3;
        while ((slash = paths.programFiles.find(L'\\', slash)) != std::wstring::npos) {
            if (!Add(paths.programFiles.substr(0, slash), true)) return false;
            ++slash;
        }
        return Add(paths.programFiles, true) && Add(paths.parent, true) && Add(paths.install, true)
            && Add(paths.exe, false) && Add(paths.results, true);
    }
};
bool SystemToken(HANDLE process, DWORD expectedSession) {
    HANDLE raw = nullptr;
    if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) return false;
    Handle token(raw); DWORD size = 0;
    GetTokenInformation(token.value, TokenUser, nullptr, 0, &size);
    if (!size || size > 16384) return false;
    std::vector<BYTE> user(size);
    if (!GetTokenInformation(token.value, TokenUser, user.data(), size, &size)
        || !IsWellKnownSid(reinterpret_cast<TOKEN_USER*>(user.data())->User.Sid, WinLocalSystemSid)) return false;
    DWORD session = MAXDWORD;
    if (!GetTokenInformation(token.value, TokenSessionId, &session, sizeof(session), &size) || session != expectedSession) return false;
    TOKEN_ELEVATION elevation{};
    return GetTokenInformation(token.value, TokenElevation, &elevation, sizeof(elevation), &size) && elevation.TokenIsElevated;
}
struct ConsoleState { DWORD session = MAXDWORD; bool physical = false, active = false, locked = false; DWORD error = 0; };
ConsoleState Console(DWORD expected = MAXDWORD) {
    ConsoleState result; result.session = WTSGetActiveConsoleSessionId();
    if (result.session == MAXDWORD || result.session == 0 || (expected != MAXDWORD && result.session != expected)) { result.error = ERROR_CTX_WINSTATION_NOT_FOUND; return result; }
    LPWSTR raw = nullptr; DWORD size = 0;
    if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, result.session, WTSSessionInfoEx, &raw, &size)) { result.error = GetLastError(); return result; }
    if (size >= sizeof(WTSINFOEXW)) {
        const auto info = reinterpret_cast<WTSINFOEXW*>(raw);
        if (info->Level == 1 && info->Data.WTSInfoExLevel1.SessionId == result.session) {
            result.active = info->Data.WTSInfoExLevel1.SessionState == WTSActive;
            result.locked = info->Data.WTSInfoExLevel1.SessionFlags == WTS_SESSIONSTATE_LOCK;
        }
    }
    WTSFreeMemory(raw); raw = nullptr;
    // WTSClientProtocolType 0 is the physical console; never accept an RDP session.
    if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, result.session, WTSClientProtocolType, &raw, &size)) { result.error = GetLastError(); return result; }
    result.physical = size >= sizeof(USHORT) && *reinterpret_cast<USHORT*>(raw) == 0;
    WTSFreeMemory(raw);
    if (!result.physical || !result.active || !result.locked) result.error = ERROR_ACCESS_DENIED;
    return result;
}
bool NameIs(HANDLE object, const wchar_t* expected) {
    wchar_t name[128]{}; DWORD needed = 0;
    return GetUserObjectInformationW(object, UOI_NAME, name, sizeof(name), &needed) && needed <= sizeof(name) && _wcsicmp(name, expected) == 0;
}
bool ParentIsService(const Paths& paths) {
    Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
    if (!snapshot.Valid()) return false;
    PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry); DWORD parent = 0;
    if (Process32FirstW(snapshot.value, &entry)) do { if (entry.th32ProcessID == GetCurrentProcessId()) { parent = entry.th32ParentProcessID; break; } } while (Process32NextW(snapshot.value, &entry));
    SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!manager) return false;
    SC_HANDLE service = OpenServiceW(manager, ServiceName, SERVICE_QUERY_STATUS);
    SERVICE_STATUS_PROCESS state{}; DWORD needed = 0;
    const bool matches = service && QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<BYTE*>(&state), sizeof(state), &needed)
        && state.dwCurrentState == SERVICE_RUNNING && state.dwProcessId == parent && parent != 0;
    if (service) CloseServiceHandle(service); CloseServiceHandle(manager);
    if (!matches) return false;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parent));
    wchar_t image[32768]; DWORD length = static_cast<DWORD>(std::size(image));
    return process.Valid() && QueryFullProcessImageNameW(process.value, 0, image, &length)
        && SamePath(image, paths.exe) && SystemToken(process.value, 0);
}
Handle NewReport(const Paths& paths, const wchar_t* filename) {
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"O:SYG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)", SDDL_REVISION_1, &descriptor, nullptr)) return {};
    LocalMemory guard; guard.value = descriptor;
    SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};
    return Handle(CreateFileW((paths.results + L"\\" + filename).c_str(), GENERIC_WRITE, FILE_SHARE_READ, &attributes,
        CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_WRITE_THROUGH, nullptr));
}
bool WriteReport(HANDLE handle, const std::string& json) {
    if (json.size() > 8192) return false;
    DWORD written = 0;
    return WriteFile(handle, json.data(), static_cast<DWORD>(json.size()), &written, nullptr) && written == json.size() && FlushFileBuffers(handle);
}
bool Watchdog(DWORD milliseconds) noexcept {
    try { std::thread([milliseconds] { Sleep(milliseconds); TerminateProcess(GetCurrentProcess(), ERROR_TIMEOUT); }).detach(); return true; }
    catch (...) { return false; }
}
bool NoOnScreenKeyboard(DWORD session) {
    Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
    if (!snapshot.Valid()) return false;
    PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
    if (!Process32FirstW(snapshot.value, &entry)) return false;
    do {
        if (_wcsicmp(entry.szExeFile, L"osk.exe") == 0) {
            DWORD observed = MAXDWORD;
            if (!ProcessIdToSessionId(entry.th32ProcessID, &observed) || observed == session) return false;
        }
    } while (Process32NextW(snapshot.value, &entry));
    return GetLastError() == ERROR_NO_MORE_FILES;
}
bool NoMouseButtonDown() {
    for (const int key : {VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2})
        if (GetAsyncKeyState(key) & 0x8000) return false;
    return true;
}
struct WorkerReport {
    probe::Gate gate{}; bool moveAttempted = false, moveAccepted = false, movementObserved = false;
    bool restoreAttempted = false, restoreAccepted = false, restored = false, pointerChanged = false;
    bool cursorVisibleBefore = false, cursorVisibleAfter = false, contextUnchanged = false;
    LONG deltaX = 0, deltaY = 0; DWORD stage = 0, error = 0;
    std::string Json() const {
        std::ostringstream s; s << std::boolalpha
            << "{\"version\":1,\"pointerOnly\":true,\"completed\":true,\"systemToken\":" << gate.system
            << ",\"protectedPaths\":" << gate.protectedPaths << ",\"serviceParent\":" << gate.serviceParent
            << ",\"physicalConsole\":" << gate.physicalConsole << ",\"active\":" << gate.active << ",\"locked\":" << gate.locked
            << ",\"winsta0\":" << gate.winsta0 << ",\"threadWinlogon\":" << gate.threadWinlogon << ",\"inputWinlogon\":" << gate.inputWinlogon
            << ",\"beforeDeadline\":" << gate.beforeDeadline << ",\"moveAttempted\":" << moveAttempted
            << ",\"noOnScreenKeyboard\":" << gate.noOnScreenKeyboard << ",\"noMouseButtonDown\":" << gate.noMouseButtonDown
            << ",\"sendInputAccepted\":" << moveAccepted << ",\"movementObserved\":" << movementObserved
            << ",\"observedDeltaX\":" << deltaX << ",\"observedDeltaY\":" << deltaY
            << ",\"restoreAttempted\":" << restoreAttempted << ",\"restoreAccepted\":" << restoreAccepted
            << ",\"pointerRestored\":" << restored << ",\"restoreSkippedPointerChanged\":" << pointerChanged
            << ",\"cursorVisibleBefore\":" << cursorVisibleBefore << ",\"cursorVisibleAfter\":" << cursorVisibleAfter
            << ",\"contextUnchanged\":" << contextUnchanged << ",\"stage\":" << stage << ",\"win32Error\":" << error << "}\n";
        return s.str();
    }
};
probe::Gate ReadGate(DWORD session, ULONGLONG start, bool paths, bool parent) {
    const auto console = Console(session); probe::Gate gate;
    gate.system = SystemToken(GetCurrentProcess(), session); gate.protectedPaths = paths; gate.serviceParent = parent;
    gate.physicalConsole = console.session == session && console.physical; gate.active = console.active; gate.locked = console.locked;
    gate.winsta0 = NameIs(GetProcessWindowStation(), L"WinSta0");
    gate.threadWinlogon = NameIs(GetThreadDesktop(GetCurrentThreadId()), L"Winlogon");
    Desktop desktop; desktop.value = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    gate.inputWinlogon = desktop.value && NameIs(desktop.value, L"Winlogon");
    gate.beforeDeadline = GetTickCount64() - start < ContextDeadlineMs;
    gate.noOnScreenKeyboard = NoOnScreenKeyboard(session); gate.noMouseButtonDown = NoMouseButtonDown();
    return gate;
}
bool VisibleCursor() { CURSORINFO info{}; info.cbSize = sizeof(info); return GetCursorInfo(&info) && (info.flags & CURSOR_SHOWING); }
RECT VirtualScreen() {
    RECT value{}; value.left = GetSystemMetrics(SM_XVIRTUALSCREEN); value.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    value.right = value.left + GetSystemMetrics(SM_CXVIRTUALSCREEN); value.bottom = value.top + GetSystemMetrics(SM_CYVIRTUALSCREEN); return value;
}
bool SameGeometry(HMONITOR display, const RECT& monitor, const RECT& virtualScreen) {
    MONITORINFO current{}; current.cbSize = sizeof(current); const RECT currentVirtual = VirtualScreen();
    return GetMonitorInfoW(display, &current) && EqualRect(&current.rcMonitor, &monitor) && EqualRect(&currentVirtual, &virtualScreen);
}
bool InputFor(probe::Point point, const RECT& virtualScreen, INPUT& event) {
    std::int32_t x = 0, y = 0;
    if (!probe::Normalize(point.x, virtualScreen.left, virtualScreen.right - virtualScreen.left, x)
        || !probe::Normalize(point.y, virtualScreen.top, virtualScreen.bottom - virtualScreen.top, y)) return false;
    event = {}; event.type = INPUT_MOUSE; event.mi.dx = x; event.mi.dy = y;
    event.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
    return true;
}
void ProbePointer(const Paths& paths, WorkerReport& result) {
    DWORD session = MAXDWORD;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session)) { result.stage = 1; result.error = GetLastError(); return; }
    const ULONGLONG start = GetTickCount64();
    // CreateProcessAsUser already bound this no-window/no-hook worker to Winlogon.
    result.gate = ReadGate(session, start, true, ParentIsService(paths));
    if (!probe::MayMove(result.gate)) { result.stage = 2; result.error = ERROR_ACCESS_DENIED; return; }
    if (!SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) { result.stage = 3; result.error = GetLastError(); return; }
    POINT original{};
    if (!GetCursorPos(&original)) { result.stage = 4; result.error = GetLastError(); return; }
    MONITORINFO monitor{}; monitor.cbSize = sizeof(monitor);
    const auto display = MonitorFromPoint(original, MONITOR_DEFAULTTONULL);
    if (!display || !GetMonitorInfoW(display, &monitor)) { result.stage = 5; result.error = ERROR_INVALID_DATA; return; }
    const RECT virtualScreen = VirtualScreen();
    probe::Point target{}; const probe::Point before{original.x, original.y};
    if (!probe::ChooseTarget(before, {monitor.rcMonitor.left, monitor.rcMonitor.top},
        {monitor.rcMonitor.right - monitor.rcMonitor.left, monitor.rcMonitor.bottom - monitor.rcMonitor.top}, target)) { result.stage = 6; result.error = ERROR_INVALID_DATA; return; }
    INPUT move{}, restore{};
    if (!InputFor(target, virtualScreen, move) || !InputFor(before, virtualScreen, restore)) { result.stage = 7; result.error = ERROR_INVALID_DATA; return; }
    result.cursorVisibleBefore = VisibleCursor();
    result.gate = ReadGate(session, start, true, ParentIsService(paths));
    POINT justBefore{};
    if (!probe::MayMove(result.gate) || !GetCursorPos(&justBefore) || !probe::SamePoint(before, {justBefore.x, justBefore.y})
        || !SameGeometry(display, monitor.rcMonitor, virtualScreen)) { result.stage = 8; result.error = ERROR_CANCELLED; return; }
    result.moveAttempted = true; SetLastError(ERROR_SUCCESS);
    result.moveAccepted = SendInput(1, &move, sizeof(move)) == 1;
    result.error = result.moveAccepted ? ERROR_SUCCESS : GetLastError();
    if (!result.moveAccepted) { result.stage = 9; if (!result.error) result.error = ERROR_ACCESS_DENIED; return; }
    Sleep(75);
    result.gate = ReadGate(session, start, true, ParentIsService(paths));
    if (!probe::MayMove(result.gate)) { result.stage = 10; result.error = ERROR_CANCELLED; return; }
    POINT after{};
    if (!GetCursorPos(&after)) { result.stage = 11; result.error = GetLastError(); return; }
    result.deltaX = after.x - before.x; result.deltaY = after.y - before.y;
    result.movementObserved = probe::SamePoint(target, {after.x, after.y}) && !probe::SamePoint(before, target);
    result.cursorVisibleAfter = VisibleCursor();
    if (!result.movementObserved) { result.stage = 12; result.error = ERROR_INVALID_DATA; return; }
    Sleep(650);
    result.gate = ReadGate(session, start, true, ParentIsService(paths));
    result.contextUnchanged = probe::MayMove(result.gate);
    POINT current{};
    if (!GetCursorPos(&current)) { result.stage = 13; result.error = GetLastError(); return; }
    result.pointerChanged = !probe::SamePoint({current.x, current.y}, target);
    if (!probe::MayRestore(result.gate, result.moveAccepted, result.movementObserved, {current.x, current.y}, target)
        || !SameGeometry(display, monitor.rcMonitor, virtualScreen)) { result.stage = 14; result.error = ERROR_CANCELLED; return; }
    result.restoreAttempted = true; SetLastError(ERROR_SUCCESS);
    result.restoreAccepted = SendInput(1, &restore, sizeof(restore)) == 1;
    result.error = result.restoreAccepted ? ERROR_SUCCESS : GetLastError();
    if (!result.restoreAccepted) { result.stage = 15; if (!result.error) result.error = ERROR_ACCESS_DENIED; return; }
    Sleep(75);
    result.gate = ReadGate(session, start, true, ParentIsService(paths));
    result.contextUnchanged = probe::MayMove(result.gate);
    POINT final{};
    result.restored = result.contextUnchanged && GetCursorPos(&final) && probe::SamePoint(before, {final.x, final.y});
    if (!result.restored) { result.stage = 16; result.error = ERROR_CANCELLED; }
}
DWORD Worker() {
    if (!Watchdog(WorkerDeadlineMs)) return ERROR_NO_SYSTEM_RESOURCES;
    const Paths paths = FixedPaths(); PathLocks locks;
    DWORD session = MAXDWORD;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session) || !SystemToken(GetCurrentProcess(), session)
        || !locks.Verify(paths) || !ParentIsService(paths)) return ERROR_ACCESS_DENIED;
    auto output = NewReport(paths, L"worker-result.json");
    if (!output.Valid()) return ERROR_ALREADY_EXISTS;
    WorkerReport result;
    try { ProbePointer(paths, result); }
    catch (...) { result.stage = 99; result.error = ERROR_UNHANDLED_EXCEPTION; }
    return WriteReport(output.value, result.Json()) ? result.error : ERROR_WRITE_FAULT;
}
SERVICE_STATUS_HANDLE statusHandle = nullptr;
SERVICE_STATUS serviceStatus{};
// Kept until process exit so a concurrent SCM callback can never use a closed,
// recycled event handle. This service process exits after its one bounded run.
std::atomic<HANDLE> stopEvent{nullptr};
void SetStatus(DWORD state, DWORD error = 0) {
    serviceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    serviceStatus.dwCurrentState = state; serviceStatus.dwWin32ExitCode = error;
    serviceStatus.dwControlsAccepted = state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SESSIONCHANGE | SERVICE_ACCEPT_SHUTDOWN : 0;
    serviceStatus.dwWaitHint = state == SERVICE_START_PENDING ? ServiceDeadlineMs : 0;
    SetServiceStatus(statusHandle, &serviceStatus);
}
DWORD WINAPI Handler(DWORD control, DWORD, LPVOID, LPVOID) {
    const HANDLE event = stopEvent.load();
    if ((control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN || control == SERVICE_CONTROL_SESSIONCHANGE) && event) SetEvent(event);
    return NO_ERROR;
}
bool EnablePrivilege(HANDLE token, const wchar_t* name) {
    TOKEN_PRIVILEGES value{}; value.PrivilegeCount = 1;
    if (!LookupPrivilegeValueW(nullptr, name, &value.Privileges[0].Luid)) return false;
    value.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED; SetLastError(ERROR_SUCCESS);
    return AdjustTokenPrivileges(token, FALSE, &value, 0, nullptr, nullptr) && GetLastError() == ERROR_SUCCESS;
}
struct AttributeList {
    std::vector<BYTE> memory;
    LPPROC_THREAD_ATTRIBUTE_LIST value = nullptr;
    ~AttributeList() { if (value) DeleteProcThreadAttributeList(value); }
    bool Initialize(HANDLE* job) {
        SIZE_T bytes = 0; InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
        if (!bytes || bytes > 65536) return false;
        memory.resize(bytes); auto raw = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(memory.data());
        if (!InitializeProcThreadAttributeList(raw, 1, 0, &bytes)) return false;
        value = raw;
        return UpdateProcThreadAttribute(value, 0, PROC_THREAD_ATTRIBUTE_JOB_LIST, job, sizeof(*job), nullptr, nullptr) != FALSE;
    }
};
DWORD RunWorker(const Paths& paths, DWORD session, bool& launched, DWORD& childExit) {
    HANDLE raw = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_ADJUST_PRIVILEGES, &raw)) return GetLastError();
    Handle token(raw);
    if (!EnablePrivilege(token.value, SE_TCB_NAME) || !EnablePrivilege(token.value, SE_ASSIGNPRIMARYTOKEN_NAME)
        || !EnablePrivilege(token.value, SE_INCREASE_QUOTA_NAME)) return ERROR_PRIVILEGE_NOT_HELD;
    HANDLE primaryRaw = nullptr;
    if (!DuplicateTokenEx(token.value, TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_SESSIONID,
        nullptr, SecurityIdentification, TokenPrimary, &primaryRaw)) return GetLastError();
    Handle primary(primaryRaw);
    if (!SetTokenInformation(primary.value, TokenSessionId, &session, sizeof(session))) return GetLastError();
    Handle job(CreateJobObjectW(nullptr, nullptr));
    if (!job.Valid()) return GetLastError();
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_ACTIVE_PROCESS;
    limits.BasicLimitInformation.ActiveProcessLimit = 1;
    if (!SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return GetLastError();
    AttributeList attributes;
    if (!attributes.Initialize(&job.value)) return GetLastError();
    STARTUPINFOEXW startup{}; startup.StartupInfo.cb = sizeof(startup); startup.lpAttributeList = attributes.value;
    wchar_t desktop[] = L"WinSta0\\Winlogon"; startup.StartupInfo.lpDesktop = desktop;
    std::wstring command = L"\"" + paths.exe + L"\" --worker";
    const auto console = Console(session);
    if (!console.physical || !console.active || !console.locked || WaitForSingleObject(stopEvent.load(), 0) != WAIT_TIMEOUT) return ERROR_CANCELLED;
    PROCESS_INFORMATION process{};
    // Assign the kill-on-close job atomically at creation: no orphaned SYSTEM
    // worker if the service dies between creating and assigning a child.
    if (!CreateProcessAsUserW(primary.value, paths.exe.c_str(), command.data(), nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, nullptr, paths.install.c_str(), &startup.StartupInfo, &process)) return GetLastError();
    launched = true; Handle worker(process.hProcess), thread(process.hThread);
    HANDLE waits[] = {worker.value, stopEvent.load()};
    const DWORD wait = WaitForMultipleObjects(2, waits, FALSE, 8000);
    if (wait == WAIT_OBJECT_0) { if (!GetExitCodeProcess(worker.value, &childExit)) return GetLastError(); return childExit; }
    // Closing the sole job handle terminates this one probe process, never a user app.
    job.Reset(); WaitForSingleObject(worker.value, 500);
    return wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : ERROR_CANCELLED;
}
void WINAPI ServiceMain(DWORD argc, LPWSTR*) {
    statusHandle = RegisterServiceCtrlHandlerExW(ServiceName, Handler, nullptr);
    if (!statusHandle) return;
    SetStatus(SERVICE_START_PENDING);
    if (!Watchdog(ServiceDeadlineMs)) { SetStatus(SERVICE_STOPPED, ERROR_NO_SYSTEM_RESOURCES); return; }
    stopEvent.store(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    DWORD error = ERROR_ACCESS_DENIED, childExit = MAXDWORD; bool launched = false;
    try {
        const Paths paths = FixedPaths(); PathLocks locks;
        if (argc != 1 || !stopEvent.load() || !SystemToken(GetCurrentProcess(), 0) || !locks.Verify(paths)) { SetStatus(SERVICE_STOPPED, error); return; }
        // A second invocation cannot replace the report or repeat the input.
        auto output = NewReport(paths, L"service-result.json");
        if (!output.Valid()) { SetStatus(SERVICE_STOPPED, ERROR_ALREADY_EXISTS); return; }
        SetStatus(SERVICE_RUNNING);
        const auto console = Console();
        if (console.physical && console.active && console.locked) error = RunWorker(paths, console.session, launched, childExit);
        else error = console.error ? console.error : ERROR_ACCESS_DENIED;
        std::ostringstream json;
        json << std::boolalpha << "{\"version\":1,\"pointerOnly\":true,\"completed\":true,\"physicalConsole\":" << console.physical
            << ",\"active\":" << console.active << ",\"locked\":" << console.locked << ",\"workerLaunched\":" << launched
            << ",\"workerExitCode\":" << childExit << ",\"win32Error\":" << error << "}\n";
        if (!WriteReport(output.value, json.str())) error = ERROR_WRITE_FAULT;
    } catch (...) { error = ERROR_UNHANDLED_EXCEPTION; }
    SetStatus(SERVICE_STOPPED, error);
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    const auto mode = probe::ParseMode(argc, argv);
    if (mode == probe::Mode::Invalid) return ERROR_INVALID_PARAMETER;
    // Static CRT + system DLL search only; no plugin/config/DLL path arguments.
    if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32)) return ERROR_ACCESS_DENIED;
    try {
        if (mode == probe::Mode::Preflight) {
            const auto state = Console();
            return state.physical && state.active && state.locked && NoOnScreenKeyboard(state.session) ? ERROR_SUCCESS : ERROR_ACCESS_DENIED;
        }
        if (mode == probe::Mode::Worker) return static_cast<int>(Worker());
        SERVICE_TABLE_ENTRYW table[] = {{const_cast<LPWSTR>(ServiceName), ServiceMain}, {nullptr, nullptr}};
        return StartServiceCtrlDispatcherW(table) ? ERROR_SUCCESS : static_cast<int>(GetLastError());
    } catch (...) { return ERROR_UNHANDLED_EXCEPTION; }
}
