#!/usr/bin/env python3
"""Real XTest/Unicode acceptance, exclusively on a newly owned Xvfb server.

Never reuses DISPLAY or a user's desktop. Requires Xvfb, GTK3/PyGObject,
libX11, libXtst and libxdo3. A passing result is not physical iPhone proof.
"""

import ctypes as C
import json
import os
from pathlib import Path
import queue
import select
import shutil
import subprocess
import sys
import threading
import time
import uuid


HERE = Path(__file__).resolve().parent


def isolated_run():
    executable = shutil.which("Xvfb")
    if not executable:
        raise SystemExit("Xvfb is required; refusing to use an existing DISPLAY")
    read_fd, write_fd = os.pipe()
    server = subprocess.Popen([executable, "-displayfd", str(write_fd), "-screen", "0", "1024x768x24", "-nolisten", "tcp"],
                              pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(write_fd)
    try:
        if not select.select([read_fd], [], [], 10)[0]:
            raise RuntimeError("Owned Xvfb startup timed out")
        number = os.read(read_fd, 64).strip().decode("ascii")
        if not number.isdigit() or server.poll() is not None:
            raise RuntimeError("Owned Xvfb did not start")
        environment = dict(os.environ, DISPLAY=":" + number, XDG_SESSION_TYPE="x11", SOFATAP_OWNED_XVFB=str(server.pid), LC_ALL="C.UTF-8")
        environment.pop("WAYLAND_DISPLAY", None)
        # The child sentinel is meaningful only with the actual live owned PID.
        return subprocess.run([sys.executable, str(Path(__file__).resolve()), "--owned-child"], env=environment, timeout=75).returncode
    finally:
        os.close(read_fd)
        server.terminate()
        try: server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)


