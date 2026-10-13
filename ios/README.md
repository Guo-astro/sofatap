# Sofatap iPhone controller

Native SwiftUI app, iOS 17+, no third-party libraries. Development source: version 0.7.0, build 10. The published Windows/Mac 0.3.0 and Linux 0.4.0 receiver packages predate the new focus hints. Open `SofaTap.xcodeproj` in Xcode. Select your company's Apple development team and a connected iPhone to install. The repository contains no provisioning profiles or developer account identifiers. `project.yml` is the reproducible XcodeGen source; use `xcodegen generate --spec ios/project.yml` from the repository root after changing it.

The receiver's QR code or full `sofatap://pair?...` URI supplies the host, port, secret and leaf certificate fingerprint. Pairing credentials are stored in Keychain with `WhenUnlockedThisDeviceOnly`. Native WSS trusts only that exact host, port and certificate; redirects are rejected. Local-network ATS permission is scoped with `NSAllowsLocalNetworking`; there is no global ATS exemption.

The everyday interface is one large rounded touch surface, enclosing the logo and QR control at the top and the microphone and left-hand keyboard control at the bottom. Its resting state has icons only, with no instructional text or separate mouse arrow. Connection and recording states have accessible labels; tapping the logo opens status and gesture help, while the QR control opens pairing. A slowly flowing dot matrix fills the entire pad. Touch displaces and bends nearby dots, which settle back after release; single and double taps retain distinct ripples, and a hold strengthens the local deformation. Ambient animation pauses while inactive, detached or unable to control; Reduce Motion uses a static grid and simpler touch feedback. Effects do not mirror the desktop pointer or acknowledge desktop actions. Slide one finger to move, tap once for a left click, tap twice for a right click, hold still for 300 ms then move to drag, and slide two fingers to scroll. There is no mouse-mode selector or separate click/drag panel. Single clicks wait briefly for the double-tap decision; lifting, cancelling or leaving the app releases a drag. Movement is coalesced at 45 Hz with bounded ACK backpressure and old samples dropped. The receiver independently releases held buttons on disconnect or idle timeout. See the [interaction specification](../docs/INTERACTION.md).

Only when needed, text appears in an inline `UITextView` so iOS keyboards, system dictation and Typeless can compose normally. A supported current field opens in live mode by default: its complete existing text and native selection are imported, then confirmed keyboard edits, Backspace, Select All → Delete and selection changes synchronize without Send. Marked IME composition stays on the phone until committed. Windows currently supports native Edit/RichEdit controls; Mac requires writable AX selected-text and selection-range attributes. Unsupported fields, Linux and older receivers use a separate review-and-send draft. Neither path appends an extra Enter or form-submit action.

The bottom microphone starts Sofatap's own on-device recognition after an explicit tap and microphone/Speech permission. In live mode, partial results and subsequent corrections replace the active dictated span and synchronize with the computer. Tap again to stop; stopping does not undo already synchronized text. In fallback mode, review the local draft and tap **Send**. Unsupported recognition devices/languages fall back to keyboard input rather than cloud recognition.

The editor preserves UIKit changes that have not yet reached its delegate when SwiftUI renders other state. Deliberate clears and speech replacements take precedence over earlier edit callbacks; replacements wait for an active marked composition to finish. Run `bash ios/scripts/test-draft-editor.sh` on macOS for offscreen UIKit regressions covering this ordering, Unicode, marked text, selection and external replacement. These checks create no window and send no computer input; real keyboard and microphone acceptance remains a separate device test.

Live field text is ephemeral: the imported value, selection and subsequent live edits stay in memory and do not overwrite the saved `localTextDraft` in UserDefaults. A live session uses an opaque session UUID, strictly increasing revisions and one acknowledged snapshot at a time. A native focus, selection or text conflict, disconnect or uncertain write pauses synchronization and never replays the edit automatically. Reopen the editor deliberately after inspecting the computer. A successful live ACK includes exact native text/selection readback; it does not mean the target app saved a document or submitted a form.

The separate fallback draft stays local until Send and persists in UserDefaults for recovery. Unsent and uncertain fallback drafts remain available. A successful fallback send means the receiver submitted input events to the system, not that a target field consumed or saved them. Pending/uncertain/success markers survive process termination; uncertain or unchanged accepted text requires review before a manual resend. Nothing is replayed on reconnect. Clear the fallback draft with **清空草稿**. In live mode, deleting or clearing text edits the actual computer field.

A compatible receiver can automatically open the keyboard when a new supported native or web text field becomes editable and focused; an active drag finishes before it opens. This background probe reads accessibility metadata, never field contents. Once the editor opens, the separate live-session request reads and transfers the complete supported field text and selection. Detection and live editing have different compatibility scopes; a browser can summon the keyboard yet still use fallback sending. Protected, read-only or unknown targets do not trigger the keyboard. Protected targets also disable Sofatap's microphone; the manual keyboard remains available. Dismissing the keyboard keeps it dismissed for that target. Linux detection depends on an optional AT-SPI bridge and still uses fallback text input. See [focus detection and platform limits](../docs/TEXT-FOCUS.md).

Launching with `--demo` never connects to a computer. An amber play badge marks the offline preview; VoiceOver and the logo's status sheet identify it as a demo without adding text to the touch surface. A receiver with `inputAvailable=false` disables controls. New receivers distinguish dry-run, missing Mac Accessibility permission and an unavailable desktop; old receivers show a generic unavailable state. Heartbeats refresh this state. Backgrounding disconnects and stops capture; temporary inactivity for the app's own permission prompt pauses pointer input without cancelling the permission request.

## Privacy manifest

