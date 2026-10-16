# Android TV disconnect cleanup — October 17, 2026

## Observed failure

During first installation and accessibility setup on a physical Xiaomi MiTV-MOEU0 running Android 14 / API 34, a UI inspection caused the accessibility service to unbind. With an established TLS controller, `InputBridge.detach()` called the receiver interruption listener on Android main. Conscrypt wrote TLS shutdown data in `SSLSocket.close()` and raised `NetworkOnMainThreadException`, terminating the receiver. Two matching application crash traces were captured privately. This is a lifecycle failure; it does not establish a failure in TV click targeting.

The same socket teardown helper is reachable from controller disconnect, pairing replacement and foreground-service destruction. No permission bypass or weakened thread policy is part of the fix.

## Change

The receiver synchronously clears controller ownership and notifies input cleanup once. It closes connected TLS sockets on a dedicated cleanup executor, independently of the bounded input workers. Pending old-session input becomes invalid immediately and cannot be replayed into a resumed session. Closing the receiver still releases the listening port before returning, so network refresh can bind the replacement listener. Registered sockets are drained before the cleanup executor exits; registration and shutdown are synchronized.

The candidate Android package is **0.1.3-beta.1 (code 4)**. It uses the same development signing identity as the installed 0.1.2-beta.1 package. This record is not a Google Play release or a model-compatibility certification.

## Validation

- 79 JVM tests passed, including real loopback TLS tests for immediate cancellation without credential revocation, one disconnect notification per session, old-worker/new-controller isolation, and immediate port release with repeated close.
- Android lint, debug APK and instrumentation APK builds passed.
- 12 tests passed on an explicitly opted-in headless Android TV API 31 emulator. Two new tests establish real Android TLS/WebSocket sessions and call disconnect / close on main with `detectNetwork().penaltyDeathOnNetwork()` enabled, then check peer closure and authenticated reconnection. They use temporary in-memory credentials and do not send real input or change persisted pairing.
- These StrictMode tests exercise the receiver entry points used by lifecycle callbacks. They do not replace a physical television restart, standby or input-compatibility test.

## Physical-device boundary

The user enabled Sofatap accessibility on the Xiaomi through the normal TV settings UI. The 0.1.3-beta.1 candidate was then installed in place with the matching signer. Readback confirmed version code 4, the same encrypted identity-file hash, accessibility still enabled, both receiver and accessibility services running, and no crash in the newly launched process during the post-update observation. This is setup/upgrade verification, not a completed user-input retest. The application was installed over authorized wireless ADB; ADB is not the runtime control channel. Installation, granted permission and a running foreground service are separate from physical iPhone pairing and per-application input acceptance.

Xiaomi pointer targeting, click/scroll/Back behavior, standby recovery and cold-boot startup still require observed user tests. Sony and Xiaomi are not yet qualified as fully supported models. Private device addresses, pairing material and raw device logs are not included in this repository.
