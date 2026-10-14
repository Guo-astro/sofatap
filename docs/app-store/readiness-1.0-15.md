# Sofatap 1.0 (15): App Store preparation

Metadata verified October 14, 2026, with copy corrections read back at 04:40 UTC; final screenshots, preview source and submission state verified at 05:15 UTC. **The formal App Store version remains `PREPARE_FOR_SUBMISSION`; it has not been submitted for review.** TestFlight external review is a separate workflow and is not changed by this audit.

## Saved draft and verification

| Item | Result |
| --- | --- |
| App | Sofatap; Apple ID `6822188472`; bundle `com.chekusu.sofatap`; English primary locale |
| Formal version | `1.0`, ID `91096e3e-ef6c-4da6-8e3d-64e22c760a25` |
| Attached build | Updated from 11 to **15**, ID `0b55fb0b-cd25-4893-8037-0b014a9719cd`; Apple processing `VALID`; iOS 17 minimum |
| Localized metadata | [24 canonical JSON files](metadata/README.md): 12 app-info locales and 12 version locales. All 96 fields were read back from ASC and exactly match the local files. |
| Review contact | Four required fields copied from the existing approved Sofatap TestFlight review contact. Exact readback matches. Contact values and receipts remain private. |
| Review notes | [Build-specific instructions](app-store-1.0-15-review-notes.txt) saved and read back; ASC trims the final newline. No demo account is needed. |
| Companion receiver | Public [0.7.1 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.1-beta.1), with [setup instructions](support.md) and [package verification](../verification/receiver-0.7.1.md). New desktop QR metadata requires phone build 15 or later. |
| Canonical file validation | 24 files; 0 errors, 0 warnings |
| ASC submission validation | 0 errors, 0 warnings, 1 information item: `privacy.publish_state.unverified` |
| Localized screenshots | English, Simplified Chinese and Japanese each have five approved compositions in two sizes: 1320 × 2868 (`APP_IPHONE_67`) and 1206 × 2622 (`APP_IPHONE_61`). All 30 are `COMPLETE`; source checksums, byte sizes, dimensions and display order match the approved files. |
| English app preview | Exactly one 24-second, 886 × 1920 preview from approved physical-device capture is uploaded in `IPHONE_67`. Apple reports `COMPLETE`; source MD5 and byte size match the frozen delivery file. SHA-256: `c6dc2dfa956731bca8ff084cdea0ca9ff8a7018bfab3e346254acca085b10261`; 31,972,105 bytes. Poster timecode is saved as `00:00:05:00`; the final API readback still exposes a 0 × 0 poster and no playback URL. |

The localizations are English, Simplified Chinese, Japanese, Spanish, French, German, Brazilian Portuguese, Korean, Arabic, Hindi, Russian and Indonesian. They describe free manual pointer/text control, conditional live editing and on-device dictation. They identify TV adapters as development previews, with no qualified model/application compatibility. Independent native-language editorial review is still pending.

Source review corrected two claims in all 12 descriptions and the formal review notes: Sofatap adds no extra Return after the text, but explicit line breaks can act as Enter in the destination app; live-editing fallback applies to unsupported fields, including many browser/custom controls, rather than every browser. Linux and older receivers use review-and-send. All corrected descriptions and notes were read back successfully.

The generic `asc metadata push` initially saved the app-info locales and then tried to create an already-existing version locale. A paginated localization list showed all 12 version locales; each was updated explicitly, and all fields were verified against that paginated readback. No localization was deleted. A future metadata dry run that reports these existing locales as absent must be checked against `asc localizations list --paginate` before applying it.

The four historical build-11 simulator screenshots have been removed from ASC after the five replacement images in their set finished processing. Exact original PNGs were first backed up privately and verified against ASC's original source MD5 and byte size. The replacement used append, verify, then targeted removal of only the four old asset IDs; it did not use whole-set deletion. English device names and network details were privacy-reviewed before upload. The two stored size variants are marketing compositions from the same real-device captures, not claims of separate captures from two phone models.

All 15 localized original screenshots were captured from installed TestFlight **1.0 (15)** on a physical **iPhone 16 Pro Max running iOS 18.6.2**. The full app screens were preserved and uniformly scaled into both composition sizes. Only bounded numeric IP-address regions were blurred; an independent source/output pixel comparison verified the remaining app pixels and all 15 captions. The receiver fixture ran in a private Linux Xvfb container, with no Mac desktop input. The dedicated phone was restored to its original Simplified Chinese language and released, and the owned receiver fixture was stopped with evidence retained privately.

One Japanese screenshot upload reported a relationship-order error. After resolving the duplicate/missing scanner entry, the existing five large-set asset IDs were reordered through Apple's screenshot relationship API without adding or removing assets. Final paginated/readback verification confirms exactly five complete, correctly ordered images in each of all six sets.

