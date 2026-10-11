#!/usr/bin/env python3
"""Isolated RemoteDesktop state/event checks; never connects to the session bus."""

import unittest

from input_common import InputError
from wayland_input import PortalInput, KEYSYMS, MODIFIERS, unicode_keysym


class FakePortal:
    def __init__(self):
        self.capability = "permission_required"
        self.requests = []
        self.notifications = []
        self.closed_sessions = []
        self.cancelled = []
        self.watchers = {}
        self.probes = 0
        self.fail_after = None
        self.closed = False

    def probe(self):
        self.probes += 1
        return self.capability

    def session_path(self, token):
        return "/org/freedesktop/portal/desktop/session/1_2/" + token

    def set_lost_handler(self, callback):
        self.lost = callback

    def request(self, method, arguments, options, callback):
        request = (method, arguments, options, callback)
        self.requests.append(request)
        return lambda: self.cancelled.append(request)

    def answer(self, index=-1, response=0, results=None):
        method, arguments, options, callback = self.requests[index]
        if results is None:
            results = {"session_handle": self.session_path(options["session_handle_token"])} \
                if method == "CreateSession" else {"devices": 3} if method == "Start" else {}
        callback(response, results)

    def watch_session(self, session, callback):
        self.watchers[session] = callback
        return lambda: self.watchers.pop(session, None)

    def close_session(self, session):
        self.closed_sessions.append(session)

    def notify(self, method, session, options, values, timeout):
        self.notifications.append((method, session, options, values, timeout))
        if self.fail_after is not None and len(self.notifications) >= self.fail_after:
            raise RuntimeError("simulated transport failure containing private data")

    def close(self):
        self.closed = True


def action(kind, **fields):
    return {"id": "f7f791d0-38f5-4534-bc79-a8a0d9a3e936", "type": kind, **fields}


