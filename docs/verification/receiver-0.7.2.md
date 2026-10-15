# Sofatap receiver 0.7.2 beta.1

Published **October 15, 2026 at 15:08:10 UTC** (October 16 in Japan): [v0.7.2-beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.2-beta.1). All five packages were built from clean source [`43fd98c409fbd6971ac50a971cbdb3e9d6c3ab78`](https://github.com/chekusu/sofatap/commit/43fd98c409fbd6971ac50a971cbdb3e9d6c3ab78).

This maintenance release preserves the receiver's pairing certificate and token across ordinary restarts, temporary offline operation, and the addition or removal of unrelated network addresses. It avoids invalidating an existing home-network pairing when a VPN or virtual adapter appears. Replacing an old address with an uncertified new address or renewing a certificate can still require explicit pairing; certificate trust is not bypassed.

Automatic retry on the phone is a companion change in **iPhone 1.0 build 16**. The already distributed build 15 does not contain that retry fix. The new receiver remains compatible with build 15, but updating the receiver alone does not add automatic phone retry. The separate [build 16 distribution record](testflight-1.0-16.md) confirms TestFlight external approval, public availability and installation on the dedicated iPhone; those checks do not establish phone-to-Windows restart acceptance.

## Published packages

At **15:08:55 UTC**, every archive and its adjacent checksum file was downloaded anonymously, without cookies or authorization headers. All ten requests returned HTTP 200. Full archive byte counts and SHA256 matched the verified local packages and the published checksums.

| Package | Bytes | SHA256 |
| --- | ---: | --- |
| [Windows x64 ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.2-beta.1/SofaTap-Windows-x64.zip) | 90,946,814 | `cfa3dad6f63b75cd0a7b9e0ae607b81d6394c2aac63c0a87bd266c6bc97863a8` |
| [Mac Apple Silicon ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.2-beta.1/SofaTap-macOS-arm64-notarized.zip) | 43,761,471 | `cc878a99bfb39d229a7997bf0ea8cf02eb3d72ecf217999e8599139ddc078be7` |
| [Mac Intel ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.2-beta.1/SofaTap-macOS-x64-notarized.zip) | 46,634,659 | `d8152c31caf8c7a6c1f4e3817ebb9527f2ec6e4dd83fd06c5669e50eb14dd371` |
| [Linux x64 archive](https://github.com/chekusu/sofatap/releases/download/v0.7.2-beta.1/SofaTap-Linux-x64.tar.gz) | 45,335,963 | `f8dc74f5f71218bce1a26b974e99f8a7a50d004299a49efcb1f5cafc16a45976` |
| [Linux ARM64 archive](https://github.com/chekusu/sofatap/releases/download/v0.7.2-beta.1/SofaTap-Linux-arm64.tar.gz) | 43,158,699 | `1dd77d35001ca08d41e3ab469632a56a564767b1af93d3ef3ee8086f551c33ba` |

Each archive has an adjacent `.sha256` download. Packages include the .NET runtime and resolved dependency licenses. Linux also requires the [documented GTK and input dependencies](../../desktop/linux/README.md). Windows executables remain unsigned by Authenticode.

Both Mac packages are **0.7.2 (69)**, require macOS 15 or newer, and use CHEKUSU Developer ID signing with the hardened runtime. Apple accepted both notarization submissions. The final extracted archives passed strict signature verification, stapled-ticket validation, Gatekeeper assessment, architecture checks and license-inventory checks.

## Source and software verification

[CI run 38742185505](https://github.com/chekusu/sofatap/actions/runs/38742185505) passed all four jobs—Windows, Linux, macOS/iOS and Android TV—at the reconnect-fix commit [`9b6fedb55d32be4236def0717da936d5a708bda1`](https://github.com/chekusu/sofatap/commit/9b6fedb55d32be4236def0717da936d5a708bda1). The only source change between that tested commit and release source `43fd98c` is the receiver version bump from 0.7.1 to 0.7.2. The CI run is not represented as a run at the release SHA. The Android job is a regression check; this release does not distribute a TV APK or qualify a TV model.

The [reconnection verification record](reconnect-2026-10-15.md) documents the underlying checks:

| Check | Result |
| --- | --- |
| Host regression checks | 398 passed, including 14 pairing-credential persistence/address-change checks |
| TLS and WebSocket integration | 69 passed with OS input disabled; ordinary and forced restart both accept the original trusted certificate and token |
| iPhone pairing and retry behavior | 89 passed with recording transport and explicit timer triggers |
| Saved device persistence | 35 passed; repeated scan retains a single matching identity, alias and selection |
| Explicit text / live text / drag release | 61 / 63 / 33 passed |
| Final package provenance | Clean release source; embedded version/source SHA, native architecture, archive integrity, safe paths, executable permissions where applicable and included licenses checked |

Windows and Linux executable metadata identifies `0.7.2+43fd98c409fbd6971ac50a971cbdb3e9d6c3ab78`. The Mac build manifests and notarization receipts identify the same clean source. Final archives were verified after packaging; both Mac archives were verified after notarization and stapling.

## Acceptance boundaries

This release did **not** launch interactive receiver windows or send real desktop input. Physical iPhone-to-Windows close/reopen acceptance, optical QR scanning, actual desktop mouse/keyboard input and other device-level behavior were not requalified in this release. Any later interactive test must first verify Yomado virtual-display placement and input isolation; window placement alone is insufficient.

Existing duplicate entries with different certificate identities are preserved. The fix does not merge records by machine name or IP address, discover a replacement LAN address, or silently trust a replacement certificate. Reconnection restores transport only; pending text and gestures are not replayed.

Private evidence includes `package-summary.json`, `public-download-verification.json`, per-archive verification reports, architecture-specific build manifests and notarization receipts. No pairing credentials, QR codes, signing assets or private device data are included in this public record.
