# Sofatap receiver 0.7.1 beta.1

Date: **October 14, 2026**. Release: [v0.7.1-beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.1-beta.1). All five packages were built from clean source [`6e127ac8f17124a26872d1787e7ae7adbb5647ed`](https://github.com/chekusu/sofatap/commit/6e127ac8f17124a26872d1787e7ae7adbb5647ed).

The desktop QR now includes the computer's platform and name. **Update the iPhone to 1.0 build 15 or newer before installing these receivers.** Earlier phone builds cannot parse the new codes. Build 15 also accepts the older codes from receiver 0.7.0 beta.1. Labels identify a candidate; TLS certificate pinning and pairing-credential authentication establish the connection. Device nicknames are stored locally on the iPhone and do not rename the computer.

## Published packages

The release was published at **00:33:59 UTC**. At **00:35:44 UTC**, all five archives were downloaded anonymously in full, without authorization headers or cookies. Each returned HTTP 200; byte counts and SHA256 matched both the verified local package and its published checksum file.

| Package | Bytes | SHA256 |
| --- | ---: | --- |
| [Windows x64 ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-Windows-x64.zip) | 90,945,625 | `cf35e8d93c2e3eaeb8970dfba9c67ae15c8ce485b1677d09410ccb939566fe63` |
| [Mac Apple Silicon ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-macOS-arm64-notarized.zip) | 43,761,364 | `764c5937efb497413c119e7cc5b51abfeaebeffb45f70d2ce1fd4568d17ca719` |
| [Mac Intel ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-macOS-x64-notarized.zip) | 46,634,385 | `9d59e3839304dce4db1113b27ca1740aa59d7aeda8635088abc76d2faaec17c2` |
| [Linux x64 archive](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-Linux-x64.tar.gz) | 45,336,047 | `9cb9710ade4f364fe9bb08a4251f4c9ca47ba0451a819d0fcbaeaababb4c78c6` |
| [Linux ARM64 archive](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-Linux-arm64.tar.gz) | 43,158,700 | `c1096d686da28802e4ed039062d6544c00d7ebe3c0e3fee630d0fdddd10b0940` |

Each archive has an adjacent `.sha256` download. Packages include the .NET runtime and resolved dependency licenses. Linux still needs the [documented system GTK/input dependencies](../../desktop/linux/README.md). Windows executables are not Authenticode-signed.

Both Mac packages are version **0.7.1 (61)**, require macOS 15 or newer, and are Developer ID signed with the hardened runtime. Apple accepted both notarization submissions. The final extracted archives passed strict signature verification, stapled-ticket validation, Gatekeeper assessment, architecture checks and license-inventory checks. Apple notarization does not establish physical-phone or desktop-input behavior.

## Build and software checks

[CI run 38490073528](https://github.com/chekusu/sofatap/actions/runs/38490073528) passed all four jobs at the exact release source: Windows, Linux, macOS/iOS and Android TV. The Android job is a regression check; this release does not distribute a TV APK or qualify a TV model.

| Check | Result |
| --- | --- |
| Host protocol and input-policy checks | 384 passed; recording sinks, not physical Windows/Mac input |
| Windows native protocol/lifecycle | 82 passed; no WinForms window or real input launched by that runner |
| Linux native protocol / input state / Wayland state / text-focus policy | 13 / 41 / 27 / 15 passed |
| Mac native protocol / pipe integration / test-display launch and placement | 67 / 5 / 35 passed |
| Package provenance | Final source revision, clean tree, embedded version, native architecture, safe archive structure and included licenses checked |

The local Windows/Linux checks first ran at `c6fb0b89af7518105bdf1d8484558643c8a28086`. A source comparison verified those host, platform, test and packaging scopes were unchanged in the final commit; the final packages were rebuilt at `6e127ac`. The final-source CI also passed independently.

## Physical iPhone and receiver acceptance

The resident test iPhone has **TestFlight 1.0 (15)** installed. The TestFlight interface and device installation metadata independently confirmed that version. This is separate from the earlier development-signed 0.7.0 (10) input tests.

| Check | Observed result |
| --- | --- |
| Linux camera scan | Passed: the iPhone's real camera read the Linux receiver QR displayed on the adjacent test iPad after the user positioned it. No paste or deep link substituted for that scan. |
| Automatic identification | Passed: the phone displayed **Linux** and the receiver name **Sofatap-Linux-QA**, then reached the naming form after authentication. |
| Initial naming | Passed: saved the synthetic alias **客厅 Linux 测试**. |
| Rename from My Devices | Passed: changed the alias to **客厅 Linux** through the device-management action. |
| Persistence and final-package reconnect | Passed: after a cold app restart, **客厅 Linux** remained saved and the phone authenticated to the final published Linux receiver. The receiver independently recorded the connection at 00:35 UTC. |
| Mac optical scan, identification and naming | Pending. Native dry-run receiver placement is verified separately below. |
| Windows installation | Passed: the release ZIP hash and installed 0.7.1/source revision were verified on the test PC; the receiver started on its existing port and its pairing profile remained unchanged. |
| Windows optical scan, identification and naming | Pending. The remote agent could not obtain a decodable native-window capture; installed-receiver checks do not establish physical-phone acceptance. |
| Real desktop mouse/keyboard input in this run | Not tested. Mac and Linux used dry-run mode; no Windows input actions were issued. |

The first Linux optical scan preceded replacement with the final release archive. The final receiver retained the test pairing profile and accepted the subsequent reconnection. This record distinguishes that optical scan from a fresh scan of the final running package; it does not imply every package or architecture was independently scanned.

Linux ran the actual packaged ARM64 backend and GTK frontend in an owned Ubuntu container with an isolated Xvfb desktop. The phone used the production pinned TLS connection through a TCP passthrough; TLS was not intercepted. This establishes scoped ARM64 runtime and phone-pairing behavior. It does not establish physical Linux desktop input, a real Wayland compositor, or universal Linux distribution compatibility.

After the first successful scan, the phone's rear view became nearly black in both Sofatap and Apple's Camera app, while the iPad still displayed the QR. Reopening the scanner and restarting Sofatap did not restore a visible target. Further optical tests are awaiting physical camera alignment; this observation does not establish a Sofatap camera defect. Mac and Windows QR relays were prepared read-only from the running receivers' existing identities using the production format, checked by image decoding and against the live TLS certificates. Those reconstructed images are not native-window screenshots and do not count as phone scans.

## Shared-Mac isolation

The Mac receiver's explicit `--dry-run --test-display-id <ID>` QA mode placed its windows wholly inside the existing non-primary Yomado virtual display. The physical main display, display arrangement and foreground application remained unchanged in the before/after checks. The test windows did not activate the app, and real desktop input was disabled. Linux used its separate container/Xvfb display without host display or input-device mounts.

No real Mac mouse or keyboard events were sent. Window placement alone is not claimed as input isolation; dry-run operation and the isolated Linux desktop provide the boundary for these pairing tests. This run does not replace earlier or future production input acceptance.

During cleanup, querying the closed app through the UI tool unexpectedly relaunched it without the QA arguments. It was immediately quit again; no remote input was sent. Final process/window checks confirmed no test receiver remained, the original foreground app and physical main display were restored, and the temporary QR servers and Linux relay were stopped. This cleanup incident is separate from the verified nonactivating QA launch and means the entire session should not be described as having no transient UI effect.

## Evidence and remaining scope

Local evidence includes `public-download-verification.json`, `package-summary.json`, `unchanged-check-source-proof.json`, `MAC-PUBLIC-RELEASE-VERIFICATION.json`, architecture-specific notarization/archive receipts, `mac-isolation-verification.json`, phone installation/cold-launch receipts and the Linux connection confirmation. Private QR images, pairing credentials, local addresses, hardware identifiers and raw device observations are excluded from this public record.

Mac and Windows optical pairing/naming remain separate acceptance items. Production desktop input, Intel Mac runtime, real Wayland behavior, microphone dictation and broader application compatibility were not requalified by this receiver release. TestFlight external review and public phone installation are tracked in the [iPhone distribution record](testflight-1.0-15.md); a public desktop download does not change Apple's review status.
