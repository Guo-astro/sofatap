# Direct TV control for Sofatap

Research date: **2026-10-13, Asia/Tokyo**. Status: **proposal**, not implemented support. No TV was paired or operated during this research. This original research is now followed by a [detailed implementation plan](tv-implementation-plan.md) and [source-preview verification](../verification/webos-pointer-preview.md). Physical-TV compatibility and store distribution remain to be validated.

Product priority: **free manual TV control is the next feature**. Paid voice automation follows on Windows/macOS/Linux first, then on televisions. See the [product roadmap](../ROADMAP.md). This TV work must not depend on an AI model, subscription or autonomous planner. Existing speech-to-text is a basic input method, separate from asking an agent to perform a task.

## What the example establishes

The [original greco_dev demonstration](https://x.com/greco_dev/status/2109842197654692349) shows a custom TV-control interface. In the [author's follow-up](https://x.com/greco_dev/status/2109853092409745614), they describe finding their TV's address and model, pairing, and controlling it through the local **webOS API over Wi-Fi**. REA helped investigate and build the application. These are author-reported results, not our hardware verification. The example concerns LG webOS; it does not establish Android TV compatibility or an autonomous agent operating every television app.

It supports a useful product direction: Sofatap could connect directly to supported televisions, without a Windows, Mac or Linux computer attached. LG webOS would require its own adapter; it should not share an assumed protocol with Google TV.

## Proposed Google TV / Android TV route

Google's [Android TV Remote Service](https://play.google.com/store/apps/details?id=com.google.android.tv.remote.service) provides navigation, text entry and voice-search support for its mobile remotes. The official [Google TV connection flow](https://support.google.com/googletv/answer/11136134?hl=en) uses device selection and a code displayed on the television.

For Sofatap, prototype a native iOS adapter for the Android TV Remote v2 protocol: discover the service locally, pair using the television's code, retain the client identity securely, and reconnect for bounded commands. The maintained third-party [androidtvremote2 implementation](https://github.com/tronikos/androidtvremote2) documents operation without ADB or developer options when the TV already has the Remote Service. In that configuration, a new Sofatap TV app is unnecessary. This is implementation evidence, **not a Google-supported third-party SDK guarantee**. AOSP publishes historical [pairing-protocol code](https://android.googlesource.com/platform/external/google-tv-pairing-protocol/+/refs/heads/main), but that does not document the complete current Remote v2 service contract.

Keep pairing credentials out of logs and repositories, provide “Forget TV,” and verify trust handling rather than copying permissive TLS examples. Availability depends on the service, manufacturer, firmware and network; generic Android-based televisions without this service require separate assessment.

The requested experience is manual **mouse/touchpad control**. Verify genuine pointer movement, click and scrolling on each target protocol. **Directional focus navigation** (swipe to move focus, tap to select, Back/Home/media keys) is a separate supported mode where available; do not label it mouse support or silently substitute it for the requested pointer experience. Right-click and held-button dragging also require independent verification. Preserve Sofatap's familiar touch surface while exposing the selected device's actual capabilities.

Google's [Cast SDK](https://developers.google.com/cast/docs/overview) is a separate option for compatible media sessions. Its sender and receiver applications are associated by application ID; it is not a general screenshot or arbitrary-app-control API.

## Mouse capabilities found in source

These are source-inspection findings, not physical-TV acceptance results:

| Capability | Android TV Remote v2 implementation | LG webOS pointer socket implementation |
| --- | --- | --- |
| Relative pointer movement | No pointer-delta message found | `type:move` with `dx/dy` |
| Click | `DPAD_CENTER` activates the focused item | `type:click` at the pointer |
| Wheel scrolling | No wheel message found; direction keys are separate | `type:scroll` with `dx/dy` |
| Held input | Key `START_LONG` / `END_LONG` | Movement can include `down:1`; complete drag/drop requires testing |
| Right-click | No verified interface | No independent right-click interface in the inspected implementation |

Evidence is pinned to the [Remote v2 message schema](https://github.com/tronikos/androidtvremote2/blob/e664a8e1f14ee458b14c646bfb3ea46f10367051/src/androidtvremote2/remotemessage.proto#L846) and [ConnectSDK webOS mouse socket](https://github.com/ConnectSDK/Connect-SDK-Android-Core/blob/2f7ebbc7eb909321ff41b2c6bcdf6b0881427579/src/com/connectsdk/service/webos/WebOSTVMouseSocketConnection.java#L135). The absence of pointer messages in this Remote v2 implementation is not evidence that every Android-based TV lacks all possible mouse-input routes.

For the requested mouse experience, LG webOS is a candidate for a pointer adapter. The current feature priority is the **Android/Google TV receiver capability probe**, as specified in the [implementation plan](tv-implementation-plan.md). A native receiver APK does not automatically grant global mouse input, and a direction-navigation adapter alone does not complete the requirement. Test named hardware before announcing support. Enable gestures according to verified capabilities rather than copying desktop right-click and drag behavior onto every television.

## Later paid TV automation

This section applies only after free TV control and the paid desktop automation stage. It does not change the current manual-TV priority.

The orchestration proposed in [natural-language computer control](natural-language-pro.md) can dispatch typed commands to a TV adapter. Pi can maintain task state, and DeepSeek can interpret an explicit command such as “pause” or “open this supported app.” [Cua Driver's platform matrix](https://github.com/trycua/cua/blob/7a1dcd01874647f1b65673b190a43db5e1194d2b/docs/content/docs/cua-driver/concepts/platform-support.mdx) documents Windows, macOS and Linux, not Android TV; an Android execution and observation backend would be separate work.

Remote-control commands do not establish access to a screenshot or accessibility tree. Android [accessibility](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService) and [screen-capture APIs](https://developer.android.com/media/grow/media-projection) also have permission, version and secure-content limits; protected video must not be assumed visible to a model.

Google Play's [AccessibilityService policy](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en) distinguishes static, human-defined automation from autonomous planning and execution through that API. A user giving an initial goal is not a stated exemption. General-purpose Sofatap must not claim the disability-tool exception. This restriction applies to AccessibilityService usage; it is not a blanket prohibition on AI interpreting commands sent through legitimate device or media APIs. A cross-app visual agent therefore needs its own technical and distribution review.

## Qualification before announcing support

Start with discovery, pairing and the requested mouse/touchpad behavior on named models. Record directional navigation separately, alongside text and media controls. Require evidence for:

- Real pointer movement, click and scrolling, with explicit unsupported states for unavailable right-click or drag. A moving phone animation or a shifted TV focus rectangle is not pointer acceptance.
- Chinese, Japanese and English text; IME composition, selection, backspace and replacement. PC realtime editing guarantees do not transfer automatically.
- Reconnection after app backgrounding, TV restart, network changes and revoked pairing; no duplicated commands.
- Standby wake and power behavior, distinguishing TV power from an attached streaming device and any HDMI-CEC dependency.
- Per-app search, playback and deep-link behavior; installed apps and account state affect outcomes.
- Clear unavailable states, manual takeover and credential protection.

Publish compatibility only after these checks. This proposal adds no README support claim.
