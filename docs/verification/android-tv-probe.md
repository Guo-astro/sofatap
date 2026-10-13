# Android/Google TV receiver prototype verification

Date: October 13, 2026. Scope: the first **free manual-control** receiver and native iPhone adapter. This is an installable development prototype, not a store release or a statement that a physical TV model is supported.

## Implemented

- Native landscape TV pairing/status/permission UI in English, Simplified Chinese and Japanese, using the existing Sofatap logo and mint palette. No WebView or browser pairing.
- Explicit in-app accessibility disclosure and a link to Android's permission settings. The receiver cannot approve its own permission or replace-pairing controls remotely.
- Five-minute one-use QR enrollment, persistent replacement credential, one controller, revocation, private-IPv4 peers, pinned TLS and bounded authenticated WebSocket messages. Visible QR credentials are protected from capture.
- A non-intercepting accessibility overlay pointer, conditional node activation and bounded page scrolling. Back/Home and accessibility focus navigation are separate actions. Text, dictation, drag, right-click and raw mouse injection are unavailable and disabled in the TV phone mode.
- Separate iPhone pairing storage and target selection; bounded, acknowledged command delivery without automatic action replay. Desktop editing and the LG adapter remain separate.

## Results

| Check | Result | Boundary |
| --- | --- | --- |
| Android debug APK and instrumentation APK | Built using JDK 17, Gradle 8.13, AGP 8.13.0, SDK 36 | Development signing only; not an AAB/Play submission |
| Gradle JVM tests | 66 passed, zero failures/errors | Pairing, parser, frame bounds, real TLS server, certificate profile, hit testing, pointer geometry and scrolling; input is fake |
| Android lint | Zero errors; warnings reviewed | Version updates, TV orientation, debug fixture labels, old-API attributes, backup advice and an unused dependency trust-manager class are warnings, not a clean-warning claim |
| Swift Android TV protocol/controller | 60 checks passed | Injected transport/storage; does not itself prove device interaction |
| Swift desktop target/drag checks | 33 checks passed | No desktop input |
| Existing LG controller checks | 74 checks passed | Separate adapter, no physical TV |
| Native iPhone arm64 compile | Passed | Unprovisioned build; no installation or physical iPhone test in this milestone |
| Real Swift ↔ Java TLS/WebSocket integration | Passed | Production Swift controller/socket/pinning and production Java server/certificate; in-memory credential store and counting input driver |
| Android TV runtime instrumentation | 4 tests passed | Private headless API 31 Android TV emulator; actual Android Keystore, JSON provider, native UI and accessibility service |

The real cross-language test initially caught a certificate interoperability defect: the original leaf lacked an explicit `serverAuth` extended key usage. The receiver now generates a P-256/SHA-256 server leaf with exact IP SANs, digital-signature key usage and a bounded validity period. The Swift client still checks the exact pin, host and certificate validity; it does not accept arbitrary certificates.

Cross-language verification includes wrong-pin and wrong-credential rejection, initial enrollment/credential replacement, ordered move/click/scroll/Back/Home acknowledgements, heartbeat permission changes, reconnect using saved credentials, consumed QR rejection, rejection of a second controller, and no action replay. Server tests also cover stalled TLS clients, malformed/fragmented/oversized frames, duplicate command IDs and revocation while an action is queued.

## Actual Android runtime observations

The dedicated emulator ran without a desktop window or audio. It did not change the Mac display layout or send mouse/keyboard events to the shared desktop. ADB commands were explicitly addressed to that emulator; no household TV was contacted.

Runtime tests established:

1. The Android JSON tokenizer cannot admit comments, invalid escapes, duplicate fields, alternate quoting or a leading BOM through the strict wire parser.
2. Android Keystore-backed encrypted identity persists across receiver reconstruction, preserves the certificate and credential hash, and does not store a plaintext private key or credential hash in its file.
3. The native receiver shows pairing with screenshot protection while credentials are visible; the stopped screen is capturable and contains no pairing credential.
4. The real accessibility service moved its overlay to a debug fixture button and a click increased the button's counter. Scrolling changed the fixture's actual scroll offset. Disconnect removed the overlay; revoking accessibility stopped further input and did not increase the counter.

The fixture is a separate screen from the pairing UI, but belongs to the debug application. It is non-exported and absent from release builds. This is **not third-party app coverage**. The Google API 31 TV emulator advertises touchscreen/faketouch features even with a no-touch AVD profile, so these results do not qualify no-touch OEM firmware. No gesture injection API is used in the implementation.

The test runner temporarily sets and restores the disposable emulator's accessibility configuration. Consumers must enable the service themselves using their TV remote. The automated setup is not a consumer workaround for missing permissions.

## Pending before compatibility or store claims

- Physical Sony X95L and Xiaomi TV Max 85 2025 model/region/firmware qualification, including the actual touchscreen/faketouch feature set.
- Pairing from a physical iPhone camera, the normal on-TV permission flow, reconnection/revocation, screen-off and lock behavior on each intended firmware.
- Visible click and scroll outcomes in the launcher, Settings and representative third-party apps. `framework_accepted` is only an action acknowledgement; it is not a verified screen change.
- Discovery, TV text input/IME, standby wake, drag and right-click. No general raw mouse control is claimed.
- Release signing, complete TV store assets, Accessibility API declaration/review and store release acceptance.

Paid voice-goal automation is not integrated into this prototype. Its development remains after free manual TV acceptance.

## Reproduce

See [Android build and emulator instructions](../../android/README.md). CI builds both Android APKs, executes the JVM suite and lint, and saves the development APK/reports. Physical-device tests and emulator runtime execution are not silently inferred from CI compilation.
