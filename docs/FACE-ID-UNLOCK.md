# Windows PIN control and Face ID

Status: feasibility validation, not a released lock-screen feature. Sofatap does
not ask for a Microsoft account password. A Windows Hello PIN is never sent to
the retired account-password Credential Provider.

## Product target

1. Pair the iPhone and computer while the desktop is unlocked.
2. On the Windows lock screen, use the iPhone touchpad to position/click the
   pointer. One candidate manual fallback is clicking the built-in Windows
   On-Screen Keyboard from the sign-in screen. A dedicated secure phone keypad
   would be a separate input path to validate.
3. Optionally save that PIN on the iPhone and authorize each automatic entry
   with Face ID. Windows continues to validate the PIN through its native UI.

All modes need a verified secure-desktop input path. Phone-keyboard entry
does not avoid Windows' restrictions on injected keys. Clicking Windows' own
On-Screen Keyboard can avoid direct remote key injection, but acceptance of
our pointer clicks and the actual native PIN still requires testing. The current ordinary receiver runs in the user's desktop session and
cannot supply that path. Do not describe the manual fallback as working yet.

## Verification stages

| Stage | Required evidence |
| --- | --- |
| Read-only preflight | Exact Windows build, physical console state, helper session/integrity and input-desktop access; no personal account fields |
| One-shot pointer probe | SYSTEM worker in the existing locked physical console, Winlogon input desktop, accepted movement and observed coordinate change, conditional restoration and cleanup |
| Phone pointer control | Paired iPhone controls the visible Windows lock screen through a reviewed restricted input bridge |
| Human-entered PIN | User alone clicks Windows OSK keys with the phone pointer or uses a separately verified secure phone keypad; native PIN UI accepts it and the same physical console unlocks |
| Saved PIN + Face ID | Fresh Face ID releases only the target-bound PIN; cancellation, identity changes and uncertain delivery never replay it |
| Restart before first sign-in | Separate boot-login acceptance with Windows/network running; lock-after-login success does not prove this |

The [one-shot diagnostic](../desktop/windows-secure-input-probe/README.md) is only
for the pointer stage. Close the Windows On-Screen Keyboard before a diagnostic
move because its hover-to-type mode can enter keys without a click. The probe
rejects an OSK process in the target session. It has no network listener, screenshots, keyboard events,
clicks or credential input. Its build and synthetic tests do not prove PIN entry.

## Credential and input boundaries

A future manual PIN field must not use the ordinary persisted text draft,
clipboard, dictation, analytics, diagnostics or Codex. Manual entry need not be
saved. Optional saved PINs should use device-only Keychain storage protected by
current Face ID enrollment, bound to the explicitly paired computer and login
context. A change of identity must invalidate that binding.

The same submitted digits can be accepted by a PIN field without an explicit
Enter on some configurations. Do not probe a real PIN field with dummy digits,
read its value, or record its screenshot. Input delivery is not authentication
success; show success only after verifying the intended console is unlocked.

Keep system login options, desktop permissions and security policies intact.
An ordinary-user receiver cannot acquire secure-desktop access just by removing
its lock guard. Any privileged bridge needs a separate restricted protocol,
protected installation, pairing authorization, expiry, revocation and recovery.
The diagnostic deliberately exposes no such network bridge.

Sleeping or powered-off hardware needs separate wake support. BitLocker/UEFI
preboot is outside this Windows input path. macOS and Linux lock screens require
separate platform work.

## Retired experiment

The earlier local/Microsoft account-password design is [archived](archive/PASSWORD-LOGIN-PILOT.md).
Its capability is no longer advertised by the receiver, and iOS no longer offers
enrollment or use. Legacy source remains for history and review; it is not PIN
support and must not be installed as part of this validation. An existing saved
legacy credential can only be removed, not silently reused as a PIN.

## Primary references

- [Microsoft PowerToys: SYSTEM service can control the lock screen](https://learn.microsoft.com/en-us/windows/powertoys/mouse-without-borders)
- [Microsoft: input restrictions introduced in January 2026](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/01/new-behavior-restricting-certain-applications-to-autofill-credentials-introduced-by-the-windows-janu)
- [Microsoft: On-Screen Keyboard available from the sign-in screen](https://support.microsoft.com/en-au/accessibility/windows/use-the-on-screen-keyboard-osk-to-type)
- [Microsoft: SendInput and integrity boundaries](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)
- [Apple: Keychain access control](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags)
