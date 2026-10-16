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

## Physical iPhone interface check

A dedicated iPhone 16 Pro Max ran an independently installed development fixture under an exclusive device-pool lease. Production Swift files matched implementation commit `c83a63dc3ccd99c52b8d8946d98ff9e7908a929e`; only the private app entry point, mock transport/store and two controller-injection lines differed. The fixture opened no receiver network connection, preserved the installed Sofatap app and its pairings, and sent no TV or desktop input.

Back and Home produced their respective commands at their centers and at all eight tested corner/edge positions inset eight points from the current accessibility frames. Back also worked four points inside its left edge. Two initial extreme-corner points inset only three points did not register; the entire nominal 52/64-point area is therefore not claimed as exhaustively accepted. No pointer click was emitted by the successful navigation-button tests. Physical vibration strength was not assessed by automation.

The real phone displayed the TV-specific guide with the fixture device name, Android TV platform, reported capabilities, current mappings and Back/Home diagram. Local practice showed click and move feedback without increasing any receiver-command counter. These are physical phone UI checks against a simulated receiver, not physical Sony Back acceptance.
