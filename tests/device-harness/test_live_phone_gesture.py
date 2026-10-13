"""Offline guards only: importing this suite never opens a phone connection."""
import datetime as dt
import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location("live_gesture", Path(__file__).with_name("live-phone-gesture.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

NOW = dt.datetime(2026, 10, 13, 6, 0, tzinfo=dt.timezone.utc)


def proof():
    return {"schema": "sofatap.live-gesture-ready.v1", "proofId": "offline-test-proof",
            "state": "READY", "observedAt": NOW.isoformat(), "gesture": "doubletap", "userAuthorized": True,
            "target": {"computer": "TEST-WINDOWS-PC", "kind": "sofatap-acceptance-form", "pid": 400,
                       "foregroundPid": 400, "sessionId": 2, "receiverSessionId": 2,
                       "nonSensitive": True, "normalIntegrity": True, "unlocked": True},
            "isolation": {"provider": "Yomado", "rdpInVirtualDisplay": True, "virtualDisplayNonPrimary": True,
                          "physicalTopologyUnchanged": True, "directPhoneToWindowsOnly": True}}


def node(name, kind, bounds, **extra):
    return {"name": name, "type": "XCUIElementType" + kind,
            "rect": dict(zip(("x", "y", "width", "height"), bounds)), **extra}


def nodes():
    return [node("touchpad", "Other", [20, 180, 400, 600]),
            node("connectionStatus", "Button", [40, 200, 52, 52], value="TEST-WINDOWS-PC"),
            node("dictationButton", "Button", [188, 696, 64, 64])]


class LiveGuardTests(unittest.TestCase):
    def test_accepts_fresh_dedicated_target(self):
        self.assertIs(mod.proof_guard(proof(), "doubletap", "TEST-WINDOWS-PC", NOW)["userAuthorized"], True)

    def test_expected_computer_must_match_proof_and_fresh_phone(self):
        expected = "LIVING-ROOM-TEST"
        p = proof()
        p["target"]["computer"] = expected
        mod.proof_guard(p, "doubletap", expected, NOW)
        n = nodes()
        n[1]["value"] = expected
        mod.phone_guard(n, {"width": 440, "height": 956},
                        [100, 350, 200, 200], [(200, 400)], expected)
        with self.assertRaises(mod.GuardError):
            mod.proof_guard(p, "doubletap", "DIFFERENT-TARGET", NOW)
        with self.assertRaises(mod.GuardError):
            mod.phone_guard(n, {"width": 440, "height": 956},
                            [100, 350, 200, 200], [(200, 400)], "DIFFERENT-TARGET")
        for invalid in ("", "   ", "TARGET\nOTHER"):
            with self.assertRaises(mod.GuardError):
                mod.proof_guard(p, "doubletap", invalid, NOW)

    def test_rejects_stale_future_wrong_gesture(self):
        for age in (-1, 181):
            value = proof()
            value["observedAt"] = (NOW - dt.timedelta(seconds=age)).isoformat()
            with self.assertRaises(mod.GuardError):
                mod.proof_guard(value, "doubletap", "TEST-WINDOWS-PC", NOW)
        with self.assertRaises(mod.GuardError):
            mod.proof_guard(proof(), "hold-drag", "TEST-WINDOWS-PC", NOW)

    def test_rejects_unverified_target_isolation_and_consent(self):
        cases = [("target", "computer", "OTHER"), ("target", "foregroundPid", 999),
                 ("target", "receiverSessionId", 4), ("target", "nonSensitive", False),
                 ("target", "normalIntegrity", False), ("target", "unlocked", False),
                 ("isolation", "rdpInVirtualDisplay", False), ("isolation", "directPhoneToWindowsOnly", False),
                 ("isolation", "virtualDisplayNonPrimary", False)]
        for section, field, value in cases:
            with self.subTest(section=section, field=field):
                p = proof()
                p[section][field] = value
                with self.assertRaises(mod.GuardError):
                    mod.proof_guard(p, "doubletap", "TEST-WINDOWS-PC", NOW)
        p = proof()
        p["userAuthorized"] = False
        with self.assertRaises(mod.GuardError):
            mod.proof_guard(p, "doubletap", "TEST-WINDOWS-PC", NOW)

    def test_safe_center_and_exclusion_of_buttons(self):
        v = {"width": 440, "height": 956}
        mod.phone_guard(nodes(), v, [100, 350, 200, 200], [(200, 400)], "TEST-WINDOWS-PC")
        for region in ([50, 200, 250, 300], [100, 550, 200, 200]):
            with self.assertRaises(mod.GuardError):
                mod.phone_guard(nodes(), v, region, [(200, 400)], "TEST-WINDOWS-PC")
        n = nodes() + [node("overlay", "Button", [180, 380, 40, 40])]
        with self.assertRaises(mod.GuardError):
            mod.phone_guard(n, v, [100, 350, 200, 200], [(200, 400)], "TEST-WINDOWS-PC")

    def test_refuses_modal_keyboard_and_wrong_receiver(self):
        v = {"width": 440, "height": 956}
        for kind in ("Alert", "Sheet", "Keyboard", "SecureTextField", "TextField", "TextView"):
            with self.subTest(kind=kind), self.assertRaises(mod.GuardError):
                mod.phone_guard(nodes() + [node("overlay", kind, [0, 0, 440, 956])],
                                v, [100, 350, 200, 200], [(200, 400)], "TEST-WINDOWS-PC")
        n = nodes()
        n[1]["value"] = "已配对 · 未连接"
        with self.assertRaises(mod.GuardError):
            mod.phone_guard(n, v, [100, 350, 200, 200], [(200, 400)], "TEST-WINDOWS-PC")

    def test_two_fingers_must_both_fit(self):
        _, payload, points = mod.gesture_payload("twofinger-scroll", [110, 400], [110, 500], finger_gap=36)
        self.assertEqual(len(payload["actions"]), 2)
        with self.assertRaises(mod.GuardError):
            mod.phone_guard(nodes(), {"width": 440, "height": 956}, [100, 350, 200, 200], points, "TEST-WINDOWS-PC")

    def test_hold_delay_is_not_drag_duration(self):
        endpoint, payload, _ = mod.gesture_payload("hold-drag", [200, 400], [200, 500], hold_ms=400)
        self.assertEqual(endpoint, "/wda/dragfromtoforduration")
        self.assertEqual(payload["duration"], .4)
        with self.assertRaises(mod.GuardError):
            mod.gesture_payload("hold-drag", [200, 400], [200, 500], hold_ms=100)

    def test_exclusive_receipt_prevents_second_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "proof.json"
            mod.write_private(path, {"reserved": True}, exclusive=True)
            with self.assertRaises(FileExistsError):
                mod.write_private(path, {"reserved": False}, exclusive=True)
            self.assertEqual(mod.private_json(path), {"reserved": True})

    def test_nan_and_infinite_coordinates_rejected(self):
        for value in (float("nan"), float("inf")):
            with self.assertRaises(mod.GuardError):
                mod.gesture_payload("doubletap", [value, 400])


if __name__ == "__main__":
    unittest.main()
