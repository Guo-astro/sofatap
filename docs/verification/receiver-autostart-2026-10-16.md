# Receiver startup and background lifetime

Desktop 0.7.3 beta.1 and Android/Google TV 0.1.2 beta.1 add native startup controls. This is receiver maintenance; the iPhone protocol and app are unchanged.

## Behavior

- Windows: first normal launch installs a per-user Startup shortcut; a native checkbox disables it. Login launch stays in the notification area. Closing the window keeps the receiver running; tray Quit stops it. Reopening activates the existing receiver. Windows Startup Apps remains authoritative.
- macOS: first normal packaged launch registers `SMAppService.mainApp`. The native checkbox reports enabled, pending approval or failure. A later OS disable is not undone. Login launch stays in the background; closing the window preserves the service, Dock reopening restores it and Quit stops it.
- Linux: first normal launch writes a per-user XDG autostart entry. The native checkbox and external deletion/disable are respected. Startup minimizes; normal close minimizes, explicit Quit stops. A private local activation socket prevents duplicate receivers.
- Android/Google TV: first visible launch enables Start with TV and starts the receiver. Boot restores only the foreground listener, without opening an Activity. Package updates resume only a requested running session. Stop affects this run; turning off Start with TV prevents future boot starts. System policy may block starts and force-stop is never bypassed.

A computer must have a logged-in desktop; startup is not pre-login/PIN control. TV standby wake and HDMI power control are not added. There is no evidence that HDMI switching itself terminates the receiver. The previous Windows and Mac close-window paths did stop their owned backends, and this change fixes that confirmed lifetime gap.

## Verification boundary

Regression checks use fake stores or private temporary startup directories. Shared-Mac fixtures are rendered offscreen without a receiver or input target. Linux graphical lifecycle tests use their own authenticated Xvfb. Android uses a headless emulator. No physical display arrangement, shared Mac login item, user session, household TV or real input target is changed by these tests.

The household Sony and Xiaomi TVs have **not** been field-tested. Actual cold boot, vendor power policy, Mac logout/login, Windows sign-in and physical HDMI switching remain hardware acceptance work. Existing permissions (macOS Accessibility, Wayland portal and TV Accessibility) remain required; startup does not grant or bypass them.

## Recorded checks

- Windows: 97 portable startup/protocol checks and native/preview compilation passed locally. Real COM shortcut checks run on Windows CI with temporary folders.
- macOS: 27 injected login-item checks, 35 launch-isolation checks, arm64/x64 compilation, 12 offscreen view fixtures and four QR rendering checks passed. Both release architectures use CHEKUSU Developer ID signing and require completed Apple notarization, stapling and Gatekeeper assessment before publication.
- Linux: all 15 startup/instance tests (including Gio Exec argument round-trip) passed on Linux CI; protocol, worker/portal checks and private-Xvfb GTK close/quit/opt-out checks passed. On macOS the Gio test is correctly skipped.
- Android: 73 JVM tests, 10 headless API 31 TV instrumentation tests and lint (zero errors; 22 existing warnings) passed. Actual emulator reboot verified that enabled startup resumes the foreground service while the TV launcher remains visible, and disabled startup stays stopped. The new APK has the same signing certificate as 0.1.1 beta.1 and a higher version code (3), so it can cover-install that release. A paired physical-TV reboot was not tested.
- TestFlight: at 2026-10-16 11:55 UTC, 1.0 (18) was the latest upload, VALID, beta-review APPROVED and IN_BETA_TESTING in both internal and public groups. The public invitation accepted testers, with a 10,000-person limit. This receiver release does not alter iPhone code.

## Platform references

- [Windows Startup settings and per-user Startup folder](https://support.microsoft.com/en-gb/windows/experience/startup-boot/configure-startup-applications-in-windows)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [XDG autostart specification](https://specifications.freedesktop.org/autostart/latest/) and [Exec escaping](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html)
- [Android foreground service background-start exemptions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) and [foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types#connected-device)
