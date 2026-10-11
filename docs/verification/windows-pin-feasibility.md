# Native Windows PIN route: feasibility checkpoint

Date: 2026-10-12. This report separates the requested user experience from
physical acceptance. No real PIN, account password or screen capture was used.

## Reference evidence

Microsoft documents that PowerToys Mouse Without Borders can control a lock
screen through its SYSTEM service. Windows also exposes its own On-Screen
Keyboard at the sign-in screen. These establish relevant implementation paths,
not acceptance of Sofatap's events on a particular Windows build.

- [PowerToys service mode](https://learn.microsoft.com/en-us/windows/powertoys/mouse-without-borders)
- [Windows sign-in On-Screen Keyboard](https://support.microsoft.com/en-au/accessibility/windows/use-the-on-screen-keyboard-osk-to-type)
- [January 2026 trusted-input changes](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/01/new-behavior-restricting-certain-applications-to-autofill-credentials-introduced-by-the-windows-janu)

## Read-only Windows preflight

On Windows 11 Pro x64 25H2, build 26200.9457, the ordinary receiver and agent
were in a disconnected user session with a medium-integrity, non-elevated token.
The physical console was a different locked, connected session with no signed-in
user reported. This does not establish that the intended user's PIN UI was
selected. Both OpenInputDesktop and OpenDesktop(Winlogon) in the agent session
returned access denied (5). No active-console desktop access was established.

No already-authorized elevated/SYSTEM execution channel was demonstrated.
Availability of UAC, Task Scheduler or runas does not itself grant that channel.
A proper local administrator launch is required before the temporary diagnostic
can run. The probe's lock-after-login phase also requires the physical user's
active console; it deliberately rejects disconnected and prelogin-only sessions.

The preflight changed no settings, sessions, receiver processes or system
components and sent no mouse or keyboard events.

## Display readiness is a separate gate

A later read-only check found the host awake and its locked-console display-off
timeout set to 60 seconds. A bounded 30-second display-required lease was
accepted in the disconnected agent session and then restored. That did not
establish physical HDMI output; human observation of the TV remained pending.
No persistent power setting, display layout or session state was changed.

## Source checks

- Ordinary receiver hello no longer advertises the retired password capability,
  including ready Windows status. Host checks: 239 passed on macOS with fake input.
- TLS/WebSocket dry-run checks: 58 passed.
- iOS password-retirement checks: 11 passed; legacy protocol checks: 56 passed.
- iOS simulator compilation passed. No device installation or Face ID test.
- The diagnostic policy fixture passed 51 checks on macOS without linking any
  Win32 input APIs. Native Windows compilation is a separate CI gate. Building it or passing that fixture never constitutes a live probe.

## Remaining acceptance gates

| Gate | Result at this checkpoint |
| --- | --- |
| Privileged active-console helper launch | Not performed |
| One-shot locked Winlogon pointer movement and restoration | Not performed |
| iPhone pointer/click bridge on lock screen | Not implemented or tested |
| Human-controlled Windows OSK PIN entry | Not performed |
| Dedicated secure phone PIN keypad | Not implemented or tested |
| Saved PIN and Face ID automatic entry | Not implemented or tested |
| Restart before first Windows sign-in | Separate, not tested |

Use the [diagnostic guide](../../desktop/windows-secure-input-probe/README.md)
for the bounded pointer experiment and [acceptance plan](../FACE-ID-UNLOCK.md)
for later stages. No real PIN belongs in an agent message, test command, log,
screenshot, persisted text draft or captured pointer/click trace.
