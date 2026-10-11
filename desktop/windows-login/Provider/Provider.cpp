#include <windows.h>
#include <initguid.h>
#include <credentialprovider.h>
#include <ntsecapi.h>
#include <wincred.h>
#include <shlwapi.h>
#include <wtsapi32.h>
#include <propkey.h>
#include <lm.h>
#include <sddl.h>
#include <atomic>
#include <mutex>
#include <string>
#include <vector>
#include <cstring>
#include <new>

// This optional provider does not install a filter or replace any built-in provider.
static const CLSID CLSID_Sofatap = {0xf8f3819a,0x9ab1,0x4c6f,{0x86,0xd5,0x90,0xb5,0x7d,0x9a,0x42,0xc7}};
static std::atomic<long> objects{0};
static constexpr wchar_t pipeName[] = L"\\\\.\\pipe\\Sofatap.Login.v1";
static constexpr DWORD magic = 0x5346544c;
static HRESULT CopyString(const std::wstring& value, PWSTR* out) {
    if (!out) return E_POINTER;
    const auto bytes = (value.size() + 1) * sizeof(wchar_t);
    *out = static_cast<PWSTR>(CoTaskMemAlloc(bytes));
    if (!*out) return E_OUTOFMEMORY;
    memcpy(*out, value.c_str(), bytes); return S_OK;
}
static void Clear(std::wstring& value) { if (!value.empty()) SecureZeroMemory(value.data(), value.size() * sizeof(wchar_t)); value.clear(); }
struct WipeString { std::wstring& value; ~WipeString() { Clear(value); } };
static std::wstring Setting(const wchar_t* name) {
#ifdef SOFATAP_PROVIDER_TEST
    if (wcscmp(name, L"AccountName") == 0) return L"SofatapFixture";
    if (wcscmp(name, L"AccountSid") == 0) return L"S-1-5-21-1-2-3-1001";
    if (wcscmp(name, L"Provider") == 0) return L"windows-local-password";
    return L"FIXTURE";
#else
    wchar_t value[256]{}; DWORD bytes = sizeof(value);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Chekusu\\SofatapLogin", name, RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, value, &bytes) != ERROR_SUCCESS) return {};
    return value;
#endif
}
struct Handle {
    HANDLE h = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE value = INVALID_HANDLE_VALUE):h(value) {}
    ~Handle() { if (h && h != INVALID_HANDLE_VALUE) CloseHandle(h); }
    Handle(const Handle&) = delete; Handle& operator=(const Handle&) = delete;
};
static bool Transfer(HANDLE pipe, void* data, DWORD size, bool write) {
    auto cursor = static_cast<BYTE*>(data);
    while (size) {
        Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
        OVERLAPPED overlapped{}; overlapped.hEvent = event.h; DWORD done = 0;
        const BOOL ok = write ? WriteFile(pipe, cursor, size, &done, &overlapped) : ReadFile(pipe, cursor, size, &done, &overlapped);
        if (!ok) {
            if (GetLastError() != ERROR_IO_PENDING) return false;
            if (WaitForSingleObject(event.h, 1500) != WAIT_OBJECT_0) {
                CancelIoEx(pipe, &overlapped); GetOverlappedResult(pipe, &overlapped, &done, TRUE); return false;
            }
            if (!GetOverlappedResult(pipe, &overlapped, &done, FALSE)) return false;
        }
        if (!done || done > size) return false;
        cursor += done; size -= done;
    }
    return true;
}
static bool TrustedServer(HANDLE pipe) {
    ULONG pid = 0; if (!GetNamedPipeServerProcessId(pipe, &pid) || !pid) return false;
    auto scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT); if (!scm) return false;
    auto service = OpenServiceW(scm, L"SofatapLogin", SERVICE_QUERY_STATUS);
    SERVICE_STATUS_PROCESS info{}; DWORD bytes = 0;
    const bool trusted = service && QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<BYTE*>(&info), sizeof(info), &bytes)
        && info.dwCurrentState == SERVICE_RUNNING && info.dwProcessId == pid;
    if (service) CloseServiceHandle(service); CloseServiceHandle(scm); return trusted;
}
#pragma pack(push, 1)
struct Request { DWORD magicValue = magic; DWORD operation = 1; DWORD session = 0; GUID generation{}; GUID attempt{}; LONG result = 0; };
#pragma pack(pop)
static_assert(sizeof(Request) == 48);
static HANDLE Connect() {
    if (!WaitNamedPipeW(pipeName, 200)) return INVALID_HANDLE_VALUE;
    HANDLE pipe = CreateFileW(pipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
    if (pipe != INVALID_HANDLE_VALUE && !TrustedServer(pipe)) { CloseHandle(pipe); return INVALID_HANDLE_VALUE; }
    return pipe;
}
static void Report(DWORD session, GUID generation, GUID attempt, LONG status) {
    Handle pipe(Connect()); if (pipe.h == INVALID_HANDLE_VALUE) return;
    Request request; request.operation = 2; request.session = session; request.generation = generation; request.attempt = attempt; request.result = status;
    DWORD response = 0;
    if (Transfer(pipe.h, &request, sizeof(request), true)) Transfer(pipe.h, &response, sizeof(response), false);
}
static HRESULT AuthenticationPackage(ULONG* package) {
    HANDLE lsa = nullptr; auto status = LsaConnectUntrusted(&lsa); if (status < 0) return HRESULT_FROM_WIN32(LsaNtStatusToWinError(status));
    char name[] = "Negotiate"; LSA_STRING text{9, 10, name};
    status = LsaLookupAuthenticationPackage(lsa, &text, package); LsaDeregisterLogonProcess(lsa);
    return status < 0 ? HRESULT_FROM_WIN32(LsaNtStatusToWinError(status)) : S_OK;
}
static HRESULT SerializeMicrosoft(const std::wstring& qualified, std::wstring& password, CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* out) {
    DWORD length = 0;
    constexpr DWORD flags = CRED_PACK_PROTECTED_CREDENTIALS | CRED_PACK_ID_PROVIDER_CREDENTIALS;
    if (CredPackAuthenticationBufferW(flags, const_cast<PWSTR>(qualified.c_str()), password.data(), nullptr, &length)
        || GetLastError() != ERROR_INSUFFICIENT_BUFFER || !length || length > 65536) return E_FAIL;
    auto bytes = static_cast<BYTE*>(CoTaskMemAlloc(length)); if (!bytes) return E_OUTOFMEMORY;
    const auto allocated = length;
    HRESULT hr = E_FAIL;
    if (CredPackAuthenticationBufferW(flags, const_cast<PWSTR>(qualified.c_str()), password.data(), bytes, &length)) hr = AuthenticationPackage(&out->ulAuthenticationPackage);
    else hr = HRESULT_FROM_WIN32(GetLastError());
    if (FAILED(hr)) { SecureZeroMemory(bytes, allocated); CoTaskMemFree(bytes); return hr; }
    out->clsidCredentialProvider = CLSID_Sofatap; out->cbSerialization = length; out->rgbSerialization = bytes; return S_OK;
}
static bool MicrosoftIdentity(const std::wstring& account, const std::wstring& sid, const std::wstring& qualified, const GUID& providerId) {
    if (providerId == GUID_NULL || providerId == Identity_LocalUserProvider) return false;
    USER_INFO_24* info = nullptr; PSID target = nullptr;
    if (!ConvertStringSidToSidW(sid.c_str(), &target)) return false;
    const auto status = NetUserGetInfo(nullptr, account.c_str(), 24, reinterpret_cast<BYTE**>(&info));
    bool valid = false;
    if (status == NERR_Success && info) {
        if (info->usri24_internet_identity && info->usri24_user_sid && EqualSid(target, info->usri24_user_sid)
            && info->usri24_internet_provider_name && _wcsicmp(info->usri24_internet_provider_name, L"MicrosoftAccount") == 0
            && info->usri24_internet_principal_name) {
            const std::wstring expected = std::wstring(L"MicrosoftAccount\\") + info->usri24_internet_principal_name;
            valid = _wcsicmp(expected.c_str(), qualified.c_str()) == 0;
        }
        NetApiBufferFree(info);
    }
    LocalFree(target); return valid;
}
static HRESULT Serialize(const std::wstring& domain, const std::wstring& user, std::wstring& password,
    CREDENTIAL_PROVIDER_USAGE_SCENARIO scenario, CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* out) {
    // Password protection is local to LogonUI; the resulting blob is handed only to Windows.
    DWORD chars = 0; CRED_PROTECTION_TYPE protection{};
    CredProtectW(FALSE, password.data(), static_cast<DWORD>(password.size() + 1), nullptr, &chars, &protection);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || !chars) return E_FAIL;
    std::wstring protectedPassword(chars, L'\0');
    WipeString protectedWipe{protectedPassword};
    if (!CredProtectW(FALSE, password.data(), static_cast<DWORD>(password.size() + 1), protectedPassword.data(), &chars, &protection)) {
        Clear(protectedPassword); return HRESULT_FROM_WIN32(GetLastError());
    }
    protectedPassword.resize(wcslen(protectedPassword.c_str()));
    const auto total = sizeof(KERB_INTERACTIVE_UNLOCK_LOGON) + (domain.size() + user.size() + protectedPassword.size()) * sizeof(wchar_t);
    if (total > MAXDWORD) { Clear(protectedPassword); return E_FAIL; }
    auto bytes = static_cast<BYTE*>(CoTaskMemAlloc(total));
    if (!bytes) { Clear(protectedPassword); return E_OUTOFMEMORY; }
    ZeroMemory(bytes, total);
    auto logon = reinterpret_cast<KERB_INTERACTIVE_UNLOCK_LOGON*>(bytes);
    logon->Logon.MessageType = scenario == CPUS_UNLOCK_WORKSTATION ? KerbWorkstationUnlockLogon : KerbInteractiveLogon;
    size_t offset = sizeof(*logon);
    auto pack = [&](UNICODE_STRING& field, const std::wstring& text) {
        field.Length = static_cast<USHORT>(text.size() * sizeof(wchar_t)); field.MaximumLength = field.Length;
        field.Buffer = reinterpret_cast<PWSTR>(offset); memcpy(bytes + offset, text.data(), field.Length); offset += field.Length;
    };
    pack(logon->Logon.LogonDomainName, domain); pack(logon->Logon.UserName, user); pack(logon->Logon.Password, protectedPassword);
    Clear(protectedPassword);
    auto hr = AuthenticationPackage(&out->ulAuthenticationPackage);
    if (FAILED(hr)) { SecureZeroMemory(bytes, total); CoTaskMemFree(bytes); return hr; }
    out->clsidCredentialProvider = CLSID_Sofatap; out->cbSerialization = static_cast<ULONG>(total); out->rgbSerialization = bytes;
    return S_OK;
}

