# Windows account passwords, Hello PIN and Sofatap

Research checkpoint: 2026-10-11. This explains the current development boundary;
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

## What the current code does

The 0.6.0 optional login component accepts **account passwords only**. Its local
account and personal Microsoft account branches use the corresponding Windows
authentication serialization. A numeric string can also be an account password,
so credential type must never be guessed from character content. A user's Hello
PIN must not be submitted to the password branch as though it were a password.
[Microsoft packing API](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credpackauthenticationbufferw).

This path can coexist with a user's ordinary PIN sign-in when an actual account
password exists and Windows permits password sign-in. A passwordless Microsoft
account or Hello-only sign-in setting may prevent it. Sofatap does not change
those settings. Local registry configuration alone does not establish whether
a cloud account currently has a password.

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

Keep account-password support explicitly labeled experimental, keep PIN marked
unsupported until validated, and preserve the user's current account and native
Windows sign-in methods. Do not install a password-only pilot as if it satisfies
a PIN-only acceptance test. Neither a PIN nor an account password belongs in
Codex, diagnostics, source, Yobiru messages or a test script.
