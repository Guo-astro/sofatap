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

## Physical acceptance boundary

The resident test iPhone was upgraded in place to 0.7.0 (10), and the Windows
frontend and backend were upgraded to 0.7.0 at the implementation commit above.
Existing pairing was retained. The phone reconnected automatically, opened the
keyboard and imported the fixture's existing Chinese text, emoji, line break and
selection; the live status appeared without a Send button.

Physical editing and microphone acceptance are **pending**. Before sending edits,
a fresh visual check found a Windows firewall permission prompt from the host
test runner obscuring the fixture. Native foreground-window checks alone had
reported the fixture as ready. The test was paused without sending phone edits
or changing firewall rules. After explicit authorization to cancel the prompt,
the computer-use tool rejected a click scoped to the fixture because the button
belonged to Windows Security. Its supported window API also failed to bind the
observed system window. No cancel or permission-grant click executed. Physical
editing and microphone testing therefore remain blocked on dismissal of the
system prompt. Both mobile test devices were returned to their home screens and
released; the unused voice playback server was stopped. The RDP viewer and
physical displays were left in place.

Use the resident test iPhone and dedicated Windows Edit/RichEdit fixture only.
The Windows RDP viewer must remain on the non-primary Yomado virtual display,
with physical display topology unchanged. Test input travels directly to the
Windows receiver; Mac foreground keyboard/mouse injection is not part of this
test. Verify Windows field contents and selections after each action, including
already-existing text, Unicode, selection-only changes, deletion, partial speech,
focus conflicts and reconnect behavior. Also confirm the visible target is free
of system prompts or overlays; native foreground identity alone is insufficient.

Do not publish pairing credentials, QR images, private device identifiers or raw
field logs. See [protocol and content lifetime](../../PROTOCOL.md) for how the live
session handles field contents.
