# Development source consolidation — October 26, 2026

This integrates the reviewed development changes onto main's `8621711` baseline. It is a source integration, not a new TestFlight upload, public APK, receiver release, or hardware qualification.

## Included changes

- Android controller missing-recognition-provider fallback from `5f3606c` and `fdbf7ea` (PR #20): preserve the draft and selection, open the current keyboard when no supported speech service is available, and cancel stale keyboard requests. The existing public Android controller APK does not contain this change.
- TV navigation and YouTube/Netflix shortcuts from `74083e9` (PR #16): avoid accessibility-tree reads on native input acknowledgements, discard confirmations that depend on expired directions, and expose only the receiver's fixed advertised application shortcuts.

The integration retains main's desktop volume/pointer-speed controls, Android editor UUID normalization, iOS and Android hold-to-drag fixes, and all existing translations. The translation conflicts were resolved by retaining both main's strings and the TV additions. The old candidate build 21 was not restored: iOS source stays at build 23, Android TV at `0.2.1-beta.1` / code 7, and Android controller at `0.1.0-beta.1` / code 2. A future distribution must use an appropriate new build/version and complete its release checks.

The separately uncommitted Remote v2 diagnostics and local-address fallback experiment is not included. Historical candidate records retain their original build numbers and acceptance results.

## Validation of the combined source

- Android receiver: 143 JVM tests passed; Android controller: 125 tests discovered, 124 passed, one existing opt-in test skipped. No failures or errors.
- Both Android debug APKs and their instrumentation APKs compiled. Lint reported zero errors, with 23 receiver warnings and 20 controller warnings. No device or emulator instrumentation was run in this consolidation.
- iOS TV protocol/lifecycle: 253 checks; auxiliary pager: 102 checks; native toolbar accessibility/contact: 15 checks.
- Desktop controls: 27 checks using recording transport; gesture configuration: 69 checks; configurable gestures: 66 checks; device-aware guide: 23 checks; drag release: 66 checks.
- Actual Swift/Java pinned-TLS interoperability passed, including the app-shortcut extension, receiver restart, reconnection and no replay. The receiver used injected input and did not launch applications or operate a physical device.
- All 12 iOS locales passed validation for 460 interface strings and five permission descriptions each.
- The complete unprovisioned iPhone/iPad app compiled using `ios/scripts/build-manual.sh device`; it was not installed or uploaded.

These results were obtained with the existing test scripts and Android Gradle tasks, including `testDebugUnitTest`, `lintDebug`, `assembleDebug` and `assembleDebugAndroidTest` for both modules. `git diff --check` passed.

## Remaining release acceptance

Physical TV/application tests for navigation, shortcuts, text, rapid input and reconnection remain pending in the [TV candidate record](tv-controls-shortcuts-2026-10-19.md). Android optical pairing, acoustic dictation and actual receiver input remain pending in the [Android acceptance record](android-physical-input-2026-10-21.md). Desktop volume/output and pointer-speed hardware qualification remains pending in the [desktop controls record](desktop-controls-2026-10-18.md).

TestFlight build 23 is the immutable package described in [its release record](testflight-1.0-23.md), from source `c7ad3ab`; consolidating source does not change that uploaded package or imply it includes these additional features.
