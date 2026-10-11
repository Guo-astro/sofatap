# Retired account-password pilot

Historical design only. On 2026-10-12 the product direction changed to native Windows Hello PIN input. Ordinary receiver discovery and iPhone enrollment/use are disabled. This is not an installation or release recommendation. The prior component never passed physical authentication acceptance.

# Face ID and Windows sign-in

This is an **experimental, optional component under development**. The normal
receiver and published alpha downloads do not gain lock-screen access merely by
pairing. Real Face ID, Windows authentication, installation/recovery and
phone-to-TV acceptance must pass before this feature is represented as working
on a user's device. Do not install an unvalidated credential provider as part of
a routine receiver update.

Build and optional installation/recovery instructions are in the [Windows login component guide](../../desktop/windows-login/README.md).

## Intended experience

After installing the Windows login component with administrator approval, pair
the iPhone with the normal native receiver while the computer is unlocked. In
Sofatap's device settings, explicitly enable Face ID unlock and enter the
Windows local or personal Microsoft account password in a secure field. Each later unlock requires a new
Face ID verification. Windows validates the supplied credential; successful
transport is never displayed as successful Windows authentication.

The password is stored only in the iPhone's Keychain with
`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `biometryCurrentSet`.
It is not synchronized to iCloud, and changing enrolled biometrics invalidates
access. There is no device-passcode fallback for releasing the saved computer
password. The normal Windows sign-in options remain available.

Face ID authorizes local Keychain access. It does not turn the phone's face
recognition into Windows Hello, and the login service does not receive or verify
a claim of biometric authentication. The computer still checks the Windows
password through its normal authentication authority.

For the difference between an account password and the numeric PIN used at Windows sign-in, see [Windows sign-in research](../WINDOWS-SIGN-IN.md). The current component cannot use a Hello PIN as an account password.

## Boundaries

| Situation | Initial scope |
| --- | --- |
| Windows local or personal Microsoft account with password sign-in available | Target of this component; physical acceptance pending |
| Hello-only sign-in policy or a passwordless Microsoft account | May prevent password sign-in; Sofatap does not modify these settings |
| Domain/Entra account or Hello PIN | Unsupported |
| UAC prompts or arbitrary remote desktop sessions | Not an unlock target |
| Sleeping or powered-off computer | Requires a separate wake mechanism and network availability |
| BitLocker/UEFI pre-boot screen | Unsupported; Windows and the login service are not running yet |
| macOS and Linux lock/login screens | Separate platform work; not implemented by this Windows component |

The installer distinguishes local and personal Microsoft accounts using Windows
identity metadata. Internet-connected identity alone is not proof of a Microsoft
account. For personal Microsoft accounts, the Credential Provider obtains the
qualified identity from Windows' matching user SID and uses the official online
identity serialization path. It does not try the local-account path or a Hello
PIN as a fallback. The phone shows the account type and local Windows profile
alias; an email address or account name supplied by the phone cannot choose the
Windows authentication target.

## Separate trust and transport

The ordinary controller keeps its existing `53319` WebSocket endpoint and
user-session input restrictions. An explicitly installed Windows service uses
a separate pinned TLS identity, unlock token and port `53320`. The normal
receiver advertises that capability only to an authenticated controller on a
ready Windows desktop. It is excluded from QR codes, native UI pipe output,
dry-run mode and other platforms.

The phone derives the unlock host from the original pairing. A capability
cannot supply a redirect or another host. Enrollment binds the original
receiver certificate, independent login certificate, computer identity and
fixed Windows account SID. The cached service capability can be used at Windows
sign-in while the ordinary per-user receiver is absent. Changed identities
require explicit enrollment again; they never silently inherit a stored
password.

The Windows service fixes the Windows account at installation. A network request
cannot select another user, domain, process, desktop or command. Password
requests use expiring, single-use challenges bound to the active console and
login-provider instance. Canceled, expired, uncertain and failed attempts do
not automatically replay. A new user action and Face ID verification are needed
for another attempt.

Passwords are not sent through Codex, voice recognition, ordinary text input,
clipboard, URLs, diagnostics or server-side persistent storage. Temporary
request/credential buffers have bounded lifetimes and are cleared where the
platform permits; managed-memory clearing is not a guarantee that every
transient runtime copy can be erased immediately.

This design assumes the explicitly enrolled Windows installation and iPhone
remain trusted. It does not protect a password from a compromised target
computer that the user has authorized to receive that password.

## Verification required before deployment

- Test protocol state transitions without real credentials: different identity,
  wrong token, expired/used challenge, concurrent submissions, malformed and
  oversized requests, session change, provider/service restart and lost reply.
- Verify a canceled Face ID prompt, unavailable or changed biometrics,
  backgrounding, identity changes and removing enrollment never send a password.
- In a recoverable Windows test environment, verify wrong-password rejection,
  correct-password login/unlock, the same console session, and native fallback
  sign-in if the optional service/provider is stopped, broken or uninstalled.
- Confirm actual iPhone Face ID, Keychain behavior, local-network permissions
  and end-to-end authentication. A simulator, HTTP 202, provider serialization
  or a running service is not a successful sign-in result.
- Confirm existing mouse, voice, keyboard, pairing and other desktop platforms
  retain their prior behavior.

## References

- [Apple: Keychain access control](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags)
- [Apple: device-only, passcode-protected storage](https://developer.apple.com/documentation/security/ksecattraccessiblewhenpasscodesetthisdeviceonly)
- [Microsoft: online identity credential serialization](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credpackauthenticationbufferw)
- [Microsoft: connected identity metadata](https://learn.microsoft.com/en-us/windows/win32/api/lmaccess/ns-lmaccess-user_info_24)
- [Microsoft: credential providers and native recovery methods](https://learn.microsoft.com/en-us/windows/win32/secauthn/credential-providers-in-windows)
- [Microsoft: credential input hardening in 2026](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/01/new-behavior-restricting-certain-applications-to-autofill-credentials-introduced-by-the-windows-janu)
