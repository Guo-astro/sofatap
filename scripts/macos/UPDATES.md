# macOS receiver updates

The website app uses [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), pinned by the official release asset's SHA-256 in `update-config.json`. The framework's license is embedded in the app's `Resources/licenses/Sparkle-LICENSE.txt`. The Mac App Store basic build does not compile, link, or package Sparkle; its native menu opens Apple's Updates page. No Mac listing ID is assumed.

The normal packaged website app checks daily and downloads available updates by default. The native Sofatap menu contains **检查更新…** and **自动检查并下载更新**. Turning automatic updates off persists through Sparkle's app preferences; launch never overwrites that choice. Manual checks show Sparkle's native progress, release, error and up-to-date dialogs. Automatic installation uses the normal quit path, preserving the active phone connection. An explicit Install and Relaunch request made while connected waits for the phone to disconnect (unknown/starting/stopping receiver state also defers). Sparkle replaces the app bundle, not pairing data or preferences. A download alone does not mean installation succeeded. Closing the receiver window continues to keep it running.

Raw executables, offscreen UI fixtures, `--dry-run`, isolated `--test-display-id` launches, and Mac App Store builds never start the external updater. Tests must not launch the production app merely to inspect updater behavior on the shared Mac. Existing website builds older than this integration need one manual upgrade to acquire the updater.

## Release procedure

1. Preserve the dedicated Sparkle signing key in the publishing Mac's Keychain account `com.chekusu.sofatap.receiver.sparkle`. `generate_keys --account … -p` displays only its public key. The private key must never be exported into the repository, logs, arguments or CI artifacts. Do not regenerate it for each release. `update-config.json` contains only the public key.
2. Bump the receiver semantic version and choose a monotonically increasing `SOFATAP_MAC_BUILD_NUMBER` (greater than every published appcast build). The default is Git's commit count, suitable only if it is verified to increase. Commit and build clean source for **both** `arm64` and `x64` with `scripts/build-macos.sh`. Developer ID signing signs every reviewed Sparkle helper/framework inside out, then the receiver. The manifest records all signed framework files and symlinks. `scripts/notarize-macos.sh` verifies that inventory and nested CHEKUSU identities before upload; no unreviewed executable or escaping link is accepted.
3. Notarize and staple both architectures using `scripts/notarize-macos.sh`. Keep the completed receipts and final ZIPs. The update generator refuses ad-hoc/unnotarized or changed archives.
4. Run once per architecture with a new staging output directory, for example:

   ```sh
   python3 scripts/macos/generate-appcast.py \
     --archive /release/SofaTap-macOS-arm64-notarized.zip \
     --receipt /release/NOTARIZATION-RECEIPT.json \
     --architecture arm64 --tag v0.8.0-beta.1 \
     --output-dir /release/appcast-arm64
   ```

   On later releases also pass `--previous-feed updates/macos/arm64/appcast.xml`. Repeat for `x64`. The tool verifies the existing feed's signature and increasing build number, signs the final archive, generates and verifies a signed appcast, and writes a local publication receipt. It does not upload or install anything.
5. Upload the exact notarized ZIPs to that GitHub release. Download them anonymously and compare SHA-256 with each receipt. Only then copy the signed feeds unchanged to `updates/macos/arm64/appcast.xml` and `updates/macos/x64/appcast.xml`, commit, and publish. Their immutable enclosure URLs point to the exact release tag; they must not point to GitHub's cross-platform `latest` endpoint. Updating XML, release notes or whitespace after signing invalidates its signature; regenerate instead.
6. Verify both raw GitHub feed URLs return the exact signed bytes and reference downloadable matching ZIPs. Exercise update discovery with a dedicated test bundle and mocked/native user driver that cannot install; a real update/relaunch/data-preservation acceptance test must use verified Yomado isolation. Keep build/sign/notarization/feed publication/install acceptance as separate recorded outcomes.

Prerelease packages embed the full `SofatapReleaseVersion` and allow Sparkle’s `beta` channel. The generator marks prerelease entries with that channel; stable packages only accept the default stable channel.

Both feeds and archives require Ed25519 verification. Archive signatures are checked before extraction. Signed-feed failure never expires into an unsigned fallback (`SUSignedFeedFailureExpirationInterval=0`); losing the key therefore requires an explicit recovery/distribution plan. Automatic checks send no Sparkle system profile.

Official documentation: [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [configuration](https://sparkle-project.org/documentation/customization/), [publishing](https://sparkle-project.org/documentation/publishing/), [delegate behavior](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html).

## Noninteractive verification

`ReceiverUpdatePolicyTests.swift` checks that only normal website bundles can start
the updater and that unknown, starting, stopping or connected receiver states
defer relaunch. `python3 -m unittest discover -s scripts/macos -p test_updates.py`
checks nested inventory tampering, escaping/dangling links and rejection of
unnotarized update archives.

After the pinned dependency is already fetched,
`python3 scripts/macos/test-sparkle-discovery.py` runs the actual Sparkle discovery
engine against a loopback-only synthetic feed: a newer signed feed is found, the
current build reports up to date, and a tampered signed feed is rejected. The
same engine also verifies that a stable client skips a higher beta item and
accepts the stable item, that a beta-only feed offers nothing to a stable client,
and that a beta client can accept either a beta or a stable update. It uses
an ephemeral in-memory test key, a unique test bundle/preferences domain and a
noninteractive user driver that refuses any update archive download or install.
It never accesses the production signing key or starts the receiver. This is
discovery/security coverage, not an actual upgrade or pairing-preservation test.
