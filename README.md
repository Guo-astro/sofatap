# Sofatap

**English** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

**Your iPhone, your living-room remote.**

![Sofatap product scenario: using an iPhone from the sofa to control a computer connected to the living-room TV](docs/images/sofatap-living-room.png)

*AI-generated product scenario illustration; not an application screenshot.*

Sofatap is an open-source remote by [chekusu](https://github.com/chekusu). Turn your iPhone into a gesture-driven mouse and voice/text input surface for a Windows, Mac or supported Linux computer. Keep the computer's picture on your TV and control it from the sofa.

[Releases](https://github.com/chekusu/sofatap/releases) · [Issues](https://github.com/chekusu/sofatap/issues) · [MIT license](LICENSE)

## What you can do

- One rounded touch surface contains the logo, QR scanner, microphone and keyboard controls. A gently flowing dot matrix fills the surface; touch warps nearby dots and taps send ripples through it. There is no on-surface instruction text. Reduce Motion keeps the grid static with simpler touch feedback.
- Slide to move, tap for a left click, double-tap for a right click, hold still for 300 ms to drag, and use two fingers to scroll.
- Tap the bottom microphone for on-device dictation when supported, or use the iPhone keyboard / Typeless. Review the local draft and tap **Send** to type into the computer's focused field. Sending does not append Enter or submit the form; embedded line breaks remain part of the text.
- Pair by scanning a QR code in a **native desktop window**: AppKit/SwiftUI on Mac, WinForms on Windows and GTK3 on Linux. No browser is needed for pairing.
- Connect over your home network with WSS/TLS, certificate pinning and locally stored pairing credentials. Draft retention, send confirmation and no automatic replay help avoid accidental duplicate input after a disconnect.

**This is an alpha preview.** The single-screen interaction, microphone and focused-field hints are in the 0.5.0 (iPhone build 8) development source on `main`; the downloads below are earlier alpha releases and do not include these changes. Real iPhone gesture/dictation, Typeless and per-application focus behavior still need acceptance testing. Bluetooth and a hosted relay service are not implemented. See the [interaction specification and future standalone CUA direction](docs/INTERACTION.md).

Tap the logo for connection details and gesture help. The text composer appears only when needed, below the touch surface, and keeps draft review and explicit sending. [View the offline simulator layout](docs/images/sofatap-single-screen.png) and [dot-matrix preview](docs/images/sofatap-touch-effects.mp4). These show local rendering, not physical iPhone input or performance.

The keyboard opens automatically when a compatible receiver detects a new writable native or web field that exposes accessibility metadata. Detection never reads field contents; unsupported, read-only or protected targets do not trigger automatic input UI. Linux detection requires an optional AT-SPI bridge. Manual keyboard access remains available. See [focus detection and platform limits](docs/TEXT-FOCUS.md).

## Platform status

| Platform | Current status |
| --- | --- |
| iPhone | iOS 17+. Version 0.3.0 (4) on an iPhone 17 Pro Max passed scoped iPhone-to-Mac checks. The 0.5.0 (8) single-screen gestures, microphone and automatic keyboard still need physical-device acceptance. |
| Windows | Native receiver released in 0.3.0. This version's desktop UI and physical iPhone integration still need acceptance testing. |
| Mac | macOS 15+. Apple Silicon and Intel packages are notarized. Scoped physical-device checks passed on Apple Silicon; Intel input still needs testing. |
| Linux | Native GTK3 receiver released in 0.4.0. X11 input passed isolated desktop checks. Wayland portal support is experimental; physical iPhone integration, real Wayland compositors and ARM64 runtime testing remain pending. |

The [Mac verification record](docs/verification/macos-0.3.0.md) covers real camera pairing, TLS, exact text readback and selected key/pointer actions on 2026-10-11. The [Linux verification record](docs/verification/linux-0.4.0.md) covers native GTK rendering, X11 input on an isolated Xvfb desktop and a mock Wayland portal on a private D-Bus. Neither record establishes complete application compatibility.

Windows uses Win32 `SendInput`; Mac uses Quartz after an explicit local Accessibility grant. Linux X11 requires libX11, libXtst and libxdo; Wayland requires a compatible RemoteDesktop portal and a native user permission grant. Linux accepts up to 2,048 Unicode scalar values per text action and does not read or replace the clipboard. Unsupported Wayland sessions remain unavailable, with no XWayland fallback. See [Linux requirements and limits](desktop/linux/README.md).

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
4. Select a field on the computer, compose and review your text on the phone, then explicitly send it. Verify the result on the computer before resending an uncertain action.

Pairing links contain control credentials: keep them on your own devices. If upgrading from the earliest **Tiltro** releases, follow the [upgrade guide](docs/WINDOWS-START.md#从旧名称版本升级): those releases used different identifiers and storage, and their pairings and drafts do not migrate automatically. The current Sofatap spelling update preserves existing Sofatap pairings.

## Privacy and permissions

Sofatap connects directly over the local network. The project has no hosted relay service. Pairing uses a pinned TLS certificate; credentials are stored in iPhone Keychain, Windows DPAPI, or current-user-only receiver files on Mac/Linux. Mac input requires Accessibility permission; Wayland input requires the desktop's explicit portal grant.

The microphone starts only after an explicit tap and the required permissions. Supported on-device recognition keeps audio on the phone; Sofatap does not upload audio or silently switch to cloud recognition. Recognized text stays in the local draft until **Send**. System dictation and third-party keyboards have their own data handling.

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

Build, protocol, virtual-desktop and physical-device checks establish different things. Remaining 0.5.0 acceptance includes physical single/double taps, 300 ms hold-to-drag, scrolling, particle feedback and Reduce Motion, microphone permissions and recognition, Typeless, per-application keyboard focus, and phone-to-computer behavior on each supported desktop platform.

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
