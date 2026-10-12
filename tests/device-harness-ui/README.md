# Isolated device-test drawing window

This optional native macOS test window visualizes the private recording from
`tests/device-harness`. It does **not** exercise the production macOS input
injector or establish that any other Mac app received input.

It reads one local `state.json`; it never opens pairing files or displays a real
QR code. It draws its own pointer, trail, action counts and test text. It has no
editable field, keyboard handler, mouse handler, Accessibility access, event
posting, clipboard use, network listener or application activation. The state
must have `schemaVersion: 1`, `mode: "isolated-recording-only"` and
`osInjection: false`.

Build only (does not launch an app):

```sh
bash tests/device-harness-ui/build.sh /tmp/sofatap-device-harness-ui
```

Before launching, use the installed Yomado `--diagnose` command to select the
currently active virtual display ID. Never assume an old ID is still valid.
The harness requires Yomado's vendor/model pair (`505` / `0x5644`) and rejects
the primary display. Example invocation, **only after that read-only check**:

```sh
/tmp/sofatap-device-harness-ui \
  --display-id 20 \
  --state /absolute/private-test-directory/state.json \
  --evidence-dir /absolute/private-test-directory/ui-evidence-unique \
  --duration 900
```

The evidence directory must not already exist. It is created with mode `0700`,
and its JSON files use `0600`. The duration is bounded to one hour. The harness
closes itself on any display topology change or failed window-placement check.
It never changes displays or attempts to restore a user's pointer or focus.

The window uses `.prohibited` activation policy, a nonactivating `NSPanel` that
cannot become key/main, `ignoresMouseEvents`, and `orderFrontRegardless()`.
It verifies the actual activation-policy getter before and after launch; an
already-prohibited CLI does not need a policy change. Any other policy is refused.
It is positioned wholly inside the selected virtual display before appearing.
No other windows are moved. Closing this new test window is the only cleanup
needed; physical display geometry is never edited.

`before.json`, `after-show.json` and `after-close.json` contain display geometry,
pointer location and frontmost PID. `show-verification.json` compares the
before/after samples, checks that the harness window is on its assigned virtual
display, and records that it was neither key nor main. If the user moves the
mouse or changes apps between samples, the corresponding result correctly says
changed. A changed foreground during the initial show check closes only this
test window and preserves the failed verification, even if a user app switch may
explain it. A matching sample is useful evidence, not a guarantee about the whole
interval or production OS event delivery. No screenshot is taken automatically.

The recorded `focus` value is a synthetic field-state test fixture. Text shown
in this drawing is recorder output, not text entered into a real Mac input.
