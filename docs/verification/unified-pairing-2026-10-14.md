# Unified Add Device flow — October 14, 2026

The iPhone 1.0 (15) implementation replaces the computer/TV-type chooser with one **Scan QR Code** entry. The camera opens above the platform information. Scanned, pasted and system-opened pairing links use the same strict router. After an authenticated connection, a separate naming step lets the user keep the receiver name or save a local alias; My Devices retains its rename action.

Mac, Windows and Linux use the desktop receiver protocol. Android TV / Google TV uses its own bootstrap protocol, selected by the code. LG webOS still uses manual IP entry and TV authorization from a clearly labeled link; it has no Sofatap QR receiver. Both TV adapters remain experimental, with no hardware-qualified TV model or third-party app.

## Software checks

| Scope | Result |
| --- | --- |
| Unified QR routing, metadata and legacy compatibility | 73 passed |
| Existing desktop pairing parser | 24 passed |
| Saved-device library and migration | 32 passed |
| Cancellation, failed-save retry, duplicate bootstrap and scanner guards | 28 passed |
| Android TV iPhone controller | 63 passed |
| Explicit text input controller after pairing changes | 47 passed |
| Windows native protocol/lifecycle | 82 passed |
| Shared receiver host | 384 passed |
| macOS native protocol | 67 passed |
| Linux native protocol | 13 passed |
| Android receiver JVM tests | 69 passed; APK build and lint passed (0 errors, 15 warnings) |
| Localization | 12 locales, 309 interface strings and 5 permission descriptions each |
| Final native iPhone simulator compile | Passed |

The connection regressions run production ControllerModel with an injected recording transport and in-memory storage. They reproduce a saved device A followed by a failed save of candidate B, and verify that retry saves/connects B rather than reconnecting A. Cancellation after timeout or background disconnection remains paused on foreground. Android duplicate links, including changed query order or metadata, preserve the pending or successful attempt. A previously attempted bootstrap is not replayed after resetting the scanner; the scanner remains able to accept a fresh QR. Authentication remains distinct from merely decoding a code.

Receiver tests ran against source snapshots verified by SHA-256. The macOS/Linux/Windows protocol checks and host tests used fake or recording input, without a desktop input target. The Android checks did not launch a TV device.

## Layout review

Native screenshots use two dedicated headless iOS 26.2 simulators: iPhone SE (3rd generation) and iPhone 17 Pro. Camera and successful-device previews are explicitly simulator fixtures; they use no real QR, credential or camera feed. Chinese, English and Arabic layouts cover the scanning and naming surfaces, including the small-screen first viewport and RTL presentation. Primary buttons use dark text on the pale mint background.

- [Chinese scan page](../images/unified-pairing-20261014/zh-scan.png)
- [Chinese naming step on the small screen](../images/unified-pairing-20261014/zh-name-small.png)
- [English scan page](../images/unified-pairing-20261014/en-scan.png)
- [Arabic scan page](../images/unified-pairing-20261014/ar-scan.png)

These are rendering checks, not optical QR acceptance or physical phone-to-receiver tests. The installed idb could inspect simulator accessibility but could not inject touches because its expected SimulatorKit framework was unavailable; system frameworks were not modified. Final TestFlight installation, camera permission recovery, optical scanning, real renaming and real device switching remain physical acceptance items. No shared-Mac foreground window, physical display arrangement or user input target was changed. Real receiver input must still use verified Yomado isolation.

## QR compatibility and distribution boundary

New receiver source adds optional `platform` and `name` fields. Metadata is an untrusted display hint: it neither authenticates a receiver nor changes its capabilities. The phone still verifies the certificate pin and pairing credential before offering the completed-device naming step. Aliases stay on this iPhone.

Build 15 accepts the existing four-field codes from released desktop receiver 0.7.0 beta.1. The new six-field receiver codes require iPhone build 15 or newer; builds 14 and earlier cannot parse them. This change does not publish new receiver binaries. Keep the existing receiver installation until an updated package is released, and update the phone first when adopting the new receiver source.

TestFlight processing, internal distribution and external review are reported separately in the release record. No App Store approval or physical TV qualification follows from these software checks.
