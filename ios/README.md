# Sofatap iPhone controller

Native SwiftUI app, iOS 17+, no third-party libraries. Development source: version 0.6.0, build 9. The published Windows/Mac 0.3.0 and Linux 0.4.0 receiver packages predate the new focus hints. Open `SofaTap.xcodeproj` in Xcode. Select your company's Apple development team and a connected iPhone to install. The repository contains no provisioning profiles or developer account identifiers. `project.yml` is the reproducible XcodeGen source; use `xcodegen generate --spec ios/project.yml` from the repository root after changing it.

The receiver's QR code or full `sofatap://pair?...` URI supplies the host, port, secret and leaf certificate fingerprint. Pairing credentials are stored in Keychain with `WhenUnlockedThisDeviceOnly`. Native WSS trusts only that exact host, port and certificate; redirects are rejected. Local-network ATS permission is scoped with `NSAllowsLocalNetworking`; there is no global ATS exemption.

The everyday interface is one large rounded touch surface, enclosing the logo and QR control at the top and the microphone and left-hand keyboard control at the bottom. Its resting state has icons only, with no instructional text or separate mouse arrow. Connection and recording states have accessible labels; tapping the logo opens status and gesture help, while the QR control opens pairing. A slowly flowing dot matrix fills the entire pad. Touch displaces and bends nearby dots, which settle back after release; single and double taps retain distinct ripples, and a hold strengthens the local deformation. Ambient animation pauses while inactive, detached or unable to control; Reduce Motion uses a static grid and simpler touch feedback. Effects do not mirror the desktop pointer or acknowledge desktop actions. Slide one finger to move, tap once for a left click, tap twice for a right click, hold still for 300 ms then move to drag, and slide two fingers to scroll. There is no mouse-mode selector or separate click/drag panel. Single clicks wait briefly for the double-tap decision; lifting, cancelling or leaving the app releases a drag. Movement is coalesced at 45 Hz with bounded ACK backpressure and old samples dropped. The receiver independently releases held buttons on disconnect or idle timeout. See the [interaction specification](../docs/INTERACTION.md).

Only when needed, text appears in an inline `UITextView` so iOS keyboards, system dictation and Typeless can compose normally. The bottom microphone starts Sofatap's own on-device recognition after an explicit tap and microphone/Speech permission; unsupported devices or languages fall back to keyboard input rather than cloud recognition. Tap again to stop, review the draft, then tap **Send**. Only Send commits the complete Unicode draft; no Enter or form-submit action is appended.

The draft stays local until send and persists in the app's local UserDefaults. Unsent and uncertain drafts remain available. A successful send remains as a receipt until a new composition starts from the microphone, keyboard or a newly focused writable desktop field; the previous sent text is not reused as its prefix. Success means the receiver submitted input events to the system, not that the target application saved them. Pending/uncertain/success markers survive process termination, and uncertain or unchanged accepted text requires explicit review before a manual resend. Nothing is replayed on reconnect. Local draft data can be removed using **清空草稿**.

A compatible receiver can automatically open the keyboard when a new supported native or web text field becomes editable and focused; an active drag finishes before the keyboard opens. Detection reads accessibility metadata, never field contents. It depends on each application's accessibility support and, on Linux, an optional AT-SPI bridge. Protected, read-only or unknown targets do not trigger the keyboard. Protected targets also disable Sofatap's microphone; the manual keyboard remains available. Dismissing the keyboard keeps it dismissed for that target. Old receivers still support manual input. See [focus detection and platform limits](../docs/TEXT-FOCUS.md).

Launching with `--demo` never connects to a computer. An amber play badge marks the offline preview; VoiceOver and the logo's status sheet identify it as a demo without adding text to the touch surface. A receiver with `inputAvailable=false` disables controls. New receivers distinguish dry-run, missing Mac Accessibility permission and an unavailable desktop; old receivers show a generic unavailable state. Heartbeats refresh this state. Backgrounding disconnects and stops capture; temporary inactivity for the app's own permission prompt pauses pointer input without cancelling the permission request.

## Privacy manifest

`SofaTap/PrivacyInfo.xcprivacy` declares `UserDefaults` (`CA92.1`) for this app's local draft and delivery markers, and system boot time (`35F9.1`) to discard motion samples older than 150 ms. The uptime value and motion timestamps are not transmitted. XcodeGen includes the manifest in the app's resources; verify it is present in the final `.app` before distribution. See Apple's [required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

This declaration covers required-reason APIs, not the separate App Store privacy answers or a privacy policy. The current client sends control events and explicitly submitted text directly to the paired computer, keeps credentials in Keychain, and stores the draft locally. After an explicit microphone tap and permission, it captures audio for supported on-device speech recognition. The app does not upload audio or send it to the paired computer, and it does not silently fall back to cloud recognition. Leaving the app or interrupting capture stops the microphone. Only the reviewed text is sent after the user taps Send. System dictation and third-party keyboards have their own data handling. Review the final app, companion receiver and any future SDKs against Apple's [data collection definition](https://developer.apple.com/app-store/app-privacy-details/#data-collection) before completing distribution metadata.

## Build fallback for mismatched Xcode SDK/runtime installations

