# Sofatap

**English** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

**Your iPhone, your living-room remote.**

![Sofatap product scenario: using an iPhone from the sofa to control a computer connected to the living-room TV](docs/images/sofatap-living-room.png)

*AI-generated product scenario illustration; not an application screenshot.*

Sofatap is an open-source remote by [chekusu](https://github.com/chekusu). Turn your iPhone into a gesture-driven mouse and voice/text input surface for a Windows, Mac or supported Linux computer. Keep the computer's picture on your TV and control it from the sofa.

[Releases](https://github.com/chekusu/sofatap/releases) · [Issues](https://github.com/chekusu/sofatap/issues) · [MIT license](LICENSE)

## Watch the film

[![Watch the Sofatap film: an iPhone controls the computer on the TV with gestures, keyboard input and voice dictation](https://sofatap.app/media/sofatap-demo-poster-en.jpg)](https://sofatap.app/#video)

A one-minute tour of pointer gestures, typing on the phone keyboard and voice dictation, all from the sofa. [Watch the film on sofatap.app](https://sofatap.app/#video) or download the captioned MP4: [English](https://sofatap.app/exports/sofatap-promo-en.mp4) · [Simplified Chinese](https://sofatap.app/exports/sofatap-promo-zh-cn.mp4).

## What you can do

- One rounded touch surface contains the logo, QR scanner, microphone and keyboard controls. A gently flowing dot matrix fills the surface; touch warps nearby dots and taps send ripples through it. There is no on-surface instruction text. Reduce Motion keeps the grid static with simpler touch feedback.
- Slide to move, tap for a left click, double-tap for a right click, hold still for 300 ms to drag, and use two fingers to scroll.
- Tap the bottom microphone for on-device dictation when supported, or use the iPhone keyboard / Typeless. In supported fields, live input is the default: confirmed keyboard text, deletions, selections and speech recognition updates synchronize without a **Send** button. Unsupported fields and older receivers retain the review-and-send composer. No extra Enter or form-submit action is appended.
- Pair by scanning a QR code in a **native desktop window**: AppKit/SwiftUI on Mac, WinForms on Windows and GTK3 on Linux. No browser is needed for pairing.
- The three desktop receivers share the selected **Mint Calm (暮色薄荷)** design: charcoal background, pale mint actions and a clear white QR area. See the [design specification](docs/RECEIVER-DESIGN.md); this work is in development source, not the earlier downloads below.
- Connect over your home network with WSS/TLS, certificate pinning and locally stored pairing credentials. Live input pauses on conflicting desktop edits or a lost connection; it never automatically replays uncertain edits.

**This is an alpha preview.** Live text editing is in the 0.7.0 (iPhone build 10) development source on `main`; the downloads below are earlier alpha releases. [Scoped 0.7.0 iPhone-to-Windows checks](docs/verification/realtime-input-0.7.0.md) passed existing-text import, multilingual/emoji/newline append, keyboard deletion, Select All and deletion to empty in a native RichEdit field. Live speech and further cases remain pending. The [0.6.0 record](docs/verification/2026-10-13-iphone-input.md) separately covers gestures, microphone dictation and explicit text sending. Bluetooth and a hosted relay service are not implemented. See the [interaction specification and future standalone CUA direction](docs/INTERACTION.md).

Tap the logo for connection details and gesture help. The text composer appears only when needed, below the touch surface. Supported fields open as live editors; other fields keep draft review and explicit sending. [View the offline simulator layout](docs/images/sofatap-single-screen.png) and [dot-matrix preview](docs/images/sofatap-touch-effects.mp4). These show local rendering, not physical iPhone input or performance.

The keyboard opens automatically when a compatible receiver detects a new writable native or web field that exposes accessibility metadata. This background detection reads no field contents. Opening a live editing session then imports the supported field’s complete text and selection to the paired phone, so Backspace and Select All → Delete can edit existing computer text. Detection support and live-editing support are separate: Windows live input currently supports native Edit/RichEdit controls; Mac requires writable Accessibility selected-text and selection-range attributes. Browsers, custom controls without that support, Linux and older receivers use the review-and-send fallback. Protected and read-only fields cannot start live editing. See [focus detection, data handling and platform limits](docs/TEXT-FOCUS.md).

**Windows lock-screen PIN control (under validation):** the target is iPhone touchpad + manual PIN entry, with optional Face ID-authorized saved PIN entry. Sofatap does not require a Microsoft account password. The earlier account-password pilot is retired and disabled in ordinary discovery and iPhone UI. Pointer diagnostics, native PIN acceptance and iPhone end-to-end tests are separate gates; none is implied by pairing or compilation. See [scope and verification](docs/FACE-ID-UNLOCK.md).

## Platform status

| Platform | Current status |
| --- | --- |
| iPhone | iOS 17+. Physical 0.7.0 (10) live import, append, deletion and selection passed in a Windows RichEdit fixture; live speech and broader coverage remain pending. |
| Windows | Native receiver released in 0.3.0. Development source supports native Edit/RichEdit live editing; scoped physical RichEdit keyboard checks passed, with further device cases pending. |
| Mac | macOS 15+. Apple Silicon and Intel packages are notarized. Scoped physical-device checks passed on Apple Silicon; Intel input still needs testing. |
| Linux | Native GTK3 receiver released in 0.4.0. X11 input passed isolated desktop checks. Wayland portal support is experimental; physical iPhone integration, real Wayland compositors and ARM64 runtime testing remain pending. |

The [Mac verification record](docs/verification/macos-0.3.0.md) covers real camera pairing, TLS, exact text readback and selected key/pointer actions on 2026-10-11. The [Linux verification record](docs/verification/linux-0.4.0.md) covers native GTK rendering, X11 input on an isolated Xvfb desktop and a mock Wayland portal on a private D-Bus. Neither record establishes complete application compatibility.

Pointer, shortcut and fallback text input use Win32 `SendInput` on Windows and Quartz on Mac after an explicit local Accessibility grant. Live text instead edits and verifies the supported native field through Win32 Edit/RichEdit messages or Mac Accessibility selected-text operations, preserving text outside the changed span. Linux X11 requires libX11, libXtst and libxdo; Wayland requires a compatible RemoteDesktop portal and a native user permission grant. Linux currently uses review-and-send text, accepts up to 2,048 Unicode scalar values per text action, and does not read or replace the clipboard. Unsupported Wayland sessions remain unavailable, with no XWayland fallback. See [Linux requirements and limits](desktop/linux/README.md).

## Get started

### Install the desktop receiver

| Computer | Download | Instructions |
| --- | --- | --- |
| Windows x64 | [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha): `SofaTap-Windows-x64.zip` and its `.sha256` | Extract and run `SofaTap.exe`. Allow firewall access only on your trusted home private network. [Windows guide](docs/WINDOWS-START.md) |
| Mac | [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha): `SofaTap-macOS-arm64-notarized.zip` or `SofaTap-macOS-x64-notarized.zip` and its `.sha256` | Choose Apple Silicon or Intel. Both packages are notarized. Follow the [Mac installation and permission guide](docs/MAC-START.md). |
| Linux x64 / ARM64 | [v0.4.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.4.0-alpha): `SofaTap-Linux-x64.tar.gz` or `SofaTap-Linux-arm64.tar.gz` and its `.sha256` | Install the system GTK/input dependencies, extract and run `./sofatap`. The native window includes the Wayland authorization action. [Linux guide](desktop/linux/README.md) |

The desktop packages include the .NET runtime. Linux still requires the system dependencies in its guide. `--dry-run` previews connectivity without generating desktop input.

### Install the iPhone app and pair

1. Open `ios/SofaTap.xcodeproj` in Xcode, select your development team and connected iPhone, then run the app. Installation requires valid development signing, device pairing and Developer Mode. See the [iOS build guide](ios/README.md).
2. Connect the iPhone and computer to the same reachable home network. Guest Wi-Fi device isolation may prevent a connection.
3. Scan the QR code in the receiver's native window, or paste the complete pairing link into the iPhone app.
4. Select a field on the computer and open the phone keyboard or microphone. A supported field synchronizes typing, deletion and recognized speech automatically; an unsupported field shows **Send** for a reviewed draft. If live input pauses after a focus conflict or disconnect, inspect the computer and explicitly reopen the editor. Uncertain edits are never replayed automatically.

Pairing links contain control credentials: keep them on your own devices. If upgrading from the earliest **Tiltro** releases, follow the [upgrade guide](docs/WINDOWS-START.md#从旧名称版本升级): those releases used different identifiers and storage, and their pairings and drafts do not migrate automatically. The current Sofatap spelling update preserves existing Sofatap pairings.

## Privacy and permissions

Sofatap connects directly over the local network. The project has no hosted relay service. Pairing uses a pinned TLS certificate; credentials are stored in iPhone Keychain, Windows DPAPI, or current-user-only receiver files on Mac/Linux. Mac input requires Accessibility permission; Wayland input requires the desktop's explicit portal grant.

The microphone starts only after an explicit tap and the required permissions. Supported on-device recognition keeps audio on the phone; Sofatap does not upload audio or silently switch to cloud recognition. In a live editing session, partial recognized text and later corrections synchronize to the computer. In the fallback composer, text stays local until **Send**. System dictation and third-party keyboards have their own data handling.

Live editing sends the current supported field’s complete text and selection directly to the paired phone over pinned TLS. The phone keeps this imported live text in memory rather than its saved draft preferences. The receiver keeps bounded text-bearing acknowledgements in connection memory for duplicate suppression until the connection ends. The separate review-and-send draft remains stored locally for recovery. Field text is not logged or sent to a hosted service; background focus hints contain only metadata.

Pairing QR codes travel through a private local pipe to the native desktop UI, not a web pairing page. Never publish pairing codes, credentials or signing material. The repository includes no developer account, signing certificate or provisioning profile. See [PROTOCOL.md](PROTOCOL.md) for the transport and input behavior, and [the acceptance checklist](docs/ACCEPTANCE.md) for remaining device checks.

## Build from source

The receiver requires the **.NET 10 SDK** and Python 3. Set `SOFATAP_DOTNET` to the `dotnet` executable if your SDK is in a custom location.

```sh
# Windows distribution, built on Mac/Unix
bash scripts/build-windows.sh

# Mac distributions, built on macOS
bash scripts/build-macos.sh arm64
bash scripts/build-macos.sh x64

# Linux distributions; cross-building is supported
bash scripts/build-linux.sh x64
bash scripts/build-linux.sh arm64
```

Packages are written to `artifacts/` with licenses and SHA256 files. Windows and Mac outputs are named `SofaTap-Windows-x64.zip` and `SofaTap-macOS-<architecture>.zip`; Linux outputs are `SofaTap-Linux-<architecture>.tar.gz`. Mac builds use an ad-hoc development signature by default. Distribution signing and Apple notarization are documented in [NOTARIZATION.md](docs/NOTARIZATION.md).

Windows developers can build the underlying receiver in PowerShell; the complete package above also includes its native window:

```powershell
dotnet publish host/SofaTap.Host.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

Redistributed builds must include `LICENSE`, `THIRD-PARTY-NOTICES.md` and the relevant dependency licenses. The packaging scripts collect the licenses for the resolved runtime/NuGet versions.

For iPhone, open the checked-in Xcode project. After changing `ios/project.yml`, regenerate it with `xcodegen generate --spec ios/project.yml`. The [iOS guide](ios/README.md) also describes direct compilation; a successful device build is separate from signing and installation.

## Development checks

On macOS with .NET 10, Python 3 and Xcode installed:

```sh
python3 -m pip install websockets==16.0
dotnet run --project tests/host/SofaTap.Host.Tests.csproj -c Release
dotnet run --project desktop/windows-login/Tests/Sofatap.Login.Tests.csproj -c Release
SOFATAP_DOTNET="$(command -v dotnet)" python3 tests/smoke.py
swiftc ios/SofaTap/Core/Pairing.swift tests/PairingTests.swift -o /tmp/sofatap-pairing-tests
/tmp/sofatap-pairing-tests
swiftc ios/SofaTap/Core/ReceiverState.swift tests/ReceiverStateTests.swift -o /tmp/sofatap-receiver-tests
/tmp/sofatap-receiver-tests
swiftc ios/SofaTap/Core/TouchGestureState.swift tests/TouchGestureTests.swift -o /tmp/sofatap-gesture-tests
/tmp/sofatap-gesture-tests
python3 tests/text_focus_linux.py
bash ios/scripts/build-manual.sh device
```

The host runner uses fake input. TLS/WebSocket checks launch a temporary receiver with `--dry-run` and inject no system input. The last command compiles an unprovisioned ARM64 iOS app without installing it. CI also runs platform builds and isolated Linux desktop checks; see [the Linux guide](desktop/linux/README.md#lifecycle-and-checks) for the relevant commands.

Build, protocol, virtual-desktop and physical-device checks establish different things. The [0.7.0 physical record](docs/verification/realtime-input-0.7.0.md) confirms RichEdit import, append, deletion and selection. Live speech, plain Edit, middle-of-text replacement, conflicts, reconnects, Mac live editing, Typeless and additional applications remain outside that completed scope.

## Repository layout

| Path | Contents |
| --- | --- |
| `ios/` | Native iPhone app, Xcode project and project-generation configuration |
| `host/` | Shared receiver protocol, Windows/Mac input backends and Linux worker bridge |
| `desktop/` | Native pairing windows and Linux input workers |
| `tests/` | Protocol, authentication and input-boundary checks |
| `PROTOCOL.md` | Wire protocol |
| `docs/` | Installation guides and acceptance records |
| `scripts/build-*.sh` | Desktop distribution builds |
| `licenses/` | Third-party license and notice texts |

Local build artifacts, pairing credentials and signing material are not source files. For naming background, see [NAME.md](docs/NAME.md).

## Contributing and license

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.

Sofatap is released under the [MIT license](LICENSE). See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for dependency notices.
