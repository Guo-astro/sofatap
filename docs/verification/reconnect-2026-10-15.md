# Saved pairing and reconnection verification

Development source checked on 2026-10-15. These fixes are not included in the already distributed TestFlight 1.0 build 15 or receiver 0.7.1 beta.1. No existing App Store submission was changed by this work.

## Report and confirmed failure paths

The user reported that closing and reopening the Windows receiver after pairing did not restore the connection on the phone, and scanning again created another saved device.

- The iPhone controller attempted a connection at launch/foreground but did not schedule another attempt after a transient failure. A receiver restarting after that attempt could remain disconnected indefinitely.
- A temporarily unreadable Keychain at initialization could leave the transport's pairing empty even when the saved-device list subsequently loaded.
- The desktop receiver regenerated both its certificate and token whenever any new local IPv4 address appeared. An unrelated VPN or virtual adapter could therefore invalidate an existing home-network pairing. The phone correctly treats different certificate fingerprints as separate identities, explaining why a new scan could create a second row.

## Changes and scope

The phone restores its selected credential and device library from one successful storage read and retries transient transport failures with capped backoff. Recovery stays bound to the selected device. Authentication/TLS/protocol rejection, manual disconnect, pairing cancellation, backgrounding and target changes retain explicit control boundaries. Reconnection clears pending input and does not replay it.

The receiver preserves its certificate and bearer token when network addresses are only added, only removed, or the computer is temporarily offline. Only SAN-covered addresses are advertised. Replacing an old address with an uncertified new one still renews the certificate, even if a VPN address stays unchanged; first going online after an offline initial setup also generates a usable certificate. Address replacement and certificate renewal still require explicit pairing. This change does not implement LAN discovery, trust a replacement certificate automatically, or merge existing records by name/IP.

## Verification

| Check | Result |
| --- | --- |
| Host regression suite | 398 passed, including 14 credential persistence/address-change checks |
| TLS and WebSocket integration | 69 passed with OS input disabled; native quit/relaunch and forced exit/relaunch both accept the original trusted leaf and token without rescanning |
| iPhone pairing and reconnection | 89 passed with recording transport and explicit timer triggers |
| Saved device persistence | 35 passed, including fresh-store reopening, repeated scan, retained alias and selected device |
| Explicit text, live text, drag release | 61, 63 and 33 passed respectively |
| Native iPhone compilation | Unprovisioned device build succeeded; no device installation or TestFlight upload |
| Localization | 12 locales, 317 interface strings and 5 permission descriptions each |
| Independent diff review | Address-replacement and drag-timeout reentrancy findings fixed; no remaining blocking findings |

A separate Foundation `URLSessionWebSocketTask` loopback experiment observed `NSPOSIXErrorDomain 57` on normal closure, going-away closure and abrupt TCP termination, and `NSURLErrorDomain -1011` for HTTP 409 and 401. The controller retries the actual closure/409 cases while refusing 401. This establishes the Foundation error classifications independently of the Python WebSocket integration client.

The timeout regressions use the production serialization, pending-command and ACK path with a recording wire. They explicitly fire the same timeout handler used by the real timer, covering uncertain text, drag-down, final movement, mouse-up and obsolete callbacks. All automated checks use in-memory storage, temporary profiles or a receiver with OS input disabled. No test windows or real desktop input are used.

Physical iPhone-to-Windows close/reopen acceptance remains separate from these checks. Any later interactive receiver test must first establish Yomado virtual-display placement and input isolation. Existing duplicate entries with different certificate identities are preserved; this repair does not guess which record the user wants removed.
