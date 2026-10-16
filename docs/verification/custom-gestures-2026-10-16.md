# Custom gestures — Build 18 verification

Date: 2026-10-16. iPhone 1.0 (18) includes these settings and is available in public TestFlight. Physical-device results below are separate from [TestFlight processing and distribution](testflight-1.0-18.md).

## Implemented scope

The iPhone settings sheet offers three presets and nine editable gesture bindings. Computer and television preferences persist separately on the phone. Device capabilities restrict available actions; TV pointer clicks remain distinct from directional-focus confirmation. The guide reflects the active mapping, and the practice sheet produces local feedback without receiver input or microphone capture.

Changing settings or targets cancels pending gestures and releases an active drag through the previous callbacks. Opening settings suppresses automatic keyboard focus. Existing receiver protocols and pairing credentials are unchanged.

## Completed checks

| Check | Result |
| --- | --- |
| Configuration, persistence, malformed data and capability validation | 54 checks passed |
| Custom gesture timing, assignments, cancellation and multi-finger conflicts | 66 checks passed |
| Existing default gesture regression suite | 93 checks passed |
| UIKit draft editor tests | 41 checks passed |
| Live-text tests with recording transports | 63 checks passed |
| Controller drag-release tests | 33 checks passed |
| Localization coverage, syntax, placeholders and brand | 12 locales; 376 interface strings and 5 permission descriptions passed |
| Complete iOS Simulator Debug build | `xcodebuild` succeeded |
| Small-screen visual inspection | Headless iPhone SE (3rd generation), iOS 26.2; Chinese and English settings plus English practice sheet |

The gesture test compilations use warnings as errors. Simulator screenshots were inspected for text truncation, readable controls and practice-area layout. No Simulator window was opened on the shared desktop, and no mouse or keyboard input was sent to a receiver.

An independent code review identified a missing settings-sheet guard in automatic remote focus handling. The guard was added, related resume paths were checked, and the corrected integration was reviewed again.

## Physical-device checks

The dedicated devices were borrowed through exclusive device-pool leases. With the user's explicit authorization, public XCTest APIs drove the real production UI. The test host directly references the application's production source; no gesture-recognizer hooks, injected preferences or receiver callbacks were added. All 67 production source/resource hashes match reviewed commit `f4271dd0fe3cacd5d4a62df912ecd404ee309c2b`; the release project changes only the build number to 18.

| Device | Result |
| --- | --- |
| iPhone 16 Pro Max, iOS 18.6.2 (22G100) | Seven cases passed, zero failures or skipped cases, in a completed XCTest result bundle. |
| iPad Pro 11-inch (first generation), iPadOS 26.7 (23H24) | Six cases passed in the full run; the remaining preset case passed in a completed targeted rerun after correcting offscreen-element handling in the test harness. All seven distinct cases have passing results. This is iPhone compatibility mode, not a native iPad layout. |

The cases cover all three presets; changing an individual mapping; cancellation and application of replacement/reset confirmations; mapping, timing and scrolling-preference persistence after app termination and relaunch; single and left/right double taps; hold-to-drag release; pointer movement; simultaneous two/three-finger taps; and custom slide and dictation-shortcut mappings in local practice. Practice does not activate the keyboard, request microphone permission or send remote input.

The initial test runs exposed automation issues with clipped Form rows, iPad compatibility coordinate spaces and native popover cancellation, tapping the actual switch rather than its label, and waiting for accessibility state after a confirmation. Corrections were limited to the private test harness; failed run evidence was retained. No production code was changed to make the physical tests pass.

## Acceptance limits

Physical tests exercise the production recognizer through local practice. They do not prove effects in Windows, macOS, Linux or TV applications. No receiver was started and no mouse or keyboard events were sent to the shared Mac; its normal displays were left undisturbed. Any later live desktop input test must first establish Yomado window and input isolation.

Exact double-tap-then-hold sequencing, arbitrary parallel two-finger scroll paths and signed physical scroll direction remain unverified in this suite. Preference persistence does not prove direction. Exact timing boundaries remain covered by state-machine tests; haptic strength and subjective ergonomics require manual assessment. Development signing and the XCTest host differ from the exported App Store package, even though they use the same production source.

Household Sony and Xiaomi TV acceptance remains pending; software tests and capability filtering do not prove physical-TV compatibility.

The localization checks are mechanical coverage checks, not a native-speaker editorial review of every translation.
