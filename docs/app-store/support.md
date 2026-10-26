# Sofatap support

Use your iPhone or iPad to control a paired computer from the sofa. Sofatap needs iOS or iPadOS 17 or later, a desktop receiver, and a reachable home network. Your computer keeps displaying its picture on the monitor or TV.

For help, [open a Sofatap issue](https://github.com/chekusu/sofatap/issues/new). Include your iPhone/iPad model and OS version, computer operating system, receiver version, and the steps that failed. Do not post pairing QR codes, pairing links, passwords, private text or unredacted logs.

## Install the receiver

Install [desktop receiver 0.8.1 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.8.1-beta.1), the current desktop release, with Sofatap 1.0 (23). All five packages and matching SHA256 files are available below. This release includes native update controls and optional Mac peer transport. See the [release and package verification](../verification/main-release-2026-10-19.md). Live editing remains limited to supported Windows/Mac fields; Linux and unsupported fields use review-and-send.

Receiver 0.7.2 beta.1 remains a compatible baseline for standard local-network control. Automatic reconnection requires phone build 16 or newer and receiver 0.7.2 or newer; the QR format requires phone build 15 or newer. Mac peer transport requires receiver 0.8.1 and phone build 22 or newer. See the [automated reconnection record](../verification/reconnect-2026-10-15.md) for the earlier validation scope.

| Computer | Download | Installation guide |
| --- | --- | --- |
| Windows x64 | [Windows ZIP](https://github.com/chekusu/sofatap/releases/download/v0.8.1-beta.1/SofaTap-Windows-x64.zip) | [Windows setup](../WINDOWS-START.md). Extract the full package and run `SofaTap.exe`. Allow the receiver on a trusted private network when prompted; do not disable the firewall. Windows binaries are not Authenticode-signed. |
| Mac, macOS 15+ | [Apple Silicon ZIP](https://github.com/chekusu/sofatap/releases/download/v0.8.1-beta.1/SofaTap-macOS-arm64-notarized.zip) · [Intel ZIP](https://github.com/chekusu/sofatap/releases/download/v0.8.1-beta.1/SofaTap-macOS-x64-notarized.zip) | Both packages are signed and notarized. Place `Sofatap Receiver.app` in Applications, open it normally, and grant it Accessibility permission. [Mac permission guide](../MAC-START.md); older examples there use the historical app name. |
| Linux | [x64 archive](https://github.com/chekusu/sofatap/releases/download/v0.8.1-beta.1/SofaTap-Linux-x64.tar.gz) · [ARM64 archive](https://github.com/chekusu/sofatap/releases/download/v0.8.1-beta.1/SofaTap-Linux-arm64.tar.gz) | [Linux setup and dependencies](../../desktop/linux/README.md). X11 is the initial desktop path; Wayland is experimental and depends on the desktop's RemoteDesktop portal. |

iPhone **1.0 (23)** is the current public TestFlight build, has passed external beta review and is available through the [public invitation](https://testflight.apple.com/join/e6MuKx9S), with a limit of 10,000 testers. See the [build 23 distribution record](../verification/testflight-1.0-23.md) for its exact source and validation limits. Build 23 adds a hold-to-drag tolerance fix to build 22; unreleased desktop volume and pointer-speed controls on main are not included. The separate formal App Store build 15 submission was recorded as waiting for review on October 24, 2026; that historical status does not describe the outcome of a later replacement submission. TestFlight installation of build 16 on the dedicated test iPhone was verified, but no physical build 23 smoke test or final-build Windows drag acceptance is recorded. Earlier pairing/input acceptance remains documented under its actual versions in the [0.7.1 verification record](../verification/receiver-0.7.1.md) and [build 16 development checks](../verification/input-1.0-16.md).

The ordinary receiver requires an unlocked, interactive desktop. A Windows Remote Desktop session and the desktop shown on a TV can be different sessions. Sofatap does not unlock the computer or enter a Windows sign-in PIN in this release.

## Pair your iPhone or iPad

1. Open the receiver on the computer and choose a home-network address reachable by the phone.
2. Connect the iPhone to the same home network. A wired computer is fine; guest Wi-Fi client isolation may prevent access.
3. Tap the top-left device selector and choose **Scan QR Code** under **Add Device**, then scan the receiver code or paste the complete pairing link. The camera appears above the platform information; computers and Android/Google TV use the same scanner without a device-type choice.
4. Allow Local Network access on the phone. If it was denied, enable it for Sofatap in Settings.
5. Check the connection indicator, then look at the computer screen while controlling it.

Build 15 and newer identify the connection type automatically and display any platform/name supplied by the code. After the authenticated connection succeeds, keep the suggested name or save a new one. You can rename it later in My Devices; this changes only the name on your iPhone. LG webOS still requires manual IP entry and approval on the TV. Android/Google TV requires its development receiver and remains experimental, with no qualified physical TV model or third-party TV app.

Receiver 0.7.1 beta.1 and newer include `platform` and `name` in their desktop codes. **iPhone 1.0 build 15 or newer is required**. If your phone cannot update yet, keep [receiver 0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1); build 15 also accepts that older code format. Platform/name labels do not replace certificate and pairing-credential checks.

## Gestures and text

- Slide one finger to move the pointer.
- With the default Sofatap preset in build 23, tap once for a left click, double-tap the invisible left half for two left clicks or the right half for two right clicks. The older build 15 used a double-tap anywhere for one right click.
- Hold still for 0.3 seconds, then move to drag; lift your finger to release. Build 23 tolerates a small finger roll that settles before the hold deadline.
- Slide two fingers to drag content naturally. The strip inside the touchpad's right edge follows scrollbar direction: slide down to scroll down.
- Tap the keyboard icon to type, or the microphone to dictate where on-device recognition is supported.

Build 18 and newer include the gear button for three gesture presets, individual assignments, timing, scroll direction and local practice. Computer and TV preferences are saved separately. The guide reflects your current assignments; selecting another preset can change the defaults above. See [gesture settings](../GESTURES.md).

A compatible receiver can open the keyboard when a supported text field gains focus. Live editing is available only for certain native Windows and Mac fields. It imports the field's text and synchronizes editing automatically. Unsupported fields, including many browser and custom controls, use review-and-send; Linux and older receivers use this mode. Sofatap does not append an extra Return after your text. Line breaks you include may be handled as Enter by the destination app.

If live input pauses after a focus change or a connection problem, check the computer and reopen the editor. Do not resend uncertain text before checking whether it already arrived. If the microphone is unavailable, check the permissions or use keyboard input; Sofatap does not silently switch to a cloud recognizer.

## Reconnect after restarting the receiver (build 16+ and receiver 0.7.2+)

Use iPhone build 16 or newer and receiver 0.7.2 beta.1 or newer. Keep the saved computer selected and Sofatap open on the iPhone while reopening the receiver. The phone retries temporary failures with increasing delays of up to 30 seconds; no new QR scan should be needed when the receiver still has the original certificate and pairing credentials. Manual disconnection or switching devices stops these retries. Reconnection does not resend unconfirmed typing or mouse actions; inspect the destination before resuming an editor.

The new receiver preserves pairing when network addresses are only added, only removed, or temporarily unavailable. A real address replacement or certificate renewal can still require explicit pairing. Existing duplicate entries are preserved; use My Devices to remove an obsolete entry after checking which saved device connects. See the [automated reconnection verification](../verification/reconnect-2026-10-15.md). Physical iPhone-to-Windows restart acceptance remains pending.

Build 16 also adds a computer Backspace icon below the composer. It deletes at the computer's focused input position without changing the phone draft. Keyboard Backspace edits an unsent fallback draft locally; after clearing that draft, it can forward Backspace to the computer. Live editing continues to synchronize deletions. See the [scoped build 16 development checks](../verification/input-1.0-16.md).

## Privacy

[Read the Sofatap Privacy Policy](../../PRIVACY.md). Pairing codes and links are credentials; keep them on your own devices. Camera, microphone and speech permissions can be changed in iPhone Settings. Quit the desktop receiver to stop remote control.

## Managing paired devices (build 13+)

Tap the device name at the top left to switch between saved computers or TVs. Each row shows its name, type and address; the active target is marked explicitly. The ellipsis menu renames the device on this iPhone, disconnects it, or removes its local pairing. Removal does not revoke other phones. The top-right question mark opens the illustrated guide. Interface and permission prompts follow the device language, with the same [12 languages as the website](../APP-LANGUAGES.md).
