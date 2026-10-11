# Mint Calm offline WinForms fixtures

Run on a Windows CI runner with the .NET 10 SDK:

```powershell
dotnet run --project desktop/windows/preview/MintCalmPreview.csproj -c Release -- artifacts/mint-calm
```

This standalone harness links the real `PairingWindow` and controls. Its explicit fixture constructor does not attach the backend-start event. It creates native handles off-screen without activation, then uses `DrawToBitmap` for `windows-ready.png`, `windows-failure.png`, `windows-permission.png`, `windows-narrow.png` and `windows-narrow-scrolled.png`. The main application excludes this directory from compilation, so the harness is not a second production entry point.

The QR encodes **SOFATAP UI PREVIEW - DEMO ONLY - NOT A PAIRING CODE**, padded to approximate a real code's density. The machine identity and matching link are synthetic, using the reserved documentation address `192.0.2.17`. No real credential is read, generated or exported. Copy is visually enabled in ready fixtures, but its fixture-mode handler cannot write to the clipboard. No backend process, network listener or input event is created.

Assertions cover stale QR/Copy clearing on failure, QR-only compatibility and scroll access at a short/narrow size. The images establish native fixture rendering only; they do not prove signed installation, live QR pairing, input injection, interactive keyboard navigation or multi-monitor DPI behavior. Production uses PerMonitorV2; the rendering harness uses a fixed 96-DPI coordinate space for stable CI images.
