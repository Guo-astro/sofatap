# Direct TV control for Sofatap

Research date: **2026-10-13, Asia/Tokyo**. Status: **proposal**, not implemented support. No TV was paired or operated during this research. Protocol implementation, compatibility and store distribution remain to be validated.

## What the example establishes

The [original greco_dev demonstration](https://x.com/greco_dev/status/2109842197654692349) shows a custom TV-control interface. In the [author's follow-up](https://x.com/greco_dev/status/2109853092409745614), they describe finding their TV's address and model, pairing, and controlling it through the local **webOS API over Wi-Fi**. REA helped investigate and build the application. These are author-reported results, not our hardware verification. The example concerns LG webOS; it does not establish Android TV compatibility or an autonomous agent operating every television app.

It supports a useful product direction: Sofatap could connect directly to supported televisions, without a Windows, Mac or Linux computer attached. LG webOS would require its own adapter; it should not share an assumed protocol with Google TV.

## Proposed Google TV / Android TV route

Google's [Android TV Remote Service](https://play.google.com/store/apps/details?id=com.google.android.tv.remote.service) provides navigation, text entry and voice-search support for its mobile remotes. The official [Google TV connection flow](https://support.google.com/googletv/answer/11136134?hl=en) uses device selection and a code displayed on the television.

For Sofatap, prototype a native iOS adapter for the Android TV Remote v2 protocol: discover the service locally, pair using the television's code, retain the client identity securely, and reconnect for bounded commands. The maintained third-party [androidtvremote2 implementation](https://github.com/tronikos/androidtvremote2) documents operation without ADB or developer options when the TV already has the Remote Service. In that configuration, a new Sofatap TV app is unnecessary. This is implementation evidence, **not a Google-supported third-party SDK guarantee**. AOSP publishes historical [pairing-protocol code](https://android.googlesource.com/platform/external/google-tv-pairing-protocol/+/refs/heads/main), but that does not document the complete current Remote v2 service contract.

Keep pairing credentials out of logs and repositories, provide “Forget TV,” and verify trust handling rather than copying permissive TLS examples. Availability depends on the service, manufacturer, firmware and network; generic Android-based televisions without this service require separate assessment.

TV interaction should follow **directional focus navigation**: swipe to move focus, tap to select, with Back, Home and media controls. A PC-style free mouse cursor, right-click and drag are not universal TV behaviors. Preserve Sofatap's familiar touch surface while adapting its gestures to the selected device's capabilities.

Google's [Cast SDK](https://developers.google.com/cast/docs/overview) is a separate option for compatible media sessions. Its sender and receiver applications are associated by application ID; it is not a general screenshot or arbitrary-app-control API.

## Natural language and autonomous tasks

The orchestration proposed in [natural-language computer control](natural-language-pro.md) can dispatch typed commands to a TV adapter. Pi can maintain task state, and DeepSeek can interpret an explicit command such as “pause” or “open this supported app.” [Cua Driver's platform matrix](https://github.com/trycua/cua/blob/7a1dcd01874647f1b65673b190a43db5e1194d2b/docs/content/docs/cua-driver/concepts/platform-support.mdx) documents Windows, macOS and Linux, not Android TV; an Android execution and observation backend would be separate work.

Remote-control commands do not establish access to a screenshot or accessibility tree. Android [accessibility](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService) and [screen-capture APIs](https://developer.android.com/media/grow/media-projection) also have permission, version and secure-content limits; protected video must not be assumed visible to a model.

Google Play's [AccessibilityService policy](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en) distinguishes static, human-defined automation from autonomous planning and execution through that API. A user giving an initial goal is not a stated exemption. General-purpose Sofatap must not claim the disability-tool exception. This restriction applies to AccessibilityService usage; it is not a blanket prohibition on AI interpreting commands sent through legitimate device or media APIs. A cross-app visual agent therefore needs its own technical and distribution review.

## Qualification before announcing support

Start with discovery, pairing, directional navigation, text and media controls on named models. Require evidence for:

- Chinese, Japanese and English text; IME composition, selection, backspace and replacement. PC realtime editing guarantees do not transfer automatically.
- Reconnection after app backgrounding, TV restart, network changes and revoked pairing; no duplicated commands.
- Standby wake and power behavior, distinguishing TV power from an attached streaming device and any HDMI-CEC dependency.
- Per-app search, playback and deep-link behavior; installed apps and account state affect outcomes.
- Clear unavailable states, manual takeover and credential protection.

Publish compatibility only after these checks. This proposal adds no README support claim.
