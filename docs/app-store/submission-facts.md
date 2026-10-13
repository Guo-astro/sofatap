# Sofatap first-release submission facts

Prepared October 13, 2026. These files are submission drafts and an evidence audit, not a record of ASC upload, App Privacy publication or review approval. The release owner owns those operations.

## Record and draft fields

| Item | Value / status |
| --- | --- |
| Existing app | Sofatap, Apple ID `6822188472`, bundle `com.chekusu.sofatap` |
| Release target | Existing ASC version `1.0`; release owner is preparing build `11` from the current 0.7.0 feature set. Verify the final archive. |
| Primary locale | en-US |
| Distribution | User decision: free, no IAP/subscription, 148 non-EU territories, EU27 excluded, no automatic new-territory availability. Do not change for this task. |
| Text fields | [en-US.json](en-US.json). Split `appInfo` and `version` into the canonical metadata files after pulling existing ASC metadata; remove the routing-only `versionString`. |
| Review notes | [review-notes-en-US.txt](review-notes-en-US.txt). Before submitting, add the exact tested receiver version and direct asset URL selected for review. |
| Public policy | [PRIVACY.md](../../PRIVACY.md), intended URL `https://github.com/chekusu/sofatap/blob/main/PRIVACY.md` after publication |
| Support | Existing public [issue tracker](https://github.com/chekusu/sofatap/issues), with [setup page](support.md) to be published |
| Marketing | Use the public source repository until the website routes below are independently reachable. |
| Category | Recommended primary Utilities; optional secondary Productivity. The release owner must read the current ASC categories before changing them. |
| Copyright | Proposed `2026 CHEKUSU INC.`; do not replace an already-approved copyright holder without checking. |

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
| First-release localization | Initial source was hardcoded Chinese; the release owner is adding English and retaining Chinese. Verify archived resources and simulator/device language before declaring localized UI support. English store text alone is not English UI. |

## Privacy answers supported by current source

Recommended ASC answer for the reviewed first-release native app: **Data Not Collected**, provided final archive inspection confirms the same behavior. This recommendation uses Apple's definition of developer/partner collection, not a claim that no data crosses devices. Input text and complete live field contents do cross between the user's own paired devices; the developer and third-party partners do not receive them through Sofatap. The user's destination application can process submitted text independently.

No advertising, tracking, company-hosted input/audio service, third-party analytics SDK or app-owned crash uploader was found. The iOS project has no third-party package dependencies. Built-in recognition requires local processing. Camera frames are used to decode a QR code without being saved or uploaded. Local pairing credentials and fallback drafts require the retention/deletion explanation in the policy. External GitHub support submissions and Apple TestFlight feedback should not be misrepresented as a Sofatap input-upload feature.

Apple's collection definition and on-device guidance support this assessment; recheck if telemetry, support forms, cloud speech or AI observation is added. Do not infer that App Privacy is published from the required-reason manifest or CLI readiness output. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Age-rating facts

The app itself includes no user community/feed, messaging service, advertising, contest, gambling, medical content, sexual/violent content or catalog of entertainment. There is no embedded open-web browser or desktop video stream; it sends input to a separate computer that the user already owns. Support/receiver links are specific external links. The fact that a user can control their own computer must be explained if an age-rating question needs clarification; do not label Sofatap as a general in-app web browser without checking the current questionnaire definition.

Suggested questionnaire selections: no relevant content descriptors; no app-provided messaging/chat, UGC community, advertising, loot boxes, gambling, or age-assurance/parental-control feature. Not the Kids Category. Let ASC calculate the result rather than hard-coding a global 4+ promise; regional ratings can differ. The released build and actual questionnaire remain authoritative. [Apple age-rating workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/).

## Export-compliance facts

The iOS source uses Apple's URLSession/Security for TLS and Keychain, plus CryptoKit SHA-256 for certificate fingerprints and local text digests. No bundled cryptographic implementation, custom encryption algorithm, VPN or general encrypted-messaging service was found. The app does use encryption; do not answer that it uses none. The likely classification is exempt use through Apple operating-system facilities, subject to the release owner's final archive/dependency check and ASC questions. If confirmed, `ITSAppUsesNonExemptEncryption = false` is appropriate; do not create a non-exempt declaration merely because WSS is used. This is a technical inventory, not confirmation that Apple accepted a declaration. [Apple encryption documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).

## Review requirements and current gaps

Apple's remote-desktop clause 4.2.7 is conditional on mirroring specific software/services. Sofatap sends input without screen streaming; explain that design and its user-owned local host rather than asserting guaranteed eligibility. Reviewers need a working receiver and precise setup steps. The policy link must be accessible both in metadata and in-app; screenshots/previews must show actual functionality. Avoid presenting an offline demo or the generated product illustration as a live pairing result. [App Review Guidelines 2.1, 2.3, 4.2.7 and 5.1.1](https://developer.apple.com/app-store/review/guidelines/).

| Item | Observed state / action before submission |
| --- | --- |
| Public website | `https://sofatap.app/privacy` returned HTTP 404 with a browser user agent during this audit; ordinary scripted requests returned 403. `/support` was not verified as a public working route. The website source tree had no privacy/support route. Do not save those URLs as working facts. |
| Public receiver versions | GitHub API confirmed Windows/Mac `v0.3.0-alpha` and Linux `v0.4.0-alpha`. Windows ZIP ~90.5 MB, Mac notarized ZIP ~42.2 MB arm64 / ~45.0 MB x64. These predate live text editing. Final review notes need a publicly obtainable, tested receiver matching any live-input claim. Older packages can test fallback input only. |
| In-app policy link | Initial source lacked one; release owner is adding it. Verify on the uploaded build. Publish `PRIVACY.md` before a reviewer opens its link. |
| Purpose strings | Initial microphone purpose string incorrectly promised review/send for all input. Release owner is updating it for live synchronization. Verify English/Chinese archived strings. |
| Live speech | Prior 0.7.0 physical acceptance document explicitly leaves live speech pending. Prior 0.6.0 voice + Send testing is a separate result. Do not claim the live path passed until a new end-to-end test does. |
| Screenshots | Parent task owns capture from final real build. Show gesture surface, pairing and actual text behavior; redact any QR credentials by using a deliberately nonfunctional published fixture rather than exposing a live secret. Label conceptual material only outside store screenshots. |
| App preview | Existing website film not approved as an App Store preview by this audit. Use only actual app screen captures with permitted explanatory overlays; omit optional preview if no compliant recording exists. |
| Review contact | Must come from existing approved ASC contact details or an explicitly supplied business contact. No private address, telephone number or email has been invented or published here. |
| Content rights | The app is a utility with no bundled third-party content catalog. Final declaration still requires checking screenshot/film/music rights; open-source dependency notices are separate. |
| ASC privacy / rating / encryption | Prepared facts only; no remote write performed by this materials task. |

## Validation and handoff

Run `asc metadata pull` into the release owner's working metadata directory, merge only intended fields, validate, inspect a dry run and then save the draft. `en-US.json` is a field bundle for handoff, not the canonical ASC metadata directory itself. TestFlight `whatToTest` requires its own beta-localization API operation. A first version may not expose What's New; omit that field if ASC rejects it for this initial release.

Before an App Store review submission, replace the receiver-version gap with an exact verified download, read back the saved store fields, confirm a valid processed build and testable assignment, and complete reviewer contact/privacy/rating/encryption details. TestFlight preparation can proceed while optional marketing material is unfinished.