Normal Xcode project builds are preferred. If `xcodebuild` cannot select a destination because the installed SDK is newer than available simulator runtimes, the following compiles and links the exact same native source directly against the selected SDK without installing anything or altering Xcode:

```sh
./ios/scripts/build-manual.sh simulator
./ios/scripts/build-manual.sh device
```

The first prints an adhoc signed simulator `.app` path in a temporary staging directory; install it with `xcrun simctl install <simulator-id> <app-path>`, then use `xcrun simctl launch <simulator-id> com.chekusu.sofatap --demo`. Its synthetic `SIMULATOR0` app identity in `Simulator.entitlements` enables the native simulator Keychain through Xcode-style simulated Mach-O entitlement sections; the macOS host code signature has no restricted iOS entitlements. This identity is not an Apple development team and is never used for physical signing. The second prints an unprovisioned ARM64 device `.app`, which proves device compilation/linking and requires normal Xcode development signing for installation. Staging outside Documents avoids FileProvider metadata interfering with codesigning.

[View the offline layout](../docs/images/sofatap-single-screen.png) and [dot-matrix preview](../docs/images/sofatap-touch-effects.mp4). To reproduce the visual replay in the simulator, launch with `--demo --preview-effects`: the renderer plays three 8-second interaction cycles, then returns to the slow ambient field after 24 seconds. This simulator-only replay generates no synthetic touch events, controller actions or network events.

Offline simulator screenshots and recordings demonstrate local UI and effects, not physical-device frame rate, touch latency or desktop input. Simulator compile, UI and TLS checks do not verify real iPhone LAN permissions, camera scanning, gesture timing and drag feel, microphone permissions/recognition, Typeless, automatic keyboard behavior or actual desktop input. The 0.5.0 interaction still needs physical iPhone acceptance on each supported desktop OS. Earlier 0.3.0 Mac and 0.4.0 Linux verification records do not establish acceptance of these new features. Shared-Mac receiver tests must follow the Yomado virtual-display and input-isolation requirements in `AGENTS.md`.


## Experimental Face ID unlock (0.6.0 / build 9)

The iPhone app contains a separate Face ID flow for Windows local-account passwords and password-bearing personal Microsoft accounts. It requires the opt-in Windows login service and Credential Provider; an ordinary or older receiver does not support lock-screen input. This has not yet passed physical Face ID or Windows sign-in acceptance.

1. Unlock Windows locally, install/configure its experimental login component, then pair Sofatap through the receiver's native QR window. The phone accepts the login capability only over the existing pinned receiver connection.
2. In Sofatap, tap the logo → **Face ID 解锁电脑**. Verify the computer and account, enter the account password indicated by the account type (local or Microsoft account, not a Hello PIN), and explicitly allow local storage. Face ID confirms enrollment.
3. While the computer is locked, tap the lock/Face ID icon inside the touch surface, then **用 Face ID 解锁**. Each attempt obtains a new, short-lived challenge before requesting Face ID. A cached capability allows connecting to the login service before the ordinary receiver starts.
4. Sofatap reports success only after the Windows login component confirms it. Cancellation or an uncertain response never resends the password; inspect the TV before explicitly starting another attempt. Use the same settings page to replace/remove the saved password.

The password uses an independent, non-syncing iOS Keychain item with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `.biometryCurrentSet`; the ACL protects the actual password read. It is bound to the paired host/port/certificate/token, login-service certificate/device identity, exact Windows account SID, and password-provider kind. Each use creates a fresh `LAContext`, disables reuse and the passcode fallback, and invalidates the context afterward. Changing Face ID enrollment invalidates the password. Re-pairing or a detected service identity change removes the prior enrollment. The login capability itself is stored device-only in Keychain, never in text drafts or UserDefaults.

Passwords use a dedicated secure keyboard field, without clipboard actions, dictation/composer integration, or autofill. After Face ID, the one-use request goes directly to the separately pinned HTTPS login service on TCP 53320. Backgrounding cancels authentication and any pending attempt; a system Face ID prompt becoming inactive does not cancel itself. The ordinary `/control` connection never receives a password, and there is no mouse/keyboard injection fallback. Owned temporary `Data` buffers are cleared; Swift, Foundation and Security may still create runtime copies, so this is not a guarantee that all process memory is zeroized.

The capability keeps the Windows profile SAM alias (such as `outur`) for display, even for a Microsoft account. The Windows component obtains the Microsoft qualified sign-in identity directly from LogonUI after matching the enrolled SID; the phone does not choose or submit an account identity. Microsoft-account passwordless mode and the Windows setting that only allows Windows Hello sign-in make this password flow unavailable. Sofatap does not alter either setting.

Powered-off wake, firmware/BitLocker pre-boot screens, domain/Entra accounts and Windows Hello PIN are not supported in this first integration. Keep a working local sign-in method while testing the login component.

Protocol and binding checks (no real password, biometric prompt or desktop input):

```sh
xcrun swiftc -swift-version 5 ios/SofaTap/Core/Pairing.swift \
  ios/SofaTap/Core/UnlockCredentialVault.swift ios/SofaTap/Core/UnlockProtocol.swift \
  ios/tests/UnlockProtocolTests.swift -o /tmp/sofatap-unlock-protocol-tests
/tmp/sofatap-unlock-protocol-tests
```
