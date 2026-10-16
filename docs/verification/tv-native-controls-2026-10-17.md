# Native TV navigation and phone input — October 17, 2026

## Trigger and scope

The household user reported that the existing accessibility-node pointer could not reliably activate controls in YouTube and Netflix on either television. This is not evidence that those apps accept global mouse input. The next candidate adds a distinct remote navigation mode, immediate phone feedback for discrete actions, and phone text entry through an optional TV input method.

The software is under development on `feat/tv-native-navigation-text`. This record does not announce a public release or replace physical-device acceptance.

## Known hardware facts

| Television | Verified setup | Current acceptance boundary |
| --- | --- | --- |
| Sony XRJ-85X95L | Android 12 / API 31; receiver and normal accessibility authorization previously installed; Google Android TV Remote Service present and its pairing/control ports reachable. | Native Remote Service pairing, D-pad behavior in YouTube/Netflix, and browser IME input are pending. |
| Xiaomi MiTV-MOEU0 | Android 14 / API 34, firmware UKN1.240806.017.V816.0.25.12.1.ULBMIXM; matching-signer receiver update preserved accessibility and pairing identity. Google Remote Service was reachable. | The TV returned online after the user reopened it. The same-signed 0.1.4-beta.1 candidate is installed; encrypted pairing identity, accessibility authorization and the foreground receiver remain intact. The user enabled and selected the Sofatap input method through system settings; a subsequent system read confirmed both states. Native remote and actual application text acceptance remain pending. |

No household-TV compatibility claim follows from an APK installation, available service, software fixture or simulator result. ADB is used only for authorized development installation and diagnostics, not as a product control dependency.

## Acceptance checklist

- [x] Unit/protocol tests reject malformed commands, stale editor epochs and unauthenticated or old-controller actions.
- [x] Loopback TLS tests cover Remote v2 pairing, exact certificate pinning, handshake, heartbeat, bounded keys, disconnection and no replay.
- [x] Android emulator tests exercise a real InputMethodService/InputConnection for Unicode insertion, selection deletion, backspace, editor actions and session invalidation.
- [x] iOS tests retain old receiver compatibility and verify new capability gates, input queue ordering, appended dictation, failed/uncertain acknowledgements and reconnection.
- [x] Real idle iPhone UI fixture checks cover navigation/pointer switching, composer, keyboard controls and device-specific help. This is interface verification with synthetic receiver responses, not physical-TV control or pairing acceptance.
- [ ] Both physical TVs complete ordinary Remote Service code pairing; saved credentials reconnect after receiver restart.
- [ ] In YouTube and Netflix on each TV, up/down/left/right move focus, OK opens the selected item, Back returns and Home exits. Rapid gestures do not delay explicit Back/Home or cause disconnection.
- [ ] In a browser editor on each TV, the normally selected Sofatap input method receives phone-entered Chinese, English and emoji, appended dictation, backspace and the editor action. Changing fields or apps invalidates old text actions.
- [ ] Phone tactile feedback is confirmed by a person. Automated event/call verification alone does not establish perceived vibration.

See the [protocol contract](../research/tv-native-controls-protocol.md) for distinctions between transport acceptance, input framework acceptance and visible application response.

## Software and interface verification

The Android receiver passed 115 JVM tests, lint with no errors, and a debug build. Independent review found a natural-disconnect ownership race; the fix and a deterministic reconnect regression passed. Native key enqueue also rechecks generation under the lifecycle lock. A headless Android TV API 31 emulator passed 20 instrumentation tests, including eight real InputConnection tests. The emulator tests neither type into the host desktop nor establish household TV compatibility.

The iOS protocol/controller suite passed 228 checks; gesture configuration (54), touch gestures (66), device guide routing (23), pairing routing (73) and pairing attempts (89) also passed. All 12 shipped languages contain 433 interface strings and five permission descriptions, with matching keys and format arguments. The unchanged Swift-to-Java TLS/WebSocket integration suite passed all seven milestones, including five ordered move/click/scroll/Back/Home actions, credential recovery and no replay. A review follow-up corrected Back/Home discarding unrelated queued clicks and retained the original interoperability expectations.

An exclusively leased iPhone 16 Pro Max ran a development-only, network-disabled UI fixture. The first pass checked navigation/pointer switching, the TV-first guide, compact text controls, keyboard show/hide, Chinese/English/emoji input and two sequential acknowledged draft sends. The fixture visibly identifies itself as `UI test · No TV`; its acknowledgements do not come from a household television. That pass found and corrected a disabled scroll rail in navigation mode and a mouse illustration in the remote guide.

The final gesture-led build was checked again on that physical iPhone. Desktop and TV keyboard/microphone button rectangles matched exactly. Left/up swipes, tap-to-confirm, Back, Home, and the optional direction sheet produced the expected synthetic command types. Chinese/English/emoji text was read back exactly; one acknowledged send cleared the draft while keeping the keyboard open. Remote backspace, editor action and keyboard hiding were verified through the fixture. The updated TV-first guide and compact layout were visually inspected. These checks do not establish perceived haptics, microphone transcription, system-code pairing or visible behavior in household TV apps.

## Gesture-led interface

The keyboard and microphone retain the same anchors as desktop control. TV-only Back, Home and mode/setup controls occupy a separate compact area. The TV surface uses directional swipes and tap-to-confirm; directional hints appear during touch and fade after release. Back/Home and other auxiliary controls cancel any resting touch before sending their command, and the optional direction-button sheet retains keyboard focus until dismissed. This is free manual control. Speech dictation is still basic text input, and the later paid autonomous voice loop remains a separate feature.
