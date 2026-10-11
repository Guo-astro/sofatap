# Sofatap receiver for Linux

Use your iPhone as a touchpad, mouse and keyboard for a Linux computer. Pairing happens in a native GTK window. Sofatap does not open a browser or serve a local pairing website.

The receiver needs a logged-in graphical Linux desktop. It is not a headless remote-login service. Builds are available for x86-64 (`x64`) and 64-bit ARM (`arm64`). The self-contained backend includes .NET; Python, GTK and the desktop input libraries remain system dependencies.

## Start the packaged receiver

1. Download the archive for your computer's architecture and extract it.
2. Install the dependencies listed below using your distribution's package manager.
3. Open the extracted folder and run `./sofatap`. Depending on your file manager, you can also double-click the executable and choose **Run**.
4. On Wayland, click **允许控制桌面** and approve the desktop's native permission prompt. If you decline, the receiver cannot control the desktop; the same button lets you try again.
5. Connect the iPhone and computer to the same trusted home network. Choose the reachable address in Sofatap's window, then scan its QR code in the iPhone app.

The status must read **桌面已就绪** before mouse or keyboard input is available. A successful network connection alone does not grant desktop control. Never share the QR code or screenshots containing it.

Close the window or click **退出接收器** to stop receiving control. Closing a Wayland permission session also ends its input access. Sofatap does not install a background service, modify firewall rules, add startup items or require root access. If your distribution's firewall blocks the connection, allow TCP 53319 only on your trusted home network through the distribution's normal firewall settings.

## Desktop support and dependencies

Python 3.10 or newer, PyGObject and GTK 3 are required. Use a distribution supported by the bundled .NET 10 runtime, such as Ubuntu 24.04 or 26.04. Minimal installations may also need their [normal .NET native prerequisites](https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu-install); the runtime does not bundle glibc or OpenSSL. These packages target glibc Linux, not Alpine/musl.

- **X11:** a logged-in X11 session with the XTEST extension and `libX11` / `libXtst` / `libxdo3`. UTF-8 text uses libxdo and temporary, per-action Unicode key mappings; the clipboard is not read or overwritten. Input uses that session's standard X11 authorization. Do not run the receiver with `sudo`, disable X11 access control with `xhost +`, or expose the X server to the network.
- **Wayland:** a desktop portal implementing [`org.freedesktop.portal.RemoteDesktop`](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html) (version 1 or newer) and its pointer/keyboard notification methods, together with the matching portal backend for your desktop. Both keyboard and pointer access must be granted. Portal support varies by desktop and version. Unsupported desktops show an unavailable status and receive no injected input. A running XWayland server by itself does not provide full Wayland desktop support.

For Ubuntu/Debian, the typical packages are:

```sh
sudo apt install python3 python3-gi gir1.2-gtk-3.0 libx11-6 libxtst6 libxdo3
```

PyGObject also provides the Gio/GLib bindings used to communicate with the native portal. A normal GNOME or KDE Wayland installation also provides `xdg-desktop-portal` and its matching GNOME/KDE backend. Install or repair them using your desktop's own package documentation; do not install an unrelated backend merely to suppress an unavailable status. Sofatap never launches an installer automatically.

Sofatap sends Wayland text as XKB keysyms. Unicode support depends on the compositor and destination application; verify your text in the target application. Both Linux backends accept at most 2,048 Unicode characters per text action (after normalizing CRLF); split longer text before sending. X11 may reject a shorter selection before typing if its distinct characters exceed the available temporary key slots, or its estimated input time exceeds the action budget. A slow portal may report partial input: check the computer before resending, because retrying can duplicate text. The receiver never requests clipboard or screen-capture access and does not persist a portal restore token.

Dictation and third-party iPhone keyboards work through Sofatap's text field: finish composing, review the text, then send it to the computer's focused application. This Linux implementation still needs physical iPhone acceptance testing; automated protocol checks and virtual desktop tests do not prove microphone, voice keyboard or real-device behavior.

Development version 0.5.0 can report focused editable fields through an optional AT-SPI helper. On Debian/Ubuntu it uses `gir1.2-atspi-2.0` and a working accessibility bus (normally `at-spi2-core`), with apps that expose accessible text state. This is separate from Wayland input permission. No accessibility settings are changed automatically. Unsupported applications/sessions retain manual keyboard input, and startup waits for a focus event. Only a field classification is sent to the phone, never its contents; see [focus detection](../../docs/TEXT-FOCUS.md).

## Optional applications-menu entry

The package includes a `sofatap.desktop` template and `sofatap.png`. The template expects `sofatap` to be on the desktop session's `PATH`. To register it just for your account, keep the extracted folder in a permanent location, then run from that folder:

```sh
mkdir -p ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/1024x1024/apps
ln -s "$(pwd)/sofatap" ~/.local/bin/sofatap
cp sofatap.desktop ~/.local/share/applications/sofatap.desktop
cp sofatap.png ~/.local/share/icons/hicolor/1024x1024/apps/sofatap.png
```

Ensure `~/.local/bin` is in your desktop session's `PATH` (a logout/login may be needed). The link command deliberately refuses to replace an existing command. Removing those three installed files removes the menu entry; the application itself remains in the extracted folder. This does not create a startup item.

## Build from source

From the repository root with the .NET 10 SDK installed:

```sh
bash scripts/build-linux.sh x64
# Or: bash scripts/build-linux.sh arm64
```

The resulting `artifacts/SofaTap-Linux-<architecture>.tar.gz` contains the native Python/GTK frontend, a self-contained Linux backend, the Linux input worker, licenses and a build manifest with source revision and SHA-256 hashes. The architecture can be cross-built on macOS; that is not evidence the package ran on Linux.

For development, you can launch the native frontend against a locally published backend:

```sh
python3 desktop/linux/sofatap.py --backend /absolute/path/to/SofaTap
```

`--dry-run` is an explicit preview mode. It preserves native pairing and connectivity but sends no desktop input and makes no permission request. Normal launches enable the platform's input backend only when desktop access is available.

## Lifecycle and checks

Pairing snapshots arrive as JSON lines over the owned child's private pipe. PNG bytes remain in memory; pairing URIs are never retained by the frontend, shown as text or copied to disk. Backend diagnostics are drained without being copied into the interface or logs.

The frontend rejects unknown platforms, unknown input states, mismatched real/dry-run modes, malformed snapshots and oversized frames. A broken state pipe, or twelve seconds without a valid snapshot, clears the QR and stops the owned child. Commands have bounded nonblocking writes. Graceful shutdown has eight seconds in total, then only the owned child is terminated (two seconds) or killed (two seconds) if necessary. If shutdown still fails, the native window keeps Quit available for a retry.

Run `python3 desktop/linux/check_protocol.py` for portable frontend protocol and process-lifecycle checks. These checks start no GTK window, generate no real mouse/keyboard events and require no paired phone. Actual rendering, supported desktop sessions and physical input have separate acceptance requirements.

On Linux, `SOFATAP_TEST_BACKEND=/absolute/path/to/SofaTap /usr/bin/python3 desktop/linux/check_gtk_integration.py` starts its own authenticated Xvfb server and temporary receiver profiles. It checks native GTK QR rendering, dry-run and X11 readiness, the Quit and window-close paths, owned worker cleanup and listener shutdown. It requires `xvfb` and `xauth` in addition to the runtime dependencies, never uses the current display and sends no mouse or keyboard events.
