#!/usr/bin/env python3
"""Real AT-SPI focus metadata on private authenticated Xvfb and D-Bus only.

No existing desktop is used; no mouse, keyboard, clipboard or text values are read.
The test moves focus exclusively between its own blank GTK widgets.
"""
import ctypes as C
import json
import os
from pathlib import Path
import queue
import secrets
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time


def child_check():
    pid_text = os.environ.get("SOFATAP_FOCUS_XVFB", "")
    if not pid_text.isdecimal() or os.environ.get("SOFATAP_FOCUS_DISPLAY") != os.environ.get("DISPLAY"):
        raise RuntimeError("Missing private display identity")
    command = Path(f"/proc/{pid_text}/cmdline").read_bytes().split(b"\0")
    if Path(os.fsdecode(command[0])).name != "Xvfb" or b"-auth" not in command or b"-displayfd" not in command:
        raise RuntimeError("Refusing a display not owned by this test")
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise RuntimeError("Missing private D-Bus session")

    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("GdkX11", "3.0")
    gi.require_version("Atk", "1.0")
    from gi.repository import GLib, Gtk, GdkX11, Atk
    Gtk.init([])
    window = Gtk.Window(title="Sofatap isolated focus metadata test")
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    writable = Gtk.Entry()
    readonly = Gtk.Entry()
    readonly.set_editable(False)
    password = Gtk.Entry()
    password.set_visibility(False)
    button = Gtk.Button(label="Owned test button")
    for widget in (writable, readonly, password, button):
        content.pack_start(widget, False, False, 8)
    window.add(content)
    window.show_all()
    context = GLib.MainContext.default()

    def pump():
        while context.pending():
            context.iteration(False)

    pump()
    x = C.CDLL("libX11.so.6")
    x.XOpenDisplay.argtypes = [C.c_char_p]
    x.XOpenDisplay.restype = C.c_void_p
    x.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
    x.XSync.argtypes = [C.c_void_p, C.c_int]
    x.XCloseDisplay.argtypes = [C.c_void_p]
    display = x.XOpenDisplay(os.environ["DISPLAY"].encode())
    if not display:
        raise RuntimeError("Private X11 connection failed")
    # No input injection: only this test window gains focus on its owned X server.
    x.XSetInputFocus(display, GdkX11.X11Window.get_xid(window.get_window()), 1, 0)
    x.XSync(display, 0)
    responses = queue.Queue()
    worker_errors = tempfile.TemporaryFile()
    # Stack dumps are test-only: the shipped helper has no signal/debug endpoint.
    # Faulthandler prints code locations without local variables or UI contents.
    worker_wrapper = ("import faulthandler,runpy,signal,sys; "
                      "faulthandler.register(signal.SIGUSR1, all_threads=True); "
                      "runpy.run_path(sys.argv[1],run_name='__main__')")
    worker = subprocess.Popen([sys.executable, "-B", "-u", "-c", worker_wrapper,
                               str(Path(__file__).with_name("text_focus_worker.py"))],
                              stdout=subprocess.PIPE, stderr=worker_errors, text=True)

    def read_responses():
        for line in worker.stdout:
            responses.put(json.loads(line))

    reader = threading.Thread(target=read_responses, daemon=True)
    reader.start()

    observed = {kind: 0 for kind in ("unknown", "other", "editable", "protected")}

    def take_response():
        try:
            value = responses.get_nowait()
        except queue.Empty:
            return None
        if set(value) != {"kind", "identity"} or value["kind"] not in observed:
            raise AssertionError("Unexpected focus metadata fields")
        observed[value["kind"]] += 1
        if value["kind"] != "unknown":
            identity = value["identity"]
            if not isinstance(identity, str) or len(identity) != 32 or any(c not in "0123456789abcdef" for c in identity):
                raise AssertionError("Focus identity is not opaque")
        return value

    def diagnostics():
        # These flags concern our own blank widgets, never text or native identifiers.
        summary = json.dumps({"receivedStates": observed, "windowActive": window.is_active(),
                              "windowHasFocus": window.has_toplevel_focus(),
                              "entryHasFocus": writable.has_focus(), "buttonHasFocus": button.has_focus(),
                              "entryAtkFocus": writable.get_accessible().ref_state_set().contains_state(Atk.StateType.FOCUSED),
                              "buttonAtkFocus": button.get_accessible().ref_state_set().contains_state(Atk.StateType.FOCUSED)}, sort_keys=True)
        if worker.poll() is None:
            worker.send_signal(signal.SIGUSR1)
            time.sleep(.1)
        worker_errors.seek(0)
        # Include only bounded stack-location lines; arbitrary provider diagnostics
        # are never echoed into CI. All targets in this fixture are owned and blank.
        lines = worker_errors.read(8192).decode("utf-8", errors="replace").splitlines()
        stack = [line for line in lines if line.startswith(("Current thread", "Thread", "  File "))][-30:]
        return summary + "\nOwned helper stack:\n" + "\n".join(stack)

    def focus(widget):
        widget.grab_focus()
        pump()
        if (not widget.has_focus() or window.get_focus() != widget
                or not widget.get_accessible().ref_state_set().contains_state(Atk.StateType.FOCUSED)):
            raise AssertionError("Owned GTK widget did not gain actual focus: " + diagnostics())

    def wait_state(expected=None, previous=None):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            pump()
            if worker.poll() is not None:
                raise AssertionError("AT-SPI worker exited before metadata verification")
            value = take_response()
            if value is not None and (expected is None or (value["kind"] == expected and (previous is None or value["identity"] != previous))):
                return value
            time.sleep(.01)
        raise AssertionError(f"AT-SPI did not report {expected or 'startup'} in the isolated session: " + diagnostics())

    def synchronize_focus_events():
        # Registry.RegisterEvent returns before the GTK bridge necessarily consumes
        # its asynchronous EventListenerRegistered notification. A worker heartbeat
        # proves process liveness, not delivery of this test app's focus events.
        # Exercise bounded, real owned-widget transitions until the full bridge
        # reports an editable entry. Never fabricate metadata or relax assertions.
        deadline = time.monotonic() + 8
        next_transition = 0
        entry_selected = False
        while time.monotonic() < deadline:
            pump()
            if worker.poll() is not None:
                raise AssertionError("AT-SPI worker exited during focus readiness")
            if time.monotonic() >= next_transition:
                entry_selected = not entry_selected
                focus(writable if entry_selected else button)
                next_transition = time.monotonic() + .5
            value = take_response()
            if entry_selected and value is not None and value["kind"] == "editable":
                return value
            time.sleep(.01)
        raise AssertionError("AT-SPI focus event readiness handshake timed out: " + diagnostics())

    try:
        wait_state()  # Worker liveness; real event readiness is verified separately.
        state = synchronize_focus_events()
        focus(button)
        state = wait_state("other", state["identity"])
        focus(writable)
        state = wait_state("editable", state["identity"])
        focus(readonly)
        state = wait_state("other", state["identity"])
        focus(password)
        state = wait_state("protected", state["identity"])
        focus(button)
        state = wait_state("other", state["identity"])
        focus(writable)
        state = wait_state("editable", state["identity"])
        writable.set_editable(False)
        wait_state("other")  # State refresh without changing the focused element.
        window.destroy()
        wait_state("unknown")
        print("PASS: isolated AT-SPI editable, read-only, password, button, identity, state-change and destroyed-focus checks")
        return 0
    finally:
        worker.terminate()
        try:
            worker.wait(timeout=3)
        except subprocess.TimeoutExpired:
            worker.kill()
            worker.wait(timeout=3)
        reader.join(timeout=2)
        worker.stdout.close()
        worker_errors.close()
        window.destroy()
        pump()
        x.XCloseDisplay(display)


