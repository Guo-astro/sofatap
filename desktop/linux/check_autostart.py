#!/usr/bin/env python3
"""Startup lifecycle checks in temporary directories; no real login entry/input."""

import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from autostart import Autostart, config_home, quote_argument
from receiver_instance import ReceiverInstance


class AutostartChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sofatap-startup-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.settings = Autostart(["/usr/bin/python3", "/opt/Sofatap/lib/linux/sofatap.py", "--startup"], self.root)

    def test_first_launch_defaults_on_then_preserves_disable(self):
        self.settings.initialize()
        self.assertTrue(self.settings.enabled())
        self.settings.set_enabled(False)
        self.settings.initialize()
        self.assertFalse(self.settings.enabled())
        self.assertIn("Hidden=true", self.settings.entry.read_text())

    def test_external_removal_is_not_undone(self):
        self.settings.initialize()
        self.settings.entry.unlink()
        self.settings.initialize()
        self.assertFalse(self.settings.entry.exists())
        self.settings.set_enabled(True)
        self.assertTrue(self.settings.enabled())

    def test_existing_system_disabled_entry_is_preserved(self):
        for setting in ("Hidden=true", "X-GNOME-Autostart-enabled=false"):
            self.settings.entry.parent.mkdir(parents=True, exist_ok=True)
            original = "[Desktop Entry]\nType=Application\nExec=/old/location\n" + setting + "\n"
            self.settings.entry.write_text(original)
            self.settings.marker.unlink(missing_ok=True)
            self.settings.initialize()
            self.assertFalse(self.settings.enabled())
            self.assertEqual(self.settings.entry.read_text(), original)

    def test_default_does_not_overwrite_an_existing_custom_command(self):
        self.settings.entry.parent.mkdir(parents=True)
        original = "[Desktop Entry]\nType=Application\nExec=/user/custom/sofatap\nOnlyShowIn=GNOME;\n"
        self.settings.entry.write_text(original)
        self.settings.initialize()
        self.assertEqual(self.settings.entry.read_text(), original)

    def test_no_marker_or_entry_is_created_by_reading(self):
        self.assertFalse(self.settings.enabled())
        self.assertEqual(list(self.root.iterdir()), [])

    def test_failed_registration_does_not_claim_enabled_or_retry_automatically(self):
        with patch.object(self.settings, "set_enabled", side_effect=PermissionError):
            with self.assertRaises(PermissionError):
                self.settings.initialize()
        self.assertFalse(self.settings.enabled())
        self.settings.initialize()
        self.assertFalse(self.settings.enabled())

    def test_relative_xdg_location_is_ignored(self):
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": "relative"}):
            self.assertEqual(config_home(), Path.home() / ".config")

    def test_control_characters_and_equal_executable_are_rejected(self):
        for path in ("/tmp/bad\nname", "/tmp/bad\rname", "/tmp/bad\x00name"):
            with self.assertRaises(ValueError):
                quote_argument(path)
        with self.assertRaises(ValueError):
            Autostart(["/tmp/bad=name"], self.root).set_enabled(True)

    def test_disable_preserves_unrelated_entries(self):
        other = self.root / "autostart/other.desktop"
        other.parent.mkdir()
        other.write_text("other application")
        self.settings.set_enabled(False)
        self.assertEqual(other.read_text(), "other application")

    @unittest.skipUnless(sys.platform == "linux", "uses the real Linux desktop-entry parser")
    def test_exec_round_trip_with_spaces_shell_symbols_and_percent(self):
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio
        folder = self.root / 'a $`"\\% folder'
        folder.mkdir()
        output = self.root / "arguments.json"
        script = folder / "capture.py"
        script.write_text("import json,sys\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(json.dumps(sys.argv[2:]))\n")
        argument = '/tmp/input $`"\\% field'
        settings = Autostart([sys.executable, str(script), str(output), argument, "--startup"], self.root)
        settings.set_enabled(True)
        app = Gio.DesktopAppInfo.new_from_filename(str(settings.entry))
        self.assertIsNotNone(app)
        self.assertTrue(app.launch([], None))
        deadline = time.monotonic() + 5
        while not output.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(json.loads(output.read_text()), [argument, "--startup"])


class InstanceChecks(unittest.TestCase):
    def setUp(self):
        # AF_UNIX path length is bounded, including on the macOS test host.
        self.temporary = tempfile.TemporaryDirectory(prefix="st-", dir="/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "run"
        self.primary = ReceiverInstance(self.root)
        self.addCleanup(self.primary.close)

    def test_second_manual_launch_activates_without_taking_lock(self):
        self.assertTrue(self.primary.acquire())
        second = ReceiverInstance(self.root)
        self.addCleanup(second.close)
        self.assertFalse(second.acquire())
        self.assertTrue(self.primary.show_requested())
        self.assertFalse(self.primary.show_requested())

    def test_login_launch_does_not_raise_existing_window(self):
        self.assertTrue(self.primary.acquire())
        second = ReceiverInstance(self.root)
        self.addCleanup(second.close)
        self.assertFalse(second.acquire(startup=True))
        self.assertFalse(self.primary.show_requested())

    def test_restart_reclaims_lock_and_stale_socket(self):
        with socket.socket(socket.AF_UNIX) as stale:
            stale.bind(str(self.root / "control.sock"))
        self.assertTrue(self.primary.acquire())
        self.primary.close()
        next_run = ReceiverInstance(self.root)
        self.addCleanup(next_run.close)
        self.assertTrue(next_run.acquire())

    def test_shared_runtime_directory_is_rejected(self):
        self.root.chmod(0o755)
        with self.assertRaises(PermissionError):
            ReceiverInstance(self.root)

    def test_symlink_runtime_directory_is_rejected(self):
        link = Path(self.temporary.name) / "linked"
        link.symlink_to(self.root)
        with self.assertRaises(PermissionError):
            ReceiverInstance(link)


if __name__ == "__main__":
    unittest.main()
