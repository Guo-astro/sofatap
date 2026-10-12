# Sofatap 0.6.0: physical iPhone to isolated recording receiver

Date: 2026-10-12. This is a bounded device test, **not full macOS input acceptance**.

The resident test iPhone 16 Pro Max ran iOS 18.6.2 and the development-signed
Sofatap 0.6.0 / build 9 app. iPhone Use 0.3.9 operated the phone. The Mac ran
macOS 27.2 on arm64 with Yomado 0.3.3 / build 9. The iPad was not used.
The tested interaction code is based on `861367ae901c1c0326f445c0807d26b2af38b780`,
with the two pairing-display fixes accompanying this report. Both fixes were
rebuilt, installed, and checked on the physical phone.

## Isolation

Yomado's display shares the current macOS login session's input and focus. The
production Mac injector posts global Quartz events, so moving its window onto
a virtual display would not isolate those events.

This run instead used the test-only [recording receiver](../../tests/device-harness/README.md)
and [native read-only canvas](../../tests/device-harness-ui/README.md). The production
TLS server, authentication, protocol and acknowledgements ran unchanged, but the
input sink modified only owned memory and private test records. Focus metadata
was synthetic. No production input injector or Accessibility focus provider was
constructed. The existing installed receiver was left untouched.

The canvas was wholly inside the existing non-primary Yomado display. It could
not become key/main, ignored mouse events, and used a prohibited activation
policy. Live checks and a window-specific capture confirmed its placement and
rendered contents. Before/after-show samples had identical physical display
geometry, foreground PID and system cursor coordinates. Cleanup confirmed the
window was gone and display topology was unchanged. Matching samples do not
claim continuous observation of the user's activity.

## Physical-device results

| Check | Observed result |
| --- | --- |
| Install and native UI | 0.6.0 / build 9 installed and launched; current logo, mint controls and dot matrix visible |
| Camera entry | Native scanner opened and camera permission completed; actual QR capture was not performed |
| Invalid pairing | Incomplete link rejected without connecting |
| LAN pairing | Full private pairing link saved through native UI; local-network permission completed; TLS connection established to the test receiver's distinct host/port |
| Movement | One swipe and the drag produced 23 recorded movement messages |
| Single / double tap | Exactly one left click and one right click; double tap did not add a left click |
| Hold and drag | A 400 ms stationary hold followed by movement produced left-button down, movement, then up; no button remained held. This does not measure the exact 300 ms threshold or subjective latency |
| Two-finger scroll | 15 scroll messages and no extra click; direction matched the upward finger movement |
| Unicode draft | Chinese, Japanese, English, emoji and a newline matched exactly in the receiver record |
| Explicit send | Draft editing produced zero text events; Send produced exactly one text event and zero key events, with no extra Enter |
| Duplicate-send UI | Completed send disabled the button; manual resend opened a confirmation; cancelling did not resend |
| Background / reconnect | Backgrounding released recorded state; foregrounding reconnected without replaying text |
| Draft persistence | An unsent synthetic draft survived backgrounding and an app update/relaunch; it was never transmitted |
| Automatic keyboard | Synthetic editable-focus metadata opened the keyboard and began a fresh composition after the prior confirmed send |
| Manual dismissal | Keyboard stayed hidden across subsequent heartbeats for the same simulated field |
| Protected field | Synthetic protected-focus metadata did not open the keyboard and disabled the microphone |
| Speech lifecycle | Speech and microphone permissions completed; on-device recording started and stopped; empty recording produced no transmitted text |
| Shutdown | Stopping the test server disconnected the phone and disabled controls; listener closed and held-state cleanup completed |
| Cleanup | Test draft cleared and temporary phone pairing removed; test server and canvas stopped; temporary signing/pairing values were not published |

The synthetic text fixture was:

```text
Sofatap 测试 / 日本語 / Hello 👋
第二行 123
```

## Fixes found during the run

- Pairing instructions and errors now refer to the computer receiver instead of
  implying that only a Windows window can provide the link.
- Pairing host/port uses verbatim text so locale number formatting does not turn
  port `54439` into `54,439`. The corrected address was observed on the iPhone.

Supporting checks passed: 239 existing host checks, 24 native pairing checks,
15 recording-sink checks, 9 real TLS/ACK/deduplication/focus/disconnect checks,
and 8 harness startup/private-file/shutdown checks. The native canvas compiled
with warnings treated as errors. A separate review confirmed that the production
host's evaluated build items do not include the new test harness.

## Still unverified

- Input consumed by TextEdit, browsers or other real Mac applications; real
  Accessibility input-field detection; production receiver TCC behavior.
- Physical camera recognition of the pairing QR code.
- Spoken-audio recognition accuracy, system dictation and Typeless workflows.
- Full animation timing, reduced-motion behavior, slow/fast pointer feel,
  exact hold threshold, drag interruption while held, and input latency.
- Real mid-send network loss/uncertain delivery, device lock/unlock, Windows,
  Linux, iPad, and the proposed Windows PIN / Face ID path.

These remain separate acceptance tasks. The shared Mac must gain a verified
isolated input session before production OS input tests can run without affecting
the user's normal desktop. A virtual monitor alone does not provide that session.

Local evidence is retained under `artifacts/device-acceptance-2026-10-12/`
(Git-ignored): synthetic event/state records, window captures, placement checks
and cleanup evidence. Pairing secrets, QR images, private keys, account/device
identifiers and runtime sessions are excluded from this public report and commits.
