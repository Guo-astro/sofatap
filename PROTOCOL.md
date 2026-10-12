# Sofatap protocol v1

Native iPhone controller and Windows/macOS/Linux receivers, local network, TLS with certificate pinning.

The `v0.1.1-alpha` release adopts the Sofatap brand and the `sofatap://` pairing scheme. The wire protocol remains version 1. Its new iOS bundle ID (`com.chekusu.sofatap`) and Windows profile (`%LOCALAPPDATA%\SofaTap`) do not automatically migrate previous pairing credentials; both ends must be paired again.

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


The experimental account-password `hello.unlock` capability is retired and is no longer emitted, including on ready Windows desktops with legacy enrollment files. Clients must not use cached password capabilities or treat them as Windows Hello PIN credentials. Native lock-screen pointer/manual PIN and Face ID-authorized PIN entry need a separately verified protocol; no PIN capability is currently advertised. See [current validation scope](docs/FACE-ID-UNLOCK.md) and the [historical password design](docs/archive/PASSWORD-LOGIN-PILOT.md).

Development version 0.5.0 adds `textFocus: {"state":"editable","revision":1}` to hello and ping ACKs. The state is `editable`, `other`, `protected` or `unknown`; revision is a nonnegative connection-local integer, changing when the target/state changes. Native element identity and field contents are never serialized. Locked, unavailable and dry-run receivers return `unknown`; dry-run never creates the native focus probe. Missing, malformed or unknown metadata disables automatic keyboard behavior while preserving manual keyboard access. Clients poll at most every 750 ms when this metadata is advertised, with only one outstanding ping; legacy receivers retain the five-second heartbeat. These hints are advisory, not a promise that the application will accept input. See [platform focus detection](docs/TEXT-FOCUS.md).

Injection failure errors start with `input_failed:` when no event was submitted to the system and `input_partial:` when a prefix may have been submitted. The client must treat `input_partial:` as uncertain delivery, preserve the draft, and require an explicit review before enabling resend. Unknown text failure semantics are also treated conservatively as uncertain.

- `{"id":"...","type":"move","dx":3.5,"dy":-2}`: relative mouse movement, each finite number limited to +-500. Receiver accumulates fractional movement.
- `{"id":"...","type":"click","button":"left"}`: left/right click down+up.
- `{"id":"...","type":"button","button":"left","down":true}`: hold/release for drag. Release all held buttons on disconnect, timeout, or shutdown.
- `{"id":"...","type":"scroll","dx":0,"dy":-120}`: relative scroll units; Windows maps 120 to one wheel notch, while macOS maps 120 to a 120-point pixel-scroll request through Quartz. Both limited to +-1200.
- `{"id":"...","type":"key","key":"enter","modifiers":[]}`: allowed keys enter, tab, escape, backspace, delete, up, down, left, right, home, end, pageup, pagedown, space, a, c, v, x, z; modifiers ctrl, alt, shift, win. On macOS these mean Control, Option, Shift and Command; iOS selects `win` for Mac semantic shortcuts such as Select All, and `ctrl` for Windows. Press+release with best-effort release of owned keys on error. A lock, logout or revoked Mac permission can prevent release delivery; no input is replayed into a later session. No arbitrary executable/script commands.
- `{"id":"...","type":"text","text":"你好 Windows 👋"}`: commit an entire Unicode string, <= 16,000 UTF-16 code units. Type ordinary text into the foreground field via Windows SendInput KEYEVENTF_UNICODE (UTF-16 surrogate pairs preserved). Each embedded CRLF, lone LF or lone CR becomes one VK_RETURN down/up pair, because Windows editors can ignore Unicode CR packets. No extra Enter or submit action is appended. Embedded line breaks therefore follow the target application's Enter behavior: they insert a paragraph in multiline editors, but may submit a form or send a message in other fields; test the intended target. Windows rejects the entire multiline action before injection with `input_busy:` while Enter, Ctrl, Alt, Shift or either Windows key is held. On macOS use Quartz Unicode keyboard events, preserve surrogate pairs, and normalize line breaks to CR. A successful ACK means the backend submitted the event sequence to the system; macOS CGEventPost has no delivery result. It does not prove a specific app received, saved or submitted text. Text composed in iOS stays local until explicitly sent. Client must keep unsent text on failure, avoid accidental duplicate sends, and preserve composition/dictation state.
- `{"id":"...","type":"ping"}`: keepalive and optional focus-state refresh. Client sends every 750 ms with focus metadata, otherwise every 5 seconds while foreground; server idle limit 20 seconds. Becoming inactive stops touch input and releases held buttons; a temporary native permission sheet may keep the connection. Backgrounding closes the connection and preserves the draft; foregrounding can reconnect without replay.

