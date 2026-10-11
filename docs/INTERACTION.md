# Sofatap single-screen interaction

## The phone is the touchpad

The main iPhone screen has a small connection/pairing header, one large touch surface and a bottom microphone button with a keyboard affordance. It has no mode picker, separate left/right mouse buttons, drag button, shortcut grid or sensitivity slider. The five desktop visual proposals remain unselected; this interaction change does not select a receiver theme.

- Slide one finger to move the computer pointer.
- Tap once for a left click. Delivery waits briefly for the double-tap decision so a right click never includes an accidental left click.
- Tap twice with one finger for a right click.
- Hold still for **300 ms** to press the left mouse button, then move to drag. Lifting the finger ends the drag. Cancellation, loss of control and leaving the app release the held button; the receiver independently releases owned input on disconnect.
- Slide two fingers to scroll, keeping scrolling on the same surface.

Pairing remains an occasional sheet, rather than a second everyday control mode. A text composer appears inline only when needed. Existing uncertain-delivery and manual resend safeguards remain available in that composer.

## Voice and keyboard input

An explicit microphone tap requests the iPhone's microphone and Speech permissions and starts local speech recognition when the device/language supports it. A second tap stops capture. Audio is not sent to the desktop or a model service. Partial recognized text stays in the local draft, and the user taps Send to type it into the computer's currently focused field. The app does not append an Enter or form-submit action.

If local recognition is unavailable or permission is denied, the same composer accepts the iPhone keyboard, system dictation or Typeless. The app does not use a private API to start keyboard dictation. Backgrounding, interruption and cancellation stop microphone capture. A successful transport acknowledgement means system input was submitted, not that an application saved or submitted the text.

The receiver reports a small focus hint: `editable`, `other`, `protected` or `unknown`, plus a connection-local revision. The phone automatically opens the keyboard on a new editable target. Dismissing the keyboard keeps it dismissed for that same target. It does not automatically start recording. Protected or unknown targets never automatically open input UI. The manual keyboard remains available when a target does not expose accessibility information.

Focus detection uses native accessibility metadata and does not read the field value, selection, window title or password. Availability varies with the target app and desktop; “any input field” is a design goal, not a promise that every custom game/browser widget exposes accessibility metadata. Windows and Mac need native provider validation, and Linux requires an available accessibility bridge in addition to its input-control permission. Old receivers remain usable with manual keyboard selection.

## Future voice-controlled computer actions

The intended next stage is a standalone computer-use service: spoken command → intent/planning → explicitly authorized observation and bounded mouse/keyboard execution → progress or clarification on the phone. It must run as part of Sofatap's own product, independently of Codex. The current app and receiver already communicate directly; Codex is a development tool, not their runtime.

Dictating text and asking the computer to act are separate intents. Dictation must never silently become a command. A future command session will have an explicit start/stop boundary and visible progress on the same phone surface. Screen capture, model credentials, observation privacy, cancellation and confirmation for consequential actions need their own implementation and validation. Untrusted text from a webpage or desktop app cannot grant additional authority to the agent.

No CUA model, cloud transcription, screen streaming or arbitrary-command endpoint is enabled by this change. The existing authenticated, certificate-pinned action channel and native receiver permission gates remain the executor boundary.

## Validation boundary

Gesture timing, focus metadata, transport and compile checks can be automated without moving the user's real pointer. Real iPhone gesture/voice behavior and third-party target coverage require later device acceptance. On the shared Mac, all receiver acceptance windows and input targets must first be isolated through Yomado on a virtual display; moving a window alone is insufficient.
