# Sofatap 1.0 (17) distribution — October 16, 2026 JST

Build 17 is approved for external TestFlight testing. The companion Android/Google TV receiver 0.1.1 beta.1 is published. **The household Sony and Xiaomi televisions have not been field-tested.** Software tests and store approval do not qualify a physical TV model or third-party application.

## Verified Apple state

At 2026-10-15 17:19 UTC (October 16 JST), App Store Connect reported:

- App `6822188472`, bundle `com.chekusu.sofatap`, version **1.0**, build **17**.
- Build ID `5f4dbeaa-7e8c-42df-a3e7-8fd01a24dfa6`.
- Processing `VALID`; beta review `APPROVED`; external and internal states `IN_BETA_TESTING`.
- Membership in the existing Sofatap Team and Sofatap Public Beta groups verified by relationship reads.
- [Public invitation](https://testflight.apple.com/join/e6MuKx9S) returned HTTP 200 with the Sofatap-specific joining instructions and active “View in TestFlight” link. The existing public group remains enabled with a 10,000-person limit.
- English, Simplified Chinese and Japanese What to Test notes were written and read back. Review instructions identify the experimental TV capabilities and untested hardware; contact and other review attributes were preserved.

This operation did not replace or resubmit the separate formal App Store build 15 submission, expire older builds, or invite individual testers. No physical iPhone installation or TV pairing was performed during this release.

## Published artifacts

- [Android/Google TV 0.1.1 beta.1 release](https://github.com/chekusu/sofatap/releases/tag/android-tv-v0.1.1-beta.1): development APK, checksums and manifest.
- Receiver and companion iPhone build sources match commit `7f3bc991b075de95ef66d9b77813a40bc1c9eb67`; all 224 staged build inputs were checked against that commit.
- [CI run 38775333358](https://github.com/chekusu/sofatap/actions/runs/38775333358) completed successfully on that commit for macOS/iOS, Windows, Linux and Android.
- An anonymous full APK download returned HTTP 200 and matched SHA-256 `1702c40ad3469b8de4f21135ba56492d7bbc3b0067e7600327ede42c0b61c9a3` (6,330,592 bytes).
- Signed App Store Connect IPA SHA-256: `c397afc34dd9551b40a89d428c1d463c130ff813d42e1ff1824ceb87caa2a7cc` (3,435,753 bytes).

TV automatic reconnect requires **iPhone build 17 and TV receiver 0.1.1 beta.1 together**. Desktop receiver 0.7.2 remains current. See [software checks and remaining physical acceptance](android-tv-reconnect-2026-10-16.md) and the [acceptance checklist](../ACCEPTANCE.md).
