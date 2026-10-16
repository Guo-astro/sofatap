# Native TV navigation and phone text input

Implementation contract, October 17, 2026. This is an experimental extension; the acceptance record, not this design, determines supported hardware and applications.

## Separate input paths

The existing receiver pointer selects exposed accessibility nodes. It cannot substitute for remote-control key events in apps such as YouTube or Netflix. Navigation mode sends actual D-pad, center, Back and Home keys through the television's Android TV Remote Service. Pointer mode retains its existing semantics and limitations.

The receiver connects only to its own local Remote Service (loopback, pairing port 6467 and control port 6466). The phone continues to use the authenticated, pinned Sofatap WebSocket. Starting Remote Service pairing is an explicit action; the user enters the code shown by the television. Runtime control does not use ADB. Pairing verifies the code challenge, and subsequent connections verify the saved television certificate. Receiver and Remote Service credentials are distinct.

Text uses a separately enabled Sofatap input method and the currently active Android `InputConnection`. The user enables and selects it through normal television settings. Phone keyboard input and speech-to-text use the same text path; neither starts an autonomous task. A page that does not expose an Android editor is not promised to support text entry.

## Backward-compatible extension

Keep the existing `hello.version = 1` and legacy capabilities unchanged, including `capabilities.text = false`. Older iPhone builds require that value. New clients inspect the optional `tvControls` object in hello, ping acknowledgements and extended-action acknowledgements:

```json
{
  "version": 1,
  "navigationStatus": "pairing_required",
  "textStatus": "no_editor"
}
```

`navigationStatus` is `unsupported`, `pairing_required`, `pairing`, `ready` or `unavailable`. `textStatus` is `ime_required`, `no_editor`, `ready` or `sensitive`. A `ready` text status includes an opaque UUID `editorEpoch`; other text statuses omit it. Neither editor contents nor pairing codes appear in status messages. Absence of the extension means the receiver only supports the legacy operations.

All commands retain the existing UUID action ID and authenticated single-controller connection. Unknown fields, malformed values and unsupported commands are rejected.

| Type | Additional fields | Meaning |
| --- | --- | --- |
| `remote_pair_start` | None | Begin explicit local Remote Service authorization. |
| `remote_pair_code` | `code`: six hexadecimal characters | Complete the displayed pairing challenge. |
| `remote_key` | `key`: `up`, `down`, `left`, `right`, `confirm`, `back`, `home` | Send one discrete remote key press. |
| `text_commit` | `editorEpoch`, `text` | Commit valid Unicode text, at most 4096 UTF-8 bytes, without NUL. |
| `text_backspace` | `editorEpoch` | Delete at the current editor selection/caret. |
| `text_action` | `editorEpoch` | Invoke the current editor's action, such as Search. |

## Ordering and feedback

The phone produces immediate touch feedback for accepted discrete presses. This confirms the phone registered the press; a successful transport acknowledgement does not prove a third-party app changed its screen. Rejections remain visible and have separate feedback.

Navigation gestures are rate limited and queue bounded. Movement must not starve Back or Home. Reconnection never replays actions. Pairing work is asynchronous and does not block the input loop waiting for a user to read a code.

Text commits are bound to the current controller and editor epoch. Starting or restarting an editor, leaving it, losing the input-method connection or disconnecting the controller invalidates stale commands. The main-thread application step checks the authority and epoch again. Password/sensitive editors are refused. Phone drafts are not copies of the television's whole field, and an uncertain acknowledgement must not cause automatic resend. Appending another dictation must send only the unsent draft.

## Evidence and references

- [Android TV Remote v2 reference implementation](https://github.com/tronikos/androidtvremote2), Apache-2.0; protocol behavior must be verified against physical devices.
- [Google's phone remote pairing flow](https://support.google.com/googletv/answer/11136134).
- [Android input-method development](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method) and [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection).
- [AccessibilityService global actions](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService): real D-pad global actions require API 33 or later, so they do not cover the household Sony Android 12 television.
