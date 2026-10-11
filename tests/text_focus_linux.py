#!/usr/bin/env python3
"""Pure AT-SPI metadata decisions; does not initialize GI or query a desktop."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("text_focus_worker", Path(__file__).resolve().parents[1] / "desktop/linux/text_focus_worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class FocusMetadataTests(unittest.TestCase):
    def kind(self, **changes):
        flags = dict(focused=True, enabled=True, editable=True, read_only=False, password=False, defunct=False)
        return worker.classify_focus(**(flags | changes))

    def test_writable_field(self):
        self.assertEqual(self.kind(), "editable")

    def test_password_precedes_editable(self):
        self.assertEqual(self.kind(password=True), "protected")

    def test_not_focused_never_summons_keyboard(self):
        self.assertEqual(self.kind(focused=False), "unknown")

    def test_defunct_never_summons_keyboard(self):
        self.assertEqual(self.kind(defunct=True), "unknown")

    def test_readonly_is_not_editor(self):
        self.assertEqual(self.kind(read_only=True), "other")

    def test_disabled_is_not_editor(self):
        self.assertEqual(self.kind(enabled=False), "other")

    def test_non_text_is_not_editor(self):
        self.assertEqual(self.kind(editable=False), "other")

    def test_state_wire_is_two_bitmask_words(self):
        editable = (1 << 12) | (1 << 8) | (1 << 7)
        self.assertEqual(worker.classify_state_words([editable, 0], 61), "editable")
        self.assertEqual(worker.classify_state_words([editable, 1 << 11], 61), "other")
        self.assertEqual(worker.classify_state_words([editable, 0], 40), "protected")
        self.assertEqual(worker.classify_state_words([editable | (1 << 6), 0], 61), "unknown")

    def test_malformed_wire_fails_closed(self):
        for words in ([], [1], [1, 2, 3], [True, 0], [-1, 0], [2**32, 0], "field text"):
            self.assertEqual(worker.classify_state_words(words, 61), "unknown")


class BusError(Exception):
    pass


class Cancellation:
    def __init__(self):
        self.cancelled = False

    def cancel(self):
        self.cancelled = True


class FakeBus:
    def __init__(self):
        self.calls = []

    def call(self, *args):
        self.calls.append(args)

    def call_finish(self, result):
        if isinstance(result, Exception):
            raise result
        return SimpleNamespace(unpack=lambda: (result,))

    def reply(self, index, result):
        args = self.calls[index]
        args[-2](self, result, args[-1])

    def is_closed(self):
        return False


class AsyncMetadataTests(unittest.TestCase):
    def setUp(self):
        self.bus = FakeBus()
        self.now = 10
        gio = SimpleNamespace(Cancellable=Cancellation, DBusCallFlags=SimpleNamespace(NO_AUTO_START=1))
        glib = SimpleNamespace(Error=BusError, VariantType=SimpleNamespace(new=lambda value: value))
        self.probe = worker.FocusProbe(self.bus, gio, glib, clock=lambda: self.now)
        self.probe.reset((":1.9", "/owned/blank"))
        self.probe.refresh()

    def editable_reply(self, first=0):
        self.bus.reply(first, [(1 << 12) | (1 << 8) | (1 << 7), 0])
        self.bus.reply(first + 1, 61)

    def test_only_two_bounded_metadata_calls(self):
        self.assertEqual([call[3] for call in self.bus.calls], ["GetState", "GetRole"])
        self.assertTrue(all(call[7] == 200 for call in self.bus.calls))
        self.assertTrue(all(call[6] == 1 for call in self.bus.calls))
        self.probe.refresh()
        self.assertEqual(len(self.bus.calls), 2)

    def test_partial_metadata_never_marks_editor(self):
        self.bus.reply(0, [(1 << 12) | (1 << 8) | (1 << 7), 0])
        self.assertEqual(self.probe.kind, "unknown")
        self.bus.reply(1, 40)
        self.assertEqual(self.probe.kind, "protected")

    def test_old_target_replies_cannot_replace_new_focus(self):
        self.probe.reset((":1.9", "/owned/second"))
        self.probe.refresh()
        self.editable_reply()
        self.assertEqual(self.probe.kind, "unknown")
        self.editable_reply(2)
        self.assertEqual(self.probe.kind, "editable")

    def test_late_cancelled_reply_cannot_cancel_new_request(self):
        self.bus.reply(0, BusError())
        self.probe.refresh()
        request = self.probe.request
        self.bus.reply(1, BusError())
        self.assertIs(self.probe.request, request)
        self.assertFalse(request.cancelled)
        self.editable_reply(2)
        self.assertEqual(self.probe.kind, "editable")

    def test_stale_kind_and_identity_are_not_emitted(self):
        self.editable_reply()
        self.now += 2
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.probe.tick()
        self.assertEqual(json.loads(output.getvalue()), {"kind": "unknown", "identity": None})

    def test_closed_output_stops_own_main_loop(self):
        stopped = []
        self.probe.stop = lambda: stopped.append(True)
        output = SimpleNamespace(write=lambda value: (_ for _ in ()).throw(BrokenPipeError()), flush=lambda: None)
        with contextlib.redirect_stdout(output):
            self.assertFalse(self.probe.tick())
        self.assertEqual(stopped, [True])
        self.assertIsNone(self.probe.target)


if __name__ == "__main__":
    unittest.main()
