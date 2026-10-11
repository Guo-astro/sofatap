# Linux native pairing preview

This GTK 3 frontend uses native Linux widgets and an in-memory PNG image. It opens no browser, WebView or local pairing website. Linux mouse/keyboard injection is **not implemented**: this frontend always launches the backend with `--native-ui --dry-run` and rejects non-dry-run state. It is a development preview, not a consumer-ready Linux receiver.

The preview requires a logged-in graphical Linux session, Python 3.10 or newer, PyGObject, GTK 3 and a matching Sofa Tap backend. For Debian/Ubuntu, the GTK dependencies are provided by `python3-gi` and `gir1.2-gtk-3.0`; install them through your normal package manager. A headless server has no visible pairing window. GTK/PyGObject are system dependencies and are not bundled in this source tree.

From the repository root, developers with the .NET 10 SDK can build a self-contained backend for their machine:

```sh
dotnet publish host/SofaTap.Host.csproj -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/linux-preview
python3 desktop/linux/sofatap.py --backend artifacts/linux-preview/SofaTap --dry-run
```

Use `linux-arm64` on an ARM64 machine. The backend does not require an externally installed .NET runtime after self-contained publication. The Python/GTK frontend still requires the system packages listed above.

Choose the computer's reachable home-network address in the window, then scan the native QR code from the iPhone app. The status always identifies this as a preview with input disabled. Clicking Refresh asks the same backend for a fresh snapshot. Closing the window or clicking Quit sends `{"type":"quit"}` and waits for the owned child process to stop; only that child is terminated if graceful shutdown times out.

Pairing snapshots arrive as JSON lines on a private child-process pipe. PNG bytes remain in memory. The URI is not copied to the clipboard or displayed as text, and snapshots are never written to logs or temporary files. Do not publish QR screenshots. Backend diagnostics are drained without being copied to the interface or logs.

A malformed snapshot, oversized frame without a newline, or closed state pipe clears the QR and requests backend shutdown. Commands use nonblocking pipe writes with a deadline. Graceful shutdown has five seconds in total, including waiting for the command writer and sending Quit; the owned child then gets up to two seconds after termination and two after a forced kill. The window stays open with a generic error. If a requested shutdown fails, the window keeps its Quit button available for a retry.

Run the portable protocol/lifecycle checks with `python3 desktop/linux/check_protocol.py`. A successful check is not evidence of GTK rendering or real Linux input; the latter remains unsupported.
