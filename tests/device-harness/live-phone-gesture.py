#!/usr/bin/env python3
"""One explicitly authorized real-iPhone gesture into a dedicated Windows test window.

This is intentionally separate from phone-gestures.py's recording-only harness.
It neither starts a service nor creates a WDA session. A fresh, private READY
receipt supplied by the test coordinator is required for every gesture. It is
an attestation of the coordinator's actual checks, not a substitute for them.
No credentials, pairing files, Mac input or Windows input APIs are accessed.
"""

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import types

APP = "com.chekusu.sofatap"
GESTURES = ("doubletap", "hold-drag", "twofinger-scroll")
MAX_PROOF_AGE = 180
DEFAULT_STATE = Path.home() / ".local/share/iphone-use-dedicated"
DEFAULT_PLUGIN = Path.home() / ".codex/plugins/cache/iphone-use-local/iphone-use/0.3.9"


class GuardError(Exception):
    pass


def private_json(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077 or info.st_size > 256_000):
            raise GuardError("private_file_required")
        value = json.load(stream)
    if not isinstance(value, dict):
        raise GuardError("object_required")
    return value


def positive_int(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def proof_guard(proof, gesture, computer, now=None):
    if not isinstance(computer, str) or not computer.strip() or len(computer) > 255 or any(ord(c) < 32 for c in computer):
        raise GuardError("expected_computer_required")
    if (proof.get("schema") != "sofatap.live-gesture-ready.v1"
            or proof.get("state") != "READY" or proof.get("gesture") != gesture
            or proof.get("userAuthorized") is not True
            or not re.fullmatch(r"[a-zA-Z0-9-]{8,80}", str(proof.get("proofId", "")))):
        raise GuardError("authorized_ready_proof_required")
    try:
        observed = dt.datetime.fromisoformat(proof["observedAt"].replace("Z", "+00:00"))
        if observed.tzinfo is None:
            raise ValueError()
        age = ((now or dt.datetime.now(dt.timezone.utc)) - observed).total_seconds()
    except (KeyError, TypeError, ValueError):
        raise GuardError("proof_timestamp_invalid")
    if not 0 <= age <= MAX_PROOF_AGE:
        raise GuardError("proof_stale")
    target = proof.get("target", {})
    if (target.get("computer") != computer
            or target.get("kind") != "sofatap-acceptance-form"
            or target.get("nonSensitive") is not True
            or target.get("normalIntegrity") is not True
            or target.get("unlocked") is not True
            or not positive_int(target.get("sessionId"))
            or not positive_int(target.get("pid"))
            or target.get("foregroundPid") != target["pid"]
            or target.get("receiverSessionId") != target["sessionId"]):
        raise GuardError("dedicated_foreground_windows_target_required")
    isolation = proof.get("isolation", {})
    if (isolation.get("provider") != "Yomado"
            or isolation.get("rdpInVirtualDisplay") is not True
            or isolation.get("virtualDisplayNonPrimary") is not True
            or isolation.get("physicalTopologyUnchanged") is not True
            or isolation.get("directPhoneToWindowsOnly") is not True):
        raise GuardError("virtual_display_isolation_required")
    return proof


def finite_coordinates(values):
    return all(not isinstance(v, bool) and isinstance(v, (int, float))
               and math.isfinite(v) for v in values)


def gesture_payload(gesture, start, end=None, hold_ms=400, finger_gap=36):
    if gesture not in GESTURES:
        raise GuardError("unsupported_gesture")
    if (not finite_coordinates([*start, *(end or []), finger_gap])
            or len(start) != 2 or (end is not None and len(end) != 2)
            or not 300 <= hold_ms <= 2000 or not 10 <= finger_gap <= 100):
        raise GuardError("invalid_gesture_parameters")
    if gesture != "doubletap" and end is None:
        raise GuardError("end_required")
    starts, ends = [tuple(start)], [tuple(end or start)]
    if gesture == "doubletap":
        endpoint, payload = "/wda/doubleTap", dict(zip(("x", "y"), start))
    elif gesture == "hold-drag":
        endpoint = "/wda/dragfromtoforduration"
        payload = dict(zip(("fromX", "fromY", "toX", "toY"), [*start, *end]),
                       duration=hold_ms / 1000)
    else:
        half_gap = finger_gap / 2
        starts = [(start[0] - half_gap, start[1]), (start[0] + half_gap, start[1])]
        ends = [(end[0] - half_gap, end[1]), (end[0] + half_gap, end[1])]
        endpoint = "/actions"
        payload = {"actions": [{"type": "pointer", "id": f"finger-{index}",
            "parameters": {"pointerType": "touch"}, "actions": [
                {"type": "pointerMove", "duration": 0, "origin": "viewport", "x": a[0], "y": a[1]},
                {"type": "pointerDown", "button": 0},
                {"type": "pointerMove", "duration": 400, "origin": "viewport", "x": b[0], "y": b[1]},
                {"type": "pointerUp", "button": 0}
            ]} for index, (a, b) in enumerate(zip(starts, ends))]}
    return endpoint, payload, starts + ends


def inside(point, rect):
    x, y, w, h = rect
    return x < point[0] < x + w and y < point[1] < y + h


def intersects(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def rect(node):
    value = node.get("rect", {})
    return [value[key] for key in ("x", "y", "width", "height")]


def phone_guard(nodes, viewport, region, points, computer):
    """Use freshly read AX facts, including live pad bounds and overlay controls."""
    if len(region) != 4 or not finite_coordinates(region) or min(region[2:]) <= 0:
        raise GuardError("invalid_region")
    prohibited = {"XCUIElementTypeAlert", "XCUIElementTypeSheet", "XCUIElementTypeKeyboard",
                  "XCUIElementTypeSecureTextField", "XCUIElementTypeTextField", "XCUIElementTypeTextView"}
    if any(n.get("type") in prohibited for n in nodes):
        raise GuardError("obstructed_touchpad")
    statuses = [n for n in nodes if n.get("name") == "connectionStatus"]
    if len(statuses) != 1 or statuses[0].get("value") != computer:
        raise GuardError("expected_connected_computer_required")
    pads = [n for n in nodes if n.get("name") == "touchpad"]
    if len(pads) != 1 or pads[0].get("enabled") in (False, "false"):
        raise GuardError("active_touchpad_required")
    pad = rect(pads[0])
    # Header/footer buttons and rounded corners never belong to the test area.
    safe = [pad[0] + 32, pad[1] + 96, pad[2] - 64, pad[3] - 208]
    corners = [(region[0], region[1]), (region[0] + region[2], region[1] + region[3])]
    screen = [0, 0, viewport["width"], viewport["height"]]
    if min(safe[2:]) <= 0 or any(not inside(p, safe) or not inside(p, screen) for p in corners):
        raise GuardError("region_outside_current_safe_touchpad")
    if any(not inside(p, region) for p in points):
        raise GuardError("finger_outside_safe_region")
    for node in nodes:
        if node.get("type") == "XCUIElementTypeButton" and intersects(region, rect(node)):
            raise GuardError("region_overlaps_control")
    return {"viewport": viewport, "touchpad": pad, "safeTouchpad": safe, "region": region,
            "connectedComputer": computer, "modalFree": True}


def write_private(path, value, exclusive=False):
    flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | (os.O_EXCL if exclusive else os.O_TRUNC)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gesture", choices=GESTURES)
    parser.add_argument("--proof", type=Path, required=True)
    parser.add_argument("--computer", required=True, help="Exact authorized computer name shown in Sofatap connection status.")
    parser.add_argument("--region", type=float, nargs=4, required=True)
    parser.add_argument("--start", type=float, nargs=2, required=True)
    parser.add_argument("--end", type=float, nargs=2)
    parser.add_argument("--hold-ms", type=int, default=400)
    parser.add_argument("--finger-gap", type=float, default=36)
    parser.add_argument("--plugin-root", type=Path, default=DEFAULT_PLUGIN)
    parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE)
    args = parser.parse_args()
    runtime = None
    attempted = False
    receipt_path = None
    receipt = {"schema": "sofatap.live-gesture-result.v1", "gesture": args.gesture,
               "automaticRetryAllowed": False, "desktopOutcomeVerified": False}
    try:
        state = args.state_dir.expanduser().resolve(strict=True)
        if state != DEFAULT_STATE.resolve(strict=True):
            raise GuardError("dedicated_channel_required")
        info = state.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise GuardError("private_state_directory_required")
        config = private_json(state / "config.json")
        port = config.get("local_port")
        if not positive_int(port) or not 1024 <= port <= 65535:
            raise GuardError("configured_channel_required")
        url = f"http://127.0.0.1:{port}"
        cached = private_json(state / "session.json")
        if cached.get("url") != url or not re.fullmatch(r"[A-Za-z0-9-]{1,128}", str(cached.get("session_id", ""))):
            raise GuardError("existing_session_required")
        proof = proof_guard(private_json(args.proof), args.gesture, args.computer)
        endpoint, payload, points = gesture_payload(args.gesture, args.start, args.end, args.hold_ms, args.finger_gap)
        sys.path.insert(0, str(args.plugin_root.expanduser().resolve(strict=True) / "server"))
        from iphone_use import Runtime, SCHEMAS, VERSION, obj
        from wda_controller import fail
        if VERSION != "0.3.9":
            raise GuardError("runtime_version_requires_review")
        runtime = Runtime(str(state), url)
        ensure_existing = runtime.client.ensure_session

        def existing_session(timeout=None):
            if not runtime.client.session_id:
                fail("existing_session_required", "Use normal iPhone Use READY recovery separately.")
            return ensure_existing(timeout=timeout)

        runtime.client.ensure_session = existing_session

        def gesture(phone):
            nonlocal attempted, receipt_path
            if runtime.screen.paused():
                raise GuardError("preview_paused")
            if (runtime.client.request("GET", "/status").get("value") or {}).get("ready") is not True:
                raise GuardError("channel_not_ready")
            if runtime.client.request("GET", "/wda/locked").get("value") is not False:
                raise GuardError("phone_locked")
            if phone.active_app() != APP:
                raise GuardError("wrong_foreground_app")
            nodes, viewport = phone.tree()
            snapshot = phone_guard(nodes, viewport, args.region, points, args.computer)
            snapshot["observationId"] = phone.remember(nodes, viewport, APP)
            receipt.update(before=snapshot, endpoint=endpoint, payload=payload, proofId=proof["proofId"],
                           target=proof["target"], observedAt=dt.datetime.now(dt.timezone.utc).isoformat())
            # Recheck original attestation age immediately before the sole mutation.
            proof_guard(proof, args.gesture, args.computer)
            if runtime.screen.paused() or phone.active_app() != APP:
                raise GuardError("phone_context_changed")
            if runtime.client.request("GET", "/wda/locked").get("value") is not False:
                raise GuardError("phone_locked")
            receipts = state / "sofatap-live-gesture-receipts"
            if receipts.is_symlink():
                raise GuardError("invalid_receipt_directory")
            receipts.mkdir(mode=0o700, exist_ok=True)
            if receipts.stat().st_uid != os.getuid() or receipts.stat().st_mode & 0o077:
                raise GuardError("private_receipt_directory_required")
            receipt_path = receipts / (proof["proofId"] + ".json")
            # The initial durable receipt is a one-shot latch even on uncertain transport.
            try:
                write_private(receipt_path, {**receipt, "reserved": True}, exclusive=True)
            except FileExistsError:
                raise GuardError("proof_already_consumed")
            attempted = True
            phone.post(endpoint, payload)
            receipt.update(actionAccepted=True, mutationAttempted=True, uncertain=False,
                           nextStep="Read the dedicated Windows test window; WDA acceptance is not desktop verification.")
            # Deliberately no second gesture, recovery, retry or input on failure.
            return receipt

        SCHEMAS["sofatap_live_test_gesture"] = obj({})
        runtime.phone.sofatap_live_test_gesture = types.MethodType(gesture, runtime.phone)
        result = runtime.call("pua_sofatap_live_test_gesture", {})
        write_private(receipt_path, result)
        print(json.dumps({**result, "receiptPath": str(receipt_path)}, ensure_ascii=False))
        return 0
    except Exception as error:
        code = str(error) if isinstance(error, GuardError) else getattr(error, "code", "guard_or_runtime_failure")
        result = {**receipt, "error": code, "mutationAttempted": attempted,
                  "uncertain": attempted, "automaticRetryAllowed": False}
        if receipt_path is not None and code != "proof_already_consumed":
            try:
                write_private(receipt_path, result)
            except OSError:
                result["receiptWriteFailed"] = True
        print(json.dumps(result, ensure_ascii=False))
        return 1
    finally:
        if runtime is not None:
            try:
                runtime.close()
            except Exception:
                pass  # The action result was already reported; never replay it.


if __name__ == "__main__":
    raise SystemExit(main())
