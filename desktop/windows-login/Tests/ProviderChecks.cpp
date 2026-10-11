// Isolated compiled fixture: no registration, service connection, desktop input or real credentials.
#define SOFATAP_PROVIDER_TEST
#include "../Provider/Provider.cpp"
#include <cstdio>
#include <cstdlib>
static int checks = 0;
static void Check(bool value) { ++checks; if (!value) { std::fprintf(stderr, "provider check %d failed\n", checks); std::exit(1); } }
int wmain() {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    Check(DllCanUnloadNow() == S_OK);
    IClassFactory* factory = nullptr;
    Check(SUCCEEDED(DllGetClassObject(CLSID_Sofatap, IID_PPV_ARGS(&factory))));
    ICredentialProvider* provider = nullptr;
    Check(SUCCEEDED(factory->CreateInstance(nullptr, IID_PPV_ARGS(&provider)))); factory->Release();
    Check(provider->SetUsageScenario(CPUS_CREDUI, 0) == E_NOTIMPL);
    DWORD count = 99, defaultIndex = 99; BOOL automatic = TRUE;
    Check(SUCCEEDED(provider->GetCredentialCount(&count, &defaultIndex, &automatic)) && count == 0 && !automatic);
    Check(SUCCEEDED(provider->SetUsageScenario(CPUS_LOGON, 0)));
    Check(SUCCEEDED(provider->GetCredentialCount(&count, &defaultIndex, &automatic)) && count == 1 && !automatic && defaultIndex == CREDENTIAL_PROVIDER_NO_DEFAULT);
    ICredentialProviderCredential* credential = nullptr;
    Check(SUCCEEDED(provider->GetCredentialAt(0, &credential)));
    provider->Release(); // Credential must keep its owner alive independently.
    ICredentialProviderCredential2* v2 = nullptr; Check(SUCCEEDED(credential->QueryInterface(IID_PPV_ARGS(&v2))));
    PWSTR sid = nullptr; Check(SUCCEEDED(v2->GetUserSid(&sid)) && wcscmp(sid, L"S-1-5-21-1-2-3-1001") == 0); CoTaskMemFree(sid);
    CREDENTIAL_PROVIDER_GET_SERIALIZATION_RESPONSE response{}; CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION serialization{};
    PWSTR text = nullptr; CREDENTIAL_PROVIDER_STATUS_ICON icon{};
    Check(SUCCEEDED(v2->GetSerialization(&response, &serialization, &text, &icon)) && response == CPGSR_NO_CREDENTIAL_NOT_FINISHED && serialization.rgbSerialization == nullptr);
    Check(SUCCEEDED(v2->SetDeselected()));
    v2->Release(); credential->Release();
    Check(DllCanUnloadNow() == S_OK);
    // Packing synthetic MSA credentials invokes no logon and changes no account.
    std::wstring fakePassword = L"Sofatap fixture only - never an account password";
    WipeString passwordWipe{fakePassword};
    CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION packed{};
    Check(SUCCEEDED(SerializeMicrosoft(L"MicrosoftAccount\\sofatap-fixture@example.invalid", fakePassword, &packed)));
    Check(packed.cbSerialization > 0 && packed.rgbSerialization != nullptr && packed.clsidCredentialProvider == CLSID_Sofatap);
    SecureZeroMemory(packed.rgbSerialization, packed.cbSerialization); CoTaskMemFree(packed.rgbSerialization);
    CoUninitialize(); std::printf("%d native provider lifetime/COM checks passed; no login performed.\n", checks); return 0;
}
