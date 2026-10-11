#!/usr/bin/env python3
"""Render the production GTK window with offline fixtures on a private Xvfb.

No receiver, portal, network listener, credentials, clipboard operation or system
input is started. The pixel pattern is deliberately not a QR code. Screenshots
contain only synthetic names and documentation-only IP addresses. A window
manager is not required; PNGs show the native GTK client area without OS chrome.
"""

import argparse
import json
import os
from pathlib import Path
import secrets
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib


def illustration_png():
    """A checker pattern with a large DEMO stripe, not an encoded pairing code."""
    letters = {
        "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
        "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
        "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
        "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    }
    pixels = bytearray([255] * (224 * 224 * 3))

    def fill(x, y, width, height):
        for row in range(y, y + height):
            for column in range(x, x + width):
                offset = (row * 224 + column) * 3
                pixels[offset:offset + 3] = b"\x00\x00\x00"

    for row in range(27):
        for column in range(27):
            y = 17 + row * 7
            if 79 <= y <= 135:
                continue
            if (row * 13 + column * 7 + row * column) % 11 < 5:
                fill(17 + column * 7, y, 7, 7)
    for index, letter in enumerate("DEMO"):
        for row, line in enumerate(letters[letter]):
            for column, pixel in enumerate(line):
                if pixel == "1":
                    fill(43 + index * 36 + column * 6, 88 + row * 6, 6, 6)

    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value))

    scanlines = b"".join(b"\x00" + pixels[row * 672:(row + 1) * 672] for row in range(224))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 224, 224, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def render_fixtures(output):
    # Only the parent below can provide this Xvfb process and generated authority.
    display = os.environ.get("DISPLAY")
    if not display or display != os.environ.get("SOFATAP_PREVIEW_PRIVATE_DISPLAY"):
        raise RuntimeError("A parent-created private display is required")
    arguments = Path(f"/proc/{int(os.environ['SOFATAP_PREVIEW_XVFB_PID'])}/cmdline").read_bytes().split(b"\x00")
    authority = os.fsencode(os.environ["XAUTHORITY"])
    if (not arguments or Path(os.fsdecode(arguments[0])).name != "Xvfb" or b"-displayfd" not in arguments
            or b"-auth" not in arguments or authority not in arguments or b"-nolisten" not in arguments):
        raise RuntimeError("The preview display is not the authenticated private Xvfb")
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, GdkPixbuf, GLib, Gtk
    from sofatap import Pairing, State, create_window
    if not Gtk.init_check()[0]:
        raise RuntimeError("Private GTK display did not initialize")
    context = GLib.MainContext.default()
    output.mkdir(parents=True, exist_ok=True)
    png = illustration_png()
    results = []

    class FixtureBackend:
        stopping = False

        def __init__(self, state, on_state):
            self.state, self.on_state = state, on_state

        def start(self):
            self.on_state(self.state)

        def send(self, _command):
            raise AssertionError("Rendering must not send backend commands")

        def stop(self):
            self.stopping = True

    fixtures = (
        ("ready", "ready", "客厅电脑 · 示例", "192.0.2.17", 470, 700),
        ("permission", "permission_required", "客厅电脑 · 示例", "192.0.2.17", 470, 700),
        ("narrow", "ready", "用于布局检查的长电脑名称 · 示例", "2001:db8:1234:5678:90ab:cdef:1234:5678", 360, 720),
    )
    for name, status, computer, host, width, height in fixtures:
        # This inert marker has no token/fingerprint and cannot pair with a host.
        # Injecting it enables the Copy appearance without creating credentials.
        # No button is activated; production protocol validation remains covered
        # by check_protocol.py and does not accept this fixture-only marker.
        state = State(computer, False, False, status, (Pairing(host, png, "sofatap://visual-fixture"),))
        window = create_window(Gtk, Gdk, GdkPixbuf, GLib,
                               lambda on_state, _on_failure: FixtureBackend(state, on_state))
        window.resize(width, height)
        deadline = time.monotonic() + .5
        while time.monotonic() < deadline:
            while context.pending():
                context.iteration(False)
            time.sleep(.01)
        actual_width, actual_height = window.get_size()
        if actual_width != width or actual_height != height:
            raise AssertionError(f"{name}: requested {width}x{height}, got {actual_width}x{actual_height}")
        if (window.image.get_pixbuf() is None or not window.copy_button.get_sensitive()
                or window.access_button.get_visible() != (status == "permission_required") or window.failed):
            raise AssertionError(f"{name}: production UI did not represent its fixture state")
        image = Gdk.pixbuf_get_from_window(window.get_window(), 0, 0, actual_width, actual_height)
        if image is None:
            raise RuntimeError("Private GTK client-area capture failed")
        filename = f"linux-{name}.png"
        image.savev(str(output / filename), "png", [], [])
        results.append(dict(file=filename, width=actual_width, height=actual_height, inputStatus=status,
                            offlineFixture=True, realPairingCredentials=False))
        if name == "narrow":
            # Programmatic scroll of this fixture's native content proves that
            # long/narrow layouts keep the actions reachable. No input event is
            # emitted, and the first image above remains the real top view.
            adjustment = window.get_child().get_vadjustment()
            adjustment.set_value(max(adjustment.get_lower(), adjustment.get_upper() - adjustment.get_page_size()))
            deadline = time.monotonic() + .2
            while time.monotonic() < deadline:
                while context.pending():
                    context.iteration(False)
                time.sleep(.01)
            for button in (window.refresh, window.quit_button):
                position = button.translate_coordinates(window, 0, 0)
                if position is None:
                    raise AssertionError("Narrow fixture action could not be located")
                x, y = position
                if (x < 0 or y < 0 or x + button.get_allocated_width() > actual_width
                        or y + button.get_allocated_height() > actual_height):
                    raise AssertionError("Narrow fixture actions are not reachable at the bottom")
            image = Gdk.pixbuf_get_from_window(window.get_window(), 0, 0, actual_width, actual_height)
            if image is None:
                raise RuntimeError("Private GTK bottom-area capture failed")
            filename = "linux-narrow-bottom.png"
            image.savev(str(output / filename), "png", [], [])
            results.append(dict(file=filename, width=actual_width, height=actual_height, inputStatus=status,
                                scrollOffset=adjustment.get_value(), footerActionsReachable=True,
                                offlineFixture=True, realPairingCredentials=False))
        # No Gtk.main loop was entered. Destroy only this fixture window; neither
        # close_receiver nor any input/clipboard/backend action is invoked.
        window.stopping = True
        window.backend.stop()
        window.destroy()
        while context.pending():
            context.iteration(False)
    (output / "linux-fixtures.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results), flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("artifacts/mint-calm"))
    parser.add_argument("--child", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Native previews run only on Linux inside their own private Xvfb")
    if args.child:
        return render_fixtures(args.output.resolve())
    for program in ("Xvfb", "xauth"):
        if not shutil.which(program):
            parser.error(f"The private native preview requires {program}")
    with tempfile.TemporaryDirectory(prefix="sofatap-native-preview-") as temporary:
        authority = Path(temporary) / "Xauthority"
        authority.touch(mode=0o600)
        cookie = secrets.token_hex(16)
        subprocess.run(["xauth", "-f", str(authority), "add", ":0", ".", cookie], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        read_fd, write_fd = os.pipe()
        xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1280x1000x24",
                                 "-nolisten", "tcp", "-noreset", "-auth", str(authority)],
                                pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write_fd)
        try:
            if not select.select([read_fd], [], [], 8)[0]:
                raise RuntimeError("Private Xvfb did not start")
            number = os.read(read_fd, 64).decode("ascii").strip()
            if not number.isdecimal() or xvfb.poll() is not None:
                raise RuntimeError("Private Xvfb returned no display")
            display = ":" + number
            subprocess.run(["xauth", "-f", str(authority), "add", display, ".", cookie], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            environment = dict(os.environ)
            for key in ("WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "GTK_THEME", "GDK_SCALE", "GDK_DPI_SCALE"):
                environment.pop(key, None)
            environment.update(DISPLAY=display, XAUTHORITY=str(authority), GDK_BACKEND="x11", NO_AT_BRIDGE="1",
                               SOFATAP_PREVIEW_PRIVATE_DISPLAY=display, SOFATAP_PREVIEW_XVFB_PID=str(xvfb.pid),
                               LC_ALL="C.UTF-8", G_DEBUG="fatal-criticals")
            return subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), "--child", "--output",
                                   str(args.output.resolve())], env=environment, timeout=20).returncode
        finally:
            os.close(read_fd)
            xvfb.terminate()
            try:
                xvfb.wait(timeout=5)
            except subprocess.TimeoutExpired:
                xvfb.kill()
                xvfb.wait(timeout=2)


if __name__ == "__main__":
    raise SystemExit(main())