class Provider;
class Credential final : public ICredentialProviderCredential2 {
    std::atomic<ULONG> references{1};
    Provider* owner;
public:
    explicit Credential(Provider* value):owner(value) { ++objects; }
    ~Credential() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid == IID_IUnknown || iid == IID_ICredentialProviderCredential || iid == IID_ICredentialProviderCredential2) *out = static_cast<ICredentialProviderCredential2*>(this);
        if (!*out) return E_NOINTERFACE; AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override;
    ULONG STDMETHODCALLTYPE Release() override;
    HRESULT STDMETHODCALLTYPE Advise(ICredentialProviderCredentialEvents*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE UnAdvise() override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetSelected(BOOL* automatic) override { if (!automatic) return E_POINTER; *automatic = FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE SetDeselected() override;
    HRESULT STDMETHODCALLTYPE GetFieldState(DWORD id, CREDENTIAL_PROVIDER_FIELD_STATE* state, CREDENTIAL_PROVIDER_FIELD_INTERACTIVE_STATE* interactive) override {
        if (!state || !interactive || id > 2) return E_INVALIDARG;
        *state = CPFS_DISPLAY_IN_SELECTED_TILE; *interactive = CPFIS_NONE; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetStringValue(DWORD id, PWSTR* value) override {
        if (id == 0) return CopyString(L"Sofatap", value);
        if (id == 1) return CopyString(L"Use Face ID and your saved Windows password on your paired iPhone.", value);
        if (id == 2) return CopyString(L"Sign in", value);
        return E_INVALIDARG;
    }
    HRESULT STDMETHODCALLTYPE GetBitmapValue(DWORD, HBITMAP*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetCheckboxValue(DWORD, BOOL*, PWSTR*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetSubmitButtonValue(DWORD id, DWORD* adjacent) override { if (id != 2 || !adjacent) return E_INVALIDARG; *adjacent = 1; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetComboBoxValueCount(DWORD, DWORD*, DWORD*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetComboBoxValueAt(DWORD, DWORD, PWSTR*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE SetStringValue(DWORD, PCWSTR) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE SetCheckboxValue(DWORD, BOOL) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE SetComboBoxSelectedValue(DWORD, DWORD) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE CommandLinkClicked(DWORD) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetSerialization(CREDENTIAL_PROVIDER_GET_SERIALIZATION_RESPONSE*, CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION*, PWSTR*, CREDENTIAL_PROVIDER_STATUS_ICON*) override;
    HRESULT STDMETHODCALLTYPE ReportResult(NTSTATUS, NTSTATUS, PWSTR*, CREDENTIAL_PROVIDER_STATUS_ICON*) override;
    HRESULT STDMETHODCALLTYPE GetUserSid(PWSTR*) override;
};

class Provider final : public ICredentialProvider, public ICredentialProviderSetUserArray {
    std::atomic<ULONG> references{1};
    Credential* credential = nullptr;
    HANDLE stop = CreateEventW(nullptr, TRUE, FALSE, nullptr), worker = nullptr;
    IGlobalInterfaceTable* git = nullptr; DWORD cookie = 0; UINT_PTR context = 0;
    std::mutex gate;
    std::wstring password;
    GUID pending{}, submitted{}, generation{};
    DWORD session = 0;
    bool hasPending = false, hasSubmitted = false;
    ULONGLONG passwordDeadline = 0;
    std::wstring qualifiedUser;
    bool userVerified = false;
    CREDENTIAL_PROVIDER_USAGE_SCENARIO scenario = CPUS_INVALID;
public:
    const std::wstring account = Setting(L"AccountName"), sid = Setting(L"AccountSid"), machine = Setting(L"MachineName"), accountProvider = Setting(L"Provider"), enrolledQualifiedUser = Setting(L"QualifiedUserName");
    Provider() { ++objects; CoCreateGuid(&generation); ProcessIdToSessionId(GetCurrentProcessId(), &session);
#ifdef SOFATAP_PROVIDER_TEST
        userVerified = true; qualifiedUser = L"FIXTURE\\SofatapFixture";
#endif
    }
    ~Provider() { Stop(); if (credential) credential->Release(); if (git) git->Release(); CloseHandle(stop); Clear(password); --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid == IID_IUnknown || iid == IID_ICredentialProvider) *out = static_cast<ICredentialProvider*>(this);
        else if (iid == IID_ICredentialProviderSetUserArray) *out = static_cast<ICredentialProviderSetUserArray*>(this);
        if (!*out) return E_NOINTERFACE; AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override { auto value = --references; if (!value) delete this; return value; }
    HRESULT STDMETHODCALLTYPE SetUsageScenario(CREDENTIAL_PROVIDER_USAGE_SCENARIO value, DWORD) override {
        if (value != CPUS_LOGON && value != CPUS_UNLOCK_WORKSTATION) return E_NOTIMPL;
        if (account.empty() || sid.empty() || machine.empty()) return E_FAIL;
        Stop(false);
        scenario = value; if (!credential) credential = new(std::nothrow) Credential(this); StartWorker(); return credential ? S_OK : E_OUTOFMEMORY;
    }
    HRESULT STDMETHODCALLTYPE SetSerialization(const CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE SetUserArray(ICredentialProviderUserArray* users) override {
        Stop(false); std::lock_guard lock(gate); userVerified = false; qualifiedUser.clear();
        if (!users) return E_INVALIDARG;
        DWORD count = 0; if (FAILED(users->GetCount(&count)) || count > 1024) return E_FAIL;
        for (DWORD index = 0; index < count; ++index) {
            ICredentialProviderUser* user = nullptr; if (FAILED(users->GetAt(index, &user)) || !user) continue;
            PWSTR actualSid = nullptr, qualified = nullptr; GUID providerId{};
            try {
                if (SUCCEEDED(user->GetSid(&actualSid)) && actualSid && sid == actualSid && SUCCEEDED(user->GetProviderID(&providerId))
                    && SUCCEEDED(user->GetStringValue(PKEY_Identity_QualifiedUserName, &qualified)) && qualified && wcslen(qualified) <= 512) {
                    const bool local = accountProvider == L"windows-local-password" && providerId == Identity_LocalUserProvider
                        && _wcsicmp((machine + L"\\" + account).c_str(), qualified) == 0;
                    const bool microsoft = accountProvider == L"windows-microsoft-password" && _wcsicmp(enrolledQualifiedUser.c_str(), qualified) == 0 && MicrosoftIdentity(account, sid, qualified, providerId);
                    if (local || microsoft) { qualifiedUser = qualified; userVerified = true; }
                }
            } catch (...) { userVerified = false; qualifiedUser.clear(); }
            CoTaskMemFree(actualSid); CoTaskMemFree(qualified); user->Release();
            if (userVerified) break;
        }
        StartWorker(); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Advise(ICredentialProviderEvents* events, UINT_PTR value) override {
        if (!events) return E_INVALIDARG; Stop(); context = value;
        if (!git) { auto hr = CoCreateInstance(CLSID_StdGlobalInterfaceTable, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&git)); if (FAILED(hr)) return hr; }
        auto hr = git->RegisterInterfaceInGlobal(events, IID_ICredentialProviderEvents, &cookie); if (FAILED(hr)) return hr;
        StartWorker();
        return worker ? S_OK : E_FAIL;
    }
    HRESULT STDMETHODCALLTYPE UnAdvise() override { Stop(); return S_OK; }
    HRESULT STDMETHODCALLTYPE GetFieldDescriptorCount(DWORD* count) override { if (!count) return E_POINTER; *count = 3; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetFieldDescriptorAt(DWORD index, CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR** out) override {
        if (!out || index > 2) return E_INVALIDARG;
        auto item = static_cast<CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR*>(CoTaskMemAlloc(sizeof(CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR)));
        if (!item) return E_OUTOFMEMORY; ZeroMemory(item, sizeof(*item)); item->dwFieldID = index;
        item->cpft = index == 0 ? CPFT_LARGE_TEXT : index == 1 ? CPFT_SMALL_TEXT : CPFT_SUBMIT_BUTTON;
        auto hr = CopyString(index == 0 ? L"Sofatap" : index == 1 ? L"Phone unlock" : L"Sign in", &item->pszLabel);
        if (FAILED(hr)) { CoTaskMemFree(item); return hr; } *out = item; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetCredentialCount(DWORD* count, DWORD* defaultIndex, BOOL* automatic) override {
        if (!count || !defaultIndex || !automatic) return E_POINTER;
        std::lock_guard lock(gate); ExpirePassword(); *count = credential && userVerified ? 1 : 0;
        *defaultIndex = hasPending ? 0 : CREDENTIAL_PROVIDER_NO_DEFAULT; *automatic = hasPending ? TRUE : FALSE; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetCredentialAt(DWORD index, ICredentialProviderCredential** out) override {
        if (index != 0 || !out || !credential || !userVerified) return E_INVALIDARG; return credential->QueryInterface(IID_PPV_ARGS(out));
    }
    void StartWorker() { if (!worker && cookie) { ResetEvent(stop); worker = CreateThread(nullptr, 0, [](void* self)->DWORD { static_cast<Provider*>(self)->Run(); return 0; }, this, 0, nullptr); } }
    void Stop(bool revoke = true) {
        if (worker) {
            SetEvent(stop); DWORD index = 0;
            // Pump COM callbacks rather than deadlocking a worker's CredentialsChanged during unadvise.
            while (WaitForSingleObject(worker, 0) != WAIT_OBJECT_0) {
                const auto hr = CoWaitForMultipleHandles(COWAIT_DISPATCH_CALLS | COWAIT_DISPATCH_WINDOW_MESSAGES, 2000, 1, &worker, &index);
                if (FAILED(hr) && hr != RPC_S_CALLPENDING) WaitForSingleObject(worker, 100);
            }
            CloseHandle(worker); worker = nullptr;
        }
        if (revoke && git && cookie) { git->RevokeInterfaceFromGlobal(cookie); cookie = 0; }
        std::lock_guard lock(gate); Clear(password); hasPending = false; hasSubmitted = false;
        pending = GUID{}; submitted = GUID{}; CoCreateGuid(&generation);
    }
    void Discard() { std::lock_guard lock(gate); Clear(password); hasPending = false; }
    void ExpirePassword() { if (hasPending && GetTickCount64() >= passwordDeadline) { Clear(password); hasPending = false; } }
    void Run() {
        CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        try {
        while (WaitForSingleObject(stop, 350) == WAIT_TIMEOUT) {
            { std::lock_guard lock(gate); ExpirePassword(); if (!userVerified) continue; }
            Handle pipe(Connect()); if (pipe.h == INVALID_HANDLE_VALUE) continue;
            const auto requestStarted = GetTickCount64();
            Request request; request.session = session; request.generation = generation;
            DWORD kind = 0;
            if (!Transfer(pipe.h, &request, sizeof(request), true) || !Transfer(pipe.h, &kind, sizeof(kind), false) || kind != 1) continue;
            GUID attempt{}; USHORT sizes[2]{}; DWORD remaining = 0;
            if (!Transfer(pipe.h, &attempt, sizeof(attempt), false) || !Transfer(pipe.h, sizes, sizeof(sizes), false)
                || !Transfer(pipe.h, &remaining, sizeof(remaining), false) || remaining < 1 || remaining > 30000 || !sizes[0] || sizes[0] > 255 || !sizes[1] || sizes[1] > 1024) continue;
            std::wstring receivedAccount(sizes[0], L'\0'), receivedPassword(sizes[1], L'\0');
            WipeString receivedWipe{receivedPassword};
            bool ok = Transfer(pipe.h, receivedAccount.data(), sizes[0] * sizeof(wchar_t), false) && Transfer(pipe.h, receivedPassword.data(), sizes[1] * sizeof(wchar_t), false);
            if (ok && receivedAccount == account && receivedPassword.find(L'\0') == std::wstring::npos) {
                { std::lock_guard lock(gate); Clear(password); password.swap(receivedPassword); pending = attempt; hasPending = true; passwordDeadline = requestStarted + (remaining > 5000 ? 5000 : remaining); ExpirePassword(); }
                ICredentialProviderEvents* events = nullptr;
                if (cookie && SUCCEEDED(git->GetInterfaceFromGlobal(cookie, IID_PPV_ARGS(&events)))) { events->CredentialsChanged(context); events->Release(); }
            }
            Clear(receivedPassword);
        }
        } catch (...) { Discard(); }
        CoUninitialize();
    }
    HRESULT GetSerialization(CREDENTIAL_PROVIDER_GET_SERIALIZATION_RESPONSE* response, CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* out, PWSTR* text, CREDENTIAL_PROVIDER_STATUS_ICON* icon) {
        if (!response || !out || !text || !icon) return E_POINTER;
        *response = CPGSR_NO_CREDENTIAL_NOT_FINISHED; *text = nullptr; *icon = CPSI_NONE; ZeroMemory(out, sizeof(*out));
        std::lock_guard lock(gate); ExpirePassword(); if (!hasPending || !userVerified || WTSGetActiveConsoleSessionId() != session) { Clear(password); hasPending = false; return S_OK; }
        HRESULT hr = E_FAIL;
        try { hr = accountProvider == L"windows-microsoft-password" ? SerializeMicrosoft(qualifiedUser, password, out) : Serialize(machine, account, password, scenario, out); }
        catch (...) { hr = E_OUTOFMEMORY; }
        Clear(password); hasPending = false;
        if (SUCCEEDED(hr)) { submitted = pending; hasSubmitted = true; *response = CPGSR_RETURN_CREDENTIAL_FINISHED; }
        else Report(session, generation, pending, static_cast<LONG>(0xc0000001));
        return hr;
    }
    HRESULT Result(NTSTATUS status, PWSTR* text, CREDENTIAL_PROVIDER_STATUS_ICON* icon) {
        if (text) *text = nullptr; if (icon) *icon = status == 0 ? CPSI_SUCCESS : CPSI_ERROR;
        GUID attempt{}; bool send = false;
        { std::lock_guard lock(gate); if (hasSubmitted) { attempt = submitted; hasSubmitted = false; send = true; } Clear(password); hasPending = false; }
        if (send) Report(session, generation, attempt, status);
        if (status != 0 && text) CopyString(L"Windows did not accept this sign-in. Use your normal Windows sign-in option or try again from your iPhone.", text);
        return S_OK;
    }
};
HRESULT Credential::SetDeselected() { owner->Discard(); return S_OK; }
ULONG Credential::AddRef() { owner->AddRef(); return ++references; }
ULONG Credential::Release() { auto value = --references; if (!value) delete this; else owner->Release(); return value; }
HRESULT Credential::GetSerialization(CREDENTIAL_PROVIDER_GET_SERIALIZATION_RESPONSE* a, CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* b, PWSTR* c, CREDENTIAL_PROVIDER_STATUS_ICON* d) { return owner->GetSerialization(a,b,c,d); }
HRESULT Credential::ReportResult(NTSTATUS a, NTSTATUS, PWSTR* c, CREDENTIAL_PROVIDER_STATUS_ICON* d) { return owner->Result(a,c,d); }
HRESULT Credential::GetUserSid(PWSTR* out) { return CopyString(owner->sid, out); }

class Factory final : public IClassFactory {
    std::atomic<ULONG> references{1};
public:
    Factory() { ++objects; } ~Factory() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid == IID_IUnknown || iid == IID_IClassFactory) *out = static_cast<IClassFactory*>(this);
        if (!*out) return E_NOINTERFACE; AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override { auto value = --references; if (!value) delete this; return value; }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** out) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        try { auto provider = new(std::nothrow) Provider(); if (!provider) return E_OUTOFMEMORY; auto hr = provider->QueryInterface(iid, out); provider->Release(); return hr; }
        catch (...) { return E_OUTOFMEMORY; }
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if (lock) ++objects; else --objects; return S_OK; }
};
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** out) {
    if (clsid != CLSID_Sofatap) return CLASS_E_CLASSNOTAVAILABLE;
    auto factory = new(std::nothrow) Factory(); if (!factory) return E_OUTOFMEMORY; auto hr = factory->QueryInterface(iid, out); factory->Release(); return hr;
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects == 0 ? S_OK : S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) { if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(module); return TRUE; }