Receiver rejects unknown fields/types, non-finite/out-of-range numbers, malformed JSON, unsupported keys/buttons. Credentials must never appear in logs, build artifacts, source control, or test receipts. Sensitive action ACKs have a bounded timeout; ambiguous text delivery is shown as uncertain, not retried automatically.

## Verification boundary

Dry-run is allowed on Windows, macOS and Linux for protocol/TLS tests and must report inputAvailable=false. Linux real input uses X11 XTest/libxdo or an explicitly authorized Wayland RemoteDesktop portal. Actual pointer/text injection requires physical interactive desktop tests on each supported OS. Mac requires an active, unlocked console session and Accessibility/post-event authorization; reading availability must not prompt. The native window provides an explicit permission action through inherited process pipes. The receiver has no HTTP/HTML pairing dashboard or local HTTP action endpoints. A bounded JSON line protocol accepts only refresh, requestAccess and quit; EOF stops the receiver and releases owned input. Pairing QR PNGs and URIs are provided only to this local parent process. The network endpoint still accepts only authenticated WSS control messages. macOS secure fields and applications rejecting synthetic events are outside the verified contract. iOS simulator tests do not establish Typeless, camera, physical gyroscope, or real iPhone LAN behavior.

## Native desktop window bridge

The signed desktop launcher starts the bundled receiver with `--native-ui` and redirects both standard streams. The backend refuses this mode on an interactive terminal. Standard output is reserved for newline-delimited state objects: `type`, `name`, `platform`, `inputStatus`, `dryRun`, `connected`, and `pairings` (each `host`, `uri`, base64 `qrPng`). Do not log or persist state frames: they contain pairing credentials. Errors use a separate stream and frontends display fixed messages. Status refreshes every two seconds.

The Mint Calm native windows offer an explicit Copy pairing link action. Frontends retain the selected validated URI in memory for that action; they never automatically copy it or display its secret text. Windows and Linux accept older QR-only snapshots with Copy disabled. Missing, malformed or oversized optional URIs likewise disable Copy. This UI action is separate from remote text injection, which keeps its existing clipboard behavior. Appearance fixtures must use synthetic, non-pairing QR content and no real credentials.

The parent may send exactly one field: `{"type":"refresh"}`, `{"type":"requestAccess"}` or `{"type":"quit"}`. Commands are bounded to 4 KiB; unknown/duplicate fields are rejected. macOS and Wayland permission requests are explicit local user actions and disabled in dry-run. Pipe EOF and Quit cancel connected WebSockets before stopping the host. Native frontends must terminate their own child on unrecoverable framing errors, never an arbitrary process. Linux's GTK3 window launches in real-input mode by default; --dry-run is an explicit preview option.

## Linux receiver metadata and limits

The Linux receiver uses protocol version 1 without changing action schemas. Its
`inputStatus` is `ready`, `permission_required`, `permission_pending`,
`permission_denied`, `desktop_unavailable`, `unsupported_session`,
`dependency_missing` or `input_unavailable`; explicit dry-run remains `dry_run`.
Only `ready` enables input. Permission requests are local native-window actions,
never remote WebSocket commands. The existing iPhone client fails closed for
unknown status codes and can use a ready Linux receiver.

Linux text is limited to 2048 Unicode scalar values per action (and the common
16000 UTF-16-unit/64 KiB frame bounds). Overlong input is rejected before sending
its first character. X11 also rejects a selection before input when temporary key-slot capacity or its preflight time budget is exceeded. A desktop method failure or deadline after attempting input
is `input_partial`/unknown; no client should retry it automatically. An ACK means
input was submitted, not that a target app received or saved it. Linux text uses
X11 key events or Wayland Unicode keysyms, not clipboard replacement. Wayland
requires a compositor portal implementing the requested methods and Unicode
keysyms; mock portal checks do not establish compositor compatibility.
