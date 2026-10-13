# Sofatap support

Use your iPhone to control a paired computer from the sofa. Sofatap needs an iPhone running iOS 17 or later, a desktop receiver, and a reachable home network. Your computer keeps displaying its picture on the monitor or TV.

For help, [open a Sofatap issue](https://github.com/chekusu/sofatap/issues/new). Include your iPhone/iOS version, computer operating system, receiver version, and the steps that failed. Do not post pairing QR codes, pairing links, passwords, private text or unredacted logs.

## Install the receiver

[Receiver 0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1) is compatible with iPhone 1.0 (12). It includes native pairing, the current Sofatap icon and live editing for supported Windows/Mac fields. Linux and unsupported fields use review-and-send. All five packages and their SHA256 files are public; read the release notes for validation limits.

| Computer | Download | Installation guide |
| --- | --- | --- |
| Windows x64 | [Windows ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.0-beta.1/SofaTap-Windows-x64.zip) | [Windows setup](../WINDOWS-START.md). Extract the full package and run `SofaTap.exe`. Allow the receiver on a trusted private network when prompted; do not disable the firewall. Windows binaries are not Authenticode-signed. |
| Mac, macOS 15+ | [Apple Silicon ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.0-beta.1/SofaTap-macOS-arm64-notarized.zip) · [Intel ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.0-beta.1/SofaTap-macOS-x64-notarized.zip) | Both packages are signed and notarized. Place `Sofatap Receiver.app` in Applications, open it normally, and grant it Accessibility permission. [Mac permission guide](../MAC-START.md); older examples there use the historical app name. |
| Linux | [x64 archive](https://github.com/chekusu/sofatap/releases/download/v0.7.0-beta.1/SofaTap-Linux-x64.tar.gz) · [ARM64 archive](https://github.com/chekusu/sofatap/releases/download/v0.7.0-beta.1/SofaTap-Linux-arm64.tar.gz) | [Linux setup and dependencies](../../desktop/linux/README.md). X11 is the initial desktop path; Wayland is experimental and depends on the desktop's RemoteDesktop portal. |

The iPhone 1.0 (12) build has completed Apple processing and is available to invited internal TestFlight testers. A [public TestFlight invitation](https://testflight.apple.com/join/e6MuKx9S) is configured for up to 100 testers, and build 12 has been submitted for external review. Apple currently reports **Waiting for Review**. Friends cannot install through that link until Apple approves external testing. See the [release record](../verification/testflight-1.0-12.md). Final-build physical installation and input acceptance remain separate from build processing.

The ordinary receiver requires an unlocked, interactive desktop. A Windows Remote Desktop session and the desktop shown on a TV can be different sessions. Sofatap does not unlock the computer or enter a Windows sign-in PIN in this release.

## Pair your iPhone

1. Open the receiver on the computer and choose a home-network address reachable by the phone.
2. Connect the iPhone to the same home network. A wired computer is fine; guest Wi-Fi client isolation may prevent access.
3. In Sofatap, tap the QR icon and scan the code in the receiver's native window. You can also paste the complete pairing link.
4. Allow Local Network access on the phone. If it was denied, enable it for Sofatap in Settings.
5. Check the connection indicator, then look at the computer screen while controlling it.

## Gestures and text

- Slide one finger to move the pointer.
- Tap once for a left click; tap twice in succession for a right click.
- Hold still for 0.3 seconds, then move to drag; lift your finger to release.
- Slide two fingers to drag content naturally. The strip inside the touchpad's right edge follows scrollbar direction: slide down to scroll down.
- Tap the keyboard icon to type, or the microphone to dictate where on-device recognition is supported.

A compatible receiver can open the keyboard when a supported text field gains focus. Live editing is available only for certain native Windows and Mac fields. It imports the field's text and synchronizes editing automatically. Browsers, custom fields, Linux and older receivers use a draft with a Send action instead. No extra Enter or form submission is added to text input.

If live input pauses after a focus change or a connection problem, check the computer and reopen the editor. Do not resend uncertain text before checking whether it already arrived. If the microphone is unavailable, check the permissions or use keyboard input; Sofatap does not silently switch to a cloud recognizer.

## Privacy

[Read the Sofatap Privacy Policy](../../PRIVACY.md). Pairing codes and links are credentials; keep them on your own devices. Camera, microphone and speech permissions can be changed in iPhone Settings. Quit the desktop receiver to stop remote control.
