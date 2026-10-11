#!/usr/bin/env python3
"""Pure AT-SPI metadata decisions; does not initialize GI or query a desktop."""
import importlib.util
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