def acceptance():
    if not os.environ.get("SOFATAP_OWNED_XVFB", "").isdigit():
        raise RuntimeError("Missing owned Xvfb sentinel")
    pid = int(os.environ["SOFATAP_OWNED_XVFB"])
    command = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    if not command or Path(os.fsdecode(command[0])).name != "Xvfb" or b"-displayfd" not in command:
        raise RuntimeError("Refusing a server that is not the owned Xvfb")
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkX11", "3.0")
    from gi.repository import Gdk, GdkX11, GLib, Gtk
    from x11_input import X11Native
    Gtk.init([])
    window = Gtk.Window(title="Sofatap isolated Xvfb acceptance")
    window.set_default_size(800, 600)
    window.move(0, 0)
    editor = Gtk.TextView()
    window.add(editor)
    events = {"button": [], "scroll": [], "key": []}
    editor.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.SCROLL_MASK)
    editor.connect("button-press-event", lambda _widget, event: events["button"].append((event.button, True)) or False)
    editor.connect("button-release-event", lambda _widget, event: events["button"].append((event.button, False)) or False)
    editor.connect("scroll-event", lambda _widget, event: events["scroll"].append(event.direction) or False)
    def record_key(_widget, event):
        if len(events["key"]) < 128:
            events["key"].append((event.keyval, event.hardware_keycode, int(event.state)))
        return False
    editor.connect("key-press-event", record_key)
    window.show_all()
    editor.grab_focus()

    def wait_for(predicate, seconds=5):
        deadline = time.monotonic() + seconds
        context = GLib.MainContext.default()
        while time.monotonic() < deadline:
            while context.pending(): context.iteration(False)
            if predicate(): return
            time.sleep(.005)
        raise AssertionError("Isolated acceptance condition timed out")

    wait_for(lambda: window.get_window() is not None)
    native = X11Native()
    native.x.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
    native.x.XSetInputFocus.restype = C.c_int
    native.x.XWarpPointer.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_int, C.c_int]
    native.x.XWarpPointer.restype = C.c_int
    native.x.XQueryPointer.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong),
                                     C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint)]
    native.x.XQueryPointer.restype = C.c_int
    xid = GdkX11.X11Window.get_xid(window.get_window())
    native.x.XSetInputFocus(native.display, xid, 1, 0)
    native.x.XWarpPointer(native.display, 0, xid, 0, 0, 0, 0, 200, 200)
    native.sync()

    def pointer():
        root, child, rx, ry, wx, wy, mask = C.c_ulong(), C.c_ulong(), C.c_int(), C.c_int(), C.c_int(), C.c_int(), C.c_uint()
        assert native.x.XQueryPointer(native.display, xid, C.byref(root), C.byref(child), C.byref(rx), C.byref(ry), C.byref(wx), C.byref(wy), C.byref(mask))
        return rx.value, ry.value, mask.value

    process = subprocess.Popen([sys.executable, "-u", str(HERE / "input_worker.py")], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    replies = queue.Queue()
    def read():
        for line in process.stdout:
            try: replies.put(json.loads(line))
            except Exception: replies.put({"bad_reply": True})
    threading.Thread(target=read, daemon=True).start()

    def request(kind, payload=None, expect_ok=True):
        identifier = str(uuid.uuid4())
        value = {"id": identifier, "type": kind}
        if payload is not None: value["action"] = {"id": str(uuid.uuid4()), **payload}
        process.stdin.write((json.dumps(value, ensure_ascii=False) + "\n").encode("utf-8"))
        process.stdin.flush()
        wait_for(lambda: not replies.empty())
        result = replies.get_nowait()
        assert result["id"] == identifier, result
        assert result["ok"] is expect_ok, result
        return result

    def contents():
        buffer = editor.get_buffer()
        return buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), True)

    checks = 0
    try:
        assert request("status")["status"] == "ready"
        checks += 1
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text("clipboard must remain unchanged · 原文", -1)
        mapping_before = native.mapping()
        sample = "你好 Linux，Sofatap 真机前测试。\nHello 日本語 👋 café $()`"
        request("apply", {"type": "text", "text": sample})
        try:
            wait_for(lambda: contents() == sample)
        except AssertionError as error:
            # This is a private Xvfb containing only the fixed synthetic sample;
            # never enable target-text logging in the shipping receiver.
            raise AssertionError(f"Synthetic text mismatch: expected={sample!r}; actual={contents()[:256]!r}; keys={events['key']!r}") from error
        checks += 1
        assert clipboard.wait_for_text() == "clipboard must remain unchanged · 原文"
        assert native.mapping() == mapping_before
        checks += 2
        result = request("apply", {"type": "text", "text": "中" * 2048}, expect_ok=False)
        assert result["error"] == "text_too_long"
        assert contents() == sample
        assert native.mapping() == mapping_before
        checks += 1
        request("apply", {"type": "key", "key": "a", "modifiers": ["ctrl"]})
        request("apply", {"type": "key", "key": "backspace", "modifiers": []})
        wait_for(lambda: contents() == "")
        checks += 1
        start = pointer()
        request("apply", {"type": "move", "dx": 43, "dy": 27})
        assert pointer()[:2] == (start[0] + 43, start[1] + 27)
        checks += 1
        request("apply", {"type": "click", "button": "left"})
        wait_for(lambda: (1, True) in events["button"] and (1, False) in events["button"])
        checks += 1
        request("apply", {"type": "scroll", "dx": 120, "dy": 120})
        wait_for(lambda: Gdk.ScrollDirection.RIGHT in events["scroll"] and Gdk.ScrollDirection.UP in events["scroll"])
        checks += 1
        ctrl = native.keycode("ctrl")
        native.key(ctrl, True)
        try:
            result = request("apply", {"type": "text", "text": "must not appear"}, expect_ok=False)
            assert result["error"] == "input_busy"
            assert contents() == ""
        finally:
            native.key(ctrl, False)
        checks += 1
        request("apply", {"type": "button", "button": "left", "down": True})
        assert pointer()[2] & 256
        request("releaseAll")
        assert not pointer()[2] & 256
        checks += 1
        request("apply", {"type": "button", "button": "right", "down": True})
        assert pointer()[2] & 1024
        process.stdin.close()  # EOF must release this worker's held input.
        wait_for(lambda: process.poll() is not None)
        assert process.returncode == 0
        assert not pointer()[2] & 1024
        assert process.stderr.read() == b""
        checks += 1
        print(f"PASS: {checks} real X11/XTest checks on an owned Xvfb; Unicode GTK readback, keymap/clipboard preservation, events, EOF release.")
    finally:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        native.close()
        window.destroy()
    return 0


if __name__ == "__main__":
    raise SystemExit(acceptance() if sys.argv[1:] == ["--owned-child"] else isolated_run())
