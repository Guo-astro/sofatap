# Sofatap: physical iPhone input acceptance

Date: 2026-10-13. The requested draft, right-click, drag, scroll and speech
checks passed on the physical test iPhone and Windows target.

The test used an iPhone 16 Pro Max running iOS 18.6.2 and the Windows receiver
`0.6.0+63cf4c7`. The Windows RDP viewer was already on a non-primary Yomado
virtual display. Physical display topology remained unchanged. Mac desktop
interaction was read-only: test input traveled directly from the iPhone to a
dedicated, non-sensitive Windows test window in the receiver's unlocked session.
Moving the RDP window alone was not treated as proof of input isolation.

## Observed results

| Check | Status | Evidence |
| --- | --- | --- |
| Multilingual draft and delivery | Passed | A three-line draft containing Chinese, Japanese and emoji matched the Windows target exactly: 55 UTF-16 code units. |
| Double tap for right click | Passed | Exactly one RightDown/RightUp pair opened the target's context menu. No left-button event was recorded. |
| Two-finger scrolling | Passed | 18 wheel events totaled −800; the first visible line moved from 0 to 18. No button events or pointer movement accompanied the gesture. |
| Hold and drag, initial build | Failed; fix implemented | A 400ms hold started a drag, but the final movement arrived 9.2ms after LeftUp. The dragged object stopped before the pointer's final position. |
| Hold and drag, corrected build | Passed | After a 400ms hold, the pointer and object both moved (+47, −115) pixels. All six position-changing movements occurred with the left button held; none occurred after release. |
| Acoustic speech recognition | Passed with a fix | Audio played by a nearby iPad was captured by the iPhone microphone and recognized as a 14-character phrase. A subsequent empty final result originally erased it. With the fix, the real recognition trace rejects that empty result and retains all 14 characters. |
| Recognized speech delivered to Windows | Passed | One explicit Send delivered the retained microphone transcript and its draft prefix exactly once as two lines. Native Windows CRLF normalized to LF matched all 20 UTF-16 code units, without missing or additional characters. |

## Regression findings

The draft editor could receive a SwiftUI render between UIKit's text mutation
and its delegate notification. The new synchronization preserves the current
native edit and explicit model replacements. Twenty-two offscreen UIKit checks
pass; a deterministic race case fails with the old implementation and passes
with the fix. The earlier isolated report of a missing character was not itself
reproduced, so the deterministic regression and the successful physical Unicode
run are the evidence for this repair.

The drag fix freezes the final queued movement, waits for any in-flight movement
ACK, acknowledges the tail, then releases the button. New gestures cannot overtake
that release. Twenty-six controller checks cover ordering, rejection and the
distinction between a pending release and actual connection loss. Waiting for
release does not stop local dictation or reset the keyboard focus state.
Rejection or interruption keeps the existing disconnect/release
protection; an uncertain command is not automatically replayed.

The speech fix preserves a non-empty recognition result when the recognizer ends
with an empty result. This acoustic test used playback rather than a person
speaking, and does not measure recognition accuracy across speakers or rooms.

## Repeatable checks

These commands run offscreen without phone control or desktop input injection:

```sh
bash ios/scripts/test-draft-editor.sh
bash ios/scripts/test-drag-release.sh
bash ios/scripts/test-dictation-transcript.sh
python3 -m unittest discover -s tests/device-harness -p test_live_phone_gesture.py -v
```

The guarded [live gesture adapter](../../tests/device-harness/LIVE-GESTURES.md)
requires fresh target and isolation evidence for each physical gesture. Its WDA
acceptance result alone is not desktop acceptance.

## Installation and boundaries

The final development build, with temporary recognition diagnostics removed, was
signed and installed on the resident test iPhone. It reconnected to the existing
Windows receiver. The new regressions include 22 UIKit editor checks, 26 controller
checks, 16 transcript checks and 10 live-adapter guards; all passed. These run in CI
as well. The temporary acoustic server was stopped and the iPad returned to its
home screen.

This report does not establish
lock-screen/PIN input, administrator or secure-desktop control, game support,
full application coverage, Typeless compatibility, or exact 300ms timing under
load. It also does not substitute for Mac or Linux production input acceptance.

Private host/device identifiers, pairing tokens, QR codes, raw runtime receipts
and user content are excluded from this public record.
