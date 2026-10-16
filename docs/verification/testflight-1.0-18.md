# TestFlight 1.0 (18) — custom gestures

Checked 2026-10-16 at 10:45 UTC. Build 18 is the latest uploaded build and is available through the [public TestFlight invitation](https://testflight.apple.com/join/e6MuKx9S).

| App Store Connect check | Result |
| --- | --- |
| Build | 1.0 (18), `f2214064-1964-4e50-944b-d46eab894821` |
| Processing | `VALID` |
| Beta review submission | `APPROVED` |
| Internal / external build state | `IN_BETA_TESTING` / `IN_BETA_TESTING` |
| Public group | Build 18 is a member of Sofatap Public Beta |
| Public invitation | Accepts new testers; limit 10,000 |
| Test instructions | English, Simplified Chinese and Japanese saved and read back |

Upload, submission, approval and group membership were checked separately. The public invitation was fetched anonymously and contained the Sofatap TestFlight join link without a full/not-accepting notice. No tester was enrolled and no TestFlight-installation claim is made for the development devices in this record. The formal App Store build 15 submission was not changed.

## Source and package

- Release source: `11aaf9889e211dc7f31316471529e8cc3d87da7a` on `feat/custom-gesture-profiles`, [PR #1](https://github.com/chekusu/sofatap/pull/1).
- Production application source matches reviewed `f4271dd0fe3cacd5d4a62df912ecd404ee309c2b`; the release commit changes the build number and verification record.
- Uploaded IPA SHA-256: `3fdc0b968a944d37a0f20d20a6208d75bb8ac1043a42e5b80b28b0c41064fe5a` (3,618,488 bytes).
- Archive and App Store export succeeded. The uploaded package is the App Store export, not the development-signed test host.
- [CI run 38888482432](https://github.com/chekusu/sofatap/actions/runs/38888482432) passed all four jobs at the exact release commit: macOS/iOS, Windows, Linux and Android TV. Independent review found no outstanding issues.

## Physical acceptance

The dedicated iPhone 16 Pro Max passed all seven UI cases in one completed run. The iPad Pro 11-inch, running the iPhone compatibility layout, passed six cases in the full run and the remaining preset case in a targeted rerun after an offscreen-element fix to the private test harness. The original failure was retained; no production code was changed to accommodate the tests.

These tests cover real touch input into local practice, preset changes, individual mappings, cancellation, timing/scroll preferences and persistence across app restart. They do not prove receiver OS effects, exact double-tap-hold timing or arbitrary parallel two-finger scrolling. See the [full results and limits](custom-gestures-2026-10-16.md).

Desktop receiver 0.7.2 beta.1 and Android/Google TV receiver 0.1.1 beta.1 remain the companion packages. No receiver package was changed in this release. Household Sony and Xiaomi TV acceptance remains pending.
