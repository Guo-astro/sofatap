# Sofatap TestFlight 1.0 (14)

Checked October 14, 2026 (Japan time).

## Distribution status

- App Store Connect app: `6822188472`, bundle `com.chekusu.sofatap`.
- Build **1.0 (14)**: `1dad98bb-8df6-4370-b9c8-246ee229f2d2`, Apple processing **VALID**.
- **Sofatap Team** internal group: build assigned, **IN_BETA_TESTING**. Invited internal testers can install it.
- **Sofatap Public Beta** external group: build assigned, **READY_FOR_BETA_SUBMISSION**. Submission was attempted, but Apple rejected it because build 12 is already in beta review for this version. Apple requires submitting again after that review finishes. A fresh API read confirms there is **no build 14 beta review submission**.
- Build 12 remains **WAITING_FOR_REVIEW**; its existing submission was preserved. Adding build 14 to the group did not replace or approve that submission.
- The [public invitation](https://testflight.apple.com/join/e6MuKx9S) is enabled with a 100-tester limit, but is **not yet open for installation**. It must not be advertised as an approved build 14 public beta.
- English, Simplified Chinese and Japanese [What to Test notes](../app-store/testflight-1.0-14.json) were saved and read back exactly. Updated [reviewer instructions](../app-store/review-notes-en-US.txt) cover both the old build 12 entry point and the new named device selector; owner-approved private contact details remain outside the repository.
- Formal App Store review was not submitted by this task.

The failed external submission was an Apple review-queue constraint, not an upload or signing failure. Once the existing review is complete, submit build 14 for external beta review and verify the resulting state. Public-link installation and final physical phone acceptance remain separate steps.

## Build evidence

The implementation is [`9a54d2390e6095767a879b52c4347a155f5b8ef1`](https://github.com/chekusu/sofatap/commit/9a54d2390e6095767a879b52c4347a155f5b8ef1). It adds named device selection, a Keychain-backed library of multiple computer/TV pairings, local aliases and removal, a separate illustrated guide, keyboard toggle animation/feedback, inline connection notices and the website's twelve interface languages. Five new logo candidates are included for selection; the installed icon is unchanged.

A Release archive and App Store Connect export completed with CHEKUSU INC. distribution signing. The exported IPA is **3,281,831 bytes**, SHA-256:

```text
97948847b3cbcdbe99ddc0a6dfeff1577ce9ab0a9503c68654445186d48687f1
```

Strict signature verification passed. The App Store profile belongs to team `FKSR2JD63B`, has no provisioned-device list and disables debug entitlements. The exported app is version **1.0 (14)** with bundle ID `com.chekusu.sofatap`. All twelve embedded localizations match source, each with 288 interface strings and five permission descriptions. The staged archive inputs match 77 source/project/resource files in the repository. Signing assets and private release receipts remain outside the repository.

Build 13 was an intermediate upload, processed as `VALID` and assigned to the internal Sofatap Team group. Build 14 changes only the guide card title to explicitly identify Android TV / Google TV, plus the build number. Build 13 was not submitted for external beta review by this task.

## Verification scope

The [device-library record](device-library-2026-10-14.md) contains native simulator previews in English, Simplified Chinese, Japanese and Arabic, including the corrected RTL scroll-strip layout. Those screenshots were captured from build 13; build 14's guide-title correction was reviewed separately and is outside their shown first viewport. The final build 14 device archive and export passed.

Software checks passed: saved devices 32, explicit text 47, live text 57, drag release 33, Android TV controller 63 and webOS controller 74. Localization checks passed for all twelve languages. The [GitHub CI run for the implementation commit](https://github.com/chekusu/sofatap/actions/runs/38449482601) also passed all four jobs: macOS/iOS, Windows, Linux and Android TV. Core tests use injected storage and transports, not live receiver input. The migration tests cover failed storage writes, retained old credentials, empty-library tombstones and explicit selection; input tests cover stale callbacks and retained-draft review at target changes.

This task used an isolated, headless simulator and no physical phone, Mac input target or receiver. Physical haptic perception, final TestFlight installation, live device switching and phone-to-receiver acceptance remain separate checks. No TV model is hardware-qualified. Android/Google TV and LG webOS adapters remain experimental, with their distinct capability limits. Basic dictation is free manual input; paid autonomous operation is not included.

## Companion downloads

[Receiver 0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1) remains the desktop companion. This update changes the iPhone interface and pairing library, not the shared desktop protocol or receiver binaries. See the [support page](../app-store/support.md) for Windows, notarized Mac and Linux downloads.
