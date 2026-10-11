# Sofatap 0.6.0 Face ID unlock: development verification

Date: 2026-10-11. iPhone source version: 0.6.0, build 9.

This record describes source/build checks, not successful Windows authentication.
No real computer password was used in automated tests.

| Check | Result |
| --- | --- |
| Host protocol and enrollment boundaries | 233 checks passed with recording/fake input |
| Ordinary receiver TLS/WebSocket transport | 58 dry-run checks passed; no desktop input |
| iOS unlock identity, provider binding and challenge parsing | 56 checks passed; no biometric prompt |
| Windows login broker concurrency, expiry, cancellation, session/generation, rate limits and restart | 34 checks passed with synthetic credentials |
| Windows login service .NET build on macOS | Passed; 0 warnings, 0 errors |
| iPhone device compilation and development signing | Passed with Xcode; no biometric or Windows sign-in acceptance implied |
| Native Windows provider compile and COM fixture | Pending Windows CI at this source checkpoint |
| Face ID / Keychain on physical iPhone | Pending |
| Real Windows local/Microsoft-account authentication | Pending |
| Installation, restart-before-login, fallback and uninstall | Pending |

The optional service and provider underwent a separate static review. Identified
protocol mismatches, credential lifetime, identity-change and installation-path
issues were fixed before this checkpoint. This is not a complete security audit
or a substitute for login/recovery testing.

Follow the [Windows component guide](../../desktop/windows-login/README.md) and
[device acceptance checklist](../ACCEPTANCE.md). The installer is explicitly a
development pilot; release signing and package-manifest verification remain
unfinished. Normal receiver releases do not install it automatically.
