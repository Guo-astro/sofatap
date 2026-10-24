# TestFlight 1.0 (23) — hold-to-drag fix

Checked 2026-10-24. Build 23 is the latest uploaded build and is available to the internal group and through the [public TestFlight invitation](https://testflight.apple.com/join/e6MuKx9S).

| App Store Connect check | Result |
| --- | --- |
| Build | 1.0 (23), `90004eb6-6cdd-42e4-9475-9eecd34d02a6` |
| Processing | `VALID` |
| Beta review submission | `APPROVED` |
| Internal / external build state | `IN_BETA_TESTING` / `IN_BETA_TESTING` |
| Groups | Build 23 is the newest build in Sofatap Team and Sofatap Public Beta |
| Test instructions | English, Simplified Chinese and Japanese saved and read back |

Upload, submission, approval and group membership were checked separately. The formal App Store build 15 submission was not changed and is still waiting for review.

## Source and package

- Release source: `c7ad3ab2cb5f86c55839ff349c9026561ec8b68d` on `claude/project-thread-axmvnr`. It is the Build 22 source (`9ab17d9`) plus the iPhone part of [PR #23](https://github.com/chekusu/sofatap/pull/23) and the build number. The iOS, test and gesture-doc changes match #23 on main exactly.
- Not included: the desktop volume and pointer-speed controls from [PR #12](https://github.com/chekusu/sofatap/pull/12), which are on main but still wait for hardware acceptance. The next iPhone build from main will include them.
- Uploaded IPA SHA-256: `9090187af7d3bcaffa72ad44c58cd4875a0d88fcf012ad775ac7862faacba381` (5,138,867 bytes), `CFBundleVersion` 23.
- Archive and App Store export succeeded with cloud-managed distribution signing. The uploaded package is the App Store export.
- [CI run 40102614741](https://github.com/chekusu/sofatap/actions/runs/40102614741) passed at the exact release commit.

## Change and limits

A desktop hold no longer ends when a resting finger rolls a few points: pointer motion still starts after 3 points, but a hold is ruled out only beyond 7 points, and a finger that moved early must have rested for 100 ms at the 300 ms deadline. A slow slide still only moves the pointer. See the [hold-tolerance record](hold-tolerance-2026-10-24.md) for the automated cases.

No physical iPhone smoke test was run for this build, and no tester was enrolled. Real-device drag acceptance on a Windows receiver remains pending. No receiver package was changed in this release.
