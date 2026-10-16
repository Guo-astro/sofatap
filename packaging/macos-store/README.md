# Sofatap Receiver for the Mac App Store

This is a separate sandboxed build of the native receiver, using the stable `com.chekusu.sofatap.receiver` identifier. The website/Developer ID channel continues to use `scripts/build-macos.sh`. Do not install or launch this candidate over a running website receiver during development.

## Local build

Requirements: macOS, Xcode, XcodeGen 2.43 or later, Python 3 and .NET 10 SDK. Set `SOFATAP_DOTNET` when the SDK is not on PATH.

```sh
SOFATAP_DOTNET=/path/to/dotnet bash scripts/build-macos-store.sh
```

The default command builds a universal native AppKit/SwiftUI application and embeds separate self-contained .NET helpers for `arm64` and `x64`. It signs only with an ad-hoc identity, reads back the actual sealed entitlements, checks both architectures, verifies signatures and bundled licenses, and writes `artifacts/macos-store/BUILD-MANIFEST.json`. It does not open the app, prompt for permission, change startup preferences, upload or submit anything.

Application: `artifacts/macos-store/DerivedData/Build/Products/Release/SofatapReceiver.app`.

XcodeGen creates an ignored `.xcodeproj` beside `project.yml`; the YAML is the project source. Both Swift and .NET receive the `SOFATAP_MAC_APP_STORE` conditional. The native target's marketing version and build number are maintained in `project.yml`; resolve current App Store Connect numbers before a distribution archive.

## Archive

After signing prerequisites are prepared, use:

```sh
SOFATAP_DOTNET=/path/to/dotnet \
SOFATAP_STORE_ARCHIVE_PATH=/path/to/new/SofatapReceiver.xcarchive \
bash scripts/build-macos-store.sh --archive
```

This uses `asc xcode archive` and the configured CHEKUSU team. It does not silently replace an existing archive, enable provisioning changes, export, upload or submit. Configure the appropriate provisioning/signing in Xcode first. Exporting a Mac App Store package and submitting its metadata are separate release steps.

## Sandbox and helper signing

The main app has App Sandbox and incoming/outgoing network entitlements. Each helper inherits the parent's sandbox and has its own Hardened Runtime JIT entitlement. Keep Hardened Runtime enabled for both. A copied released .NET helper was tested with a sandboxed native parent on macOS: its own `allow-jit` was necessary for the hardened runtime to start. Parent-only `allow-jit` failed with CoreCLR HRESULT `0x80070008`. Apple requires the two **App Sandbox** entitlement keys on an inheriting helper, not a limit of two keys across all entitlement categories. See [Apple's sandbox inheritance reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) and [helper embedding guide](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).

The native parent provides container-only paths for the helper profile and `DOTNET_BUNDLE_EXTRACT_BASE_DIR`. No exception grants access to the website receiver's credentials. A fresh pairing is required; do not copy private pairing state into the app or distribution package.

## Privacy manifest

The app's own startup-choice preference uses `UserDefaults.standard`. `CA92.1` describes app-private defaults and is the only required-reason declaration in this initial manifest. Tracking is disabled and the receiver has no analytics or developer-operated data collection endpoint. Local commands and pairing state remain between the user's devices.

Apple's [current required-reason overview](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) lists iOS, iPadOS, tvOS, visionOS and watchOS in its policy scope. This native macOS candidate still includes an accurate manifest; it must not borrow unverified boot-time, file-timestamp or other reasons from the iOS app. The bundled .NET runtime's API use has not been exhaustively audited. Recheck Apple's then-current platform requirements and the distribution validation report before uploading, and investigate any concrete manifest diagnostics rather than adding guessed reasons.

## Release gates

- Valid CHEKUSU App Store distribution signing and provisioning, archive export and package validation.
- Standalone sandboxed app permission behavior and real remote pointer/click/drag/scroll/text acceptance, with all receiver windows and input targets isolated in Yomado. Dry-run pipe startup is not input acceptance.
- Intel Mac execution: the universal launcher and Intel helper can be built and inspected on Apple Silicon, but that does not prove native Intel behavior.
- User-confirmed startup choice, no silent automatic startup registration in the store channel.
- Real Mac screenshots, store metadata, privacy answers and review instructions that accurately describe the store build's reduced capabilities.
- Submission and approval remain separate from compilation or a working diagnostic helper.
