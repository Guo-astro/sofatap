# Android TV receiver 0.2.0 beta.1 release — October 17, 2026

Android/Google TV receiver **0.2.0-beta.1**, version code **6**, is [publicly released](https://github.com/chekusu/sofatap/releases/tag/android-tv-v0.2.0-beta.1). Desktop receiver 0.8.0 beta.1 remains awaiting release; the published desktop downloads are still 0.7.3 beta.1. This record does not change iPhone/TestFlight distribution.

## Source and artifact

- Built from clean reviewed commit `a9076becaad7d0d9bcca33086212de542ff8a00b`.
- Merged as `5096e2ef061d33b316456befdd6c4f6a126c0cd1` through [PR #9](https://github.com/chekusu/sofatap/pull/9). Both commits have identical source tree `b9463692cdbfd2d5f1041979fd27cecffaf45e8f`.
- [CI run 39019434666](https://github.com/chekusu/sofatap/actions/runs/39019434666) completed successfully for the reviewed commit. A separate clean local build executed all 80 tasks; 94 tracked Android source-file hashes matched before and after the build.
- Package: `com.chekusu.sofatap.tv`; APK: [Sofatap-Android-TV-0.2.0-beta.1.apk](https://github.com/chekusu/sofatap/releases/download/android-tv-v0.2.0-beta.1/Sofatap-Android-TV-0.2.0-beta.1.apk), **6,355,464 bytes**.
- APK SHA-256: `597424d0ffb0e6cfe7c97957452a0db538be6aca4169f03bd61e4191c4811f13`.
- Signing certificate SHA-256: `638afe6aadb3c2d76001ef682c6a48b0f3243755fa9ae131b9804eed36ede4d9`. The prior public 0.1.4 APK was downloaded, checked against its published digest, and its actual signing certificate compared: the certificates match exactly. This release retains that development/debug signing identity and is debuggable; it is not a Google Play production release.
- Anonymous download of the published APK returned HTTP 200 and matched the local artifact’s exact byte count and SHA-256.

## Verification and boundaries

The final source passed **132 JVM tests**, Android lint and **27 instrumentation tests** on an owned headless Android TV API-31 emulator. The emulator was stopped after the final checks. The tests cover update metadata, transfer verification, package/signature/version rejection, native controls, persistent opt-out, pending installer sessions and cancellation. See [the updater verification](android-tv-updates-2026-10-17.md) for the specific test scope and platform rules.

Automatic checks/downloads do not open an installer over another TV app. Installation requires an explicit receiver action and Android’s system confirmation. Old receivers require one manual upgrade to acquire the updater.

No household TV was upgraded or used for system-installer acceptance during this release validation. Sony/Xiaomi native remote pairing, third-party-app behavior and successful completion of this new on-TV update flow remain separate acceptance tasks. Prior Xiaomi installation, preservation of pairing/accessibility, and user-enabled/selected IME are documented in the [limited hardware record](tv-native-controls-2026-10-17.md); they do not establish universal TV compatibility.
