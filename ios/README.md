# Sofa Tap iPhone controller

Native SwiftUI app, iOS 17+, no third-party libraries. Version 0.3.0, build 4. Open `SofaTap.xcodeproj` in Xcode. Select your company's Apple development team and a connected iPhone to install. The repository contains no provisioning profiles or developer account identifiers. `project.yml` is the reproducible XcodeGen source; use `xcodegen generate --spec ios/project.yml` from the repository root after changing it.

The receiver's QR code or full `sofatap://pair?...` URI supplies the host, port, secret and leaf certificate fingerprint. Pairing credentials are stored in Keychain with `WhenUnlockedThisDeviceOnly`. Native WSS trusts only that exact host, port and certificate; redirects are rejected. Local-network ATS permission is scoped with `NSAllowsLocalNetworking`; there is no global ATS exemption.

Mouse mode sends relative moves from a touchpad or a portrait, screen-facing-user gyro clutch. Hold to move, release to recenter. Movement is coalesced at 45 Hz with bounded ACK backpressure and old samples dropped. A separate scroll strip and hold-to-drag button are available in touchpad mode. The receiver releases all held buttons independently on disconnect or idle timeout.

Text uses an ordinary `UITextView` so iOS keyboards, dictation and Typeless can compose normally. Only the explicit send button commits the complete Unicode draft; Enter is a separate button. The draft stays local until send, persists in the app's local UserDefaults, and remains after success or failure. Success means the receiver submitted input events to the system; macOS provides no application delivery acknowledgement. Pending/uncertain/success markers survive process termination, and uncertain or unchanged accepted text requires explicit review before a manual resend. Nothing is replayed on reconnect. Local draft data can be removed using **清空草稿**.

Launching with `--demo` displays a clearly labelled offline interface and never connects to a computer. A receiver with `inputAvailable=false` disables controls. New receivers distinguish dry-run, missing Mac Accessibility permission and an unavailable desktop; old receivers show a generic unavailable state. Heartbeats refresh this state. Select All sends Command+A to Mac and Control+A to Windows.

## Privacy manifest

`SofaTap/PrivacyInfo.xcprivacy` declares `UserDefaults` (`CA92.1`) for this app's local draft and delivery markers, and system boot time (`35F9.1`) to discard motion samples older than 150 ms. The uptime value and motion timestamps are not transmitted. XcodeGen includes the manifest in the app's resources; verify it is present in the final `.app` before distribution. See Apple's [required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

This declaration covers required-reason APIs, not the separate App Store privacy answers or a privacy policy. The current client sends control events and explicitly submitted text directly to the paired computer, keeps credentials in Keychain, and stores the draft locally. It does not record microphone audio; dictation and third-party keyboards have their own data handling. Review the final app, companion receiver and any future SDKs against Apple's [data collection definition](https://developer.apple.com/app-store/app-privacy-details/#data-collection) before completing distribution metadata.

## Build fallback for mismatched Xcode SDK/runtime installations

Normal Xcode project builds are preferred. If `xcodebuild` cannot select a destination because the installed SDK is newer than available simulator runtimes, the following compiles and links the exact same native source directly against the selected SDK without installing anything or altering Xcode:

```sh
./ios/scripts/build-manual.sh simulator
./ios/scripts/build-manual.sh device
```

The first prints an adhoc signed simulator `.app` path in a temporary staging directory; install it with `xcrun simctl install <simulator-id> <app-path>`, then use `xcrun simctl launch <simulator-id> com.chekusu.sofatap --demo`. Its synthetic `SIMULATOR0` app identity in `Simulator.entitlements` enables the native simulator Keychain through Xcode-style simulated Mach-O entitlement sections; the macOS host code signature has no restricted iOS entitlements. This identity is not an Apple development team and is never used for physical signing. The second prints an unprovisioned ARM64 device `.app`, which proves device compilation/linking and requires normal Xcode development signing for installation. Staging outside Documents avoids FileProvider metadata interfering with codesigning.

Simulator compile, UI and TLS checks do not verify real iPhone LAN permissions, camera scanning, physical gyro feel, Typeless dictation or actual Windows or Mac input injection. Those need the physical iPhone and interactive desktop on each supported OS.
