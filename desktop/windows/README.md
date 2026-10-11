# Windows native receiver window

`SofaTap.exe` is a native WinForms application. It starts the bundled `SofaTapHost.exe --native-ui` with redirected pipes and no console window. The QR code is a native bitmap inside the window; no browser or WebView is involved. Closing the window or clicking Quit requests graceful backend shutdown and waits before closing.

The frontend retains only the currently needed QR images in memory. It does not write pairing snapshots or URIs to files, logs or the clipboard. Backend stderr is drained privately rather than shown verbatim.

The pipe reader bounds frames while reading, including output that never sends a newline. Malformed state or an unexpectedly closed state pipe clears the QR and requests shutdown of the owned backend. The five-second graceful-shutdown deadline includes waiting for the command writer and sending Quit. On expiry the window stops only its own process tree, then waits at most two more seconds. A shutdown error keeps the window open for a retry.

Build the complete self-contained Windows x64 folder and ZIP from the repository root with `bash scripts/build-windows.sh`. Both executables and every additional file in the archive belong together. The default executable needs no separately installed .NET runtime. The build can cross-compile on macOS using the .NET 10 SDK; an actual Windows desktop is still required for native-window and input acceptance.

For developer transport checks, launch `SofaTap.exe --dry-run`; the native window labels input as disabled. The normal executable starts with input enabled when the Windows desktop is available. Portable parser and child-process checks can run with `dotnet run --project desktop/windows/tests/ProtocolChecks.csproj`; they do not substitute for real WinForms rendering tests.
