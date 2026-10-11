#!/usr/bin/env python3
"""Portable worker / input state tests. No graphical server or input events."""

import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
import uuid
from unittest.mock import patch

from input_common import InputError, MAXIMUM_LINE, parse_request, validate_action
from input_worker import UnavailableInput, choose_backend, handle_request
from x11_input import X11Input, normalize_text


def action(kind, **fields):
    return {"id": str(uuid.uuid4()), "type": kind, **fields}


class FakeNative:
    def __init__(self):
        self.events, self.busy, self.fail, self.closed = [], False, None, False

    def record(self, *event):
        self.events.append(event)
        if self.fail == len(self.events):
            raise InputError("input_partial")

    def move(self, x, y): self.record("move", x, y)
    def button(self, number, down): self.record("button", number, down)
    def key(self, code, down): self.record("key", code, down)
    def text(self, value): self.record("text", value)
    def keycode(self, key): return key
    def any_keys_down(self): return self.busy
    def button_down(self, _): return self.busy
    def close(self): self.closed = True


class ProtocolTests(unittest.TestCase):
    def test_all_supported_requests(self):
        for kind in ("status", "requestAccess", "releaseAll", "quit"):
            request = action(kind)
            self.assertEqual(parse_request(json.dumps(request)), request)

    def test_unicode_and_exact_limits(self):
        validate_action(action("text", text="中文 日本語 👋 café\r\n"))
        validate_action(action("text", text="👋" * 8000))
        with self.assertRaises(InputError): validate_action(action("text", text="👋" * 8001))

    def test_bad_unicode(self):
        for text in ("a\0b", "\ud800", "\udfff", 8):
            with self.assertRaises(InputError): validate_action(action("text", text=text))

    def test_control_text_is_rejected_before_injection(self):
        self.assertEqual(normalize_text("a\r\nb\rc\n\t"), "a\nb\nc\n\t")
        for value in ("a\x01b", "\x1b", "\x7f", "\x9f"):
            with self.assertRaises(InputError): normalize_text(value)

    def test_linux_text_limit_rejects_before_input(self):
        self.assertEqual(len(normalize_text("👋" * 2048)), 2048)
        with self.assertRaisesRegex(InputError, "text_too_long"): normalize_text("👋" * 2049)

    def test_unknown_fields_rejected(self):
        with self.assertRaises(InputError): parse_request(json.dumps(action("status", secret="x")))
        with self.assertRaises(InputError): validate_action(action("click", button="left", down=True))

    def test_unknown_and_wrong_type_actions(self):
        for kind in ("shell", "rm", [], {}, 6, None):
            with self.assertRaises(InputError): validate_action(action(kind))

    def test_duplicate_fields_rejected_recursively(self):
        identifier = str(uuid.uuid4())
        for value in (f'{{"id":"{identifier}","id":"{identifier}","type":"status"}}',
                      f'{{"id":"{identifier}","type":"apply","action":{{"type":"ping","type":"ping","id":"{identifier}"}}}}'):
            with self.assertRaises(InputError): parse_request(value)

    def test_invalid_frames(self):
        for raw in (b"\xff", b"{" , b"[]", b"x" * (MAXIMUM_LINE + 1), b'{"type": NaN}', b'[' * 2000):
            with self.assertRaises(InputError): parse_request(raw)

    def test_numeric_validation(self):
        for value in (True, "0", float("nan"), float("inf"), 501, -501):
            with self.assertRaises(InputError): validate_action(action("move", dx=value, dy=0))
        validate_action(action("move", dx=-500, dy=.5))

    def test_modifiers_and_buttons(self):
        for mods in (["ctrl", "ctrl"], ["command"], "ctrl", [{}]):
            with self.assertRaises(InputError): validate_action(action("key", key="a", modifiers=mods))
        for button in ("middle", {}, [], 1):
            with self.assertRaises(InputError): validate_action(action("click", button=button))
        with self.assertRaises(InputError): validate_action(action("button", button="left", down=1))

    def test_errors_never_include_exception_text(self):
        class Bad(UnavailableInput):
            def apply(self, _): raise RuntimeError("private text must not escape")
        result = handle_request(Bad(), action("apply", action=action("text", text="secret")))
        self.assertEqual(result["error"], "input_failed")
        self.assertNotIn("private", json.dumps(result))

    def test_status_validation(self):
        result = handle_request(UnavailableInput("private raw status"), action("status"))
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], "input_unavailable")

    def test_headless(self):
        self.assertEqual(choose_backend({}).status(), "desktop_unavailable")

    def test_unsupported_session(self):
        self.assertEqual(choose_backend({"XDG_SESSION_TYPE": "tty", "DISPLAY": ":9"}).status(), "unsupported_session")

    def test_wayland_never_falls_back_to_x11(self):
        class Module:
            @staticmethod
            def PortalInput(): return UnavailableInput("permission_required")
        with patch.dict(sys.modules, {"wayland_input": Module()}):
            for env in ({"XDG_SESSION_TYPE": "wayland", "DISPLAY": ":9"},
                        {"WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":9"}):
                self.assertEqual(choose_backend(env).status(), "permission_required")


class InputTests(unittest.TestCase):
    def setUp(self):
        self.native = FakeNative()
        self.backend = X11Input(self.native)

    def test_fractional_movement(self):
        for _ in range(4): self.backend.apply(action("move", dx=.3, dy=-.3))
        self.assertEqual(self.native.events, [("move", 1, -1)])

    def test_scroll_threshold_and_direction(self):
        self.backend.apply(action("scroll", dx=119, dy=-119))
        self.assertFalse(self.native.events)
        self.backend.apply(action("scroll", dx=1, dy=-1))
        self.assertEqual(self.native.events, [("button", 7, True), ("button", 7, False), ("button", 5, True), ("button", 5, False)])

    def test_held_button_idempotent_and_disconnect_release(self):
        for _ in range(3): self.backend.apply(action("button", button="left", down=True))
        self.backend.release_all()
        self.assertEqual(self.native.events, [("button", 1, True), ("button", 1, False)])

    def test_unowned_button_release_is_noop(self):
        self.backend.apply(action("button", button="right", down=False))
        self.assertFalse(self.native.events)

    def test_shortcut_releases_in_reverse_order(self):
        self.backend.apply(action("key", key="a", modifiers=["ctrl", "shift"]))
        self.assertEqual(self.native.events, [("key", "ctrl", True), ("key", "shift", True), ("key", "a", True),
                                             ("key", "a", False), ("key", "shift", False), ("key", "ctrl", False)])

    def test_physical_keyboard_busy_has_no_events(self):
        self.native.busy = True
        for request in (action("text", text="中文👋"), action("key", key="a", modifiers=["ctrl"])):
            with self.assertRaisesRegex(InputError, "input_busy"): self.backend.apply(request)
        self.assertFalse(self.native.events)

    def test_partial_shortcut_releases_owned_keys(self):
        self.native.fail = 2
        with self.assertRaisesRegex(InputError, "input_partial"):
            self.backend.apply(action("key", key="a", modifiers=["ctrl"]))
        self.assertIn(("key", "ctrl", False), self.native.events)
        self.assertIn(("key", "a", False), self.native.events)
        self.assertFalse(self.backend.held_keys)

    def test_partial_click_releases_owned_button(self):
        self.native.fail = 1
        with self.assertRaises(InputError): self.backend.apply(action("click", button="right"))
        self.assertEqual(self.native.events, [("button", 3, True), ("button", 3, False)])

    def test_physical_button_is_not_released(self):
        self.native.busy = True
        with self.assertRaisesRegex(InputError, "input_busy"):
            self.backend.apply(action("click", button="left"))
        self.assertFalse(self.native.events)

    def test_close_releases_and_closes_native(self):
        self.backend.apply(action("button", button="right", down=True))
        self.backend.close()
        self.assertTrue(self.native.closed)
        self.assertEqual(self.backend.status(), "input_unavailable")
        with self.assertRaises(InputError): self.backend.apply(action("move", dx=1, dy=1))

    def test_unicode_is_forwarded_without_shell(self):
        sample = "中文\n日本語 👋 café $()`"
        self.backend.apply(action("text", text=sample))
        self.assertEqual(self.native.events, [("text", sample)])


class WorkerProcessTests(unittest.TestCase):
    def run_worker(self, data):
        environment = dict(os.environ, XDG_SESSION_TYPE="x11")
        environment.pop("DISPLAY", None)
        environment.pop("WAYLAND_DISPLAY", None)
        # Headless only: this test cannot access a user's graphical session.
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("input_worker.py"))], input=data,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment, timeout=5)
        self.assertEqual(result.stderr, b"")
        return result

    def test_status_quit_and_exact_response_fields(self):
        requests = [action("status"), action("quit")]
        result = self.run_worker(b"".join(json.dumps(value).encode() + b"\n" for value in requests))
        self.assertEqual(result.returncode, 0)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(replies), 2)
        for request, reply in zip(requests, replies):
            self.assertEqual(set(reply), {"id", "ok", "status"})
            self.assertEqual(reply["id"], request["id"])
            self.assertIn(reply["status"], {"desktop_unavailable", "dependency_missing"})

    def test_clean_eof(self):
        result = self.run_worker(b"")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_partial_frame_eof(self):
        result = self.run_worker(json.dumps(action("status")).encode())
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")

    def test_newlineless_oversized_frame(self):
        result = self.run_worker(b"x" * (MAXIMUM_LINE + 100))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")

    def test_malformed_frame_cannot_reach_backend(self):
        result = self.run_worker(b'{"id":"private","type":"shell","command":"private"}\n')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
