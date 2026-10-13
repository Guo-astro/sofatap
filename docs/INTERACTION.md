# Sofatap single-screen interaction

## The phone is the touchpad

The main iPhone screen is one large rounded touch surface. The logo and QR-scanning control sit inside its top edge; the microphone and left-hand keyboard control sit inside its bottom edge. The resting surface has no instructional text or separate mouse-arrow graphic. Connection and recording states use icons with accessible labels. Tapping the logo opens connection details and gesture help; the QR control opens the pairing sheet. The five desktop visual proposals remain unselected; this phone interaction change does not select a receiver theme.

- Slide one finger to move the computer pointer.
- Tap once for a left click. Delivery waits briefly for the double-tap decision so a right click never includes an accidental left click.
- Tap twice with one finger for a right click.
- Hold still for **300 ms** to press the left mouse button, then move to drag. Lifting the finger ends the drag. Cancellation, loss of control and leaving the app release the held button; the receiver independently releases owned input on disconnect.
- Slide two fingers to scroll, keeping scrolling on the same surface.

Pairing remains an occasional sheet, rather than a second everyday control mode. A text composer appears inline below the touch surface only when needed. Existing uncertain-delivery and manual resend safeguards remain available in that composer.

## Touch feedback

A gently moving dot matrix fills the touch surface, including its resting state. Touch locally displaces and bends nearby dots; dragging strengthens the deformation, and release lets the field settle back. Single and double taps keep distinct expanding ripples that also perturb the field. These effects visualize the phone gesture, not the computer pointer's position or confirmation that a desktop application acted on it. Tapping the logo, QR, microphone or keyboard control must not also send a mouse gesture.

Effects remain inside the touch surface. Reduce Motion keeps the matrix static and uses simpler touch feedback. App inactivity, detachment and disconnect pause ambient animation. Touch cancellation clears the local deformation and releases any held mouse button while the active field can keep drifting. Screen-reader labels describe the icon controls without adding visible instruction text to the surface. The text composer and pairing sheet retain the wording needed to review drafts, errors and connection details.

## Voice and keyboard input

An explicit microphone tap requests the iPhone's microphone and Speech permissions and starts local speech recognition when supported. A second tap stops capture. Audio stays on the iPhone. In a supported live field, partial recognized text and later corrections synchronize while the user speaks; stopping keeps the already synchronized text. In the fallback composer, partial text stays in the local draft until Send. Neither mode appends an extra Enter or form-submit action.

If local recognition is unavailable or permission is denied, the same composer accepts the iPhone keyboard, system dictation or Typeless. The app does not use a private API to start keyboard dictation. Backgrounding, interruption and cancellation stop capture. In live mode, confirmed IME text, Backspace, selection changes and Select All → Delete edit the imported existing computer text. In fallback mode they edit only the local draft. A live ACK confirms native text/selection readback; a fallback ACK confirms system event submission. Neither proves application save or form submission.

The receiver reports a small focus hint: `editable`, `other`, `protected` or `unknown`, plus a connection-local revision. The phone automatically opens the keyboard on a new editable target, waiting until an active drag is released so the keyboard does not interrupt it. Dismissing the keyboard keeps it dismissed for that same target. It does not automatically start recording. Protected or unknown targets never automatically open input UI. The manual keyboard remains available when a target does not expose accessibility information.

Background focus detection uses native accessibility metadata and does not read the field value, selection, window title or password. Opening the phone editor starts a separate live-session request that reads the supported field's complete text and selection. The imported live value stays in memory; the fallback draft remains locally saved. Windows live editing is limited to native Edit/RichEdit controls; Mac requires writable AX selected text and selection range. Unsupported browser/custom controls, Linux and older receivers use review-and-send. See [focused-field detection and data handling](TEXT-FOCUS.md).

Live editing is the default where supported. A focus, text or selection conflict, disconnection or uncertain write pauses it and never causes automatic replay. The user checks the computer and explicitly reopens editing. Native replacements touch only the changed span; surrounding text and formatting are preserved. This is distinct from a promise of compatibility with every input field.

## Future voice-controlled computer actions

The intended next stage is a standalone computer-use service: spoken command → intent/planning → explicitly authorized observation and bounded mouse/keyboard execution → progress or clarification on the phone. It must run as part of Sofatap's own product, independently of Codex. The current app and receiver already communicate directly; Codex is a development tool, not their runtime.

The [October 13 architecture research](research/natural-language-pro.md) evaluates pi-durable, Cua Driver and DeepSeek for an optional paid tier, including recovery, platform limits and qualification gates. It is a proposal, not an enabled feature.

Dictating text and asking the computer to act are separate intents. Dictation must never silently become a command. A future command session will have an explicit start/stop boundary and visible progress on the same phone surface. Screen capture, model credentials, observation privacy, cancellation and confirmation for consequential actions need their own implementation and validation. Untrusted text from a webpage or desktop app cannot grant additional authority to the agent.

No CUA model, cloud transcription, screen streaming or arbitrary-command endpoint is enabled by this change. The existing authenticated, certificate-pinned action channel and native receiver permission gates remain the executor boundary.

## Validation boundary

Gesture timing, focus metadata, transport and compile checks can run without moving the user’s real pointer. The [0.7.0 scoped physical record](verification/realtime-input-0.7.0.md) confirms iPhone-to-Windows RichEdit import, append, deletion and selection; live speech and further cases remain pending. The [0.6.0 record](verification/2026-10-13-iphone-input.md) separately covers gestures and explicit-send microphone input. Offline previews do not establish frame rate or input latency, and Reduce Motion, Typeless and broader target coverage still need their own acceptance. On the shared Mac, receiver windows and input targets must be isolated through Yomado; moving a window alone is insufficient.
