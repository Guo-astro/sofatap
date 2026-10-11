# Sofa Tap protocol v1

Native iPhone controller and Windows/macOS receivers, local network, TLS with certificate pinning.

The `v0.1.1-alpha` release adopts the Sofa Tap brand and the `sofatap://` pairing scheme. The wire protocol remains version 1. Its new iOS bundle ID (`com.chekusu.sofatap`) and Windows profile (`%LOCALAPPDATA%\SofaTap`) do not automatically migrate previous pairing credentials; both ends must be paired again.

## Pairing

The desktop receiver shows a QR code containing:

`sofatap://pair?host=192.0.2.17&port=53319&token=<base64url-32-random-bytes>&fingerprint=<lowercase-sha256-hex-of-DER-leaf-certificate>`

No cloud service. Client stores the pairing in Keychain. Validate all QR fields: IP/hostname only (no URL path/userinfo), port 1..65535, token 32+ characters, fingerprint exactly 64 hex characters. IPv4 is the initial advertised host format.

## Connection

`wss://<host>:<port>/control`, header `Authorization: Bearer <token>`.

The iPhone validates the server leaf certificate against the scanned SHA256 fingerprint. Do not install a root CA, disable trust globally, or accept other certificates. Server denies browser Origins and unauthenticated requests. One controlling connection at a time. Text is never logged. A transport failure or reconnect must not replay input automatically. Each connection has a bounded cache of action IDs and their payload digest/ACK. An identical duplicate returns its original ACK without repeating input; a conflicting reused ID fails. Exhausting the cache closes the connection rather than evicting IDs that could be replayed.

## Frames

Each client frame is one UTF-8 JSON object (max 64 KiB) with a unique string `id` (UUID) and `type`. Server replies `{"type":"ack","id":"...","ok":true}` or `{"type":"ack","id":"...","ok":false,"error":"..."}`. On connection: `{"type":"hello","version":1,"name":"Computer name","platform":"macos","dryRun":false,"inputAvailable":true,"inputStatus":"ready"}`.

The additive v1 fields `platform` (`windows`, `macos`, `linux`, `unknown`), `dryRun` and `inputStatus` also distinguish `dry_run`, `accessibility_required` and `desktop_unavailable`. `inputAvailable` is false for every unavailable status. Older receivers omit the new fields; false availability must not be interpreted as proof of dry-run. Unknown statuses disable controls. A successful `ping` ACK includes current `inputAvailable`, `inputStatus` and `dryRun`, so authorization and lock changes are reflected without reconnecting. Legacy clients can ignore these additive fields.

Injection failure errors start with `input_failed:` when no event was submitted to the system and `input_partial:` when a prefix may have been submitted. The client must treat `input_partial:` as uncertain delivery, preserve the draft, and require an explicit review before enabling resend. Unknown text failure semantics are also treated conservatively as uncertain.

- `{"id":"...","type":"move","dx":3.5,"dy":-2}`: relative mouse movement, each finite number limited to +-500. Receiver accumulates fractional movement.
- `{"id":"...","type":"click","button":"left"}`: left/right click down+up.
- `{"id":"...","type":"button","button":"left","down":true}`: hold/release for drag. Release all held buttons on disconnect, timeout, or shutdown.
- `{"id":"...","type":"scroll","dx":0,"dy":-120}`: relative scroll units; Windows maps 120 to one wheel notch, while macOS maps 120 to a 120-point pixel-scroll request through Quartz. Both limited to +-1200.
- `{"id":"...","type":"key","key":"enter","modifiers":[]}`: allowed keys enter, tab, escape, backspace, delete, up, down, left, right, home, end, pageup, pagedown, space, a, c, v, x, z; modifiers ctrl, alt, shift, win. On macOS these mean Control, Option, Shift and Command; iOS selects `win` for Mac semantic shortcuts such as Select All, and `ctrl` for Windows. Press+release with best-effort release of owned keys on error. A lock, logout or revoked Mac permission can prevent release delivery; no input is replayed into a later session. No arbitrary executable/script commands.
- `{"id":"...","type":"text","text":"你好 Windows 👋"}`: commit an entire Unicode string, <= 16,000 UTF-16 code units. Type text into foreground field via Windows SendInput KEYEVENTF_UNICODE (UTF-16 surrogate pairs preserved). Normalize CRLF and lone LF to one CR packet for Windows text controls. Do not append any extra Enter or submit action; an application's handling of embedded newlines must be tested. On macOS use Quartz Unicode keyboard events, preserve surrogate pairs, and normalize line breaks to CR. A successful ACK means the backend submitted the event sequence to the system; macOS CGEventPost has no delivery result. It does not prove a specific app received, saved or submitted text. Text composed in iOS stays local until explicitly sent. Client must keep unsent text on failure, avoid accidental duplicate sends, and preserve composition/dictation state.
- `{"id":"...","type":"ping"}`: keepalive. Client sends every 5 seconds while foreground; server idle limit 20 seconds. Backgrounding stops motion, releases held buttons if possible, closes connection, preserves draft; foregrounding can reconnect without replay.

Receiver rejects unknown fields/types, non-finite/out-of-range numbers, malformed JSON, unsupported keys/buttons. Credentials must never appear in logs, build artifacts, source control, or test receipts. Sensitive action ACKs have a bounded timeout; ambiguous text delivery is shown as uncertain, not retried automatically.

## Verification boundary

Dry-run is allowed on Windows, macOS and Linux for protocol/TLS tests and must report inputAvailable=false. Linux non-dry-run is rejected until a native backend is implemented. Actual pointer/text injection requires physical interactive desktop tests on each supported OS. Mac requires an active, unlocked console session and Accessibility/post-event authorization; reading availability must not prompt. The local dashboard provides an explicit permission action. GET never changes state; local POST actions require a loopback peer, allowed Host and Origin, and a per-process nonce. macOS secure fields and applications rejecting synthetic events are outside the verified contract. iOS simulator tests do not establish Typeless, camera, physical gyroscope, or real iPhone LAN behavior.
