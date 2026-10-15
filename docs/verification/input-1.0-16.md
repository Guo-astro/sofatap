# Sofatap 1.0 build 16 input verification

Checked on 2026-10-14. This is a development build installed on the dedicated physical iPhone 16 Pro Max (iOS 18.6.2). It has **not** been uploaded to TestFlight. Build 15 retains its previous gestures.

A later release containing these changes and the receiver-restart fix was published to TestFlight on October 16. Its separate [distribution record](testflight-1.0-16.md) confirms approval and installation; it does not expand the input-test scope below.

## Changes

- The desktop touch surface has invisible physical left/right halves. A single tap anywhere sends one left click after the existing 280 ms double-tap decision. Two taps in the left half send two left clicks; two in the right half send two right clicks, without a preceding left click. No divider or instructional text was added to the touch surface. The illustrated guide explains the halves in all 12 languages.
- Long-press dragging remains 300 ms. Two-finger natural scrolling, the opposite-direction edge scroll strip, and the separate TV pointer profile remain unchanged.
- A secondary Backspace icon below the composer acts on the computer's focused input. In live editing it deletes through the text snapshot and selection; in fallback mode it sends a Backspace key and preserves the local draft and sent-text receipt.
- Keyboard Backspace on an empty fallback draft is forwarded when no sent-text receipt remains. Deleting a nonempty fallback draft stays local. Clear the local draft or use the explicit computer Backspace icon to edit text already on the computer.
- Composition, uncertain text delivery, paused/loading live editing, protected or explicitly non-text focus, dragging and disconnection prevent remote Backspace. The UI also disables it during speech capture/finalization.

## Automated checks

| Check | Result |
| --- | --- |
| Deterministic touch state | 93 passed, including each half, cross-half/cross-divider taps, cancellation, drag and TV behavior |
| Native UIKit draft editor, offscreen | 41 passed, including empty Backspace and local/marked-text separation |
| Explicit-send controller | 61 passed, including post-Backspace append receipts and blocked states |
| Live-text controller | 63 passed, including Unicode/emoji, selection deletion and pending-update coalescing |
| Edge scrolling | 33 passed |
| Drag release controller | 33 passed |
| Localization | 12 locales, 317 interface strings and 5 permission descriptions each |
| Device compilation/signing | Xcode Debug device build succeeded; install succeeded; 56 staged Swift/string files matched the working source byte-for-byte |

These checks create no desktop input or foreground windows.

## Physical phone to isolated recording receiver

The phone connected by a private deep link to the production TLS/protocol server with the test-only `RecordingInput` sink. Its distinct port and established connection to the test phone were checked; `osInjection` was false. No desktop receiver, RDP viewer, physical display layout, global pointer or keyboard focus was operated. The test used no desktop windows, so no window placement was required. This is phone/transport acceptance, not Windows application acceptance or optical QR scanning.

Between 11:24 and 11:27 UTC:

1. A real one-finger double-tap on the left half recorded exactly two left clicks and zero right clicks.
2. A double-tap on the right half added exactly two right clicks and no left clicks or moves.
3. Sending `Sofatap ABC` produced that exact synthetic receiver text.
4. The computer Backspace icon changed receiver text to `Sofatap AB`, with exactly one key event; the phone retained `Sofatap ABC`.
5. Appending `D` on the phone and sending produced `Sofatap ABD`, proving the prior sent prefix was not resent after Backspace.
6. Clearing the local draft preserved receiver text. Tapping the real iOS keyboard Delete key on the empty draft changed receiver text to `Sofatap AB`, with one additional key event.
7. Keyboard deletion of a local `XYZ` draft produced `XY` on the phone and no new receiver key event or text change. Cancelling a marked character also produced no receiver key event.

The new action row and guide were inspected on the physical phone. The test draft and temporary pairing were removed, the prior foreground app was restored, the device lease released, and the recording listener stopped. Private raw events, install receipt and source hashes are retained outside Git; pairing credentials are excluded.

## Remaining acceptance

Gaming PC was reachable over Tailscale, but its Yobiru receiver did not answer `/info`; the read-only coordination request failed before delivery. No Windows session was activated or desktop input injected. Actual `WM_LBUTTONDBLCLK` / application opening, right-button behavior and Backspace consumption in a real Windows input field remain pending. Existing click/key protocol frames are unchanged, so no receiver upgrade is required by this change. Actual desktop tests must still verify the dedicated target and Yomado input isolation before sending input.
