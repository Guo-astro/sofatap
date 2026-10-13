# Sofatap first-release submission facts

Updated October 13, 2026. iPhone 1.0 (11) is uploaded, processed `VALID` and `READY_FOR_BETA_TESTING` for internal testing. Four authentic screenshots and English store materials are saved. App Privacy responses are saved as a draft, not published. Formal App Store review has not been submitted; the internal invitation has been accepted on a test iPhone, but its TestFlight download has not completed.

## Record and draft fields

| Item | Value / status |
| --- | --- |
| Existing app | Sofatap, Apple ID `6822188472`, bundle `com.chekusu.sofatap` |
| Release target | ASC version `1.0`, build `11`, build ID `51e28d0f-57dd-414e-929a-916e0c619496`; processing `VALID`, internal status `READY_FOR_BETA_TESTING`. |
| Companion receiver | Public [0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1), built from clean source `c18f12fc5cb74db0a73903e11d43f91a68a3a22b`; five archives plus checksums. |
| Primary locale | en-US |
| Distribution | User decision: free, no IAP/subscription, 148 non-EU territories, EU27 excluded, no automatic new-territory availability. Do not change for this task. |
| Text fields | [en-US.json](en-US.json). Split `appInfo` and `version` into the canonical metadata files after pulling existing ASC metadata; remove the routing-only `versionString`. |
| Review notes | [review-notes-en-US.txt](review-notes-en-US.txt), maintained by the release owner with current receiver download references. Reviewer contact is still missing. The latest local notes contain exact asset links; ASC still contains the earlier generic releases link because updating that record now requires the missing contact fields. |
| Public policy | [PRIVACY.md](https://github.com/chekusu/sofatap/blob/main/PRIVACY.md) is public and linked in-app. |
| Support | Public [issue tracker](https://github.com/chekusu/sofatap/issues) and [setup page](https://github.com/chekusu/sofatap/blob/main/docs/app-store/support.md). |
| Marketing | Use the public source repository until the website routes below are independently reachable. |
| Category | Primary Utilities saved in ASC. |
| Copyright | `2026 CHEKUSU INC.` saved in ASC. |

The draft uses the public brand **Sofatap**. No Chinese product-name substitution, future Pro pricing, AI operation, smart-TV support, Bluetooth control, lock-screen/PIN capability or universal field compatibility is advertised.

## Verified source behavior

| Capability / data flow | Evidence |
| --- | --- |
| iPhone-only target, iOS 17 minimum | `ios/project.yml`: deployment target 17.0; device family 1. No iPad-specific or Mac Catalyst claim. |
| Pointer gestures | `TouchGestureState.swift`, `NativeControls.swift`, `RemoteView.swift`: slide, single click, double-tap right click, 300 ms hold/drag, two-finger scroll. |
| Encrypted direct pairing | `Pairing.swift`: strict four-field URI; WSS; pinned SHA-256 leaf certificate; redirect rejection. `ControllerModel.swift`: ephemeral URLSession and bearer authentication to paired host. |
| Pairing storage | `PairingStore`: Keychain `WhenUnlockedThisDeviceOnly`. Forget Pairing deletes the phone copy. It does not revoke another copy of the receiver credential. |
| Built-in speech | `SpeechDictationController.swift`: `supportsOnDeviceRecognition`, `requiresOnDeviceRecognition = true`, explicit microphone tap/permissions, partial transcripts, interruption/background teardown, 60-second capture limit. No audio-file recording/upload or cloud fallback in this path. |
| Live text | `RemoteView.swift`/`ControllerModel.swift`, `docs/TEXT-FOCUS.md`: full supported field text and selection imported to phone; partial dictation corrections and confirmed keyboard edits sent through live protocol. Imported text held in memory; separate fallback recovery draft in UserDefaults. |
| Field scope | Windows native Edit/RichEdit; Mac writable Accessibility selected-text and range. Password, read-only and unsupported targets rejected. Browser/custom fields, Linux and older receivers use review-and-send. |
| Privacy manifest | `PrivacyInfo.xcprivacy`: UserDefaults `CA92.1`, system boot time `35F9.1`. Confirm final archive contains it and audit the final binary's dependencies. Manifest is not the App Privacy label. |
| Retired login experiment | `ComputerUnlockController.swift` sets account-password flow to false. Ordinary UI exposes only legacy-record cleanup, if a prior local record exists. No new credential enrollment or PIN unlock is a released feature. |
| First-release localization | Build 1.0 (11) includes English and Simplified Chinese (`en`, `zh-Hans`) resources. English pairing, help/privacy and keyboard UI were inspected in the actual Release simulator build. |

## Privacy answers supported by current source

The ASC privacy response **Data Not Collected** is saved as a draft and is not yet published. The assessment uses Apple's definition of developer/partner collection, not a claim that no data crosses devices. Input text and complete live field contents do cross between the user's own paired devices; the developer and third-party partners do not receive them through Sofatap. The user's destination application can process submitted text independently.

No advertising, tracking, company-hosted input/audio service, third-party analytics SDK or app-owned crash uploader was found. The iOS project has no third-party package dependencies. Built-in recognition requires local processing. Camera frames are used to decode a QR code without being saved or uploaded. Local pairing credentials and fallback drafts require the retention/deletion explanation in the policy. External GitHub support submissions and Apple TestFlight feedback should not be misrepresented as a Sofatap input-upload feature.

Apple's collection definition and on-device guidance support this assessment; recheck if telemetry, support forms, cloud speech or AI observation is added. Do not infer that App Privacy is published from the required-reason manifest or CLI readiness output. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Age-rating facts

The app itself includes no user community/feed, messaging service, advertising, contest, gambling, medical content, sexual/violent content or catalog of entertainment. There is no embedded open-web browser or desktop video stream; it sends input to a separate computer that the user already owns. Support/receiver links are specific external links. The fact that a user can control their own computer must be explained if an age-rating question needs clarification; do not label Sofatap as a general in-app web browser without checking the current questionnaire definition.

Saved questionnaire answers report no relevant content descriptors; no app-provided messaging/chat, UGC community, advertising, loot boxes, gambling, or age-assurance/parental-control feature. This is not the Kids Category. ASC calculates regional ratings; the saved answers do not justify hard-coding a global 4+ promise. [Apple age-rating workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/).

## Export-compliance facts

The iOS source uses Apple's URLSession/Security for TLS and Keychain, plus CryptoKit SHA-256 for certificate fingerprints and local text digests. No bundled cryptographic implementation, custom encryption algorithm, VPN or general encrypted-messaging service was found. The app does use encryption through Apple operating-system facilities. The processed build reports `usesNonExemptEncryption: false`; source metadata sets `ITSAppUsesNonExemptEncryption = false`. Reassess if its encryption implementation changes. [Apple encryption documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).

## Review requirements and current gaps

Apple's remote-desktop clause 4.2.7 is conditional on mirroring specific software/services. Sofatap sends input without screen streaming; explain that design and its user-owned local host rather than asserting guaranteed eligibility. Reviewers need a working receiver and precise setup steps. The policy link must be accessible both in metadata and in-app; screenshots/previews must show actual functionality. Avoid presenting an offline demo or the generated product illustration as a live pairing result. [App Review Guidelines 2.1, 2.3, 4.2.7 and 5.1.1](https://developer.apple.com/app-store/review/guidelines/).

| Item | Observed state / action before submission |
| --- | --- |
| Public website | `https://sofatap.app/privacy` returned HTTP 404 with a browser user agent during this audit; ordinary scripted requests returned 403. `/support` was not verified as a public working route. The website source tree had no privacy/support route. Do not save those URLs as working facts. |
| Public receiver versions | GitHub API confirmed `v0.7.0-beta.1` Windows x64, notarized Mac arm64/x64 and Linux arm64/x64 archives with checksums, all at `c18f12f`. New live editing is included for compatible Windows/Mac fields. Package validation does not prove final-build physical input. |
| In-app policy link | Added to the actual Release UI; the English link was visible in the inspected help screenshot. Public GitHub policy is available. |
| Purpose strings | English and Chinese purpose strings now describe live synchronization and fallback sending correctly. |
| Live speech | Prior 0.7.0 physical acceptance document explicitly leaves live speech pending. Prior 0.6.0 voice + Send testing is a separate result. Do not claim the live path passed until a new end-to-end test does. |
| Screenshots | Four raw 1320 × 2868 screenshots from the actual 1.0 (11) simulator build were uploaded successfully (`COMPLETE`): touch surface, pairing, gesture/help and keyboard. These show the unpaired UI, with disabled send/microphone; no simulated connection or physical-input result is implied. No pairing secrets are visible. |
| App preview | Existing website film not approved as an App Store preview by this audit. Use only actual app screen captures with permitted explanatory overlays; omit optional preview if no compliant recording exists. |
| Review contact | Still missing. Must come from existing approved ASC details or an explicitly supplied business contact. No address, telephone number or email has been invented or published here. |
| Content rights | The app is a utility with no bundled third-party content catalog. Final declaration still requires checking screenshot/film/music rights; open-source dependency notices are separate. |
| ASC privacy / rating / encryption | Release owner saved privacy responses as draft, age-rating answers and exempt-encryption metadata. Privacy is not published. This documentation task performed no ASC writes. |
| Physical TestFlight installation | Invitation accepted; TestFlight displays Sofatap 1.0 (11). Download remains in progress and the installed app still reports 0.7.0 (10). Installation/launch of the TestFlight build is not yet passed. Earlier development-signed device acceptance is a separate result. |

## Validation and handoff

Run `asc metadata pull` into the release owner's working metadata directory, merge only intended fields, validate, inspect a dry run and then save the draft. `en-US.json` is a field bundle for handoff, not the canonical ASC metadata directory itself. TestFlight `whatToTest` requires its own beta-localization API operation. A first version may not expose What's New; omit that field if ASC rejects it for this initial release.

Before formal App Store review, complete the reviewer contact, publish the verified privacy responses, finish physical TestFlight installation and the remaining acceptance checks, and re-run readiness validation. Public receiver downloads, a valid internally testable build and four uploaded screenshots are available. Formal review has not been submitted.
