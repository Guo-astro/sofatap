# App Store resubmission — October 26, 2026

## Result and version boundaries

Sofatap 1.0 (23) was submitted for App Store review at **2026-10-26 23:11:37 JST** (14:11:37 UTC). Both the App Store Connect API and review page confirmed **WAITING_FOR_REVIEW**, with **1.0 (23)** attached. The new review submission is `3619c360-b911-4cca-9082-538dcf2a3d2c`.

This is a submission of the existing TestFlight package, not a new binary upload or approval. The existing automatic-after-approval release setting was retained.

| Distribution or source | Verified state on October 26 |
| --- | --- |
| App Store 1.0 | Build 15 withdrawn; build 23 now waiting for review. No approved App Store release was present. |
| Latest TestFlight | 1.0 (23), valid, beta review approved, internal and external testing enabled. |
| Build 23 source | `c7ad3ab2cb5f86c55839ff349c9026561ec8b68d`; see [the immutable package record](testflight-1.0-23.md). |
| Consolidated development source | `34db0bfe599ea063a82e8de3c338eecbd8504673` on main, plus subsequent documentation updates. |
| Desktop receiver release | `v0.8.1-beta.1`. |
| Android TV receiver release | `v0.2.1-beta.1`. |
| Android phone controller release | `v0.1.0-beta.1`. |

Main includes unreleased desktop volume/pointer-speed controls and the Android/TV source consolidation. Those changes are **not** added to the immutable TestFlight 23 package by merging source. A future upload needs a new build number and its own release validation.

## Previous submission and preparation

The previous submission, `5497af84-6b24-45bf-b9ea-3d9411cb3c57`, attached build 15 and had been waiting since October 15 at 21:38 JST. It was canceled, and App Store Connect subsequently reported developer rejection before build 23 was attached. The review page showed no rejection message or request for information. The internal reason for the eleven-day wait is unknown; the metadata corrections below are not evidence of that cause.

Preparation for build 23 included:

- Updated all twelve localized descriptions to describe configurable gestures, native iPad support and the current receiver setup accurately.
- Updated reviewer instructions with receiver 0.8.1 beta.1, reproducible manual-control steps, TV preview limitations and the distinction between dictation and autonomous operation. No demo account is required; the actual review form confirmed this option was unchecked.
- Removed six outdated iPhone guide screenshots and the English preview video, which described an old double-tap behavior. Four other screenshots per iPhone display class remain in each of the English, Japanese and Simplified Chinese screenshot localizations.
- Added one genuine build-23 landscape iPad screenshot to the primary English and Simplified Chinese localizations. It shows the Chinese device UI, captured on a dedicated 11-inch iPad Pro. The 2388×1668 source was scaled proportionally and padded to 2732×2048, with no UI changes, then encoded as an opaque sRGB JPEG. Both assets completed processing. This is a visual check of the disconnected UI, not receiver input acceptance.
- Confirmed in App Store Connect that the app privacy declaration was published and states that no data is collected.

Independent readback matched all twelve localizations and the reviewer notes (App Store Connect strips the final newline). Final strict submission validation reported **zero errors, zero warnings and zero blockers**. Its only informational item was the public API's inability to read the privacy publication state, which was checked in the browser.

## Development verification and cleanup

The [source consolidation record](source-consolidation-2026-10-26.md) details the integrated changes and local checks. All five platform jobs in [CI run 40334811787](https://github.com/chekusu/sofatap/actions/runs/40334811787) passed on `34db0bf`. The Windows updater test rolled back unexpectedly on the first attempt and passed a rerun of the same SHA, including 187 protocol checks and 30 real updater lifecycle assertions. No speculative code fix was made; the first failure's exact cause remains unproven.

PRs #16 and #20 were closed after their changes were integrated into main by cherry-pick. No new APK or desktop package was published. Physical TV and application compatibility, Android handset input acceptance, and the additional desktop controls remain subject to their documented device-level gates. Paid autonomous operation remains unimplemented.

Local cleanup retained the sole normal development checkout and a separate archive. Unique release packages, private evidence and the seven-file Remote v2 diagnostics/LAN experiment were preserved with hashes. The latter also remains on an unpublished local WIP branch. Duplicate checkouts and obsolete compatibility links were removed only after preservation checks. Active legacy-data link targets and unrelated worktrees were retained. The task's managed Codex checkout is protected as its primary checkout and was not forcibly removed.

The initial main consolidation was pushed to GitHub and Sandbank returned an authenticated reply matching its notification, confirming a clean fast-forward-only synchronization to `34db0bf`. Later documentation updates follow the same repository notification process.
