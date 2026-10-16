# Custom gestures — development verification

Date: 2026-10-16. This feature is development source, not a TestFlight or App Store release. Published iPhone build 17 does not include these settings.

## Implemented scope

The iPhone settings sheet offers three presets and nine editable gesture bindings. Computer and television preferences persist separately on the phone. Device capabilities restrict available actions; TV pointer clicks remain distinct from directional-focus confirmation. The guide reflects the active mapping, and the practice sheet produces local feedback without receiver input or microphone capture.

Changing settings or targets cancels pending gestures and releases an active drag through the previous callbacks. Opening settings suppresses automatic keyboard focus. Existing receiver protocols, pairing credentials and public build numbers are unchanged.

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

## Pending acceptance

Real iPhone timing, multi-finger ergonomics, persistence across a physical app restart, and actual Windows/macOS/Linux receiver behavior still need device acceptance. Any live desktop input test must first establish Yomado window and input isolation. Household Sony and Xiaomi TV acceptance remains pending; software tests and capability filtering do not prove physical-TV compatibility.

The localization checks are mechanical coverage checks, not a native-speaker editorial review of every translation.
