# Sofatap 1.0 (15): privacy and questionnaire evidence

Prepared October 14, 2026. This is an engineering assessment for release preparation, not a new privacy policy or confirmation that App Privacy answers are published. The public policy remains [PRIVACY.md](../../PRIVACY.md).

## Data handling

The current implementation supports an App Privacy answer of **Data Not Collected** under Apple's definition of collection by the developer or its third-party partners. It does transfer input and, for live editing, the complete supported field text and selection between the user's own paired devices. It therefore must not be described as an app in which no data leaves the phone. The destination application and an independently chosen third-party keyboard have their own data practices. [Apple App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

| Path | Source evidence and scope |
| --- | --- |
| Built-in dictation | `ios/SofaTap/Core/SpeechDictationController.swift` checks `supportsOnDeviceRecognition` before and after permissions and sets `requiresOnDeviceRecognition = true`. It stops when unavailable rather than falling back to a speech server. Capture starts only after an explicit microphone action and permission, and ends on interruption/background or timeout. No app-owned audio-file upload is present. This says nothing about another keyboard's dictation service. |
| Camera | QR scanning decodes pairing information locally. No camera-photo library, saved video or developer upload is part of this flow. Camera permission is used for scanning. |
| Network and text | Paired receiver connections use pinned TLS and pairing credentials. There is no Sofatap relay server. Supported live editing imports full field text/selection into phone memory; fallback drafts can be retained locally. If the target changes and the user explicitly permits reusing retained live text as a draft, `ControllerModel.allowManualResend()` saves that draft in local preferences for recovery. Switching targets alone does not send it. Password/read-only/unsupported targets do not start live editing. |
| Pairings | Pairing secrets and local aliases are retained in device-only Keychain storage. Removing a saved pairing removes this phone's copy; it is not revocation of other copies. Pairing QR codes are credentials and must be absent from public screenshots. |
| Local preferences | Local preferences and a recoverable fallback draft use UserDefaults. The policy must explain local retention and clearing. |
| Analytics and third-party SDKs | No advertising, tracking, analytics SDK or app-owned crash uploader was found. The iOS project has no external package dependencies; the final build-15 IPA contains no embedded third-party frameworks. Apple TestFlight reports and a user's external GitHub issue are separate from an app input-upload feature. |
| Experimental TV adapters | These communicate with the user's TV/receiver. Android accessibility observations describe exposed controls and bounds, not app-owned screenshot streaming. Real-device model/application qualification remains pending. |
| Future automation | Cloud speech, AI screenshots/actions, account features or telemetry would require a new assessment before release. They are not part of this version's paid offering. |

## Final archive cross-check

The inspected distribution IPA is version 1.0, build 15, bundle `com.chekusu.sofatap`, SHA-256 `274a81f50926550565284413a2ff91f981cfb223c7422d0c236f910a2ea1a3e8`. Its existing archive verification matches 68 source files to commit `4c3ada531cce86f09a2caec0d4c43ffcdd3267eb`, confirms a strict distribution signature, and verifies all 12 embedded localizations against source.

Inspection of that IPA found one `PrivacyInfo.xcprivacy`, with tracking false, an empty collected-data list, UserDefaults reason `CA92.1` and system-boot-time reason `35F9.1`. No embedded third-party frameworks were present. The required-reason manifest and App Store privacy questionnaire are different declarations; a valid manifest does not prove the questionnaire has been published.

## Existing questionnaire and other declarations

The live age-rating questionnaire reports no app-provided advertising, gambling, loot boxes, messaging/chat service, UGC community, unrestricted web access, parental controls, age assurance or relevant mature-content descriptors. Sofatap sends input to a separate device; it does not embed a general browser or mirror its screen. Apple computes regional ratings; the current answers are not a promise of one universal age rating. [Apple age-rating workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/).

The existing content-rights field is `DOES_NOT_USE_THIRD_PARTY_CONTENT`. Maintain that claim only with owned or appropriately licensed final screenshots, voice/music and other promotional assets. Open-source dependency notices are a separate obligation.

Build 15 reports `usesNonExemptEncryption: false`, consistent with system TLS, Keychain and CryptoKit usage. This is not a claim that the app uses no encryption. Reassess if the implementation changes. No custom EULA is saved; Apple's standard EULA applies by default unless a custom agreement is supplied. [Apple EULA guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement).

## Release owner's remaining checks

Inspect the saved answers and their publication status on the app's **App Privacy** page in App Store Connect. The public API/CLI readiness response explicitly cannot verify publication. Check account agreements in App Store Connect as well; the official API account audit cannot read their complete state. This assessment performs no legal acceptance or privacy publication.
