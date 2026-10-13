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

These checks do not establish physical iPhone-to-Windows editing. That acceptance
is pending for this revision. The earlier [gesture and explicit-send report](2026-10-13-iphone-input.md)
does not cover the new live path.

## Physical acceptance boundary

Use the resident test iPhone and dedicated Windows Edit/RichEdit fixture only.
The Windows RDP viewer must remain on the non-primary Yomado virtual display,
with physical display topology unchanged. Test input travels directly to the
Windows receiver; Mac foreground keyboard/mouse injection is not part of this
test. Verify Windows field contents and selections after each action, including
already-existing text, Unicode, selection-only changes, deletion, partial speech,
focus conflicts and reconnect behavior.

Do not publish pairing credentials, QR images, private device identifiers or raw
field logs. See [protocol and content lifetime](../../PROTOCOL.md) for how the live
session handles field contents.
