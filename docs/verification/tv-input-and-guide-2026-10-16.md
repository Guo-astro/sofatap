# TV input queue and device-specific help

## Trigger and fix

During Sony XRJ-85X95L field testing, rapid scrolling could fill the iPhone's pending input queue, delay later clicks and cause the app to stop the connection with a slow-TV message. The user subsequently confirmed that single clicks work; an earlier report that clicks never work was superseded. Back remained unreliable.

The iPhone now coalesces consecutive unsent scroll events within the protocol's delta bounds, preserving click/key boundaries. Back and Home cancel older unsent gestures and wait for the one outstanding response. A rejected scroll cannot discard that explicit navigation, and navigation does not expire under the 500 ms stale-gesture limit. The existing three-second response deadline bounds the wait; disconnect, permission loss and target changes still clear queued input. No input is replayed after reconnect.

Rejected operations now produce a localized explanation below the touch surface. Pointer motion and scrolling do not immediately clear a rejected-click message. Raw server error strings are not displayed. Back/Home have full 52/64-point hit areas, press feedback and separate capability checks.

The guide prioritizes the selected device, shows its reported capabilities and the user's actual gesture bindings, distinguishes clicking the pointer target from confirming a highlighted item, and locates Back/Home in the touch surface. Its practice area remains local and sends no remote input. Television help does not advertise computer-only text, right-click or drag behavior. New copy covers all twelve existing app languages.

## Validation and limits

- Swift controller tests cover burst coalescing, ordering around clicks, slow successful/rejected responses, Back/Home preservation, stale-gesture expiry, permission changes and no replay after reconnect.
- Gesture configuration/recognition and device-guide model checks pass; all twelve localization catalogs validate and the iOS simulator build succeeds.
- Android JVM tests include real local TLS exchanges for rejected clicks, bounded slow scrolling, Back ordering/rejection and continued connection health. Android input behavior, permissions and release version are unchanged by this patch.
- The Sony receiver installation and accessibility service are confirmed. User-reported click/scroll success is recorded separately from software tests. A momentary YouTube accessibility-tree snapshot does not establish whether the user's click should have succeeded.
- The updated iPhone queue and Back behavior still require physical Sony retesting. Xiaomi is untested. Software tests and phone interface checks are not TV input acceptance. This change is not a new TestFlight or receiver release.
