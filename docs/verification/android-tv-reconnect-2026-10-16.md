# Android/Google TV reconnect verification — October 16, 2026

**The household Sony and Xiaomi TVs have not been field-tested. No physical TV model or third-party TV app is qualified by this release.** The [physical acceptance checklist](../ACCEPTANCE.md) remains open. All results below come from software tests, fake input, or an explicitly addressed disposable Android TV emulator.

## Versions and distribution

- Android receiver **0.1.1 beta.1**, package `com.chekusu.sofatap.tv`, version code **2**, minimum Android API **26** and target API **36**.
- [Development APK release](https://github.com/chekusu/sofatap/releases/tag/android-tv-v0.1.1-beta.1). This is development-signed, not a Google Play release or store approval.
- Companion iPhone **1.0 build 17** contains the automatic retry logic. Earlier phone builds do not gain automatic TV retry merely by upgrading the receiver. TestFlight processing/review/distribution must be checked independently from the signed archive and export.
- Desktop receivers remain at **0.7.2 beta.1**. LG webOS is a separate adapter and did not receive this Android-specific change.

## Changed behavior

The receiver retains its valid encrypted identity and paired credential digest through ordinary restarts, reordered or added/removed unrelated adapters, and a temporary offline start. The persisted certificate's address set remains distinct from live advertised addresses. QR codes only contain addresses currently present and covered by the certificate. Genuine simultaneous address replacement, expiry or an otherwise unusable certificate requires a fresh identity and pairing; corrupt encrypted storage produces a visible failure without overwriting it.

A user-started receiver listens for network changes. It stops its listener while offline and recreates it when a usable network returns. Retired listeners cannot save a late credential over the new identity. Explicit Stop unregisters network callbacks and prevents automatic restart. A failed startup no longer leaves the service permanently marked as starting.

The phone retries only its current selected saved Android TV while in the foreground, using 1/2/4/8/16/30-second delays. Backgrounding, explicit disconnect, target switching and removing the device cancel pending retries. Foreground restoration respects an explicit disconnect. Certificate, authentication and protocol rejection stop retries; one-time QR bootstrap is never automatically retried. Reconnection discards unconfirmed actions and queued input, and preserves the device record and name. Paused input in a modal screen stays paused after reconnecting.

## Completed software checks

| Check | Result and scope |
| --- | --- |
| Android JVM suite | **73 tests passed**, zero failures/errors/skips. Includes certificate address policy, expiry, listener retirement and credential persistence boundaries. |
| Android build and lint | Main and instrumentation APKs built. Lint completed with **zero errors**; existing warnings remain. Network callback registration uses API 26-compatible calls. |
| iPhone deterministic controller suite | **135 checks passed**: backoff/reset, selected device, stale callbacks, cancellation, bootstrap boundaries, failure classification and no replay. |
| Saved-device suite | **35 checks passed** without Keychain or network access. |
| Unified QR routing | **73 checks passed**, including metadata and saved-device identity. |
| Existing webOS controller | **74 checks passed** with injected sockets; no webOS device contacted. |
| Native localization | **12 locales**, 319 interface strings and five permission descriptions each, including both recovery messages. |
| Swift/Java transport | Seven integration groups passed using the real Swift URLSession/pinned TLS client and production Java server with counting fake input. |
| Android runtime | **8 instrumentation tests passed** on the dedicated API 31 ARM64 Android TV emulator. |
| iPhone packaging | Signed Release archive and App Store Connect IPA export succeeded; bundle identity, version 1.0 and build 17 were checked. This is not a physical iPhone/TV acceptance result. |

The transport restart regression deliberately applies a click but withholds its acknowledgement, stops the receiver, and creates a new listener with the same certificate and stored credential digest. The phone reconnects automatically without another scan, credential write, device ID change or duplicate device. The ambiguous click, queued motion/key and offline input are not replayed. A fresh Home action succeeds after recovery.

The Android runtime suite verifies encrypted identity continuity through address churn/offline/restoration, expiry handling, corrupt-store preservation and service offline→online recovery followed by explicit Stop. Existing runtime checks also cover strict JSON, the protected native pairing UI and accessible-node click/scroll within a non-exported debug fixture. This fixture is not a third-party TV application.

The emulator ran with `-no-window -no-audio -no-snapshot`. Every ADB action targeted that emulator. No household TV was contacted, no physical display arrangement changed, and no mouse/keyboard input was injected into the shared Mac desktop. The test runner restored the emulator's previous accessibility configuration.

## Package identity and upgrade boundary

The APK is 6,330,592 bytes with SHA-256:

```text
1702c40ad3469b8de4f21135ba56492d7bbc3b0067e7600327ede42c0b61c9a3
```

`apksigner verify` passed. The signing certificate SHA-256 is `638afe6aadb3c2d76001ef682c6a48b0f3243755fa9ae131b9804eed36ede4d9`, matching the existing local development APK installed in the disposable emulator. Updating that emulator used `adb install -r`, without uninstalling or clearing app data. Some historical CI-generated debug APKs use a different certificate; this result does not establish in-place upgrade compatibility with those artifacts.

## Still requires on-site acceptance

For both household televisions, record the actual model, region and firmware; normal installation and user-granted accessibility permission; physical iPhone optical QR scanning, identification and naming; receiver restart and same-record recovery; network loss, revocation and background recovery; visible click/scroll results in the launcher, Settings and representative apps; and lock/screen-off behavior.

This change does not implement TV text/dictation, raw mouse injection, drag, right-click, standby wake or paid voice-goal automation. A transport acknowledgement is not proof that a real television's UI changed.

## Reproduce

Follow the [Android guide](../../android/README.md) for toolchain setup. Run the Gradle unit/lint/APK tasks, `ios/scripts/test-android-tv.sh`, `ios/scripts/test-saved-devices.sh`, `ios/scripts/test-pairing-code.sh`, `ios/scripts/test-tv-controller.sh`, and `ios/scripts/test-android-tv-interop.sh`. Run `android/scripts/test-emulator.sh emulator-SERIAL` only against a disposable headless Android TV emulator; it refuses physical device serials and checks the eight-test completion marker.
