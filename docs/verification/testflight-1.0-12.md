# Sofatap TestFlight 1.0 (12)

Checked October 14, 2026 (Japan time).

## Distribution status

- App Store Connect app: `6822188472`, bundle `com.chekusu.sofatap`.
- Build `823ff14a-847c-4097-8569-f515032436b8`: version **1.0 (12)**, processing **VALID**.
- Internal group **Sofatap Team**: build assigned; **IN_BETA_TESTING**.
- External group **Sofatap Public Beta**: build assigned; **WAITING_FOR_BETA_REVIEW**. TestFlight App Review submission is **WAITING_FOR_REVIEW**, submitted October 14, 2026 at 03:02 JST; both states were confirmed by fresh API reads.
- [Public invitation](https://testflight.apple.com/join/e6MuKx9S): configured, with a 100-tester limit. It is **not yet open for installation**. The owner-confirmed contact and prepared reviewer instructions have been saved. External review has been submitted; Apple has not approved this build for external testing. Automatic tester notification is enabled.
- English, Simplified Chinese and Japanese beta descriptions and What to Test notes were saved and read back. [Canonical beta text](../app-store/testflight-1.0-12.json) and [reviewer setup instructions](../app-store/review-notes-en-US.txt) are available. Reviewer notes are saved in App Store Connect, and the owner-selected beta feedback email is applied to all three locales. Personal contact details are kept out of the repository.
- Formal App Store review was not submitted by this release task.

## Build evidence

The implementation baseline is `278bea003e362d28f5a39adeb374e641591eea92`, with the build number advanced from 11 to 12 in `ios/project.yml` and the regenerated Xcode project. It includes the inset Send button, smaller left-side actions, natural two-finger scrolling, the independent touchpad scroll strip, microphone feedback and continued-draft fixes.

A normal **Release** archive and **App Store Connect** export completed using CHEKUSU INC. signing. The exported IPA is 2,970,605 bytes, SHA-256:

```text
8905f9c1ec7928a0d76de48c1b1e401e580202db5e6a0fdcfbaeac4560604ae5
```

The IPA signature verified with strict checking. Its distribution profile uses team `FKSR2JD63B`, has no provisioned-device list and disables `get-task-allow`. The archive contains the privacy manifest, current Sofatap assets, English and Simplified Chinese interface/permission resources, iOS 17 minimum deployment and iPhone device family. Apple reports no non-exempt encryption requirement.

The archive and export used staging outside Documents. No physical desktop input or phone interaction occurred during this release task. Earlier simulator layout checks and development-signed phone acceptance remain separate evidence; uploading and processing this build do not establish physical TestFlight installation, haptic perception, live dictation or receiver acceptance.

## Companion and preview scope

[Desktop receiver 0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1) remains protocol-compatible: desktop and shared protocol sources are unchanged from its `c18f12f` baseline. Its published Windows, notarized Mac and Linux downloads are linked in the [setup guide](../app-store/support.md). This source comparison does not replace end-to-end device testing.

The iPhone Release UI includes separate Android/Google TV experimental and LG webOS preview adapters. Android needs the development receiver and user-enabled Accessibility service; its overlay cursor and accessible-control activation are not universal mouse injection. No TV model is hardware-qualified. TV text/dictation, drag and right-click remain unavailable. AI automation, Bluetooth transport and saved-PIN unlocking are unavailable.

## Remaining release steps

1. Wait for Apple's external beta review result.
2. After approval, verify public-link installation before advertising the beta as available to friends.
3. Complete final-build physical installation and the remaining phone/receiver acceptance separately, preserving Yomado input isolation on the shared Mac.
