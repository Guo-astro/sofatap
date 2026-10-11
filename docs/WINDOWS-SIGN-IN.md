# Windows account passwords, Hello PIN and Sofatap

Research checkpoint: 2026-10-12. This explains the current development boundary;
it does not claim that Sofatap can submit a Windows Hello PIN.

## Account and sign-in method are different

A Windows profile can be connected to a personal Microsoft account while using
a numeric Windows Hello PIN for daily sign-in. Using a PIN does not make that
profile a local-only account, and does not establish that its Microsoft account
password was removed. Windows also supports local account profiles.
[Microsoft sign-in options](https://support.microsoft.com/en-us/accounts-billing/security/sign-in-options-in-windows).

An account password authenticates the local or online account. A Hello PIN
unlocks device-bound authentication material on that particular PC; it is not
the online account password. TPM hardware commonly protects that material,
although Windows Hello also has configurations without a TPM. The phone's
Face ID verifies the person locally on the phone. It cannot by itself declare
the Windows session authenticated.
[Microsoft's PIN explanation](https://learn.microsoft.com/en-us/windows/security/identity-protection/hello-for-business/hello-faq).

## Current product direction

Sofatap targets the existing native Windows Hello PIN interface. The user should
be able to control the lock-screen pointer and enter a PIN manually from iOS;
optional saving and Face ID authorization can then automate the same entry.
No Microsoft account password is requested. Both modes require the same
secure-desktop input bridge and must be verified separately from normal desktop
control.

The earlier account-password Credential Provider experiment is retired. Its
password serialization cannot accept a Hello PIN by renaming a field. Ordinary
receiver discovery and iPhone use of that protocol are disabled. Historical
source and tests are not a supported installation path.

## A separate PIN path needs validation

Entering a PIN into Windows' own PIN sign-in interface is a different approach
from submitting account-password credentials. This research found no documented
public API that simply converts an existing Windows Hello PIN into the password
blob used by Sofatap's current Credential Provider.

It would also be incorrect to conclude that a PIN can never be entered via any
remote input mechanism. Microsoft distinguishes trusted local input sources
from untrusted injection. Its January 2026 hardening restricts remote virtual
keyboards and automated credential input, and recommends supported
authentication interfaces. Administrator-level injection is described as a
temporary mitigation, not a durable product design. A secure-desktop input
proposal needs its own Windows implementation, exact-version tests, permissions,
target verification, recovery path and threat review before any compatibility
claim. Merely running the normal receiver as administrator proves none of that.
[Microsoft credential-input hardening](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/01/new-behavior-restricting-certain-applications-to-autofill-credentials-introduced-by-the-windows-janu).

The old Windows Hello Companion Device Framework resembles phone-approved
unlocking, but Microsoft deprecated its API in Windows 10 version 2004. It is
not a suitable new dependency for this product. Bluetooth Dynamic Lock is also
not evidence of a supported general-purpose phone unlock API.
[Companion framework status](https://learn.microsoft.com/en-us/windows/uwp/security/companion-device-unlock).

## Product consequence

Microsoft's own PowerToys documents a SYSTEM service mode that can control the
lock screen, providing a concrete reference for a privileged session helper.
That is evidence for the architecture, not proof of Sofatap phone input or PIN
acceptance on a particular Windows build. The first diagnostic is deliberately
a one-shot pointer probe with no network, keys, clicks or real credentials.
[PowerToys documentation](https://learn.microsoft.com/en-us/windows/powertoys/mouse-without-borders).

Keep the user's existing account, PIN and native sign-in methods. Treat pointer
movement, key acceptance, actual PIN authentication, phone transport and
restart-before-first-login as separate acceptance gates. Manual iOS input is
still injected input on Windows, so it cannot be promised as a fallback before
the shared secure-desktop route works. See [current validation plan](FACE-ID-UNLOCK.md).
