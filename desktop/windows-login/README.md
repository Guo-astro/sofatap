# Sofatap optional Windows phone sign-in — development pilot

This source adds phone-initiated Windows **local or personal Microsoft account password** authentication while the console is locked. The iPhone holds the saved password behind Face ID; the Windows service only handles an ephemeral submission through a V2 Credential Provider. It does not change normal mouse input or replace Windows sign-in methods. Read [the protocol and security boundaries](PROTOCOL.md).

This component is **not a production-ready signed installer**. C++ compilation and deterministic tests do not prove lock-screen, boot-login or recovery acceptance. Do not install a pilot on a computer without an independently usable Windows sign-in method and an approved recovery plan.

## Build and checks

On Windows x64 with .NET 10 and Visual Studio C++ tools:

```powershell
dotnet run --project desktop/windows-login/Tests/Sofatap.Login.Tests.csproj -c Release
dotnet publish desktop/windows-login/Service/Sofatap.Login.Service.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o artifacts/windows-login/Service
cmake -S desktop/windows-login/Provider -B artifacts/windows-login/provider-build -A x64
cmake --build artifacts/windows-login/provider-build --config Release
ctest --test-dir artifacts/windows-login/provider-build -C Release --output-on-failure
```

The C++ fixture uses synthetic account metadata and never registers a provider or sends input. Portable broker checks work on other hosts too. Do not ship the fixture executable.

## Explicit installation pilot

First sign in locally as the local or personal Microsoft profile to enroll, start the normal Sofatap receiver, and retain a working physical keyboard or another independent built-in Windows sign-in option. Obtain the existing receiver certificate fingerprint from its local trusted identity; the provisioner verifies it against its CurrentUser DPAPI profile. No password belongs in a command, Codex prompt, GitHub issue, log or Yobiru message.

From an elevated **same-account** 64-bit PowerShell, after approving this optional system component:

```powershell
.\desktop\windows-login\Install.ps1 -ServiceDirectory .\artifacts\windows-login\Service -ProviderDll .\artifacts\windows-login\provider-build\Release\SofatapLoginProvider.dll -ReceiverFingerprint '<existing receiver SHA256>' -AllowUnsignedPilot
```

This installer deliberately requires `-AllowUnsignedPilot`; release signing and complete package-manifest verification remain unfinished. Only provide locally trusted build directories. It refuses existing installs/enrollment instead of overwriting them, records original provider IDs privately, protects service files/configuration, creates a Private/LocalSubnet firewall rule for TCP 53320, starts a narrow LocalSystem service, and registers only its own provider GUID. It does not modify public-network classification, remove firewall blocks, enable remote desktop, add a credential-provider filter, or disable built-in login. Installation may fail closed if profile directories are busy or not trustworthy.

Reopen the normal receiver while unlocked, then explicitly enable saved-password/Face ID access on the paired iPhone. Subsequent lock-screen connection uses the separately pinned login service. Test only after confirming the fallback sign-in works. Initial support includes local and personal Microsoft profiles with a usable password; domain/Entra, passwordless accounts, Windows Hello PIN and BitLocker/preboot are unsupported. Microsoft account support still needs explicit real-device acceptance. A startup/login user session, display sleep and hardware sleep are distinct states.

## Recovery / removal

Use ordinary Windows sign-in, then run the copied administrator uninstaller at `%ProgramFiles%\Chekusu\Sofatap Login\Uninstall.ps1` (or this source copy). It unregisters only Sofatap's provider before stopping/deleting the service and firewall rule. Default removal deletes its private enrollment; `-KeepEnrollmentBackup` retains the protected service data for an explicitly planned recovery. It never deletes the ordinary receiver's pairing profile. Forget the saved password on the iPhone separately.

If Windows has a loaded provider DLL, uninstall may leave its installation directory until restart; provider registration and service removal are reported separately. Never delete unrelated provider keys. Recovery technicians can identify this component by service `SofatapLogin`, provider/COM GUID `{F8F3819A-9AB1-4C6F-86D5-90B57D9A42C7}`, and settings key `HKLM\SOFTWARE\Chekusu\SofatapLogin`. Recovery involving Windows safe mode or offline registry editing must use a verified recovery path for that machine; do not improvise on a user's only login device.

References: [Credential Providers](https://learn.microsoft.com/en-us/windows/win32/secauthn/credential-providers-in-windows), [January 2026 credential-input hardening](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/01/new-behavior-restricting-certain-applications-to-autofill-credentials-introduced-by-the-windows-janu), [service session isolation](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services).
