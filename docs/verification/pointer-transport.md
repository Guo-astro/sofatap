# Pointer pacing and optional Apple peer transport

## Shipped behavior

- Desktop touch callbacks send immediately; acknowledgements drain accumulated
  relative movement. Ordinary LAN allows 12 outstanding movement frames, and the
  peer route allows 8. Unsent movement and stalled-flight admission are bounded
  by 120 ms. Reconnection never replays uncertain input.
- Desktop touch gain uses a time-based velocity estimate. Direction and stopping
  are not smoothed into a synthetic movement tail. Drag release preserves the
  final movement ordering. TV gesture semantics remain separate.
- Mac input caches the expensive post-event permission query with bounded
  freshness. Console session and Accessibility trust checks remain synchronous.
- Automatic routing prefers a matching Bonjour service scoped to AWDL, with
  bounded discovery and ordinary LAN fallback. Retryable peer failure selects LAN
  for the next reconnect. TLS still authenticates the original hostname, full
  certificate pin and pairing token through the opaque bridge.
- My Devices offers Auto and Regular Wi-Fi only while a matching AWDL service is
  visible. The preference persists. Settings discovery remains independent of the
  selected transport and stops when settings closes or the app is inactive.
  Advertised availability does not replace connection authentication.
- Numeric pointer diagnostics are DEBUG-only, bounded histograms and counters;
  they do not include coordinates, typed text or pairing credentials. Their local
  JSON output is not a distributable test fixture.

## Repeatable checks

Run from the repository root on macOS with Xcode command-line tools and the
project .NET SDK available. The TLS integration script uses the Release receiver
assembly and creates a temporary dry-run profile.

```sh
bash ios/scripts/test-pointer-motion.sh
bash ios/scripts/test-drag-release.sh
bash ios/scripts/test-pairing-attempt.sh
bash ios/scripts/test-peer-discovery.sh
bash ios/scripts/test-explicit-text.sh
bash ios/scripts/test-live-text.sh
.tools/dotnet/dotnet build host/SofaTap.Host.csproj -c Release
.tools/dotnet/dotnet run --project tests/host/SofaTap.Host.Tests.csproj -c Release
python3 tests/peer-tls-bridge.py
python3 ios/scripts/check-localizations.py
git diff --check
```

The latest targeted review passed 122 connection/lifecycle checks, 15 pointer
motion checks, 93 touch gesture checks, 51 drag checks, 61 explicit-text checks
and 63 live-text checks. Real Bonjour tests exercise matching, interface scoping,
service removal, timeout and cancellation. The TLS bridge tests cover a valid
pinned connection, invalid pin/hostname/token, stopped endpoints and cleanup.
All 12 localization catalogs passed. The earlier complete host and TLS/WebSocket
regression runs passed 421 and 69 checks respectively. Controller fixtures and
recording sinks do not inject real desktop input.

## Physical-device observations and limits

Two physical-phone ABBA experiments compared LAN movement windows 8/12/12/8.
For the measured environment, send-interval P99 was approximately 38–46 ms with
8 slots versus 9–10 ms with 12. These were synthetic pacing experiments against
an isolated dry-run receiver, not actual touch gestures. They support reducing
sender pauses, not eliminating network jitter. The subsequent manual LAN test
was reported to feel somewhat better; residual stutter remained.

Separate encrypted peer/LAN comparisons and actual receiver sockets confirmed
AWDL transport on the tested iPhone/Mac. The final development build launched and
connected with the receiver reporting desktop-ready. This does not establish
compatibility with every Apple device or a universally optimal network setting.
Physical radio-interruption recovery and the final settings UI transitions were
not manually exercised; their policy/lifecycle behavior has automated coverage.
No automated cursor/keyboard acceptance was performed on the shared desktop
without verified input isolation.

Raw device captures, experimental apps, local profiles, signing material and
chronological development notes remain local and are excluded from the PR.
