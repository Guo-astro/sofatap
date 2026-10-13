# Device library and localized remote UI — 2026-10-14

The compact iPhone layout passed native simulator visual and accessibility checks in English, Simplified Chinese, Japanese and Arabic. The selected device is visible on the touch surface; the device sheet clearly distinguishes the selected device. Keyboard controls remain reachable with the keyboard open or closed, and text does not overlap the inset Send button.

This validates the free manual remote interface. It does not qualify physical receiver input or paid voice automation.

## Preview images

The images are original, unedited `simctl` screenshots of build 13 synthetic interface fixtures. “Interface demo” is an intentional connection label. The displayed computers and documentation-range addresses are not real paired devices. Build 14 changes the guide's television card title to `Android TV / Google TV` so its overlay-pointer limitations are not attributed to the separate LG webOS adapter; the core visual layout is unchanged. The screenshots have not been relabeled as build 14 captures.

[Default touch surface](../images/device-library-20261014/en-touchpad.png)

| Language | Keyboard open | Keyboard hidden | Device sheet | Guide |
| --- | --- | --- | --- | --- |
| English | [Preview](../images/device-library-20261014/en-keyboard-open.png) | [Preview](../images/device-library-20261014/en-keyboard-hidden.png) | [Preview](../images/device-library-20261014/en-devices.png) | [Preview](../images/device-library-20261014/en-guide.png) |
| 简体中文 | [Preview](../images/device-library-20261014/zh-keyboard-open.png) | [Preview](../images/device-library-20261014/zh-keyboard-hidden.png) | [Preview](../images/device-library-20261014/zh-devices.png) | [Preview](../images/device-library-20261014/zh-guide.png) |
| 日本語 | [Preview](../images/device-library-20261014/ja-keyboard-open.png) | [Preview](../images/device-library-20261014/ja-keyboard-hidden.png) | [Preview](../images/device-library-20261014/ja-devices.png) | [Preview](../images/device-library-20261014/ja-guide.png) |
| العربية | [Preview](../images/device-library-20261014/ar-keyboard-open.png) | [Preview](../images/device-library-20261014/ar-keyboard-hidden.png) | [Preview](../images/device-library-20261014/ar-devices.png) | [Preview](../images/device-library-20261014/ar-guide.png) |

## Native layout checks

The dedicated iPhone SE (3rd generation) simulator used iOS 26.2 at 375 × 667 points, producing 750 × 1334 pixel PNGs. It ran headlessly, without opening Simulator.app, switching Mac focus, using a physical phone or sending input to a receiver. Each fixture settled for at least three seconds before capture. Accessibility frames came from the same simulator UDID.

All eight language/keyboard combinations passed these geometry checks:

- The 44-point side scroll target stays inside the touch surface on the physical right.
- The side scroll target and keyboard button have zero intersection.
- The native editor and Send button have zero intersection.
- Clear and show/hide keyboard actions retain 44-point targets; the Send target is also 44 points.
- The header's accessibility value includes the selected device name and connection state. The keyboard control announces whether the keyboard is visible.

The first Arabic capture exposed an actual collision: RTL mirroring moved the keyboard button beneath the fixed-right scroll strip, with a 1,664 square-point intersection. The touch surface's bottom control row now keeps its physical left/center arrangement, while the header, device sheet and composer continue to use natural RTL layout. Both final Arabic keyboard states have zero intersection. The Arabic guide now describes the device entry as being at the top of the screen, avoiding a direction that changes in RTL.

The editor displays the fixture text without Send-button obstruction. The permanent input-capability explanation is absent. The guide's first viewport is readable; longer content continues inside its scroll view. No runtime error-state fixture was exercised in this pass.

## Build and automated validation

| Check | Result |
| --- | --- |
| `bash ios/scripts/build-manual.sh simulator` after the RTL correction | Passed |
| `python3 ios/scripts/check-localizations.py` | Passed: 12 locales, each with 288 interface strings and 5 permission descriptions; keys, formatting arguments, syntax, brand and Swift literals checked |
| Saved device tests | 32 passed |
| Explicit text tests | 47 passed |
| Live text tests | 57 passed |
| Drag release tests | 33 passed |
| Android TV controller tests | 63 passed |
| webOS controller tests | 74 passed |

The six test-suite totals above were provided by the coordinating release run. They are software-level checks, separate from this visual QA pass. Build 14's native device archive and TestFlight delivery are recorded separately by the release coordinator; this visual QA record does not establish that release outcome.

## Evidence boundary and cleanup

Chinese and Arabic previews, plus the default English touch surface, came from the final build 13 simulator compilation after the RTL correction. The four English composer/device/guide previews and four Japanese previews came from the immediately preceding build 13 compilation; the intervening changes were the RTL control-row correction and Arabic guide wording, which leave these LTR layouts unchanged. The later build 14 guide title correction was reviewed in source rather than recaptured in these images.

The final simulator build's Swift and localization hashes were captured before compilation and rechecked after compilation and QA. Its `RemoteView.swift` SHA-256 is `77ac555c829d105a641571b0d65041fa379b9c353bf6ec838ca8305b9df984f1`. The ignored local record at `artifacts/device-library-qa-20261014/manifest.json` contains all screenshot hashes, build mapping, source-hash manifest and cleanup receipt; `geometry.json` and the accessibility snapshots provide the measured bounds. Pre-fix Arabic screenshots remain only in the ignored evidence directory.

Static fixtures do not prove live device switching, persistence on a real phone, rename/remove dialog behavior, physical haptics, third-party keyboard behavior, microphone recognition or computer/TV input. Those capabilities require their own acceptance evidence. This pass used no network pairing credentials or live receivers.

After capture, the dedicated QA simulator was shut down and deleted, and its identified `idb_companion` exited. The cleanup receipt confirms that all four pre-existing booted simulators remained booted. The user's normal desktop was not used for testing.
