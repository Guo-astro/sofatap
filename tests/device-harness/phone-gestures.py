#!/usr/bin/env python3
"""One guarded iPhone gesture against the recording-only Sofatap test harness.

Requires an already READY iPhone Use 0.3.9 channel. This helper does not start,
recover, create or delete a WDA session. It adds one process-local Runtime
operation, retaining Runtime's shared operation.lock and session adoption.
The caller must first verify that the phone is paired to this recording harness;
state.json alone cannot prove the phone's selected receiver. Never use this
helper while paired to an OS-injecting receiver. No pairing file is read.
"""

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import stat
import sys
import types


class GuardError(Exception):
    pass


def private_json(path, limit=256_000):
    """Read one owned regular private file without following a final symlink."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                or metadata.st_mode & 0o077 or metadata.st_size > limit):
            raise GuardError("private_file_required")
        value = json.load(stream)
    if not isinstance(value, dict):
        raise GuardError("invalid_private_state")
    return value


def recording_guard(path):
    if path.name != "state.json":
        raise GuardError("harness_state_required")
    state = private_json(path)
    if (state.get("schemaVersion") != 1
            or state.get("mode") != "isolated-recording-only"
            or state.get("osInjection") is not False):
        raise GuardError("recording_only_required")
    updated = dt.datetime.fromisoformat(state["updatedAt"].replace("Z", "+00:00"))
    age = (dt.datetime.now(dt.timezone.utc) - updated).total_seconds()
    if not 0 <= age <= 300:
        raise GuardError("harness_state_stale")


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gesture", choices=["doubletap", "hold-drag", "twofinger-scroll"])
    parser.add_argument("--plugin-root", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True,
                        help="The already configured channel's existing private directory.")
    parser.add_argument("--harness-state", type=Path, required=True)
    parser.add_argument("--region", type=float, nargs=4, required=True,
                        metavar=("X", "Y", "WIDTH", "HEIGHT"),
                        help="Freshly observed unobstructed touchpad bounds in iPhone points.")
    parser.add_argument("--start", type=float, nargs=2, required=True, metavar=("X", "Y"))
    parser.add_argument("--end", type=float, nargs=2, metavar=("X", "Y"))
    parser.add_argument("--hold-ms", type=int, default=400,
                        help="Stationary hold before hold-drag, 300..2000 ms.")
    parser.add_argument("--finger-gap", type=float, default=36,
                        help="Two-finger horizontal separation in iPhone points.")
    args = parser.parse_args()
    numbers = [*args.region, *args.start, *(args.end or []), args.finger_gap]
    if not all(math.isfinite(value) for value in numbers):
        parser.error("Coordinates must be finite.")
    if args.gesture != "doubletap" and args.end is None:
        parser.error("This gesture requires --end.")
    if not 300 <= args.hold_ms <= 2000 or not 10 <= args.finger_gap <= 100:
        parser.error("Hold or finger separation is outside the supported bounds.")
    return args


def main():
    args = arguments()
    runtime = None
    attempted = False
    try:
        root = args.plugin_root.expanduser().resolve(strict=True)
        state_dir = args.state_dir.expanduser().resolve(strict=True)
        harness_state = args.harness_state.expanduser().absolute()
        directory = state_dir.stat()
        if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.getuid() or directory.st_mode & 0o077:
            raise GuardError("private_state_directory_required")
        config = private_json(state_dir / "config.json")
        port = config.get("local_port")
        if isinstance(port, bool) or not isinstance(port, int) or not 1024 <= port <= 65535:
            raise GuardError("configured_channel_required")
        url = f"http://127.0.0.1:{port}"
        cached = private_json(state_dir / "session.json")
        if cached.get("url") != url or not isinstance(cached.get("session_id"), str) or not cached["session_id"]:
            raise GuardError("existing_session_required")
        recording_guard(harness_state)
        sys.path.insert(0, str(root / "server"))
        from iphone_use import Runtime, SCHEMAS, VERSION, obj
        from wda_controller import fail
        if VERSION != "0.3.9":
            raise GuardError("runtime_version_requires_review")
        runtime = Runtime(str(state_dir), url)

        # Runtime adopts the session while holding its own operation.lock. A
        # stale/missing session must fail, never enter ensure_session's creator.
        ensure_existing = runtime.client.ensure_session

        def existing_session(timeout=None):
            if not runtime.client.session_id:
                fail("existing_session_required", "Run normal iPhone Use READY recovery separately.")
            return ensure_existing(timeout=timeout)

        runtime.client.ensure_session = existing_session

        def gesture(phone):
            nonlocal attempted
            if runtime.screen.paused():
                fail("preview_paused", "User authentication or unlock is pending.")
            if runtime.client.request("GET", "/wda/locked").get("value") is not False:
                fail("phone_locked", "User unlock is required.")
            if phone.active_app() != "com.chekusu.sofatap":
                fail("wrong_foreground_app", "Sofatap must already be foreground.")
            nodes, viewport = phone.tree()
            if any(node.get("type") in ("XCUIElementTypeAlert", "XCUIElementTypeSheet",
                                         "XCUIElementTypeSecureTextField", "XCUIElementTypeKeyboard")
                   for node in nodes):
                fail("obstructed_touchpad", "Dismiss the visible overlay through normal phone tools first.")
            x, y, width, height = args.region
            if min(x, y) < 0 or min(width, height) <= 0 or x + width > viewport["width"] or y + height > viewport["height"]:
                fail("invalid_region", "The observed touchpad must fit the current viewport.")
            starts = [tuple(args.start)]
            ends = [tuple(args.end or args.start)]
            if args.gesture == "twofinger-scroll":
                offset = args.finger_gap / 2
                starts = [(args.start[0] - offset, args.start[1]), (args.start[0] + offset, args.start[1])]
                ends = [(args.end[0] - offset, args.end[1]), (args.end[0] + offset, args.end[1])]
            if any(not (x < px < x + width and y < py < y + height) for px, py in starts + ends):
                fail("invalid_coordinates", "All fingers must remain inside the observed touchpad.")
            # Recheck the safety gate immediately before the sole mutation.
            recording_guard(harness_state)
            if runtime.screen.paused() or phone.active_app() != "com.chekusu.sofatap":
                fail("context_changed", "Observe fresh phone state before continuing.")
            if runtime.client.request("GET", "/wda/locked").get("value") is not False:
                fail("phone_locked", "User unlock is required.")
            if args.gesture == "doubletap":
                endpoint, payload = "/wda/doubleTap", {"x": starts[0][0], "y": starts[0][1]}
            elif args.gesture == "hold-drag":
                # WDA's duration is the stationary press BEFORE the drag.
                endpoint = "/wda/dragfromtoforduration"
                payload = dict(zip(("fromX", "fromY", "toX", "toY"), [*starts[0], *ends[0]]), duration=args.hold_ms / 1000)
            else:
                endpoint = "/actions"
                payload = {"actions": [{"type": "pointer", "id": f"finger-{index}",
                    "parameters": {"pointerType": "touch"}, "actions": [
                        {"type": "pointerMove", "duration": 0, "origin": "viewport", "x": start[0], "y": start[1]},
                        {"type": "pointerDown", "button": 0},
                        {"type": "pointerMove", "duration": 400, "origin": "viewport", "x": end[0], "y": end[1]},
                        {"type": "pointerUp", "button": 0}
                    ]} for index, (start, end) in enumerate(zip(starts, ends))]}
            attempted = True
            phone.post(endpoint, payload)
            return {"gestureAccepted": True, "receiverVerified": False, "osInjection": False,
                    "nextStep": "Check recording harness events; do not infer desktop input acceptance."}

        # Process-local extension only; no plugin file or MCP schema is changed.
        SCHEMAS["sofatap_test_gesture"] = obj({})
        runtime.phone.sofatap_test_gesture = types.MethodType(gesture, runtime.phone)
        result = runtime.call("pua_sofatap_test_gesture", {})
        print(json.dumps(result))
        return 0
    except Exception as error:
        # Never print backend messages, app trees, file paths, identifiers or text.
        code = str(error) if isinstance(error, GuardError) else getattr(error, "code", "guard_or_runtime_failure")
        print(json.dumps({"error": code, "mutationAttempted": attempted,
                          "uncertain": attempted, "automaticRetryAllowed": False}))
        return 1
    finally:
        if runtime is not None:
            try:
                runtime.close()
            except Exception:
                # The gesture result has already been reported; never replay it.
                pass


if __name__ == "__main__":
    raise SystemExit(main())