def main():
    if sys.platform != "linux":
        raise SystemExit("Linux required; this test never uses a Mac or physical desktop")
    if "--owned-child" in sys.argv:
        return child_check()
    for name in ("Xvfb", "xauth", "dbus-run-session"):
        if not shutil.which(name):
            raise SystemExit(f"{name} is required; refusing to reuse an existing display/session")
    with tempfile.TemporaryDirectory(prefix="sofatap-focus-") as temporary:
        root = Path(temporary)
        authority = root / "Xauthority"
        authority.touch(mode=0o600)
        cookie = secrets.token_hex(16)
        subprocess.run(["xauth", "-f", str(authority), "add", ":0", ".", cookie], check=True, capture_output=True)
        read_fd, write_fd = os.pipe()
        server = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "800x600x24", "-nolisten", "tcp",
                                   "-noreset", "-auth", str(authority)], pass_fds=(write_fd,),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write_fd)
        try:
            if not select.select([read_fd], [], [], 8)[0]:
                raise RuntimeError("Private Xvfb startup timed out")
            number = os.read(read_fd, 64).decode("ascii").strip()
            if not number.isdecimal() or server.poll() is not None:
                raise RuntimeError("Private Xvfb did not start")
            display = ":" + number
            subprocess.run(["xauth", "-f", str(authority), "add", display, ".", cookie], check=True, capture_output=True)
            environment = dict(os.environ)
            for key in ("WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "AT_SPI_BUS_ADDRESS"):
                environment.pop(key, None)
            environment.update(DISPLAY=display, XAUTHORITY=str(authority), XDG_SESSION_TYPE="x11", GDK_BACKEND="x11",
                               SOFATAP_FOCUS_XVFB=str(server.pid), SOFATAP_FOCUS_DISPLAY=display, NO_AT_BRIDGE="0",
                               GTK_MODULES="gail:atk-bridge", GTK_A11Y="always", LC_ALL="C.UTF-8",
                               XDG_CONFIG_HOME=str(root / "config"), XDG_CACHE_HOME=str(root / "cache"))
            return subprocess.run(["dbus-run-session", "--", sys.executable, "-B", str(Path(__file__).resolve()), "--owned-child"],
                                  env=environment, timeout=80).returncode
        finally:
            os.close(read_fd)
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
