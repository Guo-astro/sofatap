# Sofatap 0.7.0 live text validation

Development version: iPhone 0.7.0 (10), receiver 0.7.0. Date: 2026-10-13.

## Implemented behavior

Supported focused fields use live editing by default. The phone imports their
current text and selection, then synchronizes committed keyboard edits, selection
changes and speech recognition revisions without a Send button. Marked IME text
remains local until committed. Speech replaces the selection present when
recording starts and retains text outside that insertion.

Each request is based on the last acknowledged editing revision. Focus, text or
selection conflicts pause editing; unconfirmed edits are not replayed. Native
backends replace the changed span and read back the result. Passwords, read-only
fields and unsupported native controls do not enter live editing.

Windows support currently covers native Unicode Edit/RichEdit controls in the
unlocked receiver session. Mac support requires writable Accessibility selected
text and selected-range attributes. Unsupported fields, older receivers and Linux
retain explicit draft sending. Browser/custom controls are not covered by the
Windows native adapter.

## Automated and build checks

- 362 host checks, including native coordinate/difference checks and a real
  pinned-TLS/WebSocket session with recording input backends. The live wire test
  covers field import, selection, deletion, duplicate suppression, unsupported
  fields, bounded Chinese text and connection cleanup.
- 58 existing TLS/WebSocket dry-run checks.
- 57 iOS live controller and offscreen UIKit checks, 22 existing UIKit editor
  checks and 26 drag ordering checks. Live checks include actual UIKit backspace,
  select-all, selected deletion and IME composition; no desktop events are sent.
- 42 receiver metadata checks.
- Full signed iOS development build, Windows x64 package and ad-hoc Mac arm64
  package succeeded. The new Mac package has not been notarized or installed.
- [GitHub CI run 38349722835](https://github.com/chekusu/sofatap/actions/runs/38349722835)
  passed all three jobs (Windows, macOS and isolated Linux) for implementation
  commit `01b8990d30e070e07edf4ba039ebfc832df272bd`.

These checks do not establish physical iPhone-to-Windows editing. The earlier
[gesture and explicit-send report](2026-10-13-iphone-input.md) does not cover the
new live path. See the current device acceptance status below.

## Windows native integration

At 05:16 UTC on 2026-10-13, an external test driver using the production
`WindowsTextEditor` and `LiveTextSession` passed against dedicated WinForms
RichEdit and multiline Edit controls in the unlocked receiver session. It checked
existing Chinese text, emoji and line breaks, appending, simulated backspace,
selection-only select-all, deletion to empty and simulated speech revisions.
All 16 expected mutations were confirmed by native readback. The additional
attempt after changing field focus returned `live_text_changed` and did not
modify either field. Both fields were restored to their initial test contents.
Each mutation was gated on the owned fixture's process, window, session and
foreground focus. No Mac keyboard or mouse events were used.

The Windows host suite passed 361 checks; the additional check in the 362-check
Mac run is specific to Unix file permissions. These native integration results
exercise real Windows controls, but do not represent physical keyboard or
microphone actions on the iPhone.

## Physical iPhone-to-Windows acceptance

The resident test iPhone runs 0.7.0 (10), with Windows frontend and backend 0.7.0
at implementation commit `01b8990d30e070e07edf4ba039ebfc832df272bd`.
Existing pairing was retained. Tests use a dedicated native RichEdit fixture on
Windows, viewed through RDP on the non-primary Yomado virtual display. The Mac
viewer is read-only: phone input goes directly to Windows, with no Mac keyboard
or mouse injection and no physical display topology change.

The earlier firewall-prompt blocker was resolved at 06:09:46 UTC on 2026-10-13:
the authorized **Cancel** action was performed by a real Sofatap phone click.
No firewall permission was granted. The fixture was visibly unobstructed before
editing resumed; foreground-window metadata alone was not treated as sufficient.

The phone imported the existing synthetic text `已有文字 🛋️\n第二行` (12 UTF-16
units) and its selection. It displayed live editing without a Send button. The
following real phone actions were confirmed by Windows screenshots and separate
native fixture text/selection events:

| UTC | Phone action | Native RichEdit result |
| --- | --- | --- |
| 06:11:19 | Append ` · Sofatap\n中文・日本語 🛋️` | Exact 33-unit text; caret at 33, no selection |
| 06:11:55 | Tap the iOS keyboard Delete key once | Complete trailing 🛋️ removed (three UTF-16 units); 30 units remain |
| 06:12:15 | Use the phone's Select All control | Native selection starts at 0 and covers all 30 units |
| 06:12:36 | Tap the iOS keyboard Delete key | Empty native field; selection 0 + 0 |

No Send action was needed for any of these edits. This confirms import, append,
multilingual/emoji/newline preservation, real keyboard deletion, selection-only
synchronization and deletion to empty in this RichEdit fixture.

The run stopped before live microphone acceptance. A read-only RDP capture had
selected the Windows App connection manager; after restoring the RDP capture,
the receiver window was visibly covering the fixture. Fresh native state at
06:32:53 UTC confirmed that the fixture was not foreground and neither its
empty RichEdit nor plain Edit field had focus. The Windows helper's automatic
approval review rejected both `get_window` and `activate_window` with
`Computer Use was not approved to use livetextfixture`. No target-focus click,
input attempt or workaround followed. No microphone test or iPad reference-audio
playback was started in this run.

Cleanup was confirmed at 06:33:49 UTC: both test devices were returned to their
home screens, the owned reference-audio server was stopped, and the device lease
was released. A fresh Yomado check confirmed the Windows RDP window remained on
the non-primary virtual display and the physical displays retained their original
resolution and primary-display assignment. No Mac keyboard/mouse events, window
moves or display-configuration changes were performed.

Physical microphone/live-speech, the separate plain Edit field, replacement in
the middle of text, conflict and reconnect cases remain pending in this round.
The earlier Windows native integration driver covers some of these mechanisms,
but is not a physical iPhone test. Mac live editing has not had a device test;
Linux and unsupported browser/custom controls retain fallback sending. This
scoped result does not establish compatibility with all desktop applications.

Do not publish pairing credentials, QR images, private device identifiers or raw
field logs. See [protocol and content lifetime](../../PROTOCOL.md) for how the live
session handles field contents.