The preview was regenerated during asset packaging, changing its bytes. The final frozen file was independently reviewed, fully decoded and played locally, then uploaded and verified before removing only this task's superseded unpublished draft preview. The prior receipts and a downloaded Apple-transcoded rendition remain private; that rendition is not represented as the original uploaded bytes. ASC and the delivery package now refer to the same approved source file.

The final TestFlight read still shows build **12** as `WAITING_FOR_BETA_REVIEW` / `WAITING_FOR_REVIEW`, and build **15** as `IN_BETA_TESTING` internally and `READY_FOR_BETA_SUBMISSION` externally. Attaching build 15 to the formal App Store draft did not submit it to either review workflow.

## Audited settings preserved

The app is free, with a JPY 0 base price and no paid functionality or IAP advertised. Its existing availability contains 148 available territories and exactly the EU27 unavailable; automatic availability in new territories is false. The release type is `AFTER_APPROVAL`. This task did not change price, availability or release type.

Primary category is Utilities, copyright is `2026 CHEKUSU INC.`, and content rights are `DOES_NOT_USE_THIRD_PARTY_CONTENT`. Existing age-rating answers have no relevant app-provided content descriptors. No custom EULA is configured. Build 15 reports `usesNonExemptEncryption: false`. See the [source and archive evidence](privacy-assessment-1.0-15.md) for the scope and limits of those declarations.

## Remaining preparation

| Item | Concrete action |
| --- | --- |
| App Privacy | Inspect the saved answers and **published** status on [App Privacy in ASC](https://appstoreconnect.apple.com/apps/6822188472/appPrivacy). The public API cannot establish publication. The historical October 13 record says the answer was a draft; this audit does not infer it is still a draft or that it is now published. |
| Account agreements | Verify current agreement status in App Store Connect. Official API authentication is healthy, but the account audit cannot read complete agreement state. No agreement was accepted by this task. |
| Localized media fallback | English, Chinese and Japanese screenshots are complete. The other nine language listings use English image fallback, with no explicit overrides at the earlier audit. Inherited English images must not be described as translated screenshots. Only the English preview is supplied. |
| App preview | The final English preview is uploaded and `COMPLETE`, with verified source checksum and a saved five-second poster timecode. Confirm the generated poster and playback in ASC when processing/UI access permits; the final readback exposed a 0 × 0 poster and no playback URL despite complete asset delivery. Localized previews are separate assets. |
| Localization QA | Review terminology, line breaks and RTL presentation in the store preview. Field/character validation does not replace native-language editorial review. |
| Review test path | Keep the public receiver downloads and setup guide available; the reviewer needs an awake, unlocked computer on the same reachable network. Experimental TV adapters require their own explanation and must not be presented as universally tested. |

These are preparation requirements, not authorization to submit. A clean public-API validation report does not verify image quality, privacy publication, account agreements or Apple approval. [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

The cached CLI web-session status was `authenticated: false` during this audit. The Apple login page is retained for the release owner; no credentials or verification codes were entered, and no privacy publication or agreement acceptance was performed. The documented `asc web privacy pull` can read declarations only with a usable web session; it is not an official public-API publication-status check.

## Website URLs

The official homepage `https://sofatap.app/` returned HTTP 200 with a browser user agent during this audit, but still linked Windows/Mac receiver 0.3.0 alpha and Linux receiver 0.4.0 alpha. It described text as never being sent until Send, which is inconsistent with current compatible-field live editing. `/support` and `/privacy` both returned HTTP 404.

The saved metadata therefore uses the public GitHub repository as its marketing URL, the current GitHub setup page as support URL, and the repository's public privacy policy as privacy URL. Replace those with official-site routes only after the routes and current download/input descriptions are verified.

A separate authorized Yobiru follow-up produced a [website review preview](https://stage.sandbank.dev/sofatap/zh/). The page was inspected with current 0.7.1 downloads, build-15 QR compatibility, conditional live editing and closed public-beta wording; its [privacy](https://stage.sandbank.dev/sofatap/privacy/) and [support](https://stage.sandbank.dev/sofatap/support/) routes return HTTP 200. Existing website media remains separate from this task's new physical-device store assets. The development server reports using the existing VAS Claude Code Opus 5.5 session. Production deployment has not occurred and the store URLs have not been switched to this staging site.

## Safe recheck

```sh
asc localizations list --app 6822188472 --type app-info --paginate --output json
asc localizations list --version 91096e3e-ef6c-4da6-8e3d-64e22c760a25 --paginate --output json
asc versions view --version-id 91096e3e-ef6c-4da6-8e3d-64e22c760a25 \
  --include-build --include-submission --output json
asc validate --app 6822188472 --version 1.0 --platform IOS --output json
```

Do not publish raw reviewer-contact responses or authenticated session data. Keep production pairing credentials, QR codes, user documents and personal device names out of store images and public verification records.
