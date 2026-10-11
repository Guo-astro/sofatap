# Sofa Tap 0.4.0 Linux preview verification

Date: **2026-10-11**. Release: [v0.4.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.4.0-alpha).

Both Linux archives were built from clean source **`3fd996dbc3bb99d5de2e08642fe5271bc20d6832`**, with .NET SDK 10.0.401. This record is a subsequent documentation update; it does not change the source revision embedded in those archives.

## Automated Linux evidence

[CI #38128830028](https://github.com/chekusu/sofatap/actions/runs/38128830028) ran on Ubuntu 24.04 x64. Graphical checks created their own Xvfb servers; no phone or user's physical display was used.

| Check | Result and boundary |
| --- | --- |
| Host validation and worker lifecycle | 174 checks, including exact request IDs, malformed replies, partial/unknown outcomes, no replay, blocked pipes and child cleanup |
| GTK protocol/lifecycle checks | 10 portable tests |
| Worker/X11 state and mapping checks | 41 portable tests, including rejection before input, partial cleanup and concurrent mapping ownership |
| Wayland state machine | 27 portable tests |
| Real Gio D-Bus messages | 8 checks against a fake portal on a new private D-Bus; consent, refusal, incomplete grants, revocation, service loss and cancellation |
| X11 native input | 12 checks with real XTest events on an owned Xvfb; exact GTK readback of Chinese, English, Japanese, emoji, accented text and newline; preserved clipboard and keyboard map; shortcuts, movement, left click, both scroll axes, busy-input rejection, button release and EOF cleanup |
| Packaged GTK frontend | Actual package frontend/hash and bundled backend/worker; QR pixels rendered; real-X11 and explicit dry-run status; native buttons; Quit and window-close paths; owned processes stopped and TCP listener closed |
| Packaged shell launcher | Direct launch and a symlink with spaces both reach the packaged argument parser |
| Distribution builds | x64 and arm64 self-contained packages built with resolved license documents |

The same source's macOS/Windows CI also checks shared transport, iOS compilation and existing platform builds. These do not constitute new Windows/Mac physical-device acceptance or new notarized Mac artifacts.

## Distribution verification

| Archive | SHA256 |
| --- | --- |
| `SofaTap-Linux-x64.tar.gz` | `d296f65a07f20b89937d16f8bab6bbe0b90b3d2f6be650dbf710c86efd208f7f` |
| `SofaTap-Linux-arm64.tar.gz` | `cc8df8a6e820436b6f4c3699130b94d4ceed9d57f68d36ea25796b1759d2aff4` |

Each archive has a matching `.sha256` file, clean source manifest, executable launcher/backend, Python frontend/worker and licenses. Manifest hashes were checked against the archive bytes. Archive members were checked for safe relative paths and absence of signing assets, pairing profiles, local user paths and Python caches. The .NET runtime is included; GTK/PyGObject, Python and desktop input libraries are distribution dependencies. ARM64 has been cross-built, but has not run on an ARM64 Linux desktop. After publication, both archives and their checksum files were downloaded anonymously from the public release; the SHA256 values matched the verified local packages above.

## Remaining acceptance

- Real iPhone camera pairing, LAN behavior, text and pointer interaction with Linux.
- Real GNOME/KDE or other Wayland compositor permission dialogs and destination-application Unicode handling. The portal implementation is experimental; mock D-Bus success does not prove compositor compatibility.
- Typeless, actual dictation, physical gyroscope/air-mouse behavior, long sessions and application compatibility beyond the isolated GTK editor.
- Physical X11 desktops, differing keyboard layouts, input methods, lock/unlock and ARM64 runtime behavior.

A successful input ACK confirms system submission, not that an arbitrary application accepted or saved it. Linux text has a 2,048-scalar ceiling; X11 may reject a shorter selection before typing when temporary key slots or its time budget are insufficient. Partial or unknown delivery is not retried automatically. Neither Linux backend reads or replaces the clipboard.

The installed Mac receiver and user's normal displays were not touched. Any future shared-Mac acceptance must follow the repository's Yomado virtual-display and verified input-isolation requirements.
