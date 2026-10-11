# macOS Developer ID distribution

This pipeline prepares a Developer ID signed, notarized ZIP of the macOS receiver. Do not describe a build as notarized or publish it as the completed macOS release until Apple returns `Accepted` and the receipt records successful stapling, Gatekeeper assessment and `stage: complete`. A signed build or a successful upload alone does not meet that gate.

As of 2026-10-11, both architectures in [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha) meet this gate. Their immutable source revision is `8e6d0cea771b1e1b7879aff94bce437cb971298a`; see the [public verification record](verification/macos-0.3.0.md) for final ZIP hashes and the separately completed Apple Silicon/iPhone checks. Later documentation commits do not change the source revision of those binaries.

This is separate from the iPhone App Store/TestFlight workflow. Run the commands on a Mac that already has CHEKUSU's Developer ID Application certificate **and its private key**, plus a working App Store Connect API profile stored by `asc` in the macOS Keychain. No private keys or signing credentials belong in this repository.

The pipeline uses `asc notarization`, Apple's Notary API, and the existing Keychain profile. It does not request a password, export credentials, change Keychain trust, sign code, or create a certificate. Omitting `--profile` resolves ASC's current default stored profile once and uses that profile for the whole run. Credentials supplied through ASC environment variables are rejected to avoid using a different account accidentally. Local preflight confirms the stored profile exists; successful submission and status retrieval establish its current Notary API access.

## Build and inspect

Commit the intended source first. The build must come from the current clean Git revision; a manifest created while the source tree was dirty cannot be made releasable by committing afterward. Rebuild after committing.

```sh
git status --short
stage_dir="$(mktemp -d /tmp/sofatap-release.XXXXXX)"
SOFATAP_SIGN_IDENTITY='Developer ID Application: CHEKUSU INC. (FKSR2JD63B)' \
SOFATAP_MAC_STAGING="$stage_dir" \
  bash scripts/build-macos.sh arm64

bash scripts/notarize-macos.sh \
  --app "$stage_dir/SofaTap-macOS-arm64/Sofatap Receiver.app" \
  --manifest "$stage_dir/SofaTap-macOS-arm64/BUILD-MANIFEST.json" \
  --output-dir artifacts/notarization/arm64-release
```

Use `x64` in place of `arm64` for the Intel build. Each architecture requires its own output directory and notarization submission. Do not delete the preserved staging directory until the release is complete; it is required to resume.

Without `--submit` or `--resume`, the script performs read-only preflight and prints a JSON report. It uploads nothing and creates no output directory. It verifies:

- A clean current Git revision and a matching clean-source build manifest.
- The exact signed frontend and backend SHA-256 values from that manifest.
- Valid strict code signatures for the bundle, frontend and backend, each with the CHEKUSU Developer ID authority, Team ID `FKSR2JD63B`, hardened runtime and a secure signing timestamp.
- The expected bundle/code identifiers, absence of development `get-task-allow`, and the .NET backend's `allow-jit` entitlement.
- No unreviewed Mach-O files or symlinks in the current simple receiver bundle layout.
- An existing ASC Keychain profile and no conflicting environment credentials.

This verifies build provenance against the local manifest; it is not an independent reproducible-build attestation or a physical input acceptance test. `physicalInputVerified` in the source manifest remains unchanged by notarization.

## Submit and finish

Only run the following after reviewing the signed build and preflight result:

```sh
bash scripts/notarize-macos.sh \
  --app "$stage_dir/SofaTap-macOS-arm64/Sofatap Receiver.app" \
  --manifest "$stage_dir/SofaTap-macOS-arm64/BUILD-MANIFEST.json" \
  --output-dir artifacts/notarization/arm64-release \
  --submit
```

Add `--profile NAME` to select another already configured Keychain profile. The script invokes `asc notarization submit --file ... --output json` once, records the returned submission ID immediately, and polls `asc notarization status --id ... --output json`. The default status wait is 30 minutes with a 15-second polling interval; use `--timeout SECONDS` or `--poll-interval SECONDS` to change them.

Only the exact Apple status `Accepted` permits the remaining steps. On a temporary copy outside File Provider folders, the script runs `xcrun stapler staple`, `xcrun stapler validate`, strict code verification and `spctl --assess --type execute --verbose=2`. It then creates a new ZIP containing the stapled app. The input `.app` stays unchanged. The final ZIP must be distributed instead of `submission.zip` or the original build ZIP.

Successful output contains:

- `SofaTap-macOS-arm64-notarized.zip` (or `x64`) and its `.sha256` checksum.
- `NOTARIZATION-RECEIPT.json`, whose `stage` is `complete`, with source revision, hashes, verified signatures, Apple submission ID, accepted status, staple validation and Gatekeeper results.
- `SOURCE-BUILD-MANIFEST.json`, preserved as the input build record. Its `notarized: false` describes the pre-submission build; the separate receipt records the final result.
- `staple.txt`, `staple-validation.txt` and `gatekeeper.txt` for local verification output.
- `submission.zip`, retained as the exact pre-stapling artifact sent to Apple.

These are local release-working materials. Distribute only the final notarized ZIP and its `.sha256`, together with a reviewed public verification summary. The final ZIP contains the app and macOS archive metadata; it does not include a build manifest, raw receipt, or local pairing configuration. Although the receipt excludes raw ASC responses, upload credentials and notarization log URLs, it contains local profile/path metadata and must not be published unchanged. Keep source manifests, original receipts, local logs and `submission.zip` out of release assets.

An Apple acceptance receipt establishes Apple's notarization result; functional testing and macOS Accessibility permission remain separate requirements. The 0.3.0 build and fresh-extraction records retain `physicalInputVerified: false` because those packaging checks did not inject input. The later physical-device checks are recorded separately without modifying the packages.

## Resume without another upload

When the receipt contains a confirmed `submissionID`, rerun with the same original app, manifest, output directory, source revision and profile, changing `--submit` to `--resume`:

```sh
bash scripts/notarize-macos.sh \
  --app "$stage_dir/SofaTap-macOS-arm64/Sofatap Receiver.app" \
  --manifest "$stage_dir/SofaTap-macOS-arm64/BUILD-MANIFEST.json" \
  --output-dir artifacts/notarization/arm64-release \
  --resume
```

Resume verifies the recorded inputs and exact submission ZIP hash, queries the existing submission, and repeats only the local stapling and packaging steps after acceptance. It never uploads again. A completed receipt is not rewritten by resume.

If upload fails before ASC returns its ID, the receipt reports an unknown submission outcome. Do **not** blindly submit again: ASC may already have created a submission. Inspect `asc notarization list --output json` and the corresponding status first. If Apple returns `Invalid` or `Rejected`, inspect `asc notarization log --id SUBMISSION_ID --output json`, fix the reported issue, commit and rebuild. Those log URLs can contain temporary authorization parameters; keep them out of repository files and public messages.

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Apple notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues), [.NET on macOS](https://learn.microsoft.com/en-us/dotnet/core/deploying/macos).