class PortalChecks(unittest.TestCase):
    def setUp(self):
        self.transport = FakePortal()
        self.backend = PortalInput(self.transport)

    def grant(self):
        self.backend.request_access()
        self.transport.answer()
        self.transport.answer()
        self.transport.answer()
        self.assertEqual("ready", self.backend.status())

    def test_status_and_refused_input_never_open_permission_dialog(self):
        for _ in range(3):
            self.assertEqual("permission_required", self.backend.status())
            with self.assertRaises(InputError):
                self.backend.apply(action("move", dx=1, dy=2))
        self.assertEqual([], self.transport.requests)
        self.assertEqual(1, self.transport.probes)

    def test_explicit_permission_sequence_requests_only_keyboard_and_pointer(self):
        self.grant()
        self.assertEqual(["CreateSession", "SelectDevices", "Start"],
                         [request[0] for request in self.transport.requests])
        self.assertEqual({"types": 3}, self.transport.requests[1][2])
        self.assertEqual("", self.transport.requests[2][1][1])
        self.assertEqual({}, self.transport.requests[2][2])
        self.assertEqual([], self.transport.notifications)

    def test_repeated_permission_click_does_not_duplicate_dialog(self):
        self.backend.request_access()
        for _ in range(4):
            self.backend.request_access()
        self.assertEqual("permission_pending", self.backend.status())
        self.assertEqual(1, len(self.transport.requests))

    def test_ready_permission_click_does_not_reauthorize(self):
        self.grant()
        self.backend.request_access()
        self.assertEqual(3, len(self.transport.requests))

    def test_cancellation_at_every_stage_closes_session_without_reprompt(self):
        for stage in range(3):
            with self.subTest(stage=stage):
                self.setUp()
                self.backend.request_access()
                for _ in range(stage):
                    self.transport.answer()
                self.transport.answer(response=1)
                self.assertEqual("permission_denied", self.backend.status())
                self.assertEqual(1, len(self.transport.closed_sessions))
                self.assertFalse(self.transport.watchers)
                self.assertEqual(stage + 1, len(self.transport.requests))

    def test_portal_error_and_timeout_fail_closed(self):
        self.backend.request_access()
        self.transport.answer(response=2)
        self.assertEqual("input_unavailable", self.backend.status())
        with self.assertRaises(InputError):
            self.backend.apply(action("click", button="left"))
        self.assertEqual([], self.transport.notifications)

    def test_refuses_mismatched_session_handle(self):
        self.backend.request_access()
        self.transport.answer(results={"session_handle": "/someone/elses/session"})
        self.assertEqual("input_unavailable", self.backend.status())
        self.assertEqual(1, len(self.transport.requests))

    def test_partial_permission_and_malformed_devices_fail_closed(self):
        for devices in (0, 1, 2, True, "3", None):
            with self.subTest(devices=devices):
                self.setUp()
                self.backend.request_access()
                self.transport.answer()
                self.transport.answer()
                self.transport.answer(results={"devices": devices})
                self.assertEqual("permission_denied", self.backend.status())
                self.assertEqual([], self.transport.notifications)

    def test_backend_missing_remote_desktop_never_starts_session(self):
        self.transport.capability = "unsupported_session"
        self.backend.request_access()
        self.assertEqual("unsupported_session", self.backend.status())
        self.assertEqual([], self.transport.requests)

    def test_session_revocation_clears_held_buttons_and_requires_new_consent(self):
        self.grant()
        self.backend.apply(action("button", button="left", down=True))
        next(iter(self.transport.watchers.values()))()
        self.assertEqual("permission_required", self.backend.status())
        self.assertFalse(self.backend._buttons)
        with self.assertRaises(InputError):
            self.backend.apply(action("move", dx=5, dy=5))
        self.assertEqual(1, len(self.transport.notifications))
        self.assertEqual(3, len(self.transport.requests))

    def test_name_owner_loss_invalidates_session(self):
        self.grant()
        self.transport.lost()
        self.assertEqual("desktop_unavailable", self.backend.status())
        self.assertFalse(self.transport.watchers)
        self.assertEqual(1, len(self.transport.closed_sessions))

    def test_close_cancels_pending_request_and_late_callback_cannot_start_session(self):
        self.backend.request_access()
        self.backend.close()
        self.transport.answer()
        self.assertEqual("desktop_unavailable", self.backend.status())
        self.assertEqual(1, len(self.transport.cancelled))
        self.assertEqual(1, len(self.transport.requests))
        self.assertTrue(self.transport.closed)
        self.backend.request_access()
        self.backend.close()
        self.assertEqual(1, len(self.transport.closed_sessions))

    def test_stale_response_and_revocation_do_not_change_new_session(self):
        self.backend.request_access()
        old_closed = next(iter(self.transport.watchers.values()))
        self.transport.answer(response=1)
        self.backend.request_access()
        self.transport.answer(index=0)
        old_closed()
        self.assertEqual("permission_pending", self.backend.status())
        self.assertEqual(2, len(self.transport.requests))
        self.transport.answer()
        self.transport.answer()
        self.transport.answer()
        self.assertEqual("ready", self.backend.status())

    def test_motion_preserves_fractional_values_and_scroll_direction(self):
        self.grant()
        self.backend.apply(action("move", dx=0.25, dy=-1.5))
        self.backend.apply(action("scroll", dx=1.5, dy=2.5))
        first, second = self.transport.notifications
        self.assertEqual(("NotifyPointerMotion", (0.25, -1.5)), (first[0], first[3]))
        self.assertEqual(("NotifyPointerAxis", (1.5, -2.5), {"finish": True}),
                         (second[0], second[3], second[2]))
        self.assertTrue(all(0 < entry[4] <= 500 for entry in self.transport.notifications))

    def test_click_uses_evdev_codes_and_release(self):
        self.grant()
        self.backend.apply(action("click", button="right"))
        self.assertEqual([(0x111, 1), (0x111, 0)], [item[3] for item in self.transport.notifications])

    def test_only_owned_buttons_are_released_and_duplicate_down_is_idempotent(self):
        self.grant()
        self.backend.apply(action("button", button="right", down=False))
        self.backend.apply(action("button", button="left", down=True))
        self.backend.apply(action("button", button="left", down=True))
        self.backend.release_all()
        self.backend.release_all()
        self.assertEqual([(0x110, 1), (0x110, 0)], [item[3] for item in self.transport.notifications])

    def test_click_and_text_refused_during_owned_drag(self):
        self.grant()
        self.backend.apply(action("button", button="left", down=True))
        for value in (action("click", button="right"), action("text", text="x")):
            with self.assertRaises(InputError) as caught:
                self.backend.apply(value)
            self.assertEqual("input_busy", caught.exception.code)
        self.assertEqual(1, len(self.transport.notifications))
        self.assertEqual("ready", self.backend.status())

    def test_shortcut_press_and_reverse_release_order(self):
        self.grant()
        self.backend.apply(action("key", key="a", modifiers=["ctrl", "shift"]))
        self.assertEqual([(MODIFIERS["ctrl"], 1), (MODIFIERS["shift"], 1), (ord("a"), 1),
                          (ord("a"), 0), (MODIFIERS["shift"], 0), (MODIFIERS["ctrl"], 0)],
                         [item[3] for item in self.transport.notifications])
        self.assertFalse(self.backend._keys)

    def test_unicode_text_keeps_latin1_cjk_emoji_and_explicit_linebreaks(self):
        self.grant()
        self.backend.apply(action("text", text="é中👋\r\n日\t本"))
        codes = [0xE9, 0x01004E2D, 0x0101F44B, 0xFF0D, 0x010065E5, 0xFF09, 0x0100672C]
        self.assertEqual([(code, down) for code in codes for down in (1, 0)],
                         [item[3] for item in self.transport.notifications])

    def test_unrepresentable_text_rejected_before_first_character(self):
        self.grant()
        for text in ("prefix\x1b", "prefix\x7f", "prefix\x85", "prefix\ud800"):
            with self.subTest(text=repr(text)), self.assertRaises(InputError):
                self.backend.apply(action("text", text=text))
        self.assertEqual([], self.transport.notifications)
        self.assertEqual("ready", self.backend.status())

    def test_overlong_text_is_refused_before_any_input(self):
        self.grant()
        with self.assertRaises(InputError) as caught:
            self.backend.apply(action("text", text="👋" * 2049))
        self.assertEqual("text_too_long", caught.exception.code)
        self.assertEqual([], self.transport.notifications)
        self.assertEqual("ready", self.backend.status())
        self.backend.apply(action("text", text="👋" * 2048))
        self.assertEqual(4096, len(self.transport.notifications))

    def test_failed_first_call_is_uncertain_and_must_not_retry(self):
        self.grant()
        self.transport.fail_after = 1
        with self.assertRaises(InputError) as caught:
            self.backend.apply(action("text", text="private text"))
        self.assertEqual("input_partial", caught.exception.code)
        self.assertNotIn("private", str(caught.exception))
        self.assertEqual("input_unavailable", self.backend.status())
        self.assertEqual(1, len(self.transport.closed_sessions))
        self.assertFalse(self.backend._keys)

    def test_failure_after_modifier_down_closes_session_without_replay(self):
        self.grant()
        self.transport.fail_after = 2
        with self.assertRaises(InputError):
            self.backend.apply(action("key", key="c", modifiers=["ctrl"]))
        self.assertEqual(2, len(self.transport.notifications))
        self.assertEqual("input_unavailable", self.backend.status())
        self.assertFalse(self.backend._keys)

    def test_deadline_bounds_even_successful_slow_calls(self):
        self.grant()
        times = iter([0, 0, 1, 2, 3.01])
        self.backend.clock = lambda: next(times)
        with self.assertRaises(InputError) as caught:
            self.backend.apply(action("text", text="abcdef"))
        self.assertEqual("input_partial", caught.exception.code)
        self.assertEqual(3, len(self.transport.notifications))
        self.assertEqual("input_unavailable", self.backend.status())

    def test_release_failure_closes_portal_session(self):
        self.grant()
        self.backend.apply(action("button", button="left", down=True))
        self.transport.fail_after = 2
        self.backend.release_all()
        self.assertEqual("input_unavailable", self.backend.status())
        self.assertFalse(self.backend._buttons)

    def test_unknown_action_does_not_inject(self):
        self.grant()
        with self.assertRaises(InputError):
            self.backend.apply(action("shell", command="anything"))
        self.assertEqual([], self.transport.notifications)

    def test_unicode_keysym_matches_xkb_encoding(self):
        self.assertEqual(0x41, unicode_keysym("A"))
        self.assertEqual(0xA0, unicode_keysym("\xa0"))
        self.assertEqual(0xE9, unicode_keysym("é"))
        self.assertEqual(0x010020AC, unicode_keysym("€"))
        self.assertEqual(0x0110FFFF, unicode_keysym(chr(0x10FFFF)))


if __name__ == "__main__":
    unittest.main()
