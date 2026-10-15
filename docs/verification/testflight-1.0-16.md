# Sofatap TestFlight 1.0 (16)

Checked **October 16, 2026, 00:14 JST** (October 15, 15:14 UTC).

## Distribution

- Build **1.0 (16)**, ID `aa7a81fb-c55d-4410-b9e5-9cef72a01c19`, is processed **VALID** and is the latest uploaded build.
- Apple beta review is **APPROVED**; both internal and external build states are **IN_BETA_TESTING**. The initial submission response briefly said waiting; fresh review and build-detail reads confirm approval.
- Membership in **Sofatap Team** and **Sofatap Public Beta** is confirmed. The [public invitation](https://testflight.apple.com/join/e6MuKx9S) accepts testers, with its existing 10,000-person limit. The app-specific invitation page offers the live TestFlight link.
- English, Simplified Chinese and Japanese [What to Test](../app-store/testflight-1.0-16.json) notes and shared reviewer instructions were saved and read back. Existing contact and demo-account fields were preserved. Public beta descriptions now point to receiver 0.7.2 and explain the minimum phone build.
- The separate formal App Store submission remains **1.0 build 15, WAITING_FOR_REVIEW**. This release did not replace or withdraw it and does not claim formal App Store approval.

## Package and implementation

The app was archived from clean source [`43fd98c409fbd6971ac50a971cbdb3e9d6c3ab78`](https://github.com/chekusu/sofatap/commit/43fd98c409fbd6971ac50a971cbdb3e9d6c3ab78), then exported with CHEKUSU distribution signing. Version, bundle ID, team, App Store profile, disabled debug entitlement and strict signature verification passed. All twelve embedded localizations match source: 317 interface strings and five permission descriptions each.

IPA: **3,419,717 bytes**, SHA256 `20e0e6c0608cd87e3a3f107b227d861392d2076c862beb189cdd1ec0c7cdf783`.

Build 16 adds foreground retries for the selected saved computer after a temporary connection failure or receiver restart. It cancels retries on explicit disconnect, target switching or backgrounding, and never replays uncertain input. Use [receiver 0.7.2 beta.1](receiver-0.7.2.md) for the companion pairing-persistence fix. Existing differently authenticated duplicate records are not automatically merged; a true certificate/address replacement may still require pairing again.

Since public build 15, the desktop touch surface also gains invisible left/right double-tap halves and a computer Backspace button. The [input development record](input-1.0-16.md) and [reconnection regression record](reconnect-2026-10-15.md) describe their actual test scope. All four jobs in [CI run 38757221786](https://github.com/chekusu/sofatap/actions/runs/38757221786) passed at `57f1e60dcd51ff6c0388121162d925745f50c5ca`; that commit only adds distribution documentation after the package source.

## Physical installation

On the dedicated iPhone 16 Pro Max, TestFlight displayed **1.0, Build 16** and the matching Chinese test notes. Installing through TestFlight changed its action from **Install** to **Open**. An independent device installation query confirms `com.chekusu.sofatap`, version **1.0**, bundle version **16**. The actual TestFlight screenshot and installation metadata are retained privately.

This verifies the distributed build's installation, not final-build receiver input behavior. Sofatap control was not opened, no receiver windows or desktop input were used, and the phone's prior foreground app was restored before releasing the device lease. Phone-to-Windows receiver restart acceptance remains pending. Future desktop input tests must first verify Yomado placement and input isolation.

The twice-daily monitor retains its 09:00/21:00 Japan schedule, now records build 16's approval, and will avoid a duplicate approval notification. Signing credentials, pairing codes and private device identifiers are excluded from this record.
