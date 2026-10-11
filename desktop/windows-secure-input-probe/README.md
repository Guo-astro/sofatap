# Sofatap secure-desktop pointer diagnostic

This is an optional development diagnostic, not a remote-control receiver or a PIN feature. It has no network listener, clicks, keyboard events, credential submission, clipboard, screen capture, hooks, or account/provider/policy configuration. Building it and passing the tests do not prove locked-console control or Windows Hello PIN acceptance.

The first experiment is intentionally limited to **an existing physical-console session after a normal human sign-in and Win+L**. The console must be `WTSActive`, locked, and use the `Winlogon` input desktop. A pre-first-login `Connected` session, a disconnected RDP session, an unlocked desktop, or unknown state is rejected. Do not reconnect sessions or weaken security settings to make a failed check pass.

## Build and no-input checks

Use 64-bit MSVC (VS 2019/v142 or newer), Windows 10 SDK 19041 or newer, and CMake 3.20 or newer:

```powershell
cmake -S desktop/windows-secure-input-probe -B build/windows-secure-input-probe -A x64
cmake --build build/windows-secure-input-probe --config Release
ctest --test-dir build/windows-secure-input-probe -C Release --output-on-failure
Get-FileHash build/windows-secure-input-probe/Release/Sofatap.SecureInputProbe.exe -Algorithm SHA256
```

The executable uses a static CRT and Windows system DLLs only. `ProbeChecks.cpp` has 51 checks covering denied/unknown context, argument rejection, each mandatory gate, cursor-interference restoration, and bounded coordinate mapping. This fixture does not link or invoke Windows input APIs and also builds on macOS/Linux. Native Windows compilation and operator acceptance are separate gates.

## Explicit local operator sequence

Keep a working physical keyboard/mouse available. Close Windows On-Screen Keyboard and all third-party hover/dwell input tools. The probe also refuses to move while `osk.exe` exists in the console session or a mouse button is held. No automatic lock, elevation, wake, RDP reconnection, or alternate remote administration channel is provided.

1. Normally sign in at the physical television/monitor. Open a **64-bit elevated Windows PowerShell** window and complete the normal UAC prompt yourself. Obtain the executable's expected SHA-256 from the independently reviewed build artifact. Do not substitute a hash supplied by an untrusted source alongside an untrusted executable.
2. Install only. Substitute the actual artifact hash:

   ```powershell
   .\desktop\windows-secure-input-probe\Probe.ps1 -Action Install `
     -SourceExe .\build\windows-secure-input-probe\Release\Sofatap.SecureInputProbe.exe `
     -ExpectedSha256 <REVIEWED_SHA256> -AllowUnsignedDiagnostic
   ```

3. From that same already approved elevated window, start this short delay, then **press Win+L yourself** and watch the physical display without touching the mouse. The delay is not consent and does not lock the computer. `Run` still checks that it is already locked when the delay ends:

   ```powershell
   Start-Sleep -Seconds 15
   .\desktop\windows-secure-input-probe\Probe.ps1 -Action Run
   ```

   Paste both lines together (or put them on one line separated by a semicolon) before pressing Win+L. The probe requests one eight-pixel horizontal move, waits approximately 650 ms, and attempts a restore only when the exact observed target position and all context gates still match. It does not retry. A six-second worker deadline and twelve-second service deadline terminate the experiment even on failure. No PIN or other credential should be typed during the probe.

4. Unlock normally using the physical keyboard. Read the protected report, then remove the diagnostic:

   ```powershell
   .\desktop\windows-secure-input-probe\Probe.ps1 -Action Status
   .\desktop\windows-secure-input-probe\Probe.ps1 -Action Remove
   ```

Installation adds only a manual `SofatapSecureInputProbe` service and its private directory under `%ProgramFiles%\Chekusu\SofatapSecureInputProbe`. It does not start the service. One installation permits one run: `CREATE_NEW` reports prevent retrying even after an incomplete run. Preserve the sanitized report separately before `Remove` if needed; removal deletes it. Removal verifies the service identity, stops it, confirms deletion, and deletes only the fixed file allowlist. The shared `Chekusu` parent remains.

An installation failure before service registration attempts rollback only of the new private directory created by that invocation. A registered manual service or uncertain rollback is retained with an explicit diagnostic; normal `Remove` works when its manifest is intact. Do not recursively delete an unexpected directory or reuse a partially installed service. Inspect it first. No existing service or directory is overwritten.

## What the evidence means

