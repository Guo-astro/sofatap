# Mint Calm offline WinForms fixtures

Run on Windows with the .NET 10 SDK. The default uses production's `PerMonitorV2` mode and the current display DPI:

```powershell
dotnet run --project desktop/windows/preview/MintCalmPreview.csproj -c Release -- artifacts/mint-calm
```

This standalone harness links the real `PairingWindow` and controls. Its explicit fixture constructor does not attach the backend-start event. It creates native handles off-screen without activation, then uses `DrawToBitmap` for `windows-ready.png`, `windows-failure.png`, `windows-permission.png`, `windows-narrow.png` and `windows-narrow-scrolled.png`. The main application excludes this directory from compilation, so the harness is not a second production entry point.

The QR encodes **SOFATAP UI PREVIEW - DEMO ONLY - NOT A PAIRING CODE**, padded to approximate a real code's density. The machine identity and matching link are synthetic, using the reserved documentation address `192.0.2.17`. No real credential is read, generated or exported. Copy is visually enabled in ready fixtures, but its fixture-mode handler cannot write to the clipboard. No backend process, network listener or input event is created.

Assertions cover the constructor's default window size, the pending-to-ready startup transition, the complete QR being visible without horizontal scrolling, stale QR/Copy clearing on failure, QR-only compatibility, short/narrow layouts, and repeated resizing after scrolling. The harness does not override the startup size; doing so would hide a missing DPI baseline in the production constructor. `windows-layout.json` records the actual DPI, viewport and QR bounds, scroll position and scrollbar visibility for each checked state.

Run it on a machine already configured to the display scaling being checked (for example 125%, 150%, 200% or 300%). The harness does not change display settings or send synthetic `WM_DPICHANGED` messages: those messages alone do not reproduce the operating system's per-monitor child notifications and native font metrics. A run at 96 DPI establishes only the 100% result; it is not evidence for higher scaling settings.

For optional comparison with earlier fixed-96-DPI images:

```powershell
dotnet run --project desktop/windows/preview/MintCalmPreview.csproj -c Release -- artifacts/mint-calm-96 --stable-96
```

The images establish native fixture rendering only; they do not prove signed installation, live QR pairing, input injection, interactive keyboard navigation, foreground startup focus or multi-monitor DPI behavior. The windows stay off-screen without activation. Physical high-DPI acceptance remains separate from these offline fixtures.
