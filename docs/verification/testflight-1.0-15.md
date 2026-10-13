# Sofatap TestFlight 1.0 (15)

Checked October 14, 2026 (Japan time).

## Distribution status

- App Store Connect app: `6822188472`, bundle `com.chekusu.sofatap`.
- Build **1.0 (15)**: `0b55fb0b-cd25-4893-8037-0b014a9719cd`, Apple processing **VALID**.
- **Sofatap Team** internal group: assigned and **IN_BETA_TESTING**. Invited internal testers can install it.
- **Sofatap Public Beta** external group: assigned, **READY_FOR_BETA_SUBMISSION**. Apple rejected the submission request because another build in this version is already in beta review. A fresh API read confirms that build 15 has no beta review submission.
- Build 12 remains **WAITING_FOR_REVIEW**; its existing submission was preserved. Submit build 15 after that review finishes. Adding it to the external group did not replace the queued submission.
- The [public invitation](https://testflight.apple.com/join/e6MuKx9S), configured for up to 100 testers, is not yet open for installation. No public-beta or App Store approval is claimed.
- English, Simplified Chinese and Japanese [What to Test notes](../app-store/testflight-1.0-15.json) were saved and read back exactly. Updated [reviewer instructions](../app-store/review-notes-en-US.txt) cover build 12, builds 13–14 and build 15; API readback matches apart from Apple's removal of the final newline. Owner-approved contact details were not changed by this update.

The external submission blocker is Apple's review queue, not signing, upload or internal distribution. Formal App Store review was not submitted by this task.

## Build evidence

The implementation is [`4c3ada531cce86f09a2caec0d4c43ffcdd3267eb`](https://github.com/chekusu/sofatap/commit/4c3ada531cce86f09a2caec0d4c43ffcdd3267eb). Add Device now opens one scanner with a camera above platform information, automatically routes computer and Android TV codes, and offers local naming after authenticated connection. It also prevents old-device reconnection after a failed save or cancellation, and duplicate Android bootstrap attempts. LG webOS retains its manual TV-authorization flow.

A Release archive and App Store Connect export completed with CHEKUSU INC. distribution signing. The exported IPA is **3,384,861 bytes**, SHA-256:

```text
274a81f50926550565284413a2ff91f981cfb223c7422d0c236f910a2ea1a3e8
```

Strict signature verification passed. The App Store profile belongs to team `FKSR2JD63B`, has no provisioned-device list and disables debug entitlements. The exported app is version **1.0 (15)** with bundle ID `com.chekusu.sofatap`. All twelve embedded localizations match source, each with 309 interface strings and five permission descriptions. The 68 app, project and resource inputs match both the repository snapshot and the implementation commit. Signing assets and private release receipts remain outside the repository.

## Verification scope

The [unified-pairing record](unified-pairing-2026-10-14.md) contains software checks and native simulator previews in Chinese, English and Arabic, including the small-screen naming form. It distinguishes a parsed QR, an authenticated connection and a saved local alias. The [implementation CI run](https://github.com/chekusu/sofatap/actions/runs/38454373507) passed all four jobs: macOS/iOS, Windows, Linux and Android TV. Sandbank Dev acknowledged fast-forward synchronization to the exact implementation SHA through a matching authenticated Yobiru reply; that reply does not claim a receiver deployment or physical test.

This task used dedicated headless simulators and recording transports, with no shared-Mac input target or physical phone. Optical QR scanning, camera permission recovery, final TestFlight installation, haptic perception and phone-to-receiver acceptance remain separate checks. The two task-created simulators were removed after review; pre-existing simulators were preserved. Android/Google TV and LG webOS remain experimental, with no hardware-qualified TV model. Basic dictation remains free manual input; paid autonomous operation is not included.

## Companion downloads

[Receiver 0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1) remains compatible through its older four-field codes. New receiver source adds platform/name metadata and requires phone build 15 or newer; new receiver binaries have not been published. See the [support page](../app-store/support.md) for the existing Windows, notarized Mac and Linux downloads.