Results contain only fixed booleans, Win32 errors, stage numbers and cursor deltas. They contain no usernames, account IDs, process lists, absolute pointer coordinates, screen contents or credentials.

| Observation | What it establishes |
| --- | --- |
| `workerLaunched` | The worker process was created, not that input worked. |
| `systemToken`, `physicalConsole`, `active`, `locked`, `winsta0`, `threadWinlogon`, `inputWinlogon` | The corresponding context checks passed at their last observation. |
| `sendInputAccepted` | `SendInput` accepted one mouse event; this alone is not target UI success. |
| `movementObserved` and delta of `8` or `-8`, `0` | A subsequent `GetCursorPos` exactly matched the requested tiny move. |
| `pointerRestored` and `contextUnchanged` | The original cursor position was subsequently observed while the guarded context still matched. |
| Human sees that move on the physical TV | The movement was visible on the intended output; API coordinates cannot prove that a TV has signal. |

Service success alone is insufficient. A nonzero worker error propagates to the service; a successful process exit still does not prove physical visibility. Inspect the worker fields and separately record the human observation. An absent/empty/truncated report is incomplete evidence. `stage` 2/8/10/14 indicates a rejected or changed context; 9/15 is a rejected injection; 12 means the expected coordinate was not observed; 16 means restoration was not confirmed. Other stages are setup/query failures, and 99 is an internal exception.

Restore is best effort. Context/cursor checks and `SendInput` are not atomic Windows operations. A human input or desktop/topology change can still race the final check; the diagnostic refuses restoration when interference is observed. It never blocks human input. Mouse hover tools can act without clicks, which is why closing them is a required operator precondition and `osk.exe` is explicitly checked before both events.

## Narrow architecture

The service duplicates **its own LocalSystem token**, changes only that new token's session to the active physical console, and launches the same fixed protected executable with `lpDesktop = WinSta0\\Winlogon`. It never opens a Winlogon process token or changes window-station/desktop ACLs. The child is atomically assigned to a kill-on-close job at creation. A service stop or session-change notification cancels the worker.

The no-window/no-hook worker revalidates LocalSystem, its SCM service parent, its fixed executable path, protected owner/DACL/reparse-free ancestors, physical-console session, `WTSActive` + locked, the thread and input desktop names, no OSK, no held mouse buttons and a monotonic deadline. Before each single mouse event it also checks cursor position and the original monitor/virtual-screen geometry. It never calls `SwitchDesktop`, `LockWorkStation`, `SetCursorPos`, `SendSAS`, or any keyboard injection API.

This is a hash-bound unsigned diagnostic only. A shipping input service would require its own authenticated protocol, enrollment/revocation, signed installation and updates, security review and separate real-device acceptance. It must not reinterpret the retired password credential-provider protocol as a PIN protocol.

## Primary references and remaining PIN question

- Microsoft [PowerToys Mouse Without Borders](https://learn.microsoft.com/en-us/windows/powertoys/mouse-without-borders) documents an optional System service for lock-screen/elevated-app control. This demonstrates a supported product pattern, not successful Sofatap execution on a particular Windows build.
- [Interactive services](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services), [desktops](https://learn.microsoft.com/en-us/windows/win32/winstation/desktops), and [CreateProcessAsUserW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw) explain Session 0, desktop isolation and token/session process creation. Merely pairing or elevating the ordinary receiver does not put it in the console's secure desktop.
- [OpenInputDesktop](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openinputdesktop) can describe a would-be active desktop for a disconnected session, hence the independent console/WTS gates. [SetThreadDesktop](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setthreaddesktop) has thread/window/hook restrictions; this worker starts directly on the fixed desktop instead.
- [SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput) is constrained by input trust/UIPI, and its return count is not authentication success. Microsoft's [January 2026 credential-input hardening](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/01/new-behavior-restricting-certain-applications-to-autofill-credentials-introduced-by-the-windows-janu) means elevated remote input cannot be assumed to work in every credential surface.
- Windows [On-Screen Keyboard](https://support.microsoft.com/en-au/accessibility/windows/use-the-on-screen-keyboard-osk-to-type) has a hover-to-type mode. This probe excludes it; it does not validate a later user-controlled OSK fallback.

Neither automated native Hello PIN entry nor a phone-controlled manual PIN/OSK path has been tested by this diagnostic. Manual phone typing can share the same injection restrictions as automatic typing; it is not an established fallback until verified separately. No authentication success claim follows from this pointer-only experiment.
