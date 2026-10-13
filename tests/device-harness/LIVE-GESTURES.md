# Dedicated Windows gesture acceptance

`live-phone-gesture.py` is an explicit live test adapter for the resident test
phone and the explicitly authorized Windows acceptance window. It is separate from
`phone-gestures.py`; the original recording-only guard must remain unchanged.
The adapter sends one phone gesture through the existing iPhone Use 0.3.9 Runtime
session and operation lock. It never creates/restarts a session, reads pairing
credentials, sends Mac input, or directly calls Windows input APIs.

Before each action, the coordinator must establish normal iPhone Use READY,
observe the current Sofatap touchpad, and obtain a fresh Windows-side report
that the dedicated non-sensitive acceptance form is foreground, unlocked, in the
receiver's session, and not elevated. The RDP viewer must already be in a
non-primary Yomado virtual display without physical display changes. The
coordinator must verify that actual input travels directly from phone to Windows;
moving a Mac window by itself does not prove input isolation.

Save a private mode-0600 JSON proof outside source control, populated from those
actual checks. The adapter accepts it for 180 seconds and consumes `proofId` once.
A timeout or uncertain result must be inspected, never automatically retried.
This receipt is a coordinator attestation, not a Windows monitoring service.
Do not copy this example as evidence without performing the checks:

```json
{
  "schema": "sofatap.live-gesture-ready.v1",
  "proofId": "unique-one-use-identifier",
  "state": "READY",
  "observedAt": "ACTUAL-UTC-TIMESTAMP",
  "gesture": "doubletap",
  "userAuthorized": true,
  "target": {
    "computer": "TEST-WINDOWS-PC",
    "kind": "sofatap-acceptance-form",
    "pid": 12345,
    "foregroundPid": 12345,
    "sessionId": 2,
    "receiverSessionId": 2,
    "nonSensitive": true,
    "normalIntegrity": true,
    "unlocked": true
  },
  "isolation": {
    "provider": "Yomado",
    "rdpInVirtualDisplay": true,
    "virtualDisplayNonPrimary": true,
    "physicalTopologyUnchanged": true,
    "directPhoneToWindowsOnly": true
  }
}
```

Use current iPhone point coordinates, never Mac display pixels. `--region` must
be a rectangle strictly inside the current touchpad's central safe region, away
from header/footer buttons. A fresh AX tree is checked inside the operation lock.
The proof target and fresh connection status must both exactly match the required
`--computer` argument; keyboard, text editor and modal
surfaces are rejected. All fingers, endpoints and paths must remain in the region.

```sh
python3 tests/device-harness/live-phone-gesture.py doubletap \
  --computer TEST-WINDOWS-PC --proof /private/path/current-proof.json \
  --region X Y WIDTH HEIGHT --start X Y

python3 tests/device-harness/live-phone-gesture.py hold-drag \
  --computer TEST-WINDOWS-PC --proof /private/path/new-proof.json \
  --region X Y WIDTH HEIGHT --start X Y --end X Y --hold-ms 400

python3 tests/device-harness/live-phone-gesture.py twofinger-scroll \
  --computer TEST-WINDOWS-PC --proof /private/path/another-proof.json \
  --region X Y WIDTH HEIGHT --start X Y --end X Y --finger-gap 36
```

Supported native routes are WDA `doubleTap`, WDA `dragfromtoforduration` (duration
means stationary hold before movement), and two simultaneous W3C touch pointer
actions. Endpoint acceptance does not prove Windows right-click/drag/scroll;
read the dedicated target's real event log and resulting state afterward. The
adapter writes an action receipt including the checked pre-action geometry in
`~/.local/share/iphone-use-dedicated/sofatap-live-gesture-receipts/` (private files).
The receipt deliberately has `desktopOutcomeVerified: false`.

Offline guard tests, without any phone connection:

```sh
python3 -m unittest discover -s tests/device-harness -p test_live_phone_gesture.py -v
```
