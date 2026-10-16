"""Per-user XDG login startup. No system settings are changed on import."""

import configparser
import os
from pathlib import Path
import tempfile


def config_home():
    configured = os.environ.get("XDG_CONFIG_HOME", "")
    return Path(configured) if configured and Path(configured).is_absolute() else Path.home() / ".config"


def quote_argument(value):
    # Desktop Entry Exec has two escaping passes, not shell quoting.
    value = str(value)
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("Startup paths cannot contain control characters")
    value = value.replace("%", "%%")
    value = "".join("\\" + c if c in '\\"`$' else c for c in value)
    return '"' + value.replace("\\", "\\\\") + '"'


def atomic_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".sofatap-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Autostart:
    def __init__(self, command, root=None):
        self.root = Path(root) if root is not None else config_home()
        self.entry = self.root / "autostart/com.chekusu.sofatap.receiver.desktop"
        self.marker = self.root / "sofatap/autostart-initialized"
        self.command = tuple(str(value) for value in command)

    def enabled(self):
        parser = configparser.ConfigParser(interpolation=None, strict=True)
        try:
            parser.read_string(self.entry.read_text(encoding="utf-8"))
            entry = parser["Desktop Entry"]
            return (entry.get("Type") == "Application" and bool(entry.get("Exec"))
                    and not entry.getboolean("Hidden", fallback=False)
                    and entry.getboolean("X-GNOME-Autostart-enabled", fallback=True))
        except FileNotFoundError:
            return False
        except (configparser.Error, KeyError, ValueError):
            return False

    def initialize(self):
        # Existing entries (including Hidden=true) and a removed entry after
        # first launch are user choices. Never silently restore them.
        if self.marker.exists():
            return
        atomic_text(self.marker, "1\n")
        if not self.entry.exists():
            self.set_enabled(True)

    def set_enabled(self, enabled):
        if enabled:
            if not self.command or "=" in self.command[0]:
                raise ValueError("Invalid startup executable")
            command = " ".join(quote_argument(value) for value in self.command)
            content = ("[Desktop Entry]\nType=Application\nName=Sofatap\n"
                       "Comment=Receive phone control after login\n"
                       f"Exec={command}\nTerminal=false\nStartupNotify=false\nHidden=false\n")
        else:
            # A tombstone also overrides any same-name system-wide entry.
            content = "[Desktop Entry]\nType=Application\nName=Sofatap\nHidden=true\n"
        atomic_text(self.entry, content)
        atomic_text(self.marker, "1\n")