`SofaTap/PrivacyInfo.xcprivacy` declares `UserDefaults` (`CA92.1`) for this app's local draft and delivery markers, and system boot time (`35F9.1`) to discard motion samples older than 150 ms. The uptime value and motion timestamps are not transmitted. XcodeGen includes the manifest in the app's resources; verify it is present in the final `.app` before distribution. See Apple's [required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

This declaration covers required-reason APIs, not the separate App Store privacy answers or a privacy policy. The client sends control events and text directly to the paired computer and keeps credentials in Keychain. Opening a live editor transfers the focused supported field's complete text and selection to the phone over pinned TLS; this text stays in app memory instead of saved draft preferences. The receiver retains bounded text-bearing ACKs in connection memory for duplicate suppression, until disconnect. It does not log field text. The separate review-and-send draft is stored locally for recovery.

After an explicit microphone tap and permission, supported speech recognition runs on the iPhone. Audio is not uploaded, sent to the paired computer or silently routed to cloud recognition. Partial recognized text and revisions are transmitted during live editing; fallback text requires Send. Leaving the app or interrupting capture stops the microphone. System dictation and third-party keyboards have their own data handling. Review the final app, companion receiver and future SDKs against Apple's [data collection definition](https://developer.apple.com/app-store/app-privacy-details/#data-collection) before completing distribution metadata.

## Build fallback for mismatched Xcode SDK/runtime installations

Normal Xcode project builds are preferred. If `xcodebuild` cannot select a destination because the installed SDK is newer than available simulator runtimes, the following compiles and links the exact same native source directly against the selected SDK without installing anything or altering Xcode:

```sh
./ios/scripts/build-manual.sh simulator
./ios/scripts/build-manual.sh device
```

The first prints an adhoc signed simulator `.app` path in a temporary staging directory; install it with `xcrun simctl install <simulator-id> <app-path>`, then use `xcrun simctl launch <simulator-id> com.chekusu.sofatap --demo`. Its synthetic `SIMULATOR0` app identity in `Simulator.entitlements` enables the native simulator Keychain through Xcode-style simulated Mach-O entitlement sections; the macOS host code signature has no restricted iOS entitlements. This identity is not an Apple development team and is never used for physical signing. The second prints an unprovisioned ARM64 device `.app`, which proves device compilation/linking and requires normal Xcode development signing for installation. Staging outside Documents avoids FileProvider metadata interfering with codesigning.

[View the offline layout](../docs/images/sofatap-single-screen.png) and [dot-matrix preview](../docs/images/sofatap-touch-effects.mp4). To reproduce the visual replay in the simulator, launch with `--demo --preview-effects`: the renderer plays three 8-second interaction cycles, then returns to the slow ambient field after 24 seconds. This simulator-only replay generates no synthetic touch events, controller actions or network events.

Offline simulator screenshots and recordings demonstrate local UI and effects, not physical-device frame rate, touch latency or desktop input. The [0.7.0 physical Windows record](../docs/verification/realtime-input-0.7.0.md) confirms existing RichEdit text import, multilingual/emoji/newline append, real keyboard deletion, Select All and deletion to empty. Live speech and additional cases remain pending. The [0.6.0 record](../docs/verification/2026-10-13-iphone-input.md) separately covers gestures, microphone recognition and explicit sending. These scoped records do not establish Mac live editing, Typeless or application-wide compatibility. Shared-Mac receiver tests must follow `AGENTS.md` and keep Yomado display/input isolation.


## Windows Hello PIN direction (0.6.0 / build 9)

The account-password unlock experiment has been retired. Sofatap no longer offers account-password enrollment, replacement or Face ID submission. The ordinary receiver's legacy `unlock` advertisement is ignored, cached password capabilities are not activated, and the retained experimental controller has a fixed disabled gate on enrollment, authentication and network requests. Its protocol/binding source remains for review; it must not be relabeled as a Windows Hello PIN implementation.

If an earlier experimental build saved a credential, the logo's status sheet exposes only **删除旧版解锁记录** to delete that iPhone's legacy Keychain record and service authorization. This cleanup reads only binding metadata and deletes the items; it does not read the protected password, request Face ID or contact Windows. The Face ID purpose string is removed because the current UI cannot request biometric authentication.

The intended product direction is saved Windows Hello PIN use after explicit Face ID, with a manual phone pointer/PIN fallback while Windows is locked. Neither path is enabled in this build. Both depend on a separately verified Windows secure-desktop component and protocol. Ordinary desktop controls remain unchanged and do not gain lock-screen access. PIN input must not reuse the ordinary text composer: fallback drafts persist in UserDefaults and both modes support dictation. A future manual PIN path needs its own native input surface, no clipboard/dictation or stored PIN, no secret echo, and no automatic resend after an uncertain result.

Legacy protocol/binding checks (synthetic fixtures, no real password, biometric prompt or desktop input):

```sh
xcrun swiftc -swift-version 5 ios/SofaTap/Core/Pairing.swift \
  ios/SofaTap/Core/UnlockCredentialVault.swift ios/SofaTap/Core/UnlockProtocol.swift \
  ios/tests/UnlockProtocolTests.swift -o /tmp/sofatap-unlock-protocol-tests
/tmp/sofatap-unlock-protocol-tests
```

Retirement regression checks also exercise the disabled controller with synthetic capability advertisements:

```sh
xcrun swiftc -swift-version 5 ios/SofaTap/Core/Pairing.swift \
  ios/SofaTap/Core/UnlockCredentialVault.swift ios/SofaTap/Core/UnlockProtocol.swift \
  ios/SofaTap/Core/ComputerUnlockController.swift ios/tests/UnlockRetirementTests.swift \
  -o /tmp/sofatap-unlock-retirement-tests
/tmp/sofatap-unlock-retirement-tests
```
